from app.models import PriceRange
from app.prices import (
    GENERIC_NOTE,
    build_price_range,
    find_comparables,
    history_stats,
    keywords,
    load_history,
    mo_ratio,
    mo_ratio_sentence,
)


def test_somme_de_controle_historique():
    stats = history_stats(load_history())
    assert stats == {"count": 12, "total": 115810, "median": 5750, "min": 1500, "max": 33110}


def test_mots_cles():
    assert {"peinture", "appartement", "plafond"} <= keywords("Peinture d'un appart, plafonds")
    assert "les" not in keywords("les travaux")


def test_comparables_meme_corps_meme_mode_surface():
    h = load_history()
    ids = [c["id"] for c in find_comparables(h, "rénovation d'appartement", 50, "main_oeuvre_seule")]
    assert ids == ["h08"]
    ids = [c["id"] for c in find_comparables(h, "magasin d'optique", 55, "complet")]
    assert ids == ["h10"]
    # Surface hors de ±40 % → exclu
    assert find_comparables(h, "magasin d'optique", 120, "complet") == []
    assert len(find_comparables(h, "peinture rénovation appartement plafond", None, "complet")) <= 3


def test_ratio_mo_seule():
    info = mo_ratio(load_history())
    assert info["percent"] == 54 and info["ids"] == ["h10", "h11"]
    assert "54" in mo_ratio_sentence(load_history())


def test_fourchette():
    comps = [{"id": "h06", "ttc": 4500}, {"id": "h07", "ttc": 6500}]
    pr = build_price_range(comps, None)
    assert (pr.low, pr.high, pr.basis, pr.comparable_ids) == (4500, 6500, "comparables", ["h06", "h07"])
    # Moins de 2 comparables : estimation générique signalée, jamais présentée comme des cas réels
    pr = build_price_range([comps[0]], PriceRange(low=5000, high=7000, basis="comparables"))
    assert pr.basis == "estimation_generique" and pr.note == GENERIC_NOTE
    assert build_price_range([], None).basis == "aucune"
