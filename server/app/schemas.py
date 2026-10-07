"""Schémas JSON imposés au modèle (sorties structurées `output_config.format`).

Contraintes de l'API (doc officielle) : `additionalProperties: false` partout, au plus
24 champs optionnels et 16 champs « union » (anyOf) par requête. D'où ces choix :
- une valeur absente est soit une chaîne vide "", soit un champ optionnel omis (jamais anyOf) ;
- la valeur d'une opération de modification est transmise en texte JSON (`value_json`).
Le résultat est ensuite validé par Pydantic (models.py), qui reste la source de vérité.
"""

from __future__ import annotations

from typing import Any


def _obj(properties: dict[str, Any], optional: tuple[str, ...] = ()) -> dict[str, Any]:
    return {
        "type": "object",
        "properties": properties,
        "required": [k for k in properties if k not in optional],
        "additionalProperties": False,
    }


def _str(description: str = "") -> dict[str, Any]:
    return {"type": "string", "description": description} if description else {"type": "string"}


def _str_list(description: str = "") -> dict[str, Any]:
    schema: dict[str, Any] = {"type": "array", "items": {"type": "string"}}
    if description:
        schema["description"] = description
    return schema


EMPTY = "Chaîne vide \"\" si l'information n'est pas fournie (ne jamais l'inventer)."

LOT_SCHEMA = _obj(
    {
        "title": _str("Titre court du lot (ex. « Peinture »)."),
        "bullets": _str_list("2 à 6 puces courtes. Omettre si `paragraph` est utilisé."),
        "paragraph": _str("Un paragraphe court. Omettre si `bullets` est utilisé."),
    },
    optional=("bullets", "paragraph"),
)

QUOTE_DRAFT_SCHEMA = _obj(
    {
        "title": _str("Titre du devis."),
        "intro": _str("Phrase d'introduction. " + EMPTY),
        "lots": {"type": "array", "items": LOT_SCHEMA},
        "mode": {"type": "string", "enum": ["complet", "main_oeuvre_seule"]},
        "price": _obj(
            {
                "amount_ttc": {
                    "type": "integer",
                    "description": "Prix TTC en euros. À OMETTRE sauf si l'utilisateur a donné ce montant dans son propre message.",
                },
                "vat_rate": {"type": "number", "enum": [5.5, 10, 20], "description": "Taux de TVA proposé."},
            },
            optional=("amount_ttc", "vat_rate"),
        ),
        "duration": _str("Durée des travaux. " + EMPTY),
        "start_delay": _str("Délai de démarrage. " + EMPTY),
        "validity_days": {"type": "integer", "description": "Validité du devis en jours (30 par défaut)."},
        "nota": _str("Remarque éventuelle. " + EMPTY),
        "client": _obj({"name": _str(EMPTY), "email": _str(EMPTY), "phone": _str(EMPTY)}),
        "site_address": _str("Adresse exacte du chantier. " + EMPTY),
        "payment_schedule": {
            "type": "array",
            "description": "Échéancier ; liste vide par défaut.",
            "items": _obj(
                {
                    "label": _str(),
                    "percent": {"type": "number"},
                    "amount_ttc": {"type": "integer"},
                },
                optional=("percent", "amount_ttc"),
            ),
        },
        "options": _obj(
            {
                "show_price_table": {"type": "boolean"},
                "show_signatures": {"type": "boolean"},
                "cover_photo": {"type": "boolean"},
            }
        ),
    }
)

OP_SCHEMA = _obj(
    {
        "op": {"type": "string", "enum": ["add", "replace", "remove", "move"]},
        "path": _str("Chemin JSON-Pointer autorisé, ex. /price/amount_ttc ou /lots/-"),
        "value_json": _str("La nouvelle valeur écrite en JSON (ex. 3500, \"3 semaines\", true, null, {\"title\": …}). \"null\" pour remove/move."),
        "from": _str("Pour « move » uniquement : /lots/i d'origine."),
    },
    optional=("from",),
)

ADVICE_SCHEMA = _obj(
    {
        "price_range": _obj(
            {
                "low": {"type": "integer"},
                "high": {"type": "integer"},
                "basis": {"type": "string", "enum": ["comparables", "estimation_generique", "aucune"]},
                "comparable_ids": _str_list(),
                "note": _str(),
            },
            optional=("low", "high"),
        ),
        "risks": {
            "type": "array",
            "items": _obj({"label": _str(), "why": _str()}),
        },
        "questions": _str_list(),
    },
    optional=("price_range",),
)

RESPOND_SCHEMA = _obj(
    {
        "intent": {"type": "string", "enum": ["new", "modify", "question", "client_reply_only"]},
        "assistant_text": _str("Réponse courte à l'utilisateur, en français, tutoiement."),
        "quote": QUOTE_DRAFT_SCHEMA,
        "ops": {"type": "array", "items": OP_SCHEMA, "description": "Opérations de modification (intent = modify)."},
        "questions": _str_list("Questions à poser à l'utilisateur."),
        "advice": ADVICE_SCHEMA,
        "client_reply": _str("Message prêt à copier pour le client, si demandé."),
    },
    optional=("quote", "advice", "client_reply"),
)

CLIENT_SHEET_SCHEMA = _obj(
    {
        "source": {
            "type": "string",
            "enum": ["allovoisins", "sms", "whatsapp", "email", "photo_chantier", "autre"],
        },
        "client_name": _str("Nom de famille du client s'il est lisible. " + EMPTY),
        "client_first_name": _str(EMPTY),
        "city": _str(EMPTY),
        "postal_code": _str(EMPTY),
        "job_summary": _str("Nature des travaux demandés, en une phrase. " + EMPTY),
        "surface_m2": {"type": "number", "description": "Surface lue. À omettre si absente ou illisible."},
        "rooms": _str_list(),
        "constraints": _str_list(),
        "deadline": _str(EMPTY),
        "budget_hint": _str("Budget évoqué par le client. " + EMPTY),
        "snippets": _str_list("3 extraits verbatim courts maximum, sans coordonnées."),
        "observations": _str_list("Constats visibles sur des photos de chantier."),
        "uncertain": _str_list("Ce qui est lu partiellement ou à confirmer."),
    },
    optional=("surface_m2",),
)


def count_complexity(schema: Any) -> tuple[int, int]:
    """(champs optionnels, champs union) d'un schéma — vérifié par les tests contre les limites de l'API."""
    optional = unions = 0
    if isinstance(schema, dict):
        if "anyOf" in schema or isinstance(schema.get("type"), list):
            unions += 1
        if schema.get("type") == "object":
            optional += len(set(schema.get("properties", {})) - set(schema.get("required", [])))
        for value in schema.values():
            o, u = count_complexity(value)
            optional += o
            unions += u
    elif isinstance(schema, list):
        for item in schema:
            o, u = count_complexity(item)
            optional += o
            unions += u
    return optional, unions
