"""Typographie française : montants, dates, pourcentages, surfaces, ponctuation.

Toutes les fonctions sont pures et idempotentes (les appliquer deux fois ne change rien).
"""

from __future__ import annotations

import re
from datetime import date as Date
from decimal import ROUND_HALF_UP, Decimal
from typing import Optional, Union

NBSP = " "  # espace insécable (avant : ; ? ! € % m²)
NNBSP = " "  # espace fine insécable (séparateur de milliers)

MONTHS = [
    "janvier", "février", "mars", "avril", "mai", "juin",
    "juillet", "août", "septembre", "octobre", "novembre", "décembre",
]

Number = Union[int, float, Decimal]


def format_number(value: Number, decimals: int = 0) -> str:
    """6500 → « 6 500 » (fine insécable) ; 5.5 avec decimals=1 → « 5,5 »."""
    quant = Decimal(1) if decimals == 0 else Decimal(1).scaleb(-decimals)
    d = Decimal(str(value)).quantize(quant, ROUND_HALF_UP)
    sign = "-" if d < 0 else ""
    int_part, _, frac = f"{abs(d):.{decimals}f}".partition(".")
    groups = []
    while len(int_part) > 3:
        groups.insert(0, int_part[-3:])
        int_part = int_part[:-3]
    groups.insert(0, int_part)
    out = NNBSP.join(groups)
    if frac:
        out += "," + frac
    return sign + out


def format_amount(value: Number, cents: bool = False) -> str:
    """3000 → « 3 000 € » ; avec cents=True → « 3 000,00 € »."""
    return format_number(value, 2 if cents else 0) + NBSP + "€"


def _short_decimal(value: Number) -> str:
    """5.5 → « 5,5 » ; 10.0 → « 10 » ; 12.25 → « 12,25 »."""
    d = Decimal(str(value)).normalize()
    if d == d.to_integral_value():
        return format_number(d, 0)
    decimals = max(0, -d.as_tuple().exponent)
    return format_number(d, min(decimals, 2))


def format_percent(value: Number) -> str:
    """10 → « 10 % » ; 5.5 → « 5,5 % »."""
    return _short_decimal(value) + NBSP + "%"


def format_surface(value: Number) -> str:
    """53 → « 53 m² »."""
    return _short_decimal(value) + NBSP + "m²"


def format_date(d: Date) -> str:
    """date(2026, 10, 7) → « 7 octobre 2026 » ; le 1er du mois → « 1er octobre 2026 »."""
    day = "1er" if d.day == 1 else str(d.day)
    return f"{day} {MONTHS[d.month - 1]} {d.year}"


# --- Texte libre -------------------------------------------------------------------

# Zones à ne jamais retoucher : URL, adresses e-mail, heures (14:05).
_PROTECT_RE = re.compile(
    r"(https?://\S+|www\.\S+|[\w.+-]+@[\w-]+(?:\.[\w-]+)+|\b\d{1,2}:\d{2}\b)"
)
_SPACES = "[   ]"
_AMOUNT_RE = re.compile(
    r"(?<![\d,.])(\d{1,3}(?:[ .  ]\d{3})+|\d+)(,\d{1,2})?" + _SPACES + r"?€"
)
_PERCENT_RE = re.compile(r"(\d)" + _SPACES + r"?%")
_SURFACE_RE = re.compile(r"(\d)" + _SPACES + r"?m(?:²|2)(?!\w)")
_HIGH_PUNCT_RE = re.compile(r"(?<=[^\s:;?!«])\s?([:;?!]+)")


def _fix_amount(m: re.Match) -> str:
    digits = re.sub(r"\D", "", m.group(1))
    out = format_number(int(digits))
    if m.group(2):
        out += m.group(2)
    return out + NBSP + "€"


def _fr_chunk(text: str) -> str:
    text = re.sub(r"[ ]{2,}", " ", text)
    text = text.replace("'", "’")
    text = re.sub(r'"([^"\n]+)"', lambda m: "«" + NBSP + m.group(1).strip() + NBSP + "»", text)
    text = re.sub("«" + _SPACES + "*", "«" + NBSP, text)
    text = re.sub(_SPACES + "*»", NBSP + "»", text)
    text = _HIGH_PUNCT_RE.sub(lambda m: NBSP + m.group(1), text)
    text = _AMOUNT_RE.sub(_fix_amount, text)
    text = _PERCENT_RE.sub(lambda m: m.group(1) + NBSP + "%", text)
    text = _SURFACE_RE.sub(lambda m: m.group(1) + NBSP + "m²", text)
    return text


def fr_text(text: Optional[str]) -> Optional[str]:
    """Applique la typographie française à un texte libre (sans toucher URL, e-mails, heures)."""
    if not text:
        return text
    parts = _PROTECT_RE.split(text)
    # Avec un groupe capturant, les indices impairs sont les zones protégées.
    return "".join(part if i % 2 else _fr_chunk(part) for i, part in enumerate(parts))


def plain_spaces(text: str) -> str:
    """Remplace les espaces insécables par des espaces normaux (utile pour comparer dans les tests)."""
    return text.replace(NBSP, " ").replace(NNBSP, " ")
