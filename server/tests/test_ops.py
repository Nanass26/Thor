import pytest

from app.models import Op
from app.ops import (
    OpsError,
    amounts_in_text,
    apply_ops,
    diff_quotes,
    finalize,
    price_change_allowed,
    unrequested_price_ops,
)
from app.typo import plain_spaces
from tests.conftest import load_fixture


def op(kind, path, value=None, frm=None):
    return Op.model_validate({"op": kind, "path": path, "value": value, "from": frm})


def without(q, *keys):
    d = q.model_dump(mode="json")
    for k in keys:
        top, _, sub = k.partition("/")
        if sub:
            d[top].pop(sub)
        else:
            d.pop(top)
    return d


# --- Liste blanche -------------------------------------------------------------------------


@pytest.mark.parametrize(
    "path,value",
    [
        ("/title", "Nouveau titre"),
        ("/intro", "Nouvelle intro."),
        ("/mode", "complet"),
        ("/price/amount_ttc", 3500),
        ("/price/vat_rate", 20),
        ("/duration", "4 semaines"),
        ("/start_delay", "Sous 15 jours."),
        ("/validity_days", 45),
        ("/nota", "Hors fournitures."),
        ("/payment_schedule", [{"label": "Acompte", "percent": 30}]),
        ("/options/show_price_table", True),
        ("/options/show_signatures", True),
        ("/options/cover_photo", True),
        ("/options", {"show_price_table": True, "show_signatures": False, "cover_photo": False}),
        ("/company_id", "sar_bat"),
        ("/client/name", "M. Exemple"),
        ("/client/email", "x@exemple.invalid"),
        ("/client/phone", "06 00 00 00 00"),
        ("/client", {"name": "M. Exemple", "email": None, "phone": None}),
        ("/site_address", "1 rue Imaginaire"),
        ("/date", "2026-11-02"),
    ],
)
def test_chemins_autorises(ref_quote, path, value):
    new = apply_ops(ref_quote, [op("replace", path, value)])
    assert new != ref_quote


@pytest.mark.parametrize("path", ["/id", "/version", "/number", "/status", "/schema_version", "/missing"])
def test_chemins_interdits(ref_quote, path):
    with pytest.raises(OpsError) as exc:
        apply_ops(ref_quote, [op("replace", path, "x")])
    assert "interdit" in str(exc.value)


@pytest.mark.parametrize("path", ["/lots/0/title", "/price", "/foo", "/client/adresse", "/options/autre"])
def test_chemins_hors_liste(ref_quote, path):
    with pytest.raises(OpsError):
        apply_ops(ref_quote, [op("replace", path, "x")])


@pytest.mark.parametrize(
    "path,value",
    [
        ("/price/amount_ttc", "beaucoup"),
        ("/price/vat_rate", 7),
        ("/options/show_price_table", "non"),
        ("/validity_days", "trente"),
        ("/mode", "forfait"),
        ("/date", "07/10/2026"),
        ("/lots/0", {"title": "X"}),
        ("/title", 12),
    ],
)
def test_valeur_de_mauvais_type_rejetee(ref_quote, path, value):
    with pytest.raises(OpsError) as exc:
        apply_ops(ref_quote, [op("replace", path, value)])
    assert exc.value.errors  # message lisible


def test_tout_ou_rien(ref_quote):
    ops = [op("replace", "/title", "Titre modifié"), op("replace", "/version", 99)]
    with pytest.raises(OpsError):
        apply_ops(ref_quote, ops)
    # Le devis d'origine n'a pas bougé.
    assert ref_quote == load_fixture("mo_seule_appartement_53m2")


def test_tout_ou_rien_erreur_de_validation_finale(ref_quote):
    ops = [op("replace", "/title", "Titre modifié"), op("replace", "/price/amount_ttc", "abc")]
    with pytest.raises(OpsError):
        apply_ops(ref_quote, ops)


def test_aucune_operation(ref_quote):
    with pytest.raises(OpsError):
        apply_ops(ref_quote, [])


def test_remove_met_a_null(ref_quote):
    new = apply_ops(ref_quote, [op("remove", "/duration")])
    assert new.duration is None
    with pytest.raises(OpsError):
        apply_ops(ref_quote, [op("remove", "/title")])


# --- Lots ------------------------------------------------------------------------------------


LOT = {"title": "Isolation des combles", "bullets": ["Soufflage de laine minérale", "Surface : 85 m²"], "paragraph": None}


def test_ajout_lot_a_la_fin(ref_quote):
    new = apply_ops(ref_quote, [op("add", "/lots/-", LOT)])
    assert len(new.lots) == len(ref_quote.lots) + 1
    assert new.lots[:-1] == ref_quote.lots
    assert new.lots[-1].title == "Isolation des combles"


