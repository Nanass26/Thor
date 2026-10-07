# Rapport de fin de mission — DevisChat

Date : 7 octobre 2026. Branche : `claude/jolly-cori-ablbzp`.

## Contexte important : machine de développement sans Mac

Le travail a été fait dans un conteneur **Linux** (Ubuntu 24.04), sans Xcode, sans simulateur iOS et sans Homebrew. Tout ce qui pouvait être vérifié ici l'a été :

- **Serveur** : entièrement testé.
- **Logique de l'app** (modèles, numérotation, réseau, view models) : compilée et testée avec le compilateur **Swift 6.0 officiel pour Linux** (Docker).
- **Projet Xcode** : **généré** à partir de `ios/project.yml` avec **XcodeGen 2.42.0** compilé sous Linux.

En revanche, **`xcodebuild` n'a jamais tourné**. Les écrans SwiftUI, SwiftData, le Trousseau et la compression UIKit sont écrits mais **pas compilés**. Voir « Ce qui n'a pas pu être testé ».

## Ce qui fonctionne, avec preuves

### Serveur (Python 3.13, FastAPI) — `make test`

```
166 passed, 3 skipped in 14.46s      (les 3 « skipped » = tests live, sans clé API)
```

| Domaine | Fichier de test | Ce qui est prouvé |
|---|---|---|
| Typographie | `test_typo.py` | `6 500 €` avec espaces insécables ; `: ; ? !` (sauf URL, e-mail, heure) ; `’` ; « » ; `7 octobre 2026`, `1er août 2026` ; `5,5 %` ; `53 m²` ; idempotence |
| Modèle | `test_models.py` | HT/TVA au centime ; `missing` déterministe ; TVA 5,5/10/20 seulement ; montants entiers stricts ; lot = puces OU paragraphe ; les 6 fixtures valides |
| Opérations | `test_ops.py` | Liste blanche (21 chemins acceptés, chemins interdits ou hors liste refusés) ; valeur de mauvais type refusée ; **tout-ou-rien** ; lots (ajout, insertion, remplacement, suppression, réordonnancement) ; `number = null` au changement d'entreprise ; garde-fou prix ; diff lisible |
| Rendu | `test_render.py` | Phrase de prix exacte ; **montant d'un seul tenant** (1 run) ; numéro, date, validité ; crochets **jaunes** sans prix inventé ; tableau 6 800 / 2 200 twips ; pied de page issu du profil ; A4, marges 2,54 cm, titres teal gras-italique-soulignés ; bandeau BROUILLON ; page de garde ; **PDF de 1 à 3 pages** et montant retrouvé par `pdftotext` (6 fixtures) |
| Scénarios | `test_scenarios.py` | **Les 9 scénarios de la section 10**, de bout en bout via l'API en mode mock, plus « photo de chantier sans texte » et « message client » |
| API | `test_api.py` | 401 sans jeton (5 routes) ; `/v1/health` limité à `{ok}` sans jeton ; refus de démarrer en live sans `APP_TOKEN` ; plafond d'images (7 → 400) ; HEIC refusé ; corps trop gros (413) ; plafond quotidien (429) et remise à zéro ; erreurs JSON en français sans écho du contenu ; **journal sans contenu** ; erreur interne masquée ; **une seule relance** puis erreur propre ; rendu docx/pdf ; nom de fichier nettoyé |
| IA | `test_llm.py` | Schémas dans les limites documentées de l'API (≤ 24 champs optionnels, ≤ 16 unions : ici 13 et 0) ; requête Anthropic conforme (sorties structurées, `effort`, cache du prompt système, `fallbacks`, **ni `temperature` ni `tool_choice`**) ; refus et coupure gérés |
| Prix | `test_prices.py` | Somme de contrôle de l'historique : **12 entrées, 115 810 €, médiane 5 750 €, min 1 500, max 33 110** ; comparables ; ratio MO seule / complet = 54 % |

**Serveur lancé en vrai** (`MOCK_LLM=1`), routes testées au `curl` (sorties dans le README) :

