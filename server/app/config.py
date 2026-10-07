"""Configuration du serveur (fichier server/.env + variables d'environnement) et profils d'entreprise."""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

SERVER_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = SERVER_DIR / "data"
PROMPTS_DIR = SERVER_DIR / "prompts"


def load_env_file(path: Path) -> dict[str, str]:
    """Lit un fichier .env simple (CLE=valeur, commentaires # autorisés). Pas de dépendance externe."""
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if value[:1] in ("'", '"') and value[-1:] == value[:1] and len(value) >= 2:
            value = value[1:-1]
        else:
            value = re.split(r"\s+#", value, maxsplit=1)[0].strip()
        values[key.strip()] = value
    return values


def _flag(value: str) -> bool:
    return value.strip().lower() in ("1", "true", "yes", "oui", "on")


@dataclass
class Settings:
    anthropic_api_key: str = ""
    model_respond: str = "claude-opus-5-5"
    model_extract: str = "claude-sonnet-5-5"
    effort_respond: str = "medium"
    effort_extract: str = "low"
    llm_fallback: bool = True
    app_token: str = ""
    mock_llm: bool = False
    soffice_bin: str = ""
    daily_call_cap: int = 300
    max_images: int = 6
    max_body_mb: int = 20
    data_dir: Path = field(default_factory=lambda: DATA_DIR)

    @property
    def mode(self) -> str:
        return "mock" if self.mock_llm else "live"

    @classmethod
    def load(cls, env_file: Optional[Path] = None) -> "Settings":
        """Variables d'environnement > fichier server/.env > valeurs par défaut."""
        file_values = load_env_file(env_file or SERVER_DIR / ".env")

        def get(key: str, default: str = "") -> str:
            return os.environ.get(key, file_values.get(key, default))

        mock = _flag(get("MOCK_LLM", "0"))
        token = get("APP_TOKEN")
        if mock and not token:
            token = "demo"  # mode démo : même jeton que l'app lancée avec -DEMO
        return cls(
            anthropic_api_key=get("ANTHROPIC_API_KEY"),
            model_respond=get("MODEL_RESPOND") or cls.model_respond,
            model_extract=get("MODEL_EXTRACT") or cls.model_extract,
            effort_respond=get("EFFORT_RESPOND") or cls.effort_respond,
            effort_extract=get("EFFORT_EXTRACT") or cls.effort_extract,
            llm_fallback=_flag(get("LLM_FALLBACK", "1")),
            app_token=token,
            mock_llm=mock,
            soffice_bin=get("SOFFICE_BIN"),
            daily_call_cap=int(get("DAILY_CALL_CAP") or 300),
            max_images=int(get("MAX_IMAGES") or 6),
            max_body_mb=int(get("MAX_BODY_MB") or 20),
        )


# --- Profils d'entreprise -----------------------------------------------------------

LEGAL_FIELDS = ("legal_form", "siret", "naf", "address", "insurance_text")


@dataclass
class Company:
    id: str
    label: str
    tagline: str = ""
    legal_form: str = ""
    siret: str = ""
    naf: str = ""
    address: str = ""
    email: str = ""
    phone: str = ""
    insurance_text: str = ""
    font: str = "American Typewriter"
    accent_color: str = "2E6F8E"

    def legal_problems(self) -> list[str]:
        """Champs légaux vides ou manifestement factices (le devis sera alors un brouillon)."""
        problems = [f for f in LEGAL_FIELDS if not getattr(self, f).strip()]
        digits = re.sub(r"\D", "", self.siret)
        if self.siret.strip() and (len(digits) != 14 or len(set(digits)) == 1):
            problems.append("siret")
        joined = " ".join(getattr(self, f) for f in LEGAL_FIELDS).lower()
        if "factice" in joined or "exemple" in joined:
            problems.append("valeurs factices")
        return sorted(set(problems))

    @property
    def is_complete(self) -> bool:
        return not self.legal_problems()

    def public(self) -> dict[str, str]:
        return {"id": self.id, "label": self.label, "tagline": self.tagline}


def load_companies(data_dir: Path = DATA_DIR) -> dict[str, Company]:
    """Charge companies.json (vrai, gitignoré) sinon companies.example.json (factice)."""
    path = data_dir / "companies.json"
    if not path.exists():
        path = data_dir / "companies.example.json"
    raw = json.loads(path.read_text(encoding="utf-8"))
    allowed = set(Company.__dataclass_fields__)
    companies = {}
    for entry in raw:
        company = Company(**{k: str(v) for k, v in entry.items() if k in allowed})
        companies[company.id] = company
    return companies
