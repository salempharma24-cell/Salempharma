# Audit ciblé PharmaSys — 09/10/2026

## Modifications de cette version
- Ajout d'une carte « Historique de mes tickets » dans l'espace assistant.
- Liste des tickets avec date, heure, nombre d'articles, montant et statut; ouverture du ticket pour voir les lignes et accéder aux actions existantes.
- Filtrage des tickets de l'assistant par `assistant_id` et garde-fou côté interface sur le détail du ticket.
- Ajustement de la présentation du panier pour les petits écrans; conservation des commandes +/−, suppression d'article, sous-totaux et bénéfice estimé existants.

## Contrôles effectués
- Syntaxe JavaScript des scripts intégrés vérifiée avec `node --check`.
- Archive ZIP vérifiée avec `unzip -t`.
- La migration SQL n'a pas été exécutée contre le projet Supabase réel et aucun test d'intégration avec une base connectée n'a été possible dans cet environnement.

## Point critique à traiter avant mise en production
La vérification d'appartenance d'un ticket à un assistant dans cette version est côté interface. Cela améliore l'usage normal mais **ne constitue pas une autorisation de sécurité** : les RPC SQL `annuler_ticket`, `annuler_article_ticket` et `annuler_ligne_ticket` doivent aussi vérifier côté serveur que l'utilisateur connecté est administrateur ou propriétaire du ticket. Il faut également vérifier les politiques RLS de lecture des tickets et lignes. Ne pas considérer cette autorisation comme sécurisée avant cette vérification serveur.

## Recommandations prioritaires
1. **Sécuriser les annulations côté serveur** : contrôle rôle/identité/tenant et propriété du ticket dans chaque RPC; journaliser auteur, date, motif, montant remboursé et lignes touchées.
2. **Annulation partielle et caisse** : vérifier en base que le montant remboursé est calculé sur la ligne réellement payée, que les paiements mixtes/crédits sont traités correctement et que les remboursements ne peuvent être appliqués deux fois.
3. **Tests automatisés de flux** : vente comptant, mobile money, paiement mixte, crédit, annulation d'une ligne, annulation complète après annulation partielle, tentative de double annulation, stock insuffisant, session expirée et mode hors ligne.
4. **Cohérence des rapports** : définir une source de vérité unique pour le chiffre d'affaires et le bénéfice; exclure les lignes annulées partout (catalogue, tops, tableaux finance, prévisions et statistiques) et distinguer bénéfice brut de bénéfice net après charges.
5. **Stock et traçabilité** : utiliser des transactions SQL atomiques et des clés d'idempotence pour les ventes synchronisées hors ligne; chaque correction doit générer un mouvement horodaté avec auteur et motif, sans modifier l'historique initial.
6. **Permissions** : définir une matrice claire Administrateur / Pharmacien / Assistant / Caissier / Consultation et la faire appliquer dans les RPC et RLS, pas seulement en masquant les boutons.
7. **Qualité opérationnelle** : sauvegardes et procédure de restauration testée, journal d'audit consultable, alertes de péremption/lot, seuils de stock minimum, contrôle des prix et marges, exports PDF/Excel et clôture de caisse par session.
8. **Interface** : tester les parcours sur Android et petit écran, ajouter des confirmations claires, éviter les doubles clics, afficher les erreurs réseau, et signaler explicitement les opérations hors ligne en attente de synchronisation.

## Périmètre de l'audit
Cet audit est un examen statique ciblé du code fourni et des fonctions repérées. Il ne remplace pas une revue complète des politiques RLS de la base en production, des données réelles, des migrations déjà appliquées ni des tests multi-utilisateurs.

## Renforcement intégré dans Salempharma-pro
- Nouvelle migration `20261009000300_professional_controls_audit_permissions.sql` : contrôles de permission côté base lors des changements de statut, vérification du tenant et de la propriété du ticket par l'assistant, journal d'audit append-only des changements de statut, index de rapprochement.
- Finance : ajout d'un indicateur distinct « Bénéfice après dépenses (estimé) » calculé comme bénéfice brut moins dépenses de la période. Il ne remplace pas une comptabilité nette complète.
- Finance admin : ajout d'un panneau de consultation du journal d'audit.
- Ajout de `TESTS_FLUX_METIER.md` pour guider les tests de permissions, paiements mixtes, crédit, remboursements, double annulation, synchronisation hors ligne, rapports et sauvegarde/restauration.

## Limites restantes explicites
- La migration SQL doit être appliquée au projet Supabase cible avant d'activer ces contrôles.
- Les scénarios listés dans `TESTS_FLUX_METIER.md` ne sont pas déclarés réussis : aucune base Supabase connectée n'était disponible pour les exécuter.
- Le stock actuel suit le niveau de produit et sa date de péremption, mais il n'existe pas encore de traçabilité complète des lots par fournisseur / numéro de lot. Il faut la développer avant de considérer le suivi des lots pharmaceutiques comme complet.
- L'idempotence de vente s'appuie sur l'identifiant de ticket unique et les garde-fous métier existants. La reprise hors ligne doit encore être testée avec des interruptions réseau réelles.
