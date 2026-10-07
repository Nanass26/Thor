"""Serveur FastAPI DevisChat : routes, authentification, limites, journal sans contenu.

Lancement : ./server/run_server.sh (ou `make server`, `make demo`).
"""

from __future__ import annotations

import base64
import binascii
import hmac
import json
import logging
import re
import threading
import time
import unicodedata
from datetime import date as Date
from typing import Callable, Optional
from urllib.parse import quote as url_quote

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response

from . import __version__
from .config import Company, Settings, load_companies
from .llm import AnthropicLLM, ImageIn, LLMClient, LLMError, MockLLM
from .models import ChatRequest, ExtractRequest, Quote, RenderRequest, compute_missing
from .orchestrator import ChatOrchestrator
from .prices import load_history
from .render_docx import RenderError, render_docx
from .render_pdf import PdfError, docx_to_pdf, find_soffice

log = logging.getLogger("devischat")
if not log.handlers:
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(handler)
    log.setLevel(logging.INFO)

DOCX_MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
MAX_IMAGE_BYTES = 5 * 1024 * 1024  # limite de l'API par image


class QuotaExceeded(Exception):
    pass


class DailyQuota:
    """Plafond d'appels à l'IA par jour (en mémoire, remis à zéro au changement de date)."""

    def __init__(self, cap: int, today: Callable[[], Date] = Date.today):
        self.cap = cap
        self.today = today
        self.day = today()
        self.count = 0
        self._lock = threading.Lock()

    def charge(self, n: int = 1) -> None:
        with self._lock:
            now = self.today()
            if now != self.day:
                self.day, self.count = now, 0
            if self.count + n > self.cap:
                raise QuotaExceeded()
            self.count += n


# --- Images -----------------------------------------------------------------------------------


