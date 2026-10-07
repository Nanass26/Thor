# Héberger le serveur (optionnel)

Par défaut, le serveur tourne sur le Mac, et l'iPhone l'appelle sur le même Wi-Fi. Pour utiliser l'app partout (sur un chantier, en 4G), il faut héberger le serveur sur une machine joignable depuis Internet, **obligatoirement en HTTPS** : le jeton et les captures ne doivent jamais circuler en clair sur Internet.

## Image Docker

Le fichier `server/Dockerfile` construit une image avec Python, le serveur et LibreOffice :

```bash
docker build -t devischat-server server/
docker run -d --name devischat --restart unless-stopped \
  --env-file server/.env -p 127.0.0.1:8000:8000 \
  -v "$PWD/server/data/companies.json:/app/data/companies.json:ro" \
  -v "$PWD/server/data/price_history.json:/app/data/price_history.json:ro" \
  devischat-server
```

- `server/.env` n'est **pas** copié dans l'image : il est passé au démarrage (`--env-file`).
- Les vrais profils et l'historique des prix sont **montés** depuis la machine, pas copiés dans l'image.
- **Police** : American Typewriter n'existe pas sous Linux. Dans le PDF produit par le serveur hébergé, elle est remplacée par **DejaVu Serif** (libre). Le fichier Word, lui, déclare toujours American Typewriter : il s'affiche correctement quand on l'ouvre sur un Mac ou un iPhone.

> État : ce Dockerfile n'a **pas** pu être construit pendant le développement, car l'environnement de travail bloquait l'accès aux dépôts Debian. Le serveur lui-même est testé (`make test`). La première construction est à faire sur la machine d'hébergement.

## HTTPS avec Caddy (exemple sur un petit serveur Linux)

1. Réserve un nom de domaine, par exemple `devis.mon-entreprise.fr`, et fais-le pointer vers l'adresse IP du serveur.
2. Installe Caddy (https://caddyserver.com). Il obtient et renouvelle tout seul les certificats HTTPS.
3. Crée le fichier `/etc/caddy/Caddyfile` :
   ```
   devis.mon-entreprise.fr {
       reverse_proxy 127.0.0.1:8000
   }
   ```
4. Recharge Caddy : `sudo systemctl reload caddy`.
5. Dans l'app → Réglages : URL `https://devis.mon-entreprise.fr`, même jeton. Puis **Tester la connexion**.

## Sécurité à garder en tête

- Choisis un `APP_TOKEN` long (la commande du README en génère un bon). Change-le si un téléphone est perdu.
- Garde `DAILY_CALL_CAP` raisonnable, et une limite de dépense dans la console Anthropic.
- Le serveur ne stocke ni images ni devis, et son journal ne contient pas le contenu des messages.
