# Refonte UX/UI PharmaSys

## Modifications réalisées
- En-tête compact : identité de pharmacie, utilisateur, connexion et actions utilisent une ligne flexible qui se replie proprement sur les petits écrans.
- Navigation mobile plus compacte avec icônes vectorielles cohérentes et libellés raccourcis ; les quatre espaces fonctionnels et leurs identifiants JavaScript sont conservés.
- Réduction des marges, espacements, ombres et paddings des cartes, filtres, KPI et formulaires.
- Grilles de KPI en deux colonnes sur mobile.
- Tableaux des conteneurs `.table-responsive` transformés en fiches empilées sur les écrans étroits. Les titres des colonnes sont injectés en `data-label`, y compris après les mises à jour dynamiques.
- Sur le catalogue, les champs secondaires sont masqués sur téléphone afin de prioriser médicament, catégorie, stock, prix de vente et bénéfice ; les colonnes complètes restent disponibles sur grand écran.
- Pagination mobile compacte et visible pendant la consultation des longues listes.
- Prévention des débordements horizontaux de page et prise en compte de la zone de navigation inférieure.
- Respect de `prefers-reduced-motion`.

## Préservation fonctionnelle
Aucune table métier, fonction SQL, logique de vente, calcul de stock ou autorisation n'a été modifiée par cette refonte visuelle. Les identifiants des quatre boutons de navigation sont conservés.

## Contrôles effectués
- Syntaxe des scripts JavaScript intégrés vérifiée avec `node --check`.
- Syntaxe de `all.js` vérifiée avec `node --check`.
- Archive ZIP vérifiée après génération.

## Limites restantes
- Les tests d'interaction réels sur Android/iOS et les tests Supabase ne sont pas exécutés dans cet environnement.
- Les tableaux créés sans classe `.table-responsive` peuvent conserver une présentation spécifique ; ils devront être vérifiés pendant les tests sur appareil.
- Les formulaires ne sont pas tous repliés automatiquement afin de ne pas cacher des actions métier existantes sans validation préalable.
