-- PharmaSys: correction sûre du stock depuis le contrôle physique des ventes.
-- L'écart historique est appliqué au stock courant (stock courant + écart),
-- afin de préserver les mouvements intervenus après la journée contrôlée.

CREATE OR REPLACE FUNCTION public.corriger_stock_controle_vente(
  p_controle_id bigint,
  p_observation text DEFAULT 'Correction depuis le contrôle physique des ventes'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant uuid := public.current_tenant_id();
  c public.controles_inventaire%ROWTYPE;
  v_stock_avant numeric;
  v_stock_apres numeric;
  v_ecart numeric;
  v_nom text;
BEGIN
  IF v_tenant IS NULL OR NOT public.is_current_admin() THEN
    RAISE EXCEPTION 'Correction réservée à l’administration';
  END IF;

  SELECT * INTO c
  FROM public.controles_inventaire
  WHERE id = p_controle_id
    AND tenant_id = v_tenant
    AND source = 'VENTE'
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Contrôle de vente introuvable'; END IF;
  IF c.stock_corrige THEN RAISE EXCEPTION 'Ce contrôle a déjà été appliqué au stock'; END IF;
  IF c.ecart IS NULL THEN RAISE EXCEPTION 'Écart de stock manquant'; END IF;

  SELECT stock, nom INTO v_stock_avant, v_nom
  FROM public.inventaire
  WHERE id = c.produit_id AND tenant_id = v_tenant
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Produit introuvable dans ce tenant'; END IF;

  v_ecart := c.stock_physique - c.stock_systeme;
  v_stock_apres := v_stock_avant + v_ecart;
  IF v_stock_apres < 0 THEN
    RAISE EXCEPTION 'Correction refusée : elle rendrait le stock négatif (%)', v_stock_apres;
  END IF;

  IF v_ecart <> 0 THEN
    UPDATE public.inventaire
    SET stock = v_stock_apres, dernier_controle = now()
    WHERE id = c.produit_id AND tenant_id = v_tenant;

    INSERT INTO public.mouvements_stock(
      date, assistant, produit_id, produit, type, quantite,
      stock_avant, stock_apres, observation, tenant_id
    ) VALUES (
      to_char(now(), 'DD/MM/YYYY HH24:MI:SS'),
      COALESCE(NULLIF(c.auteur, ''), 'Administration'),
      c.produit_id, COALESCE(NULLIF(c.produit_nom, ''), v_nom, 'Produit'),
      'AJUSTEMENT_INVENTAIRE', abs(v_ecart), v_stock_avant, v_stock_apres,
      COALESCE(NULLIF(p_observation, ''), 'Correction depuis contrôle physique ventes')
        || ' · Contrôle #' || c.id || ' · Écart historique ' || v_ecart,
      v_tenant
    );
  END IF;

  UPDATE public.controles_inventaire
  SET stock_corrige = true,
      statut = CASE WHEN v_ecart = 0 THEN 'CONFORME' ELSE 'CORRIGE' END,
      cause = COALESCE(cause, 'Écart constaté au contrôle physique des ventes'),
      observation = concat_ws(' · ', NULLIF(observation, ''), NULLIF(p_observation, ''))
  WHERE id = c.id AND tenant_id = v_tenant;

  RETURN jsonb_build_object(
    'success', true,
    'controle_id', c.id,
    'ecart', v_ecart,
    'stock_avant', v_stock_avant,
    'stock_apres', v_stock_apres,
    'stock_corrige', true
  );
END;
$$;

REVOKE ALL ON FUNCTION public.corriger_stock_controle_vente(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.corriger_stock_controle_vente(bigint, text) TO anon, authenticated;

-- Relier un contrôle à son mouvement de vente pour éviter les doublons et
-- permettre de retrouver l'état du pointage après actualisation de la page.
ALTER TABLE public.controles_inventaire
  ADD COLUMN IF NOT EXISTS mouvement_id bigint;
CREATE UNIQUE INDEX IF NOT EXISTS controles_vente_mouvement_unique
  ON public.controles_inventaire (tenant_id, mouvement_id)
  WHERE mouvement_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.get_sales_control_day(p_date date)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tenant uuid := public.current_tenant_id(); v_result jsonb;
BEGIN
  IF v_tenant IS NULL OR NOT public.is_current_admin() THEN
    RAISE EXCEPTION 'Accès réservé à l’administration';
  END IF;
  WITH rows AS (
    SELECT ms.id, ms.created_at, ms.assistant_id, ms.assistant, ms.produit_id,
           ms.produit, ms.quantite, ms.stock_avant, ms.stock_apres, ms.ticket,
           ci.id AS controle_id, ci.stock_physique, ci.ecart,
           COALESCE(ci.stock_corrige,false) AS stock_corrige
    FROM public.mouvements_stock ms
    LEFT JOIN public.controles_inventaire ci
      ON ci.tenant_id = ms.tenant_id AND ci.mouvement_id = ms.id
    WHERE ms.tenant_id = v_tenant AND ms.type = 'VENTE'
      AND ms.created_at >= p_date::timestamptz
      AND ms.created_at < (p_date + 1)::timestamptz
  )
  SELECT jsonb_build_object(
    'date', p_date,
    'tickets', COALESCE((SELECT COUNT(DISTINCT ticket) FROM rows),0),
    'articles', COALESCE((SELECT SUM(quantite) FROM rows),0),
    'ca', COALESCE((SELECT SUM(t.montant_total) FROM public.tickets t
      WHERE t.tenant_id=v_tenant AND t.date=p_date AND t.statut='VALIDE'),0),
    'assistants_count', COALESCE((SELECT COUNT(DISTINCT COALESCE(assistant_id::text,assistant)) FROM rows),0),
    'movements', COALESCE((SELECT jsonb_agg(to_jsonb(rows) ORDER BY created_at,id) FROM rows),'[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_sales_control_day(date) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.enregistrer_controle_vente(
  p_mouvement_id bigint,
  p_produit_id bigint,
  p_vente_date date,
  p_assistant_id bigint,
  p_assistant text,
  p_produit_nom text,
  p_quantite_vendue numeric,
  p_stock_attendu numeric,
  p_stock_physique numeric
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tenant uuid := public.current_tenant_id();
  v_id bigint; v_ecart numeric; v_assistant_id bigint; v_assistant text;
  v_produit_id bigint; v_produit text; v_stock numeric; v_qty numeric; v_date date;
  v_existing_corrected boolean;
BEGIN
  IF v_tenant IS NULL OR NOT public.is_current_admin() THEN
    RAISE EXCEPTION 'Pointage réservé à l’administration';
  END IF;
  IF p_stock_physique IS NULL OR p_stock_physique < 0 THEN
    RAISE EXCEPTION 'Stock physique invalide';
  END IF;
  SELECT ms.assistant_id, ms.assistant, ms.produit_id, ms.produit,
         ms.stock_apres, ms.quantite, ms.created_at::date
  INTO v_assistant_id, v_assistant, v_produit_id, v_produit, v_stock, v_qty, v_date
  FROM public.mouvements_stock ms
  WHERE ms.id=p_mouvement_id AND ms.tenant_id=v_tenant AND ms.type='VENTE';
  IF NOT FOUND OR v_produit_id IS NULL THEN RAISE EXCEPTION 'Mouvement de vente introuvable'; END IF;

  SELECT id, stock_corrige INTO v_id, v_existing_corrected
  FROM public.controles_inventaire
  WHERE tenant_id=v_tenant AND mouvement_id=p_mouvement_id
  FOR UPDATE;
  IF COALESCE(v_existing_corrected,false) THEN
    RAISE EXCEPTION 'Ce contrôle a déjà été corrigé ; créez un nouvel inventaire si un nouvel écart est constaté';
  END IF;

  v_ecart := p_stock_physique - v_stock;
  INSERT INTO public.controles_inventaire(
    produit_id, produit_nom, stock_systeme, stock_physique, ecart, valeur_ecart,
    statut, cause, observation, stock_corrige, auteur, date_controle, tenant_id,
    assistant_id, vente_date, quantite_vendue, stock_attendu, source, mouvement_id
  ) VALUES (
    v_produit_id, COALESCE(v_produit,p_produit_nom,''), v_stock, p_stock_physique,
    v_ecart, 0, CASE WHEN v_ecart=0 THEN 'CONFORME' ELSE 'A_ANALYSER' END,
    NULL, 'Pointage vente du '||COALESCE(v_date,p_vente_date)::text||' · Assistant: '||COALESCE(v_assistant,p_assistant,'Système'),
    false, COALESCE(v_assistant,p_assistant,'Administration'), now(), v_tenant,
    COALESCE(v_assistant_id,p_assistant_id), COALESCE(v_date,p_vente_date),
    COALESCE(v_qty,p_quantite_vendue), v_stock, 'VENTE', p_mouvement_id
  )
  ON CONFLICT (tenant_id, mouvement_id) WHERE mouvement_id IS NOT NULL
  DO UPDATE SET
    stock_systeme=EXCLUDED.stock_systeme,
    stock_physique=EXCLUDED.stock_physique,
    ecart=EXCLUDED.ecart,
    valeur_ecart=EXCLUDED.valeur_ecart,
    statut=EXCLUDED.statut,
    observation=EXCLUDED.observation,
    date_controle=now()
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success',true,'id',v_id,'ecart',v_ecart);
END;
$$;
GRANT EXECUTE ON FUNCTION public.enregistrer_controle_vente(bigint,bigint,date,bigint,text,text,numeric,numeric,numeric) TO anon, authenticated;
