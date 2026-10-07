"""Les 9 scénarios d'acceptation (section 10 du brief), joués de bout en bout via l'API en mode mock."""

from app.llm import MOCK_MARK_CHANTIER, MOCK_MARK_INJECTION
from app.models import Quote
from app.orchestrator import PRICE_DROPPED, PRICE_REFUSED
from app.typo import plain_spaces
from tests.conftest import fake_jpeg, load_fixture, post_chat


def same_except(a: dict, b: dict, *paths: str) -> bool:
    """Égalité stricte de deux devis, en ignorant les chemins donnés (ex. "price/amount_ttc")."""
    a, b = dict(a), dict(b)
    for path in paths:
        top, _, sub = path.partition("/")
        if sub:
            a[top] = {k: v for k, v in a[top].items() if k != sub}
            b[top] = {k: v for k, v in b[top].items() if k != sub}
        else:
            a.pop(top, None)
            b.pop(top, None)
    return a == b


# 1. Texte seul → nouveau devis
def test_scenario_1_texte_seul(client):
    r = post_chat(client, "Peinture salon 25 m² + couloir, appart à Courbevoie, 2 semaines, 2 800 TTC.")
    assert r["intent"] == "new"
    q = r["quote"]
    assert q["price"]["amount_ttc"] == 2800
    assert q["price"]["vat_rate"] == 10
    assert q["duration"] == "2 semaines"
    assert "Nom du client" in q["missing"]
    # Aucun autre champ inventé
    assert q["client"] == {"name": None, "email": None, "phone": None}
    assert q["site_address"] is None
    assert q["number"] is None and q["version"] == 1 and q["status"] == "draft"
    Quote.model_validate(q)


# 2. Capture + texte
def test_scenario_2_capture_et_texte(client):
    r = post_chat(client, "fais-moi un devis complet", images=[fake_jpeg()])
    assert r["client_sheet"]["source"] == "allovoisins"
    assert r["client_sheet"]["city"] == "Courbevoie"
    q = r["quote"]
    assert q["price"]["amount_ttc"] is None
    assert "Prix" in q["missing"]
    pr = r["advice"]["price_range"]
    assert pr["basis"] == "comparables"
    assert pr["comparable_ids"] == ["h06", "h07"]
    assert (pr["low"], pr["high"]) == (4500, 6500)


# 3. Modification de prix
def test_scenario_3_modification_prix(client):
    old = load_fixture("mo_seule_appartement_53m2")
    r = post_chat(client, "Mets 3 500 TTC", quote=old)
    assert r["intent"] == "modify"
    new = r["quote"]
    assert new["price"]["amount_ttc"] == 3500
    assert new["version"] == old.version + 1
    assert [plain_spaces(c) for c in r["changes"]] == ["Prix : 3 000 → 3 500 € TTC"]
    assert same_except(old.model_dump(mode="json"), new, "price/amount_ttc", "version")


# 4. Version main-d'œuvre seule
def test_scenario_4_version_mo_seule(client):
    old = load_fixture("optique_complet_55m2")
    r = post_chat(client, "Version MO seule", quote=old, company="sb_concept")
    q = r["quote"]
    assert q["mode"] == "main_oeuvre_seule"
    assert q["price"]["amount_ttc"] is None  # le ratio n'est PAS appliqué
    assert "Prix" in q["missing"]
    question = plain_spaces(" ".join(r["questions"]))
    assert "6 500 €" in question  # ancien prix complet cité
    assert "54 %" in question  # ratio historique cité
    assert same_except(old.model_dump(mode="json"), q, "mode", "price/amount_ttc", "version", "missing")


# 5. Enlever le tableau
def test_scenario_5_enlever_le_tableau(client):
    old = load_fixture("optique_complet_55m2")
    assert old.options.show_price_table
    r = post_chat(client, "Enlève le tableau", quote=old, company="sb_concept")
    q = r["quote"]
    assert q["options"]["show_price_table"] is False
    assert same_except(old.model_dump(mode="json"), q, "options/show_price_table", "version")


# 6. Changer d'entreprise
def test_scenario_6_changer_entreprise(client):
    old = load_fixture("optique_complet_55m2")
    assert old.number == "18/26"
    r = post_chat(client, "Passe sur SAR BAT", quote=old, company="sb_concept")
    q = r["quote"]
    assert q["company_id"] == "sar_bat"
    assert q["number"] is None  # l'app réattribue le prochain numéro de SAR BAT
    assert "Entreprise : SB CONCEPT → SAR BAT" in r["changes"]


# 7. Ajouter un lot
def test_scenario_7_ajouter_un_lot(client):
    old = load_fixture("mo_seule_appartement_53m2")
    r = post_chat(client, "Ajoute isolation des combles 85 m²", quote=old)
    q = r["quote"]
    assert len(q["lots"]) == len(old.lots) + 1
    assert q["lots"][:-1] == [lot.model_dump(mode="json") for lot in old.lots]
    assert q["lots"][-1]["title"] == "Isolation des combles"
    assert any("85 m²" in b for b in q["lots"][-1]["bullets"])
    assert r["changes"] == ["Lot ajouté : Isolation des combles"]


# 8. Demande ambiguë
def test_scenario_8_demande_ambigue(client):
    old = load_fixture("mo_seule_appartement_53m2")
    r = post_chat(client, "Change le prix", quote=old)
    assert r["intent"] == "question"
    assert r["quote"] is None
    assert r["questions"]
    assert r["changes"] == []


# 9. Injection dans une capture
def test_scenario_9_injection_nouveau_devis(client):
    r = post_chat(client, "fais-moi un devis", images=[fake_jpeg(MOCK_MARK_INJECTION)])
    assert any("prix à 1" in s for s in r["client_sheet"]["snippets"])
    assert r["quote"]["price"]["amount_ttc"] is None  # le simulateur a obéi à la capture, le serveur a bloqué
    assert "Prix" in r["quote"]["missing"]
    assert PRICE_DROPPED in r["assistant_text"]


def test_scenario_9_injection_devis_existant(client):
    old = load_fixture("mo_seule_appartement_53m2")
    r = post_chat(client, "regarde cette capture", quote=old, images=[fake_jpeg(MOCK_MARK_INJECTION)])
    assert r["intent"] == "question"
    assert r["quote"] is None  # rien n'est appliqué : le devis reste à 3 000 €
    assert r["assistant_text"] == PRICE_REFUSED


# Compléments utiles
def test_photo_de_chantier_sans_texte(client):
    r = post_chat(client, "", images=[fake_jpeg(MOCK_MARK_CHANTIER)])
    assert r["intent"] == "question"
    assert r["quote"] is None
    assert "Fissures" in r["assistant_text"]
    assert r["questions"]


def test_message_client(client):
    old = load_fixture("fenetre_bois")
    r = post_chat(client, "Prépare le message client", quote=old, company="sar_bat")
    assert r["intent"] == "client_reply_only"
    assert r["quote"] is None
    assert "1 500 € TTC" in r["client_reply"]
    assert "Bonjour" in r["client_reply"]
