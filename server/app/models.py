"""Modèle de données du devis — source de vérité (miroir Codable côté iOS).

Un devis = des données JSON validées. Le fichier Word/PDF est produit ensuite
par un moteur de rendu déterministe (render_docx.py), jamais par le LLM.
"""

from __future__ import annotations

import uuid
from datetime import date as Date
from decimal import ROUND_HALF_UP, Decimal
from typing import Annotated, Any, Literal, Optional

from pydantic import (
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    StrictBool,
    field_serializer,
    model_validator,
)

SCHEMA_VERSION = 1
DEFAULT_INTRO = "Nous avons le plaisir de vous présenter notre devis pour les travaux décrits ci-dessous."
DEFAULT_VALIDITY_DAYS = 30
ALLOWED_VAT = (5.5, 10.0, 20.0)

Status = Literal["draft", "validated", "sent"]
Mode = Literal["complet", "main_oeuvre_seule"]
Intent = Literal["new", "modify", "question", "client_reply_only"]


# --- Validateurs réutilisables -------------------------------------------------


def _blank_to_none(v: Any) -> Any:
    """Une chaîne vide ou faite d'espaces est traitée comme « absente »."""
    if isinstance(v, str) and not v.strip():
        return None
    return v


def _strict_euros(v: Any) -> Optional[int]:
    """Montant en euros entiers. Refuse les textes et les booléens (pas de conversion silencieuse)."""
    if v is None:
        return None
    if isinstance(v, bool):
        raise ValueError("le montant doit être un nombre entier d'euros")
    if isinstance(v, int):
        amount = v
    elif isinstance(v, float) and v.is_integer():
        amount = int(v)
    else:
        raise ValueError("le montant doit être un nombre entier d'euros")
    if amount < 0:
        raise ValueError("le montant ne peut pas être négatif")
    if amount > 10_000_000:
        raise ValueError("montant irréaliste")
    return amount


def _vat_rate(v: Any) -> Optional[float]:
    if v is None:
        return None
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise ValueError("taux de TVA invalide (5,5, 10 ou 20)")
    rate = float(v)
    if rate not in ALLOWED_VAT:
        raise ValueError("taux de TVA invalide (5,5, 10 ou 20)")
    return rate


def _strict_days(v: Any) -> int:
    if isinstance(v, bool) or not isinstance(v, (int, float)) or (isinstance(v, float) and not v.is_integer()):
        raise ValueError("la validité doit être un nombre entier de jours")
    days = int(v)
    if not 1 <= days <= 365:
        raise ValueError("la validité doit être comprise entre 1 et 365 jours")
    return days


def _strict_percent(v: Any) -> Optional[float]:
    if v is None:
        return None
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise ValueError("le pourcentage doit être un nombre")
    pct = float(v)
    if not 0 < pct <= 100:
        raise ValueError("le pourcentage doit être compris entre 0 et 100")
    return pct


Euros = Annotated[Optional[int], BeforeValidator(_strict_euros)]
VatRate = Annotated[Optional[float], BeforeValidator(_vat_rate)]
ValidityDays = Annotated[int, BeforeValidator(_strict_days)]
Percent = Annotated[Optional[float], BeforeValidator(_strict_percent)]


def _opt_text(max_len: int):
    return Annotated[Optional[Annotated[str, Field(max_length=max_len)]], BeforeValidator(_blank_to_none)]


ShortText = _opt_text(300)
LongText = _opt_text(2000)


def _num_out(v: Optional[float]) -> Any:
    """10.0 → 10 dans le JSON (plus lisible) ; 5.5 reste 5.5."""
    if v is None:
        return None
    return int(v) if float(v).is_integer() else v


# --- Devis ---------------------------------------------------------------------


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class ClientInfo(_Strict):
    name: ShortText = None
    email: ShortText = None
    phone: ShortText = None


