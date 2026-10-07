#!/usr/bin/env bash
# Lance le serveur DevisChat.
#   ./server/run_server.sh             → utilise server/.env
#   MOCK_LLM=1 ./server/run_server.sh  → mode démo, aucun appel à l'IA
# Le serveur écoute sur toutes les interfaces (0.0.0.0) pour que l'iPhone,
# sur le même Wi-Fi, puisse l'appeler via http://<nom-du-mac>.local:8000
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
PYTHON="${ROOT}/.venv/bin/python"
if [ ! -x "$PYTHON" ]; then
  echo "Environnement Python absent. Lance d'abord : make install" >&2
  exit 1
fi

PORT="${PORT:-8000}"
echo "Serveur DevisChat sur http://0.0.0.0:${PORT}  (Ctrl+C pour arrêter)"
# --no-access-log : notre propre journal (sans contenu de message) suffit.
exec "$PYTHON" -m uvicorn app.main:app --host 0.0.0.0 --port "$PORT" --no-access-log
