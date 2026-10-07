"""Conversion .docx → .pdf avec LibreOffice (mode sans interface).

Chaque conversion utilise son propre dossier temporaire ET son propre profil LibreOffice :
sans ça, deux conversions simultanées se bloquent mutuellement.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Optional

MAC_SOFFICE = "/Applications/LibreOffice.app/Contents/MacOS/soffice"
TIMEOUT_S = 60


class PdfError(Exception):
    pass


def find_soffice(configured: str = "") -> Optional[str]:
    """Chemin de LibreOffice : SOFFICE_BIN, sinon le PATH, sinon l'emplacement macOS habituel."""
    candidates = [configured, os.environ.get("SOFFICE_BIN", ""), shutil.which("soffice") or "",
                  shutil.which("libreoffice") or "", MAC_SOFFICE]
    for c in candidates:
        if c and Path(c).is_file() and os.access(c, os.X_OK):
            return c
    return None


def docx_to_pdf(docx_bytes: bytes, soffice: Optional[str] = None) -> bytes:
    binary = soffice or find_soffice()
    if not binary:
        raise PdfError("LibreOffice n'est pas installé sur le serveur.")
    workdir = Path(tempfile.mkdtemp(prefix="devis_"))
    profile = Path(tempfile.gettempdir()) / f"lo_{uuid.uuid4().hex}"
    try:
        src = workdir / "devis.docx"
        src.write_bytes(docx_bytes)
        cmd = [
            binary,
            f"-env:UserInstallation={profile.as_uri()}",
            "--headless", "--norestore", "--nolockcheck",
            "--convert-to", "pdf", "--outdir", str(workdir), str(src),
        ]
        try:
            subprocess.run(cmd, capture_output=True, timeout=TIMEOUT_S, check=False)
        except subprocess.TimeoutExpired:
            raise PdfError("La conversion PDF a pris trop de temps (plus de 60 s).") from None
        pdf = workdir / "devis.pdf"
        if not pdf.exists():
            raise PdfError("La conversion PDF a échoué (LibreOffice n'a produit aucun fichier).")
        return pdf.read_bytes()
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
        shutil.rmtree(profile, ignore_errors=True)
