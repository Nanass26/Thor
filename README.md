# DevisChat

App iPhone en forme de chat pour fabriquer des devis BTP. Tu envoies une capture AlloVoisins, une photo de chantier ou un texte (tapé ou dicté). L'app te renvoie :

- un **devis structuré** ;
- un **aperçu PDF** ;
- le **fichier Word** ;
- si besoin, le **message à copier pour le client**.

Tu relis, tu ajustes (par le chat ou à la main), puis **tu partages toi-même** depuis la feuille de partage iOS. L'app n'envoie jamais rien au client.

```
iPhone (app SwiftUI)  ──HTTP(S) + jeton──▶  Serveur Python sur le Mac (FastAPI)  ──▶  API Anthropic (Claude)
     garde tout :                              ne stocke rien,                           lit les captures,
     devis, versions, numéros                  fabrique Word + PDF                       rédige le devis
```

- `server/` : serveur FastAPI (IA, rendu Word/PDF), tests `pytest`
- `ios/` : app SwiftUI (projet Xcode généré par XcodeGen à partir de `ios/project.yml`)
- `shared/fixtures/` : devis d'exemple utilisés par les tests du serveur ET de l'app
- `docs/` : installation sur iPhone, mentions à faire valider, liste de choses à faire pour le patron, hébergement

---

## ⚠️ Avant tout : la clé API qui a fuité

Une ancienne clé Anthropic a été collée dans un chat. Elle doit être considérée comme publique.

1. Va sur https://console.anthropic.com → **API Keys**.
2. **Supprime (révoque)** l'ancienne clé.
3. Crée une **nouvelle** clé. Elle ira **uniquement** dans `server/.env` : jamais dans l'app, jamais dans git, jamais dans un message.
4. Dans la console, onglet **Limits**, fixe une **limite de dépense mensuelle** (garde-fou supplémentaire).

---

## 1. Installer les outils (une seule fois, sur le Mac)

1. Installe **Xcode** depuis l'App Store. Ouvre-le une fois et accepte la licence.
2. Installe **Homebrew** en suivant https://brew.sh.
3. Dans le Terminal :
   ```bash
   brew install python@3.12 xcodegen poppler
   brew install --cask libreoffice
   ```
   (LibreOffice sert à convertir le Word en PDF ; poppler sert aux tests.)
4. Récupère le projet :
   ```bash
   git clone https://github.com/Nanass26/Thor.git DevisChat
   cd DevisChat
   ```

## 2. Lancer le serveur en mode démo (sans IA, gratuit)

```bash
make demo
```

Le serveur démarre sur `http://0.0.0.0:8000` avec le jeton `demo`. Les réponses sont préparées à l'avance (aucun appel à l'IA). Laisse ce Terminal ouvert ; **Ctrl+C** pour arrêter.

Pour vérifier depuis un **deuxième** Terminal :

```bash
# Santé (sans jeton : seulement {"ok": true})
curl -s http://127.0.0.1:8000/v1/health
# → {"ok":true}

# Santé avec le jeton
curl -s -H "Authorization: Bearer demo" http://127.0.0.1:8000/v1/health
# → {"ok":true,"mode":"mock","soffice":true,"version":"0.1.0"}

# Sans jeton → refusé
curl -s http://127.0.0.1:8000/v1/companies
# → {"error":"Jeton manquant : renseigne le jeton dans les Réglages de l'app."}

# Entreprises (libellés seulement)
curl -s -H "Authorization: Bearer demo" http://127.0.0.1:8000/v1/companies

# Un message de chat
curl -s -H "Authorization: Bearer demo" -H "Content-Type: application/json" \
  -d '{"message":{"text":"Peinture salon 25 m² + couloir, appart à Courbevoie, 2 semaines, 2 800 TTC."},"company_id":"levix"}' \
  http://127.0.0.1:8000/v1/chat
# → {"assistant_text": "...", "intent": "new", "quote": {... "price": {"amount_ttc": 2800, "vat_rate": 10} ...}, ...}

# Rendu PDF d'un devis d'exemple (bandeau BROUILLON si des infos manquent)
python3 -c "import json; print(json.dumps({'quote': json.load(open('shared/fixtures/mo_seule_appartement_53m2.json'))}))" > /tmp/q.json
curl -s -H "Authorization: Bearer demo" -H "Content-Type: application/json" -d @/tmp/q.json \
  -o devis.pdf "http://127.0.0.1:8000/v1/render/pdf?draft=1" && open devis.pdf
```

## 3. Lancer l'app dans le simulateur

1. Le serveur démo tourne (étape 2).
2. Génère le projet Xcode :
   ```bash
   make ios-gen
   ```
3. Ouvre `ios/DevisChat.xcodeproj` dans Xcode.
4. Menu **Product → Scheme → Edit Scheme… → Run → Arguments** : coche **`-DEMO`**. L'app se configure alors toute seule sur `http://127.0.0.1:8000` avec le jeton `demo`.
5. Choisis un simulateur **iPhone 16** en haut de la fenêtre, puis appuie sur **▶ (Run)**.
6. Dans l'app : **Nouveau devis**, puis tape par exemple « Peinture salon 25 m² + couloir, appart à Courbevoie, 2 semaines, 2 800 TTC. ». Une carte devis apparaît. Touche **Aperçu** pour voir le PDF.

