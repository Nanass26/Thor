"""Orchestration d'un message du chat : extraction (images) → rédaction/modification → garde-fous → diff.

Le serveur ne stocke rien : il reçoit le devis courant et renvoie le devis modifié.
"""

from __future__ import annotations

import re
from datetime import date as Date
from typing import Callable, Optional

from .config import Company
from .llm import ImageIn, LLMClient, LLMError, LLMOutputError, RespondContext
from .models import (
    DEFAULT_INTRO,
    DEFAULT_VALIDITY_DAYS,
    Advice,
    ChatRequest,
    ChatResponse,
    ClientSheet,
    Op,
    Quote,
    RespondOutput,
    compute_missing,
)
from .ops import OpsError, apply_ops, diff_quotes, finalize, price_change_allowed, unrequested_price_ops
from .prices import build_price_range, find_comparables, mo_ratio_sentence

PRICE_QUESTION = "Quel prix TTC veux-tu indiquer ?"
PRICE_REFUSED = (
    "Je n'ai rien modifié : le prix ne peut changer que si tu donnes toi-même le montant dans ton message "
    "(ex. « mets 3 500 TTC »)."
)
PRICE_DROPPED = "Je n'ai pas mis de prix : c'est toi qui le fixes."

_SURFACE_RE = re.compile(r"(\d+(?:[.,]\d+)?)\s*m(?:²|2)\b")


def _surface(sheet: Optional[ClientSheet], *texts: Optional[str]) -> Optional[float]:
    if sheet and sheet.surface_m2:
        return sheet.surface_m2
    for t in texts:
        m = _SURFACE_RE.search(t or "")
        if m:
            return float(m.group(1).replace(",", "."))
    return None


def _trade_text(req: ChatRequest, sheet: Optional[ClientSheet], quote: Optional[Quote]) -> str:
    parts = [req.message.text or ""]
    if sheet:
        parts.append(sheet.job_summary or "")
    if quote:
        parts += [quote.title, " ".join(lot.title for lot in quote.lots)]
    return " ".join(parts)


def _guess_mode(text: str, quote: Optional[Quote]) -> str:
    t = text.lower()
    if "mo seule" in t or "main-d'œuvre seule" in t or "main d'oeuvre seule" in t or "main-d’œuvre seule" in t:
        return "main_oeuvre_seule"
    return quote.mode if quote else "complet"


def _with_question(questions: list[str], q: str) -> list[str]:
    return questions if q in questions else [*questions, q]