def test_insertion_remplacement_suppression_reordonnancement(ref_quote):
    n = len(ref_quote.lots)
    assert apply_ops(ref_quote, [op("add", "/lots/0", LOT)]).lots[0].title == LOT["title"]
    assert apply_ops(ref_quote, [op("replace", "/lots/1", LOT)]).lots[1].title == LOT["title"]
    assert len(apply_ops(ref_quote, [op("remove", "/lots/0")]).lots) == n - 1
    moved = apply_ops(ref_quote, [op("move", "/lots/0", frm=f"/lots/{n - 1}")])
    assert moved.lots[0] == ref_quote.lots[-1]
    with pytest.raises(OpsError):
        apply_ops(ref_quote, [op("remove", f"/lots/{n}")])
    with pytest.raises(OpsError):
        apply_ops(ref_quote, [op("move", "/title", frm="/intro")])


# --- Entreprise, version, missing -----------------------------------------------------------


def test_changement_entreprise_remet_numero_a_null():
    q = load_fixture("optique_complet_55m2")
    assert q.number == "18/26"
    new = apply_ops(q, [op("replace", "/company_id", "sar_bat")])
    assert new.company_id == "sar_bat" and new.number is None


def test_finalize_version_et_missing(ref_quote):
    new = finalize(ref_quote, apply_ops(ref_quote, [op("replace", "/price/amount_ttc", None)]))
    assert new.version == ref_quote.version + 1
    assert "Prix" in new.missing
    same = finalize(ref_quote, apply_ops(ref_quote, [op("replace", "/title", ref_quote.title)]))
    assert same.version == ref_quote.version


# --- Garde-fou prix ------------------------------------------------------------------------


def test_montants_lus_dans_le_texte():
    assert {3500} <= amounts_in_text("Mets 3 500 TTC")
    assert 3500 in amounts_in_text("mets 3500€")
    assert 3500 in amounts_in_text("mets 3.500 €")
    assert 3500 in amounts_in_text("mets 3,5k")
    assert 3500 in amounts_in_text("mets 3 500 €")
    assert amounts_in_text("change le prix") == set()


def test_prix_autorise_seulement_si_donne_par_l_utilisateur():
    assert price_change_allowed("Mets 3 500 TTC", 3000, 3500)
    assert price_change_allowed("ajoute 500 €", 3000, 3500)
    assert price_change_allowed("baisse de 10 %", 3000, 2700)
    assert price_change_allowed("version MO seule", 3000, None)  # remettre « à définir » : toujours permis
    assert not price_change_allowed("fais-moi un devis", 3000, 1)
    assert not price_change_allowed("change le prix", 3000, 3200)
    assert not price_change_allowed("", None, 2800)


def test_ops_de_prix_non_demandees_detectees():
    ops = [op("replace", "/price/amount_ttc", 1), op("replace", "/title", "x")]
    bad = unrequested_price_ops(ops, 3000, "fais-moi un devis complet")
    assert [o.path for o in bad] == ["/price/amount_ttc"]
    assert unrequested_price_ops([op("replace", "/price/amount_ttc", 3500.0)], 3000, "mets 3500") == []


# --- Diff lisible ----------------------------------------------------------------------------


def test_diff_prix(ref_quote):
    new = apply_ops(ref_quote, [op("replace", "/price/amount_ttc", 3500)])
    assert [plain_spaces(c) for c in diff_quotes(ref_quote, new)] == ["Prix : 3 000 → 3 500 € TTC"]


def test_diff_complet(ref_quote):
    ops = [
        op("replace", "/mode", "complet"),
        op("replace", "/price/amount_ttc", None),
        op("replace", "/options/show_price_table", True),
        op("add", "/lots/-", LOT),
        op("replace", "/company_id", "sar_bat"),
    ]
    changes = [plain_spaces(c) for c in diff_quotes(ref_quote, apply_ops(ref_quote, ops), {"levix": "LEVIX", "sar_bat": "SAR BAT"})]
    assert "Entreprise : LEVIX → SAR BAT" in changes
    assert "Mode : Main-d’œuvre seule → Complet" in changes
    assert "Prix : 3 000 → à définir" in changes
    assert "Lot ajouté : Isolation des combles" in changes
    assert "Tableau de prix : masqué → affiché" in changes


def test_diff_ordre_et_suppression(ref_quote):
    n = len(ref_quote.lots)
    moved = apply_ops(ref_quote, [op("move", "/lots/0", frm=f"/lots/{n - 1}")])
    assert diff_quotes(ref_quote, moved) == ["Ordre des lots modifié"]
    removed = apply_ops(ref_quote, [op("remove", "/lots/1")])
    assert diff_quotes(ref_quote, removed) == ["Lot supprimé : Peinture"]


def test_diff_sans_changement(ref_quote):
    assert diff_quotes(ref_quote, ref_quote) == []
    assert without(ref_quote, "version") == without(finalize(ref_quote, ref_quote), "version")