def decode_image(item: str) -> ImageIn:
    data_url = re.match(r"^data:[\w/+.-]+;base64,", item)
    if data_url:
        item = item[data_url.end():]
    try:
        data = base64.b64decode(item, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(400, "Image illisible (base64 invalide).") from None
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(400, "Image trop lourde (5 Mo maximum par image).")
    if data[:3] == b"\xff\xd8\xff":
        return ImageIn(data, "image/jpeg")
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return ImageIn(data, "image/png")
    if data[4:12] in (b"ftypheic", b"ftypheix", b"ftypmif1", b"ftyphevc"):
        raise HTTPException(400, "Format HEIC non accepté : l'app doit convertir la photo en JPEG.")
    raise HTTPException(400, "Format d'image non accepté (JPEG attendu).")


def decode_images(items: list[str], max_images: int) -> list[ImageIn]:
    if len(items) > max_images:
        raise HTTPException(400, f"Trop d'images : {max_images} maximum par message.")
    return [decode_image(i) for i in items]


# --- Nom de fichier ---------------------------------------------------------------------------


def _slug(text: Optional[str], max_len: int = 40) -> str:
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = re.sub(r"[^\w\s-]", " ", text)
    text = re.sub(r"[\s_-]+", "_", text).strip("_")
    return text[:max_len].strip("_")


def quote_filename(quote: Quote, company: Company, ext: str) -> str:
    """Devis_{entreprise}_{client}_{objet}.ext, sans caractère interdit."""
    parts = ["Devis", _slug(company.label, 20), _slug(quote.client.name, 25), _slug(quote.title, 40)]
    return "_".join(p for p in parts if p) + f".{ext}"


def _attachment(data: bytes, media_type: str, filename: str) -> Response:
    ascii_name = filename.encode("ascii", "ignore").decode() or "devis"
    disposition = f'attachment; filename="{ascii_name}"; filename*=UTF-8\'\'{url_quote(filename)}'
    return Response(content=data, media_type=media_type, headers={"Content-Disposition": disposition})


# --- Middleware : taille du corps, journal, erreurs ---------------------------------------------


class _BodyTooLarge(Exception):
    pass


class GuardMiddleware:
    """Limite la taille du corps, journalise (méthode, route, statut, durée, taille) et masque les erreurs.

    Le journal ne contient JAMAIS le contenu des messages, des images ni des champs client.
    """

    def __init__(self, app, max_body_bytes: int):
        self.app = app
        self.max_body = max_body_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        start = time.monotonic()
        state = {"status": 0, "started": False, "received": 0}

        async def send_json(status: int, message: str):
            body = json.dumps({"error": message}, ensure_ascii=False).encode()
            await send({"type": "http.response.start", "status": status,
                        "headers": [(b"content-type", b"application/json; charset=utf-8"),
                                    (b"content-length", str(len(body)).encode())]})
            await send({"type": "http.response.body", "body": body})
            state["status"] = status

        async def limited_receive():
            message = await receive()
            if message["type"] == "http.request":
                state["received"] += len(message.get("body", b""))
                if state["received"] > self.max_body:
                    raise _BodyTooLarge()
            return message

        async def tracking_send(message):
            if message["type"] == "http.response.start":
                state["started"] = True
                state["status"] = message["status"]
            await send(message)

        too_large = f"Requête trop volumineuse ({self.max_body // (1024 * 1024)} Mo maximum)."
        headers = dict(scope.get("headers") or [])
        length = headers.get(b"content-length")
        try:
            if length is not None and int(length) > self.max_body:
                await send_json(413, too_large)
            else:
                await self.app(scope, limited_receive, tracking_send)
        except _BodyTooLarge:
            if not state["started"]:
                await send_json(413, too_large)
        except Exception as exc:  # aucune trace ni contenu dans la réponse ou le journal
            log.error("erreur interne %s sur %s %s", type(exc).__name__, scope.get("method"), scope.get("path"))
            if not state["started"]:
                await send_json(500, "Erreur interne du serveur.")
        finally:
            ms = int((time.monotonic() - start) * 1000)
            log.info("%s %s %s %dms %do", scope.get("method"), scope.get("path"), state["status"], ms, state["received"])


# --- Application ------------------------------------------------------------------------------


def create_app(settings: Optional[Settings] = None, llm: Optional[LLMClient] = None) -> FastAPI:
    settings = settings or Settings.load()
    if not settings.mock_llm:
        if not settings.app_token:
            raise RuntimeError(
                "APP_TOKEN manquant dans server/.env : le serveur refuse de démarrer en mode live. "
                "Génère-le avec : python3 -c \"import secrets;print(secrets.token_urlsafe(32))\""
            )
        if llm is None and not settings.anthropic_api_key:
            raise RuntimeError("ANTHROPIC_API_KEY manquante dans server/.env (ou lance le mode démo : MOCK_LLM=1).")
    if llm is None:
        llm = MockLLM() if settings.mock_llm else AnthropicLLM(settings)

    companies = load_companies(settings.data_dir)
    history = load_history(settings.data_dir)
    quota = DailyQuota(settings.daily_call_cap)
    soffice = find_soffice(settings.soffice_bin)

    def charge(n: int) -> None:
        quota.charge(n)

    orchestrator = ChatOrchestrator(llm, companies, history, charge=charge)

    app = FastAPI(title="DevisChat", version=__version__, docs_url=None, redoc_url=None, openapi_url=None)
    app.add_middleware(GuardMiddleware, max_body_bytes=settings.max_body_mb * 1024 * 1024)
    app.state.settings = settings
    app.state.quota = quota
    app.state.orchestrator = orchestrator

    @app.exception_handler(HTTPException)
    async def http_error(_request: Request, exc: HTTPException):
        return JSONResponse({"error": str(exc.detail)}, status_code=exc.status_code)

    @app.exception_handler(RequestValidationError)
    async def validation_error(_request: Request, exc: RequestValidationError):
        details = []
        for err in exc.errors()[:5]:
            loc = "/".join(str(x) for x in err.get("loc", ()) if x != "body")
            msg = err.get("msg", "valeur invalide")
            details.append(f"{loc} : {msg.removeprefix('Value error, ')}")
        return JSONResponse({"error": "Requête invalide — " + " ; ".join(details)}, status_code=422)

    def check_token(authorization: Optional[str]) -> None:
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(401, "Jeton manquant : renseigne le jeton dans les Réglages de l'app.")
        given = authorization[len("Bearer "):].strip().encode()
        if not hmac.compare_digest(given, settings.app_token.encode()):
            raise HTTPException(401, "Jeton refusé : vérifie le jeton dans les Réglages de l'app.")

    def require_token(authorization: Optional[str] = Header(default=None)) -> None:
        check_token(authorization)

    def company_of(quote: Quote) -> Company:
        company = companies.get(quote.company_id)
        if company is None:
            raise HTTPException(400, f"Entreprise inconnue : {quote.company_id}.")
        return company

    def decode_cover(b64: Optional[str]) -> Optional[bytes]:
        return decode_image(b64).data if b64 else None

    @app.get("/v1/health")
    def health(authorization: Optional[str] = Header(default=None)):
        if authorization is None:
            return {"ok": True}
        check_token(authorization)
        return {"ok": True, "mode": settings.mode, "soffice": soffice is not None, "version": __version__}

    @app.get("/v1/companies", dependencies=[Depends(require_token)])
    def list_companies():
        return [c.public() for c in companies.values()]

    @app.post("/v1/extract", dependencies=[Depends(require_token)])
    def extract(req: ExtractRequest):
        images = decode_images(req.images, settings.max_images)
        if not images:
            raise HTTPException(400, "Aucune image à lire.")
        try:
            sheet = orchestrator.extract(req.text, images)
        except QuotaExceeded:
            raise HTTPException(429, quota_message()) from None
        except LLMError as e:
            raise HTTPException(502, str(e)) from None
        return sheet.model_dump(mode="json")

    def quota_message() -> str:
        return f"Plafond quotidien d'appels à l'IA atteint ({settings.daily_call_cap}). Il sera remis à zéro à minuit."

    @app.post("/v1/chat", dependencies=[Depends(require_token)])
    def chat(req: ChatRequest):
        if req.company_id not in companies:
            raise HTTPException(400, f"Entreprise inconnue : {req.company_id}.")
        images = decode_images(req.message.images, settings.max_images)
        if not (req.message.text or "").strip() and not images:
            raise HTTPException(400, "Message vide : écris un texte ou ajoute une image.")
        try:
            resp = orchestrator.handle(req, images)
        except QuotaExceeded:
            raise HTTPException(429, quota_message()) from None
        except LLMError as e:
            raise HTTPException(502, str(e)) from None
        return JSONResponse(resp.model_dump(mode="json"))

    def prepared(req: RenderRequest) -> tuple[Quote, Company, Optional[bytes]]:
        company = company_of(req.quote)
        quote = req.quote.model_copy(update={"missing": compute_missing(req.quote)})
        return quote, company, decode_cover(req.cover_photo_b64)

    @app.post("/v1/render/docx", dependencies=[Depends(require_token)])
    def render_docx_route(req: RenderRequest, draft: bool = False):
        quote, company, cover = prepared(req)
        try:
            data = render_docx(quote, company, cover_photo=cover, draft=draft)
        except RenderError as e:
            raise HTTPException(400, str(e)) from None
        return _attachment(data, DOCX_MIME, quote_filename(quote, company, "docx"))

    @app.post("/v1/render/pdf", dependencies=[Depends(require_token)])
    def render_pdf_route(req: RenderRequest, draft: bool = False):
        if soffice is None:
            raise HTTPException(503, "LibreOffice n'est pas installé sur le serveur.")
        quote, company, cover = prepared(req)
        try:
            pdf = docx_to_pdf(render_docx(quote, company, cover_photo=cover, draft=draft), soffice)
        except RenderError as e:
            raise HTTPException(400, str(e)) from None
        except PdfError as e:
            raise HTTPException(500, str(e)) from None
        return _attachment(pdf, "application/pdf", quote_filename(quote, company, "pdf"))

    return app


def build() -> FastAPI:
    """Point d'entrée d'uvicorn (`uvicorn app.main:build --factory`) : message clair si la config est incomplète."""
    try:
        return create_app()
    except RuntimeError as e:
        log.error("%s", e)
        raise SystemExit(1) from None
