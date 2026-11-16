# AFTER DARK — pack complet GitHub Pages

## Fichiers à déposer à la racine du dépôt
- `index.html` : application V7 (600 cartes régulières intégrées + 25 Mythiques intégrées).
- `manifest.webmanifest` : configuration installable PWA.
- `sw.js` : cache hors-ligne et mise à jour du shell.
- `icons/icon-192.png` et `icons/icon-512.png` : icônes PWA.
- `catalogue_600.json` et `cartes_mythiques.json` : copies de sauvegarde/export des catalogues.

## Installation depuis zéro
1. Dans le dépôt GitHub, téléverser tous les éléments de ce dossier en conservant exactement l'arborescence.
2. Vérifier que `index.html`, `manifest.webmanifest` et `sw.js` sont à la racine et que le dossier `icons` contient les deux PNG.
3. Dans Settings → Pages, choisir Deploy from a branch, branche `main`, dossier `/ (root)`, puis enregistrer.
4. Attendre le déploiement puis ouvrir l'URL GitHub Pages.
5. Si l'ancien site reste en cache, faire Ctrl+F5 ou vider les données du site sur le téléphone.

## Fonctionnalités présentes et limites
- Jeu local sur un appareil, modes solo et téléphone commun, cartes glissables, onglets Jouer / À faire / Succès / Mode.
- Les 600 cartes et les 25 cartes Mythiques sont intégrées dans `index.html`; les JSON sont des copies séparées.
- La V7 affiche un espace préparatoire pour le jeu à distance, mais **la synchronisation entre deux téléphones, les comptes de couple et les invitations Supabase ne sont pas encore implémentés**. Le bouton de configuration distante ne crée pas de vraie session.
- La sauvegarde actuelle est locale au navigateur/appareil. Changer d'appareil ne transfère donc pas automatiquement la progression.

## Important
Ne supprimez pas les fichiers de la racine et ne renommez pas `manifest.webmanifest`, `sw.js` ou le dossier `icons`. Pour mettre à jour l'application, remplacez les fichiers par ceux de la nouvelle version en conservant cette structure.
