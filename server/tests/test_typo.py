from datetime import date

import pytest

from app.typo import (
    NBSP,
    NNBSP,
    format_amount,
    format_date,
    format_number,
    format_percent,
    format_surface,
    fr_text,
)


def test_montants_espace_fine_et_insecable():
    assert format_amount(6500) == f"6{NNBSP}500{NBSP}€"
    assert format_amount(33110) == f"33{NNBSP}110{NBSP}€"
    assert format_amount(1500000) == f"1{NNBSP}500{NNBSP}000{NBSP}€"
    assert format_amount(950) == f"950{NBSP}€"
    assert format_amount(2727.27, cents=True) == f"2{NNBSP}727,27{NBSP}€"
    assert format_number(-1234) == f"-1{NNBSP}234"


def test_montant_jamais_coupe():
    # Aucun espace « sécable » dans un montant formaté.
    assert " " not in format_amount(1234567, cents=True)


def test_pourcentages_et_surfaces():
    assert format_percent(5.5) == f"5,5{NBSP}%"
    assert format_percent(10) == f"10{NBSP}%"
    assert format_percent(10.0) == f"10{NBSP}%"
    assert format_surface(53) == f"53{NBSP}m²"
    assert format_surface(12.5) == f"12,5{NBSP}m²"


def test_dates():
    assert format_date(date(2026, 10, 7)) == "7 octobre 2026"
    assert format_date(date(2026, 8, 1)) == "1er août 2026"
    assert format_date(date(2027, 2, 14)) == "14 février 2027"


def test_ponctuation_haute():
    assert fr_text("Prix: 3 semaines") == f"Prix{NBSP}: 3 semaines"
    assert fr_text("Vraiment ?") == f"Vraiment{NBSP}?"
    assert fr_text("Attention!") == f"Attention{NBSP}!"
    assert fr_text("Oui ; non") == f"Oui{NBSP}; non"
    assert fr_text("Quoi ?!") == f"Quoi{NBSP}?!"


@pytest.mark.parametrize(
    "texte",
    [
        "RDV à 14:05 sur place",
        "Voir https://exemple.fr/devis?id=3",
        "Écrire à contact@exemple.fr",
    ],
)
def test_zones_protegees(texte):
    protected = texte.split(" ")[-1] if "14:05" not in texte else "14:05"
    assert protected in fr_text(texte)


def test_apostrophes_guillemets_oe():
    assert fr_text("main-d'œuvre") == "main-d’œuvre"
    assert fr_text('il dit "bonjour"') == f"il dit «{NBSP}bonjour{NBSP}»"
    assert fr_text("« bonjour »") == f"«{NBSP}bonjour{NBSP}»"
    assert "œ" in fr_text("cœur de l'œuvre")


def test_montants_surfaces_dans_le_texte():
    assert fr_text("Total 3500€") == f"Total 3{NNBSP}500{NBSP}€"
    assert fr_text("soit 2 800 €") == f"soit 2{NNBSP}800{NBSP}€"
    assert fr_text("salon de 25 m2") == f"salon de 25{NBSP}m²"
    assert fr_text("TVA à 10 %") == f"TVA à 10{NBSP}%"


@pytest.mark.parametrize(
    "texte",
    [
        "Prix: 3500 € pour 25 m2 ; TVA 10 % ! L'œuvre \"ok\" ?",
        "Rendez-vous à 9:30, écrire à a.b@c.fr : merci",
        "",
    ],
)
def test_idempotent(texte):
    once = fr_text(texte)
    assert fr_text(once) == once
