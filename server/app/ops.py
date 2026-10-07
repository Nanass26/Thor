"""Application sécurisée des opérations de modification + diff lisible.

Règles :
- liste blanche de chemins (tout le reste est refusé) ;
- tout-ou-rien : si une seule opération est invalide, aucune n'est appliquée ;
- le prix ne change que si le montant vient du message de l'utilisateur (garde-fou 3).
"""

from __future__ import annotations

import copy
import difflib
import json
import re
from decimal import ROUND_HALF_UP, Decimal
from typing import Any, Optional

from pydantic import ValidationError

from .models import Op, Quote, compute_missing
from .typo import format_number, format_percent

FORBIDDEN_PATHS = {"/id", "/version", "/number", "/status", "/schema_version", "/missing"}

# Chemins « simples » que l'on peut remplacer (replace/add) ou effacer (remove → null).
SCALAR_PATHS = {
    "/title", "/intro", "/mode", "/duration", "/start_delay", "/validity_days", "/nota",
    "/company_id", "/site_address", "/date",
    "/price/amount_ttc", "/price/vat_rate",
    "/options/show_price_table", "/options/show_signatures", "/options/cover_photo",
    "/client/name", "/client/email", "/client/phone",
}
# Objets ou listes remplaçables d'un bloc.
WHOLE_PATHS = {"/lots", "/payment_schedule", "/options", "/client"}
# Ce que « remove » a le droit d'effacer, et la valeur « vide » correspondante.
REMOVABLE = {
    "/intro": None, "/duration": None, "/start_delay": None, "/nota": None, "/site_address": None,
    "/price/amount_ttc": None, "/price/vat_rate": None,
    "/client/name": None, "/client/email": None, "/client/phone": None,
    "/payment_schedule": [],
}
_LOT_RE = re.compile(r"^/lots/(\d+|-)$")


class OpsError(Exception):
    """Opérations refusées. `errors` contient des messages lisibles en français."""

    def __init__(self, errors: list[str]):
        self.errors = errors
        super().__init__(" ; ".join(errors))


class _OpError(Exception):
    pass


# --- Application ---------------------------------------------------------------------


def _set_path(data: dict, path: str, value: Any) -> None:
    keys = path.strip("/").split("/")
    target = data
    for key in keys[:-1]:
        target = target[key]
    target[keys[-1]] = value


def _lot_index(token: str, lots: list, allow_end: bool) -> int:
    if token == "-":
        if not allow_end:
            raise _OpError("« - » n'est utilisable que pour ajouter un lot à la fin")
        return len(lots)
    index = int(token)
    upper = len(lots) if allow_end else len(lots) - 1
    if index > upper:
        raise _OpError(f"il n'y a pas de lot n° {index} (le devis en a {len(lots)}, numérotés à partir de 0)")
    return index


def _apply_one(data: dict, op: Op) -> None:
    path = op.path
    if path in FORBIDDEN_PATHS or any(path.startswith(p + "/") for p in FORBIDDEN_PATHS):
        raise _OpError("chemin interdit (géré par l'application ou le serveur)")

    lots = data["lots"]
    if op.op == "move":
        src = _LOT_RE.match(op.from_ or "")
        dst = _LOT_RE.match(path)
        if not src or not dst or "-" in (src.group(1), dst.group(1)):
            raise _OpError("« move » sert uniquement à réordonner les lots (from /lots/i vers /lots/j)")
        i = _lot_index(src.group(1), lots, allow_end=False)
        j = _lot_index(dst.group(1), lots, allow_end=False)
        lots.insert(j, lots.pop(i))
        return

    lot_match = _LOT_RE.match(path)
    if lot_match:
        token = lot_match.group(1)
        if op.op == "add":
            if not isinstance(op.value, dict):
                raise _OpError("un lot doit être un objet {title, bullets | paragraph}")
            lots.insert(_lot_index(token, lots, allow_end=True), copy.deepcopy(op.value))
        elif op.op == "replace":
            if not isinstance(op.value, dict):
                raise _OpError("un lot doit être un objet {title, bullets | paragraph}")
            lots[_lot_index(token, lots, allow_end=False)] = copy.deepcopy(op.value)
        else:  # remove
            lots.pop(_lot_index(token, lots, allow_end=False))
        return

    if path in SCALAR_PATHS or path in WHOLE_PATHS:
        if op.op in ("replace", "add"):
            _set_path(data, path, copy.deepcopy(op.value))
        elif path in REMOVABLE:
            _set_path(data, path, copy.deepcopy(REMOVABLE[path]))
        else:
            raise _OpError("ce champ ne peut pas être supprimé, seulement remplacé")
        return

    raise _OpError("chemin non autorisé")


