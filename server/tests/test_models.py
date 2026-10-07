from decimal import Decimal

import pytest
from pydantic import ValidationError

from app.models import Lot, PaymentStep, Price, Quote, compute_missing, ht_and_vat
from tests.conftest import FIXTURE_NAMES, load_fixture


@pytest.mark.parametrize("name", FIXTURE_NAMES)
def test_fixtures_valides_et_missing_coherent(name):
    q = load_fixture(name)
    assert q.missing == compute_missing(q)


def test_au_moins_six_fixtures():
    assert len(FIXTURE_NAMES) >= 6


def test_ht_tva_arrondis_au_centime():
    assert ht_and_vat(3000, 10) == (Decimal("2727.27"), Decimal("272.73"))
    assert ht_and_vat(6500, 20) == (Decimal("5416.67"), Decimal("1083.33"))
    assert ht_and_vat(1000, 5.5) == (Decimal("947.87"), Decimal("52.13"))
    ht, vat = ht_and_vat(4500, 10)
    assert ht + vat == 4500
    assert ht_and_vat(None, 10) is None
    assert ht_and_vat(3000, None) is None


def test_missing_deterministe(ref_quote):
    q = ref_quote.model_copy(deep=True)
    q.price.amount_ttc = None
    q.price.vat_rate = None
    q.duration = None
    assert compute_missing(q) == ["Nom du client", "Adresse du chantier", "Prix", "Taux de TVA", "Durée des travaux"]
    q.client.name = "M. Exemple"
    q.site_address = "1 rue Imaginaire"
    q.price.amount_ttc = 1
    q.price.vat_rate = 20
    q.duration = "1 jour"
    assert compute_missing(q) == []


def test_tva_autorisee_seulement():
    assert Price(amount_ttc=100, vat_rate=5.5).vat_rate == 5.5
    assert Price(vat_rate=10).model_dump()["vat_rate"] == 10
    for bad in (7, "10", True, 19.6):
        with pytest.raises(ValidationError):
            Price(vat_rate=bad)


def test_montant_entier_strict():
    assert Price(amount_ttc=3500.0).amount_ttc == 3500
    for bad in ("3500", 3500.5, -1, True):
        with pytest.raises(ValidationError):
            Price(amount_ttc=bad)


def test_lot_puces_ou_paragraphe():
    Lot(title="Peinture", bullets=["a", "b"])
    Lot(title="Peinture", paragraph="Texte")
    with pytest.raises(ValidationError):
        Lot(title="Peinture", bullets=["a"], paragraph="Texte")
    with pytest.raises(ValidationError):
        Lot(title="Peinture")
    with pytest.raises(ValidationError):
        Lot(title="Peinture", bullets=[str(i) for i in range(9)])


def test_echeance_pourcentage_ou_montant():
    PaymentStep(label="Acompte", percent=30)
    PaymentStep(label="Acompte", amount_ttc=2500)
    with pytest.raises(ValidationError):
        PaymentStep(label="Acompte", percent=30, amount_ttc=2500)
    with pytest.raises(ValidationError):
        PaymentStep(label="Acompte")


def test_options_booleens_stricts(ref_quote):
    data = ref_quote.model_dump(mode="json")
    data["options"]["show_price_table"] = "oui"
    with pytest.raises(ValidationError):
        Quote.model_validate(data)


def test_chaine_vide_devient_null(ref_quote):
    data = ref_quote.model_dump(mode="json")
    data["client"]["name"] = "   "
    assert Quote.model_validate(data).client.name is None


def test_aller_retour_json(ref_quote):
    again = Quote.model_validate_json(ref_quote.model_dump_json())
    assert again == ref_quote
