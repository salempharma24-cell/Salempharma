-- Security hardening for PharmaSys sessions and reapprovisionnement log.
-- Apply in Supabase SQL Editor or through the project's migration workflow.
-- This migration does not delete existing sessions or business data.

BEGIN;

-- A client must never read, forge, edit, or delete bearer-token rows directly.
-- Session validation is provided through validate_session(uuid); creation is
-- performed only inside the trusted SECURITY DEFINER login function below.
DROP POLICY IF EXISTS "session_select_all" ON public.sessions;
DROP POLICY IF EXISTS "session_insert_all" ON public.sessions;
DROP POLICY IF EXISTS "session_update_all" ON public.sessions;
DROP POLICY IF EXISTS "session_delete_all" ON public.sessions;
DROP POLICY IF EXISTS "sessions_select_own" ON public.sessions;
DROP POLICY IF EXISTS "sessions_insert_own" ON public.sessions;
DROP POLICY IF EXISTS "sessions_update_own" ON public.sessions;
DROP POLICY IF EXISTS "sessions_delete_own" ON public.sessions;

REVOKE ALL PRIVILEGES ON TABLE public.sessions FROM PUBLIC, anon, authenticated;

-- Do not allow clients to invoke the primitive that accepts arbitrary user,
-- tenant, and role values. PUBLIC is revoked explicitly because functions
-- normally grant EXECUTE to PUBLIC by default.
REVOKE ALL PRIVILEGES ON FUNCTION public.create_session(bigint, uuid, text)
  FROM PUBLIC, anon, authenticated;

-- The login endpoint remains callable before application-session creation.
-- Capture the exact token returned by INSERT ... RETURNING to avoid a race
-- where concurrent logins could receive another login's most-recent token.
CREATE OR REPLACE FUNCTION public.authenticate_user(p_code text, p_tenant_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_user record;
  v_session_id uuid;
BEGIN
  IF p_code IS NULL OR btrim(p_code) = '' OR p_tenant_id IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'Code incorrect ou compte désactivé');
  END IF;

  SELECT u.id, u.nom, u.code, u.role, u.actif, u.tenant_id
    INTO v_user
  FROM public.utilisateurs AS u
  WHERE u.code = p_code
    AND u.tenant_id = p_tenant_id
    AND u.actif = true
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'message', 'Code incorrect ou compte désactivé');
  END IF;

  -- Never accept the role from the caller; it comes from the matched user row.
  INSERT INTO public.sessions (user_id, tenant_id, role)
  VALUES (v_user.id, v_user.tenant_id, v_user.role)
  RETURNING id INTO v_session_id;

  RETURN json_build_object(
    'success', true,
    'user', json_build_object(
      'id', v_user.id,
      'nom', v_user.nom,
      'code', v_user.code,
      'role', v_user.role,
      'actif', v_user.actif,
      'tenant_id', v_user.tenant_id
    ),
    'session_token', v_session_id
  );
END;
$function$;

-- Validation may be called by the client, but do not return the user's login
-- code in a session-validation response. The UUID remains a bearer credential.
CREATE OR REPLACE FUNCTION public.validate_session(p_token uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_session record;
BEGIN
  IF p_token IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'Session invalide ou expirée');
  END IF;

  SELECT s.id, s.user_id, s.tenant_id, s.role, s.expires_at, u.nom
    INTO v_session
  FROM public.sessions AS s
  JOIN public.utilisateurs AS u
    ON u.id = s.user_id AND u.tenant_id = s.tenant_id
  WHERE s.id = p_token
    AND s.expires_at > now()
    AND u.actif = true;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'message', 'Session invalide ou expirée');
  END IF;

  RETURN json_build_object(
    'success', true,
    'session', json_build_object(
      'id', v_session.id,
      'user_id', v_session.user_id,
      'tenant_id', v_session.tenant_id,
      'role', v_session.role,
      'nom', v_session.nom
    )
  );
END;
$function$;

-- Preserve the intended public login and validation flows, while explicitly
-- preventing direct execution of the arbitrary session-creation primitive.
REVOKE ALL PRIVILEGES ON FUNCTION public.authenticate_user(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.authenticate_user(text, uuid) TO anon, authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION public.validate_session(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_session(uuid) TO anon, authenticated;

COMMIT;