_TYPE_MESSAGES = {
    "int_type": "doit être un nombre entier",
    "int_parsing": "doit être un nombre entier",
    "bool_type": "doit être vrai ou faux",
    "string_type": "doit être un texte",
    "literal_error": "valeur non autorisée",
    "extra_forbidden": "champ inconnu",
    "missing": "champ obligatoire manquant",
    "date_parsing": "date invalide (format AAAA-MM-JJ)",
    "date_from_datetime_parsing": "date invalide (format AAAA-MM-JJ)",
    "date_type": "date invalide (format AAAA-MM-JJ)",
    "string_too_long": "texte trop long",
    "string_too_short": "texte vide",
    "too_long": "trop d'éléments",
    "list_type": "doit être une liste",
    "model_type": "doit être un objet",
    "dict_type": "doit être un objet",
}


def french_validation_errors(exc: ValidationError) -> list[str]:
    """Traduit les erreurs Pydantic en messages courts, sans recopier les valeurs reçues."""
    messages = []
    for err in exc.errors():
        loc = "/" + "/".join(str(x) for x in err.get("loc", ()))
        msg = err.get("msg", "")
        if msg.startswith("Value error, "):
            text = msg[len("Value error, "):]
        else:
            text = _TYPE_MESSAGES.get(err.get("type", ""), "valeur invalide")
        messages.append(f"{loc} : {text}")
    return messages


def apply_ops(quote: Quote, ops: list[Op]) -> Quote:
    """Applique toutes les opérations ou aucune. Lève OpsError avec des messages en français."""
    if not ops:
        raise OpsError(["aucune opération fournie"])
    data = quote.model_dump(mode="json")
    errors: list[str] = []
    for n, op in enumerate(ops, 1):
        try:
            _apply_one(data, op)
        except _OpError as e:
            errors.append(f"opération {n} ({op.op} {op.path}) : {e}")
        except (KeyError, IndexError, TypeError, ValueError):
            errors.append(f"opération {n} ({op.op} {op.path}) : opération impossible")
    if errors:
        raise OpsError(errors)
    try:
        new = Quote.model_validate(data)
    except ValidationError as e:
        raise OpsError(french_validation_errors(e)) from None
    if new.company_id != quote.company_id:
        new.number = None  # l'app réattribue un numéro pour la nouvelle entreprise
    return new


def finalize(old: Quote, new: Quote) -> Quote:
    """Incrémente la version si le contenu a changé et recalcule `missing`."""
    changed = old.content_dump() != new.content_dump()
    result = new.model_copy(update={"version": old.version + 1 if changed else old.version})
    result.missing = compute_missing(result)
    return result


# --- Garde-fou prix -------------------------------------------------------------------

_NUM_RE = re.compile(
    r"(?<![\d,.])(\d{1,3}(?:[ .  ]\d{3})+|\d+)(?:[,.](\d{1,2}))?(\s?k(?![a-zà-ÿ]))?",
    re.IGNORECASE,
)
_PCT_RE = re.compile(r"(\d+(?:[.,]\d+)?)\s?%")


def amounts_in_text(text: Optional[str]) -> set[int]:
    """Montants (en euros entiers) cités dans un texte : « 3 500 », « 3500 € », « 3,5k »…"""
    found: set[int] = set()
    for m in _NUM_RE.finditer(text or ""):
        whole = int(re.sub(r"\D", "", m.group(1)))
        value = Decimal(whole)
        if m.group(2):
            value += Decimal("0." + m.group(2))
        if m.group(3):
            value *= 1000
        found.add(int(value.quantize(Decimal(1), ROUND_HALF_UP)))
    return found


def price_change_allowed(user_text: Optional[str], old: Optional[int], new: Optional[int]) -> bool:
    """Vrai si le nouveau prix vient du message de l'utilisateur.

    Accepté : montant cité tel quel, ancien prix ± un montant cité, ancien prix ± un pourcentage cité.
    Remettre le prix à « à définir » (None) est toujours permis.
    """
    if new is None or new == old:
        return True
    amounts = amounts_in_text(user_text)
    if new in amounts:
        return True
    if old is None:
        return False
    if any(old + a == new or old - a == new for a in amounts):
        return True
    for m in _PCT_RE.finditer(user_text or ""):
        pct = Decimal(m.group(1).replace(",", "."))
        for sign in (1, -1):
            target = Decimal(old) * (1 + sign * pct / 100)
            if abs(target - new) <= 1:
                return True
    return False


def unrequested_price_ops(ops: list[Op], old: Optional[int], user_text: Optional[str]) -> list[Op]:
    """Opérations qui fixeraient un prix que l'utilisateur n'a pas donné."""
    bad = []
    for op in ops:
        if op.path == "/price/amount_ttc" and op.op in ("replace", "add"):
            value = op.value
            if isinstance(value, float) and value.is_integer():
                value = int(value)
            new = value if isinstance(value, int) and not isinstance(value, bool) else None
            if op.value is not None and (new is None or not price_change_allowed(user_text, old, new)):
                bad.append(op)
    return bad


# --- Diff lisible ----------------------------------------------------------------------

