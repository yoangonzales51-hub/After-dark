AFTER DARK — ÉTAPE 1 : COMPTES ET ASSOCIATION DU COUPLE

Installation GitHub Pages
1. Décompressez ce ZIP.
2. Remplacez les fichiers du dépôt GitHub par TOUT le contenu de ce dossier.
3. Gardez le dossier icons/ et ses deux fichiers.
4. GitHub → Settings → Pages → Deploy from a branch → main → /(root).
5. Attendez la publication puis rechargez le site.

Configuration Supabase
- Le projet Supabase configuré est ejmidupqavmgyowwlwqn.
- Le client utilise la clé publishable (publique), jamais une clé service_role.
- Le SQL déjà exécuté doit fournir les tables/RPC : couple_members, create_couple(text), create_invite(), join_couple(text).
- Chaque partenaire crée son propre compte avec son e-mail, puis l'un crée le couple et transmet le code à l'autre.

IMPORTANT
Cette version réalise uniquement l'inscription/connexion et l'association des deux comptes.
La synchronisation en direct des cartes, réponses privées, progression et reprise sur deux téléphones n'est PAS encore intégrée. Ne commencez pas une partie à distance en pensant qu'elle est synchronisée.
La partie locale/solo et le téléphone commun restent disponibles.
