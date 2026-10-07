"""Rend tous les devis d'exemple (shared/fixtures/) en .docx et .pdf dans server/out/.

Usage (depuis le dossier server/) : python -m scripts.render_fixtures
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from app.config import SERVER_DIR, load_companies
from app.models import Quote
from app.render_docx import render_docx
from app.render_pdf import PdfError, docx_to_pdf

FIXTURES = SERVER_DIR.parent / "shared" / "fixtures"
OUT = SERVER_DIR / "out"


def main() -> int:
    OUT.mkdir(exist_ok=True)
    companies = load_companies()
    for path in sorted(FIXTURES.glob("*.json")):
        quote = Quote.model_validate(json.loads(path.read_text(encoding="utf-8")))
        docx = render_docx(quote, companies[quote.company_id], draft=True)
        (OUT / f"{path.stem}.docx").write_bytes(docx)
        try:
            pdf = docx_to_pdf(docx)
        except PdfError as e:
            print(f"{path.stem}: docx OK, PDF impossible : {e}")
            continue
        (OUT / f"{path.stem}.pdf").write_bytes(pdf)
        print(f"{path.stem}: docx {len(docx) // 1024} Ko, pdf {len(pdf) // 1024} Ko")
    return 0


if __name__ == "__main__":
    sys.exit(main())