_MODE_LABELS = {"complet": "Complet", "main_oeuvre_seule": "Main-d’œuvre seule"}
_OPTION_LABELS = {
    "show_price_table": "Tableau de prix",
    "show_signatures": "Bloc signatures",
    "cover_photo": "Page de garde",
}


def _money(v: Optional[int]) -> str:
    return "à définir" if v is None else format_number(v)


def _txt(v: Any) -> str:
    return "—" if v in (None, "") else str(v)


def _lot_key(lot: dict) -> str:
    return json.dumps(lot, sort_keys=True, ensure_ascii=False)


def _diff_lots(old: list[dict], new: list[dict]) -> list[str]:
    if old == new:
        return []
    if sorted(map(_lot_key, old)) == sorted(map(_lot_key, new)):
        return ["Ordre des lots modifié"]
    out = []
    sm = difflib.SequenceMatcher(a=[_lot_key(x) for x in old], b=[_lot_key(x) for x in new], autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "insert":
            out += [f"Lot ajouté : {lot['title']}" for lot in new[j1:j2]]
        elif tag == "delete":
            out += [f"Lot supprimé : {lot['title']}" for lot in old[i1:i2]]
        elif tag == "replace":
            a, b = old[i1:i2], new[j1:j2]
            for k in range(max(len(a), len(b))):
                if k < len(a) and k < len(b):
                    if a[k]["title"] == b[k]["title"]:
                        out.append(f"Lot modifié : {b[k]['title']}")
                    else:
                        out.append(f"Lot remplacé : {a[k]['title']} → {b[k]['title']}")
                elif k < len(b):
                    out.append(f"Lot ajouté : {b[k]['title']}")
                else:
                    out.append(f"Lot supprimé : {a[k]['title']}")
    return out


def diff_quotes(old: Quote, new: Quote, company_labels: Optional[dict[str, str]] = None) -> list[str]:
    """Liste lisible (en français) de ce qui a changé entre deux versions d'un devis."""
    labels = company_labels or {}
    a, b = old.model_dump(mode="json"), new.model_dump(mode="json")
    out: list[str] = []

    if a["company_id"] != b["company_id"]:
        out.append(
            f"Entreprise : {labels.get(a['company_id'], a['company_id'])} → {labels.get(b['company_id'], b['company_id'])}"
        )
    if a["title"] != b["title"]:
        out.append(f"Titre : {_txt(b['title'])}")
    if a["intro"] != b["intro"]:
        out.append("Phrase d’introduction modifiée")
    if a["date"] != b["date"]:
        out.append(f"Date : {a['date']} → {b['date']}")
    for key, label in (("name", "Nom du client"), ("email", "E-mail du client"), ("phone", "Téléphone du client")):
        if a["client"][key] != b["client"][key]:
            out.append(f"{label} : {_txt(a['client'][key])} → {_txt(b['client'][key])}")
    if a["site_address"] != b["site_address"]:
        out.append(f"Adresse du chantier : {_txt(a['site_address'])} → {_txt(b['site_address'])}")
    if a["mode"] != b["mode"]:
        out.append(f"Mode : {_MODE_LABELS[a['mode']]} → {_MODE_LABELS[b['mode']]}")
    out += _diff_lots(a["lots"], b["lots"])
    pa, pb = a["price"], b["price"]
    if pa["amount_ttc"] != pb["amount_ttc"]:
        unit = " € TTC" if pb["amount_ttc"] is not None else ""
        out.append(f"Prix : {_money(pa['amount_ttc'])} → {_money(pb['amount_ttc'])}{unit}".replace(" €", " €"))
    if pa["vat_rate"] != pb["vat_rate"]:
        va = "à définir" if pa["vat_rate"] is None else format_percent(pa["vat_rate"])
        vb = "à définir" if pb["vat_rate"] is None else format_percent(pb["vat_rate"])
        out.append(f"TVA : {va} → {vb}")
    if a["duration"] != b["duration"]:
        out.append(f"Durée des travaux : {_txt(a['duration'])} → {_txt(b['duration'])}")
    if a["start_delay"] != b["start_delay"]:
        out.append("Délai de démarrage modifié")
    if a["validity_days"] != b["validity_days"]:
        out.append(f"Validité : {a['validity_days']} → {b['validity_days']} jours")
    if a["nota"] != b["nota"]:
        out.append("Nota supprimé" if b["nota"] is None else ("Nota ajouté" if a["nota"] is None else "Nota modifié"))
    if a["payment_schedule"] != b["payment_schedule"]:
        out.append("Échéancier de paiement supprimé" if not b["payment_schedule"] else "Échéancier de paiement modifié")
    for key, label in _OPTION_LABELS.items():
        if a["options"][key] != b["options"][key]:
            state = lambda v: "affiché" if v else "masqué"  # noqa: E731
            out.append(f"{label} : {state(a['options'][key])} → {state(b['options'][key])}")
    return out
