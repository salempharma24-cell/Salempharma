# Plan de tests avant mise en production

Ces scénarios doivent être exécutés dans un environnement Supabase de test avec au moins deux assistants, un administrateur, un caissier, des produits avec stock suffisant et un stock insuffisant. Aucun test n'est réputé réussi simplement parce que la migration SQL s'applique.

## Permissions et audit
- [ ] Assistant A peut annuler une ligne de son propre ticket.
- [ ] Assistant A ne peut pas annuler le ticket ni une ligne appartenant à l'assistant B (l'appel RPC doit échouer côté serveur).
- [ ] Un caissier non administrateur ne peut pas annuler un ticket.
- [ ] L'administrateur peut annuler un ticket de son tenant, mais jamais d'un autre tenant.
- [ ] Chaque changement de statut d'un ticket ou d'une ligne génère un événement dans `journal_audit_pharmasys`.
- [ ] Les rôles non administrateurs ne peuvent ni lire le journal complet ni le modifier.

## Stock, caisse et remboursements
- [ ] Vente espèces : stock décrémenté une fois, paiement et entrée de caisse enregistrés.
- [ ] Vente Mobile Money : mode et montant corrects.
- [ ] Paiement mixte : somme des paiements égale au total et chaque remboursement réparti sans dépasser le montant initial par mode.
- [ ] Crédit : solde client exact après annulation partielle et complète.
- [ ] Annulation d'une ligne : quantité remise au stock, montant et bénéfice recalculés, remboursement enregistré une seule fois.
- [ ] Annulation complète après annulation partielle : seul le reliquat est remboursé.
- [ ] Double clic / répétition RPC : pas de deuxième mouvement de stock ou de remboursement.
- [ ] Stock insuffisant et vente simultanée : une seule vente passe si le stock ne permet pas les deux.
- [ ] Vente hors ligne synchronisée deux fois : le ticket existant est rejeté sans double débit de stock.

## Rapports et rapprochement
- [ ] Comparer les totaux Finance, historique des ventes, caisse et rapport journalier sur la même période.
- [ ] Vérifier que les tickets annulés ne comptent plus dans le CA net ni le bénéfice courant.
- [ ] Vérifier que les annulations restent visibles dans le journal de mouvements et dans l'audit.
- [ ] Rapprocher les remboursements par mode de paiement avec les sorties de caisse correspondantes.
- [ ] Vérifier qu'un règlement de crédit est une entrée de caisse mais pas une nouvelle vente.

## Stock avancé et exploitation
- [ ] Valider les seuils de stock bas et les alertes de péremption avec les lots réels.
- [ ] Tester la reprise de synchronisation après coupure réseau, fermeture du navigateur et session expirée.
- [ ] Réaliser une sauvegarde puis une restauration d'essai avant migration de production.

## Critère de sortie
Ne déployer en production qu'après exécution de ces scénarios et vérification des politiques RLS sur le projet Supabase cible. Les rapports ne doivent pas être déclarés réconciliés avant comparaison avec des données de test connues.