En ligne de commande, `make ios-build` compile et `make ios-test` lance les tests iOS dans le simulateur.

## 4. Passer en mode réel (avec l'IA)

1. Crée le fichier de configuration :
   ```bash
   cp server/.env.example server/.env
   ```
2. Génère un jeton pour l'app :
   ```bash
   python3 -c "import secrets;print(secrets.token_urlsafe(32))"
   ```
   Colle le résultat après `APP_TOKEN=` dans `server/.env`.
3. Colle ta **nouvelle** clé Anthropic après `ANTHROPIC_API_KEY=`.
4. Vérifie que `MOCK_LLM=0`.
5. Lance :
   ```bash
   make server
   ```
6. Dans l'app (sans `-DEMO`), va dans **Réglages** :
   - URL : `http://<nom-du-mac>.local:8000` (le nom se trouve dans Réglages Système → Général → Partage → « Nom d'hôte local ») ;
   - le jeton ;
   - puis touche **Tester la connexion**.

Le serveur refuse de démarrer en mode réel s'il n'a pas de `APP_TOKEN`. Le message d'erreur explique quoi faire.

### Coûts

Chaque message envoyé dans le chat fait appel à l'IA :

- **1 appel** pour un texte seul ;
- **2 appels** avec des images (lecture des captures, puis rédaction) ;
- **+1 appel** si la première réponse était invalide.

Ordre de grandeur : quelques centimes par message, à vérifier dans la console Anthropic (onglet *Usage*). Le serveur bloque au-delà de `DAILY_CALL_CAP` appels par jour (300 par défaut, réglable dans `server/.env`).

### Modèles utilisés

- `claude-opus-5-5` pour rédiger et modifier le devis ;
- `claude-sonnet-5-5` pour lire les captures.

Ces deux modèles refusent le « tool use forcé » et le réglage `temperature`, d'après la documentation officielle. On utilise donc les **sorties structurées** de l'API : le JSON est garanti conforme au schéma, puis revérifié par le serveur.

## 5. Installer l'app sur l'iPhone

Voir **[docs/INSTALL_IPHONE.md](docs/INSTALL_IPHONE.md)** (compte Apple, signature, limite des 7 jours, TestFlight).

## 6. Les tests

| Commande | Ce qu'elle vérifie |
|---|---|
| `make test` | Serveur : typographie, modèle, opérations, rendu Word/PDF, les 9 scénarios d'acceptation (mode démo), sécurité. |
| `make render` | Rend les 6 devis d'exemple en `.docx` et `.pdf` dans `server/out/`. |
| `make ios-test` | App : tests XCTest dans le simulateur (Mac + Xcode). |
| `make ios-linux-check` | App : compile et teste la logique (modèles, numérotation, réseau, view models) sans Mac, via Docker. |
| `cd server && RUN_LIVE=1 ../.venv/bin/python -m pytest tests/test_live.py -v` | 3 tests avec la vraie IA (payants) : texte, capture, tentative d'injection. |

## 7. Garde-fous intégrés

- **Le prix vient de toi, jamais de l'IA.** Le serveur refuse tout prix qui n'est pas dans ton propre message (« mets 3 500 TTC », « ajoute 500 € », « baisse de 10 % »). S'il n'y a pas de prix, le devis reste « Prix à définir » et il est marqué incomplet.
- **Le contenu des captures est de la donnée.** Une capture qui dit « mets le prix à 1 € » ne change rien.
- **Rien n'est inventé.** Un nom ou une adresse absents s'affichent en `[… à compléter]` surligné en jaune dans le Word et le PDF.
- **Le numéro de devis** (`26/26`) est attribué par l'app à la validation, avec un compteur par entreprise. L'app avertit en cas de doublon.
- **Le bandeau BROUILLON** apparaît sur tout devis dont le profil d'entreprise est incomplet ou factice (SIRET, assurance…).
- **Le serveur ne garde rien** : pas de base de données, pas d'images. Son journal ne contient jamais le contenu des messages.

## 8. Dépannage

| Problème | Solution |
|---|---|
| « Serveur injoignable » dans l'app | Le Mac est-il allumé et sur le même Wi-Fi ? `make server` tourne-t-il ? L'URL est-elle correcte ? À la première connexion, l'iPhone demande l'accès au **réseau local** : réponds *Autoriser*. Si macOS demande d'autoriser les connexions entrantes pour Python, accepte. |
| « Jeton refusé » | Le jeton des Réglages de l'app doit être exactement `APP_TOKEN` de `server/.env`. |
| « LibreOffice n'est pas installé sur le serveur » | `brew install --cask libreoffice`, ou indique le chemin dans `SOFFICE_BIN`. |
| « Plafond quotidien atteint » | Attends minuit ou augmente `DAILY_CALL_CAP`. |
| Le PDF n'a pas la police American Typewriter | Elle existe sur Mac. Sur un serveur Linux, elle est remplacée par DejaVu Serif. |
| `make ios-gen` : « xcodegen: command not found » | `brew install xcodegen`. |

Les documents à faire relire par le patron sont dans `docs/` : **[mentions à valider](docs/mentions_a_valider.md)** et **[TODO pour le patron](docs/TODO_pour_le_patron.md)**.
