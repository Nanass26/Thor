"""Comparables de prix tirés de l'historique réel (price_history.json).

Aucune moyenne inventée : on renvoie les cas réels les plus proches, avec leur identifiant.
"""

from __future__ import annotations

import json
import re
import statistics
import unicodedata
from pathlib import Path
from typing import Optional

from .config import DATA_DIR
from .models import PriceRange
from .typo import format_percent

GENERIC_NOTE = (
    "Peu de données. Les estimations génériques sont souvent au-dessus de tes prix réels "
    "(écarts de −15 % à −58 % observés sur ton historique)."
)

_STOPWORDS = {
    "les", "des", "une", "pour", "sur", "avec", "dans", "par", "aux", "sans", "plus", "tout", "tous",
    "complet", "complete", "travaux", "lot", "lots", "devis", "prix", "ttc", "faire", "refaire",
    "environ", "chez", "etage", "remplacement", "creation", "pose", "fourniture", "fais", "moi",
    # Les pièces ne sont pas un corps d'état (« chambre » ≠ « chambre froide »)
    "salon", "chambre", "couloir", "sejour", "entree", "piece",
}
_SYNONYMS = {"appart": "appartement", "apt": "appartement", "elec": "electricite", "reno": "renovation"}


def normalize(text: Optional[str]) -> str:
    """Minuscules, sans accents, apostrophes typographiques remplacées : pour comparer des mots."""
    text = (text or "").replace("’", "'").replace("œ", "oe").replace("Œ", "oe")
    text = unicodedata.normalize("NFKD", text)
    return "".join(c for c in text if not unicodedata.combining(c)).lower()


def keywords(text: Optional[str]) -> set[str]:
    words = set()
    for w in re.findall(r"[a-z]+", normalize(text)):
        w = _SYNONYMS.get(w, w)
        if len(w) < 3 or w in _STOPWORDS:
            continue
        if len(w) > 4 and w[-1] in "sx":
            w = w[:-1]  # pluriel très simple : plafonds → plafond
        words.add(w)
    return words


def load_history(data_dir: Path = DATA_DIR) -> list[dict]:
    """price_history.json (réel, gitignoré) sinon l'exemple."""
    path = data_dir / "price_history.json"
    if not path.exists():
        path = data_dir / "price_history.example.json"
    return json.loads(path.read_text(encoding="utf-8"))


def history_stats(history: list[dict]) -> dict:
    values = [h["ttc"] for h in history]
    return {
        "count": len(values),
        "total": sum(values),
        "median": statistics.median(values),
        "min": min(values),
        "max": max(values),
    }


def find_comparables(
    history: list[dict],
    trade_text: str,
    surface_m2: Optional[float],
    mode: Optional[str],
    limit: int = 3,
) -> list[dict]:
    """0 à 3 chantiers réels proches : même corps d'état (mots-clés), même mode, surface à ±40 %."""
    wanted = keywords(trade_text)
    scored = []
    for h in history:
        if mode and h.get("mode") != mode:
            continue
        overlap = len(wanted & keywords(h.get("trade")))
        if overlap == 0:
            continue
        score = overlap * 10
        hs = h.get("surface_m2")
        if surface_m2 and hs:
            if not 0.6 * surface_m2 <= hs <= 1.4 * surface_m2:
                continue
            score += 5
        scored.append((-score, h["id"], h))
    scored.sort(key=lambda x: (x[0], x[1]))
    return [h for _, _, h in scored[:limit]]


def mo_ratio(history: list[dict]) -> Optional[dict]:
    """Part de la main-d'œuvre seule dans le prix complet, sur des chantiers chiffrés dans les deux modes."""
    pairs = []
    by_key: dict[tuple, dict[str, dict]] = {}
    for h in history:
        key = (normalize(h.get("trade")), h.get("surface_m2"))
        by_key.setdefault(key, {})[h.get("mode")] = h
    for modes in by_key.values():
        if "complet" in modes and "main_oeuvre_seule" in modes:
            full, labour = modes["complet"], modes["main_oeuvre_seule"]
            pairs.append((labour["ttc"] / full["ttc"], full["id"], labour["id"]))
    if not pairs:
        return None
    ratio = statistics.median(p[0] for p in pairs)
    ids = [i for p in pairs for i in p[1:]]
    return {"ratio": round(ratio, 2), "percent": round(ratio * 100), "ids": ids}


def mo_ratio_sentence(history: list[dict]) -> Optional[str]:
    info = mo_ratio(history)
    if not info:
        return None
    return (
        f"Dans ton historique, la MO seule représente environ {format_percent(info['percent'])} "
        f"du complet sur un chantier comparable ({' / '.join(info['ids'])})."
    )


def build_price_range(comparables: list[dict], llm_range: Optional[PriceRange]) -> PriceRange:
    """Fourchette indicative : cas réels si au moins 2 comparables, sinon estimation générique signalée."""
    if len(comparables) >= 2:
        values = [c["ttc"] for c in comparables]
        return PriceRange(
            low=min(values),
            high=max(values),
            basis="comparables",
            comparable_ids=[c["id"] for c in comparables],
            note=f"{len(comparables)} chantiers proches dans ton historique",
        )
    low = llm_range.low if llm_range else None
    high = llm_range.high if llm_range else None
    if low is None and high is None:
        return PriceRange(basis="aucune", comparable_ids=[c["id"] for c in comparables], note=GENERIC_NOTE)
    return PriceRange(
        low=low,
        high=high,
        basis="estimation_generique",
        comparable_ids=[c["id"] for c in comparables],
        note=GENERIC_NOTE,
    )