class Lot(_Strict):
    title: Annotated[str, Field(min_length=1, max_length=150)]
    bullets: Optional[list[Annotated[str, Field(min_length=1, max_length=300)]]] = None
    paragraph: Optional[Annotated[str, Field(min_length=1, max_length=2000)]] = None

    @model_validator(mode="after")
    def _bullets_or_paragraph(self) -> "Lot":
        if self.bullets is not None and len(self.bullets) == 0:
            self.bullets = None
        has_bullets = self.bullets is not None
        has_paragraph = self.paragraph is not None
        if has_bullets and has_paragraph:
            raise ValueError("un lot a soit des puces, soit un paragraphe, pas les deux")
        if not has_bullets and not has_paragraph:
            raise ValueError("un lot doit avoir des puces ou un paragraphe")
        if has_bullets and len(self.bullets or []) > 8:
            raise ValueError("8 puces maximum par lot")
        return self


class Price(_Strict):
    amount_ttc: Euros = None
    vat_rate: VatRate = None

    @field_serializer("vat_rate")
    def _ser_vat(self, v: Optional[float]) -> Any:
        return _num_out(v)


class PaymentStep(_Strict):
    label: Annotated[str, Field(min_length=1, max_length=100)]
    percent: Percent = None
    amount_ttc: Euros = None

    @model_validator(mode="after")
    def _percent_or_amount(self) -> "PaymentStep":
        if (self.percent is None) == (self.amount_ttc is None):
            raise ValueError("une échéance a soit un pourcentage, soit un montant (un seul des deux)")
        return self

    @field_serializer("percent")
    def _ser_pct(self, v: Optional[float]) -> Any:
        return _num_out(v)


class Options(_Strict):
    show_price_table: StrictBool = False
    show_signatures: StrictBool = False
    cover_photo: StrictBool = False


class Quote(_Strict):
    schema_version: int = SCHEMA_VERSION
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    version: int = Field(default=1, ge=1)
    status: Status = "draft"
    company_id: Annotated[str, Field(min_length=1, max_length=50)]
    number: ShortText = None
    date: Date
    client: ClientInfo = Field(default_factory=ClientInfo)
    site_address: ShortText = None
    title: Annotated[str, Field(max_length=200)] = ""
    intro: LongText = DEFAULT_INTRO
    lots: list[Lot] = Field(default_factory=list, max_length=20)
    mode: Mode = "complet"
    price: Price = Field(default_factory=Price)
    duration: ShortText = None
    start_delay: ShortText = None
    validity_days: ValidityDays = DEFAULT_VALIDITY_DAYS
    nota: LongText = None
    payment_schedule: list[PaymentStep] = Field(default_factory=list, max_length=10)
    options: Options = Field(default_factory=Options)
    missing: list[str] = Field(default_factory=list)

    def ht_and_vat(self) -> Optional[tuple[Decimal, Decimal]]:
        """(HT, TVA) arrondis au centime, calculés à partir du TTC. None si prix ou taux absent."""
        return ht_and_vat(self.price.amount_ttc, self.price.vat_rate)

    def content_dump(self) -> dict[str, Any]:
        """Contenu comparable d'une version à l'autre (sans version ni champs calculés)."""
        return self.model_dump(mode="json", exclude={"version", "missing"})


def ht_and_vat(amount_ttc: Optional[int], vat_rate: Optional[float]) -> Optional[tuple[Decimal, Decimal]]:
    if amount_ttc is None or vat_rate is None:
        return None
    ttc = Decimal(amount_ttc)
    ht = (ttc / (Decimal(1) + Decimal(str(vat_rate)) / Decimal(100))).quantize(Decimal("0.01"), ROUND_HALF_UP)
    return ht, ttc - ht


def compute_missing(q: Quote) -> list[str]:
    """Champs obligatoires absents, en français. Déterministe : jamais laissé au LLM."""
    missing: list[str] = []
    if not q.client.name:
        missing.append("Nom du client")
    if not q.site_address:
        missing.append("Adresse du chantier")
    if not q.title:
        missing.append("Titre du devis")
    if not q.lots:
        missing.append("Description des travaux")
    if q.price.amount_ttc is None:
        missing.append("Prix")
    if q.price.vat_rate is None:
        missing.append("Taux de TVA")
    if not q.duration:
        missing.append("Durée des travaux")
    return missing


