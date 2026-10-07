# À faire par le patron

## 1. Remplir les vrais profils d'entreprise (`server/data/companies.json`)

Pour l'instant, le serveur utilise des profils **factices** (`server/data/companies.example.json`, SIRET `000 000 000 00000`). Tant que c'est le cas, chaque devis porte un bandeau « BROUILLON — profil entreprise incomplet ou factice ».

1. Copie le modèle : `cp server/data/companies.example.json server/data/companies.json`.
2. Pour chaque entreprise, remplace les valeurs :
   - `label` et `tagline` : nom et sous-titre de l'en-tête ;
   - `legal_form`, `siret` (14 chiffres), `naf`, `address`, `email`, `phone` ;
   - `insurance_text`, par exemple : « Assurance décennale n° … — Assureur … — Zone : France — Activités : peinture, plâtrerie… » ;
   - `font` (police du document, American Typewriter par défaut) et `accent_color` (couleur des titres, `2E6F8E` par défaut).
3. Retire les mentions « (exemple factice) » et les fausses adresses `exemple.invalid`.
4. Redémarre le serveur.

Ce fichier n'est **jamais** envoyé sur GitHub (il est dans `.gitignore`).

## 2. Valider les mentions

Relire **[mentions_a_valider.md](mentions_a_valider.md)** et cocher ce qui est bon ou indiquer les corrections.

## 3. Enrichir l'historique des prix (`server/data/price_history.json`)

L'IA s'appuie sur tes **vrais prix passés** pour proposer une fourchette indicative. Elle ne met jamais de prix dans le devis.

1. Copie le modèle : `cp server/data/price_history.example.json server/data/price_history.json`.
2. Ajoute une ligne par devis accepté :
   ```json
   {"id": "h13", "trade": "peinture appartement", "surface_m2": 60, "mode": "complet", "ttc": 4900, "vat_rate": 10, "duration": "2 semaines"}
   ```
   - `trade` : quelques mots-clés sur la nature des travaux ;
   - `mode` : `complet` ou `main_oeuvre_seule` ;
   - `surface_m2` et `duration` : `null` si inconnus.
3. Plus il y a de lignes, plus la fourchette est pertinente. Avec moins de 2 chantiers comparables, l'app prévient que l'estimation est générique (souvent trop haute par rapport à tes prix réels).

Ce fichier n'est jamais envoyé sur GitHub.

## 4. Clé API Anthropic et budget

1. Révoquer l'ancienne clé (elle a fuité) et en créer une neuve : voir le README.
2. Fixer une limite de dépense mensuelle dans la console Anthropic.
3. Le serveur limite aussi à 300 appels par jour (`DAILY_CALL_CAP` dans `server/.env`).

## 5. Compte développeur Apple

- **Gratuit** : l'app se réinstalle depuis le Mac tous les 7 jours.
- **Payant (99 $/an)** : installation durable par TestFlight. À souscrire par un adulte, idéalement au nom de l'entreprise.

## 6. Choisir où faire tourner le serveur

| Option | Pour | Contre |
|---|---|---|
| **Le Mac de la maison** (actuel) | Gratuit, rien à configurer | Ne marche que sur le même Wi-Fi ; le Mac doit rester allumé |
| **Petit serveur loué** (VPS, environ 5 € par mois) + HTTPS | Marche partout, sur chantier | Un peu d'installation (voir `docs/HEBERGEMENT.md`) |
| **Plateforme gérée** (conteneur Docker) | Moins d'entretien | Selon l'offre, un peu plus cher |

Dans tous les cas, l'adresse doit être en **HTTPS** dès qu'on sort du réseau local. Dans l'app, seule l'URL change dans les Réglages.