```
GET  /v1/health   (sans jeton) → {"ok":true}
GET  /v1/health   (jeton)      → {"ok":true,"mode":"mock","soffice":true,"version":"0.1.0"}
GET  /v1/companies (sans jeton)→ 401 {"error":"Jeton manquant : renseigne le jeton dans les Réglages de l'app."}
POST /v1/chat                  → new {'amount_ttc': 2800, 'vat_rate': 10} 2 semaines ['Nom du client', 'Adresse du chantier']
POST /v1/render/pdf?draft=1    → 200 application/pdf 53203o, 1 page
journal : "POST /v1/chat 200 3ms 121o"   (méthode, route, statut, durée, taille — aucun contenu)
mode live sans APP_TOKEN       → refus de démarrer, message clair, code de sortie 1
```

**Rendu des 6 fixtures** (`make render` → `server/out/`) :

```
fenetre_bois 1 page · incomplet_sans_prix 1 page · mo_seule_appartement_53m2 1 page
optique_complet_55m2 2 pages · optique_mo_seule_55m2 2 pages · peinture_acompte 1 page
```

Quatre PDF ont été convertis en image (`pdftoppm`) et regardés. Deux défauts ont été corrigés :

1. le bloc « Conditions » se coupait, laissant une page 2 presque vide (il est désormais gardé d'un seul tenant avec les signatures) ;
2. l'en-tête collait au numéro du devis.

Deux exemples sont joints : `docs/exemples/`.

### App iOS — partie logique (Swift 6.0, Linux, Docker) — `make ios-linux-check`

```
Executed 37 tests, with 0 failures (0 unexpected)
```

- **Fixtures** : décodage, réencodage **identique au JSON du serveur** (null explicites, snake_case) ; `missing` et HT/TVA identiques au serveur.
- **APIClient** (`URLProtocol` factice) : jeton Bearer, corps snake_case, délai de 90 s pour `/v1/chat` ; erreurs typées en français (401, 429, 5xx, serveur injoignable, réponse illisible).
- **ChatViewModel** (API simulée) : nouveau devis, modification puis **annulation sans perte d'historique**, erreur puis **Réessayer** sans doublon, images (plafond de 6), validation avec numéro, **scénario 6** (changement d'entreprise → prochain numéro de la nouvelle entreprise, **doublon détecté et sauté**), saisie manuelle, export PDF avec nom propre (`Devis_SAR_BAT_M_B_Exemple_Remplacement_d_une_fenetre_bois.pdf`, identique au serveur), page de garde, résumé d'historique, rechargement depuis le stockage.
- **Numérotation** : `NN/AA`, remise à 1 au changement d'année, doublons évités et signalés.

### Projet Xcode

`xcodegen generate` (XcodeGen 2.42.0 compilé sous Linux) produit `ios/DevisChat.xcodeproj` :

- 36 fichiers Swift référencés (app + tests) ;
- cible de tests hébergée par l'app (`TEST_HOST`) ;
- iOS 17.0, icône `AppIcon`, schéma avec l'argument `-DEMO` ;
- `Info.plist` avec `NSLocalNetworkUsageDescription` et `NSAllowsLocalNetworking`.

## Ce qui n'a pas pu être testé, et pourquoi

| Non testé | Pourquoi | Que faire |
|---|---|---|
| `xcodebuild build` / `test` | Pas de macOS ni de Xcode dans l'environnement | Sur le Mac : `make ios-build` puis `make ios-test`. Les 17 fichiers d'interface (SwiftUI, SwiftData, PDFKit, PhotosUI, Security, UIKit) n'ont jamais été compilés : quelques erreurs de compilation sont possibles au premier build. Elles se corrigent en recollant le message d'erreur à Claude. |
| Captures d'écran du simulateur (chat, carte devis, aperçu, réglages, éditeur) | Pas de simulateur | Lancer avec `-DEMO` (voir README §3) |
| `ImageCompressorTests` (UIKit) | Nécessite le simulateur | Inclus dans `make ios-test` |
| Installation sur l'iPhone | Signature manuelle dans Xcode (point d'arrêt humain n° 4) | `docs/INSTALL_IPHONE.md` |
| Appels réels à l'API Anthropic | Pas de clé fournie (point d'arrêt humain n° 2) | Coller la clé dans `server/.env`, puis `RUN_LIVE=1` (3 tests : texte, capture, injection) |
| Construction de l'image Docker | Dépôts Debian bloqués par le réseau de l'environnement | `docker build -t devischat-server server/` sur la machine d'hébergement |
| Rendu avec la vraie police American Typewriter | Police absente sous Linux (substitution lors des tests) | Vérifier un PDF sur le Mac ; un devis long peut prendre une page de plus |

