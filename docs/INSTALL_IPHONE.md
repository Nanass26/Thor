# Installer DevisChat sur l'iPhone 16

Il te faut : le Mac avec Xcode, l'iPhone, un câble USB-C, et un identifiant Apple.

## Les étapes

1. **Mode développeur sur l'iPhone**
   1. Branche l'iPhone au Mac avec le câble. Sur l'iPhone, réponds « Faire confiance » si on te le demande.
   2. Sur l'iPhone : **Réglages → Confidentialité et sécurité → Mode développeur** → active-le.
   3. L'iPhone redémarre. Confirme l'activation au redémarrage.
   (Si l'option n'apparaît pas, ouvre d'abord Xcode avec l'iPhone branché, puis réessaie.)

2. **Ajouter ton identifiant Apple dans Xcode**
   1. Xcode → menu **Xcode → Settings… → Accounts**.
   2. Clique sur **+** → **Apple ID**, puis connecte-toi.

3. **Signer l'app**
   1. Dans le Terminal, à la racine du projet : `make ios-gen`.
   2. Ouvre `ios/DevisChat.xcodeproj`.
   3. À gauche, clique sur le projet **DevisChat**, puis sur la cible **DevisChat** → onglet **Signing & Capabilities**.
   4. Coche **Automatically manage signing**.
   5. Dans **Team**, choisis ton nom (Personal Team).
   6. Si Xcode affiche une erreur sur le **Bundle Identifier** (`com.devischat.app` déjà pris), remplace-le par un identifiant unique, par exemple `com.devischat.app.tonprenom`. Fais la même chose pour la cible **DevisChatTests** si besoin.
   7. Pour ne pas refaire cette étape à chaque `make ios-gen`, reporte l'identifiant choisi dans `ios/project.yml` (ligne `PRODUCT_BUNDLE_IDENTIFIER`). Tu peux aussi y mettre ton identifiant d'équipe (`DEVELOPMENT_TEAM`, visible dans Xcode).

4. **Lancer l'app sur l'iPhone**
   1. En haut de la fenêtre Xcode, choisis ton **iPhone** comme destination (à la place du simulateur).
   2. Clique sur **▶ (Run)**.

5. **Faire confiance au certificat (première fois seulement)**
   1. Si l'iPhone affiche « Développeur non approuvé » : **Réglages → Général → VPN et gestion de l'appareil**.
   2. Touche ton identifiant Apple → **Faire confiance**.
   3. Relance l'app.

6. **Connecter l'app au serveur**
   1. Sur le Mac : `make server` (mode réel) ou `make demo` (mode démo).
   2. Trouve le nom du Mac : **Réglages Système → Général → Partage**, en bas : « Nom d'hôte local », par exemple `MacBook-de-Papa.local`.
   3. Dans l'app → **Réglages** :
      - URL : `http://MacBook-de-Papa.local:8000` ;
      - le jeton (`APP_TOKEN` de `server/.env`, ou `demo` en mode démo).
   4. Touche **Tester la connexion**. La première fois, l'iPhone demande l'accès au **réseau local** : réponds **Autoriser**.
   5. Touche **Enregistrer**.

L'iPhone et le Mac doivent être sur **le même Wi-Fi**. Le Mac doit rester allumé (et pas en veille) pendant l'utilisation.

## Les limites à connaître

- **Compte Apple gratuit :**
  - l'app **cesse de s'ouvrir au bout de 7 jours** : il faut rebrancher l'iPhone et refaire **Run** depuis Xcode (les devis enregistrés sont conservés) ;
  - le nombre d'apps installables ainsi est limité (3 apps par appareil).
- **Installation durable (TestFlight) :** il faut le **programme développeur Apple payant (99 $ par an)**. Il doit être souscrit par un **adulte** : le père, responsable de l'entreprise, idéalement au nom de l'entreprise. L'app s'installe alors via TestFlight et reste valable 90 jours par version, sans câble.
- **Hors de la maison :** l'iPhone ne joint le serveur que sur le même Wi-Fi. Pour utiliser l'app partout, il faut héberger le serveur avec une adresse HTTPS (voir `docs/HEBERGEMENT.md`). Ensuite, seule l'URL change dans les Réglages.