class ChatOrchestrator:
    def __init__(
        self,
        llm: LLMClient,
        companies: dict[str, Company],
        history: list[dict],
        charge: Callable[[int], None] = lambda n: None,
        today: Callable[[], Date] = Date.today,
    ):
        self.llm = llm
        self.companies = companies
        self.history = history
        self.charge = charge  # compte les appels à l'IA (plafond quotidien)
        self.today = today

    @property
    def labels(self) -> dict[str, str]:
        return {cid: c.label for cid, c in self.companies.items()}

    def extract(self, text: Optional[str], images: list[ImageIn]) -> ClientSheet:
        self.charge(1)
        return self.llm.extract(text, images)

    def handle(self, req: ChatRequest, images: list[ImageIn]) -> ChatResponse:
        user_text = req.message.text or ""
        sheet = self.extract(user_text, images) if images else None
        quote = req.quote
        comparables = find_comparables(
            self.history,
            _trade_text(req, sheet, quote),
            _surface(sheet, user_text, quote.title if quote else None),
            _guess_mode(user_text, quote),
        )
        ctx = RespondContext(
            user_text=user_text,
            company_id=req.company_id,
            companies=[c.public() for c in self.companies.values()],
            today=self.today(),
            quote=quote,
            client_sheet=sheet,
            has_images=bool(images),
            history_summary=req.history_summary,
            comparables=comparables,
            mo_ratio_sentence=mo_ratio_sentence(self.history),
        )

        last_error: Optional[Exception] = None
        for _attempt in range(2):  # une seule relance en cas de réponse invalide
            self.charge(1)
            try:
                out = self.llm.respond(ctx)
                return self._process(out, req, sheet, comparables)
            except (LLMOutputError, OpsError) as e:
                last_error = e
                ctx.previous_error = "; ".join(getattr(e, "errors", [str(e)])[:5])
        if isinstance(last_error, OpsError):
            return ChatResponse(
                intent="question",
                assistant_text="Je n'ai pas pu appliquer cette modification ("
                + "; ".join(last_error.errors[:3])
                + "). Rien n'a été changé : peux-tu reformuler ?",
                client_sheet=sheet,
            )
        raise LLMError("L'IA a renvoyé deux réponses invalides de suite. Réessaie ou reformule ta demande.")

    # -- Traitement de la sortie du modèle --------------------------------------------------

    def _process(self, out: RespondOutput, req: ChatRequest, sheet: Optional[ClientSheet], comparables: list[dict]) -> ChatResponse:
        user_text = req.message.text or ""
        old = req.quote
        questions = list(out.questions)
        notes: list[str] = []
        new_quote: Optional[Quote] = None
        changes: list[str] = []
        intent = out.intent

        if intent == "new":
            if out.quote is None:
                raise LLMOutputError(["intent « new » sans devis"])
            new_quote = self._build_new_quote(out, req)
            if new_quote.price.amount_ttc is not None and not price_change_allowed(user_text, None, new_quote.price.amount_ttc):
                # Garde-fou 3 : un prix que l'utilisateur n'a pas donné n'entre jamais dans le devis.
                new_quote.price.amount_ttc = None
                new_quote.missing = compute_missing(new_quote)
                notes.append(PRICE_DROPPED)
                questions = _with_question(questions, PRICE_QUESTION)
            if old is not None:
                changes = diff_quotes(old, new_quote, self.labels)

        elif intent == "modify":
            if old is None:
                return ChatResponse(
                    intent="question",
                    assistant_text="Il n'y a pas encore de devis à modifier : décris-moi d'abord les travaux.",
                    client_sheet=sheet,
                )
            ops = list(out.ops)
            if unrequested_price_ops(ops, old.price.amount_ttc, user_text):
                return ChatResponse(
                    intent="question",
                    assistant_text=PRICE_REFUSED,
                    questions=[PRICE_QUESTION],
                    client_sheet=sheet,
                )
            mode_ops = [o for o in ops if o.path == "/mode" and o.value != old.mode]
            price_ops = [o for o in ops if o.path == "/price/amount_ttc"]
            if mode_ops and not price_ops:
                # Changer de mode sans nouveau prix : l'ancien prix ne vaut plus, on le remet « à définir ».
                ops.append(Op(op="replace", path="/price/amount_ttc", value=None))
            if not ops:
                raise LLMOutputError(["intent « modify » sans opération"])
            new_quote = finalize(old, apply_ops(old, ops))
            changes = diff_quotes(old, new_quote, self.labels)

        # Conseils : fourchette fondée sur les cas réels, jamais écrite dans le devis.
        need_price = new_quote is not None and new_quote.price.amount_ttc is None
        advice = self._finish_advice(out.advice, comparables, need_price or intent == "new")

        text = out.assistant_text.strip()
        if notes:
            text = (text + " " + " ".join(notes)).strip()
        return ChatResponse(
            assistant_text=text,
            intent=intent,
            quote=new_quote,
            changes=changes,
            client_sheet=sheet,
            advice=advice,
            client_reply=out.client_reply or None,
            questions=questions,
        )

    def _build_new_quote(self, out: RespondOutput, req: ChatRequest) -> Quote:
        assert out.quote is not None
        data = out.quote.model_dump(mode="json")
        data["validity_days"] = data["validity_days"] or DEFAULT_VALIDITY_DAYS
        data["intro"] = data["intro"] or DEFAULT_INTRO
        old = req.quote
        quote = Quote.model_validate({**data, "company_id": req.company_id, "date": self.today().isoformat()})
        if old is not None:
            # Réécriture complète du devis de la conversation : même identifiant, version suivante.
            quote.id = old.id
            quote.version = old.version + 1
            quote.number = old.number if old.company_id == req.company_id else None
        quote.missing = compute_missing(quote)
        return quote

    def _finish_advice(self, advice: Optional[Advice], comparables: list[dict], need_range: bool) -> Optional[Advice]:
        advice = advice.model_copy(deep=True) if advice else Advice()
        if need_range or advice.price_range is not None:
            advice.price_range = build_price_range(comparables, advice.price_range)
        if advice.price_range is None and not advice.risks and not advice.questions:
            return None
        return advice