## Choix et écarts par rapport au brief

- **Pas de « tool use forcé » ni de `temperature`** : d'après la documentation officielle à jour, `claude-opus-5-5` et `claude-sonnet-5-5` répondent par une erreur 400 à `tool_choice` any/tool et à `temperature`. Remplacés par les **sorties structurées** (`output_config.format`, JSON garanti conforme), puis une validation Pydantic et une seule relance. La réflexion du modèle se règle avec `effort` (`medium` pour la rédaction, `low` pour la lecture des captures).
- **Repli automatique** `fallbacks: "default"` activé (bêta Anthropic) : si un modèle refuse une demande par erreur, l'API la relance sur un autre modèle. Désactivable avec `LLM_FALLBACK=0`.
- **Valeurs des opérations en texte JSON** (`value_json`) : c'est le seul moyen de rester sous la limite de 16 champs « union » par requête. La valeur est revalidée par le serveur.
- **`ClientSheet.observations`** ajouté : constats visibles sur une photo de chantier, pour décrire puis demander quoi faire.
- **Garde-fou prix déterministe** côté serveur, en plus du prompt. Un prix n'est accepté que s'il figure dans le message de l'utilisateur (montant exact, ancien prix ± montant, ou ± pourcentage). Sinon : nouveau devis → prix remis à « à définir » ; modification → **rien n'est appliqué** et une question est posée.
- **Changement de mode** (complet ↔ MO seule) sans nouveau prix : le serveur remet le prix à « à définir », quoi que réponde l'IA.
- **Bandeau BROUILLON** dès que le profil d'entreprise est factice, même sur un brouillon : aucun devis avec un faux SIRET ne doit pouvoir partir.
- **Numéro** : attribué à la **validation**. Au changement d'entreprise, un devis déjà numéroté (validé ou envoyé) reçoit aussitôt le prochain numéro de la nouvelle entreprise ; un brouillon le recevra à sa validation.
- **« Annuler »** recopie la version précédente comme nouvelle version. Annuler deux fois revient donc à la version annulée (l'historique complet est conservé).
- **`ios/DevisChat.xcodeproj` non commité** : il est généré par `make ios-gen`.

## Limites connues

- Le **mode démo** ne comprend que des phrases types (celles des scénarios et des raccourcis). Le scénario 9 (injection) n'est jouable à la main qu'en mode réel ; il est couvert par les tests automatiques.
- Les montants **dictés en toutes lettres** (« trois mille cinq cents ») ne sont pas reconnus par le garde-fou prix : l'app pose alors la question. Les chiffres et la saisie manuelle fonctionnent.
- Délai de 90 s sur `/v1/chat` : avec des images, la lecture puis la rédaction (et une éventuelle relance) peuvent s'en approcher.
- Compteurs de numéros **locaux à l'iPhone** : deux téléphones auraient des compteurs séparés.
- Devis **forfaitaires** (lots sans prix ligne par ligne) : conformité à faire valider (`docs/mentions_a_valider.md`).

## Prochaines idées

1. Importer un devis Word ou PDF existant pour le modifier par chat (phase 5a, non faite).
2. Extension de partage iOS pour envoyer une capture directement depuis Photos ou AlloVoisins (phase 5b, non faite).
3. Lancer les 3 tests live avec la vraie clé et ajuster les prompts sur 5 à 10 vraies demandes.
4. Hébergement HTTPS (`docs/HEBERGEMENT.md`) pour utiliser l'app hors de la maison.

## Actions humaines restantes

1. **Clé API** : révoquer l'ancienne, créer une neuve, la coller dans `server/.env` avec `APP_TOKEN` (README §4).
2. **`companies.json`** : vrais SIRET, NAF, adresses et assurances (`docs/TODO_pour_le_patron.md`), et validation des mentions.
3. **Mac** : `make ios-build && make ios-test`, puis installation sur l'iPhone (`docs/INSTALL_IPHONE.md`).
