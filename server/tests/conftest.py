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