# --- Fiche client lue dans les captures ------------------------------------------


class _Lenient(BaseModel):
    """Sorties du LLM : on ignore les clés inconnues plutôt que d'échouer."""

    model_config = ConfigDict(extra="ignore", str_strip_whitespace=True)


class ClientSheet(_Lenient):
    source: ShortText = None
    client_name: ShortText = None
    client_first_name: ShortText = None
    city: ShortText = None
    postal_code: ShortText = None
    job_summary: LongText = None
    surface_m2: Optional[float] = None
    rooms: list[str] = Field(default_factory=list)
    constraints: list[str] = Field(default_factory=list)
    deadline: ShortText = None
    budget_hint: ShortText = None
    snippets: list[str] = Field(default_factory=list)
    # Constatations visibles sur des photos de chantier (ajout utile quand il n'y a pas de texte).
    observations: list[str] = Field(default_factory=list)
    uncertain: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def _limit_snippets(self) -> "ClientSheet":
        self.snippets = [s[:200] for s in self.snippets[:3]]
        return self


# --- Conseils (jamais écrits dans le devis) ----------------------------------------


class PriceRange(_Lenient):
    low: Optional[int] = None
    high: Optional[int] = None
    basis: Literal["comparables", "estimation_generique", "aucune"] = "aucune"
    comparable_ids: list[str] = Field(default_factory=list)
    note: Optional[str] = None


class Risk(_Lenient):
    label: str
    why: str


class Advice(_Lenient):
    price_range: Optional[PriceRange] = None
    risks: list[Risk] = Field(default_factory=list)
    questions: list[str] = Field(default_factory=list)


# --- Sortie structurée du LLM (étape « respond ») -----------------------------------


class QuoteDraft(_Strict):
    """Ce que le modèle a le droit de rédiger pour un nouveau devis.

    id, version, numéro, statut, date et `missing` sont fixés par le serveur.
    """

    title: Annotated[str, Field(max_length=200)] = ""
    intro: LongText = None
    lots: list[Lot] = Field(default_factory=list, max_length=20)
    mode: Mode = "complet"
    price: Price = Field(default_factory=Price)
    duration: ShortText = None
    start_delay: ShortText = None
    validity_days: Optional[ValidityDays] = None
    nota: LongText = None
    client: ClientInfo = Field(default_factory=ClientInfo)
    site_address: ShortText = None
    payment_schedule: list[PaymentStep] = Field(default_factory=list, max_length=10)
    options: Options = Field(default_factory=Options)


class Op(BaseModel):
    """Opération de modification (type JSON-Patch, restreinte à une liste blanche dans ops.py)."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    op: Literal["add", "replace", "remove", "move"]
    path: Annotated[str, Field(min_length=1, max_length=100)]
    value: Any = None
    from_: Optional[str] = Field(default=None, alias="from")


class RespondOutput(_Lenient):
    intent: Intent
    assistant_text: str
    quote: Optional[QuoteDraft] = None
    ops: list[Op] = Field(default_factory=list)
    questions: list[str] = Field(default_factory=list)
    advice: Optional[Advice] = None
    client_reply: Optional[str] = None


# --- API ----------------------------------------------------------------------------


class MessageIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    text: Optional[str] = Field(default=None, max_length=8000)
    images: list[str] = Field(default_factory=list)


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    message: MessageIn
    quote: Optional[Quote] = None
    company_id: Annotated[str, Field(min_length=1, max_length=50)]
    history_summary: Optional[str] = Field(default=None, max_length=4000)


class ChatResponse(BaseModel):
    assistant_text: str
    intent: Intent
    quote: Optional[Quote] = None
    changes: list[str] = Field(default_factory=list)
    client_sheet: Optional[ClientSheet] = None
    advice: Optional[Advice] = None
    client_reply: Optional[str] = None
    questions: list[str] = Field(default_factory=list)


class ExtractRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    text: Optional[str] = Field(default=None, max_length=8000)
    images: list[str] = Field(default_factory=list)


class RenderRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    quote: Quote
    cover_photo_b64: Optional[str] = None
