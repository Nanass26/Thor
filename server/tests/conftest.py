import json
import shutil
from pathlib import Path

import pytest

from app.config import load_companies
from app.models import Quote

FIXTURES = Path(__file__).resolve().parents[2] / "shared" / "fixtures"
FIXTURE_NAMES = sorted(p.stem for p in FIXTURES.glob("*.json"))
HAS_SOFFICE = bool(shutil.which("soffice") or shutil.which("libreoffice"))
HAS_POPPLER = bool(shutil.which("pdftotext") and shutil.which("pdfinfo"))


def load_fixture(name: str) -> Quote:
    return Quote.model_validate(json.loads((FIXTURES / f"{name}.json").read_text(encoding="utf-8")))


@pytest.fixture
def companies():
    return load_companies()


@pytest.fixture
def ref_quote() -> Quote:
    """Devis de référence : MO seule, 53 m², 3 000 € TTC."""
    return load_fixture("mo_seule_appartement_53m2")


def tiny_png(width: int = 40, height: int = 30) -> bytes:
    """Petite image PNG valide (couleur unie), générée sans dépendance."""
    import struct
    import zlib

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes((46, 111, 142)) * width for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


# --- Serveur de test (mode mock) ----------------------------------------------------------------

TOKEN = "jeton-de-test"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


def fake_jpeg(marker: bytes = b"") -> bytes:
    """Octets commençant comme un JPEG (le serveur ne vérifie que l'en-tête), avec un marqueur pour le simulateur."""
    return b"\xff\xd8\xff\xe0\x00\x10JFIF\x00" + marker + b"\x00" * 64 + b"\xff\xd9"


def b64(data: bytes) -> str:
    import base64

    return base64.b64encode(data).decode()


def make_client(llm=None, **overrides):
    from fastapi.testclient import TestClient

    from app.config import Settings
    from app.main import create_app

    settings = Settings(mock_llm=llm is None, app_token=TOKEN, **overrides)
    if llm is not None:
        settings.mock_llm = False
    return TestClient(create_app(settings, llm=llm))


@pytest.fixture
def client():
    return make_client()


def post_chat(client, text, quote=None, images=(), company="levix", expect=200):
    body = {"message": {"text": text, "images": [b64(i) for i in images]}, "company_id": company}
    if quote is not None:
        body["quote"] = quote.model_dump(mode="json")
    r = client.post("/v1/chat", json=body, headers=AUTH)
    assert r.status_code == expect, r.text
    return r.json()
