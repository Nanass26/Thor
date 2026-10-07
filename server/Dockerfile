# Image du serveur DevisChat, pour l'héberger ailleurs que sur le Mac (voir docs/HEBERGEMENT.md).
# HTTPS obligatoire hors réseau local : place un reverse proxy (ex. Caddy) devant ce conteneur.
#   docker build -t devischat-server server/
#   docker run --env-file server/.env -p 8000:8000 \
#     -v "$PWD/server/data/companies.json:/app/data/companies.json:ro" devischat-server
ARG BASE=python:3.12-slim
FROM ${BASE}

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    SOFFICE_BIN=/usr/bin/soffice

# LibreOffice (conversion PDF) + polices libres. American Typewriter est remplacée par DejaVu Serif.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libreoffice-writer-nogui fonts-dejavu fonts-liberation fontconfig \
    && rm -rf /var/lib/apt/lists/*
COPY docker/fonts-local.conf /etc/fonts/local.conf

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
COPY prompts ./prompts
COPY data ./data

RUN useradd --create-home devis && chown -R devis /app
USER devis
EXPOSE 8000
HEALTHCHECK CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/v1/health')" || exit 1
CMD ["python", "-m", "uvicorn", "app.main:build", "--factory", "--host", "0.0.0.0", "--port", "8000", "--no-access-log", "--proxy-headers"]
