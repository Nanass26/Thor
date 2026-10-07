import Foundation
import XCTest
@testable import DevisChat

@MainActor
final class ChatViewModelTests: XCTestCase {
    private var store: InMemoryConversationStore!
    private var api: FakeQuoteAPI!
    private let conversation = UUID()

    override func setUp() async throws {
        try await super.setUp()
        store = InMemoryConversationStore(defaultYear: 2026)
        api = FakeQuoteAPI()
    }

    private func makeVM(company: String = "levix") -> ChatViewModel {
        let api = self.api
        return ChatViewModel(conversationId: conversation, defaultCompanyId: company, store: store,
                             apiProvider: { api }, currentYear: { 2026 })
    }

    private func seed(_ quote: Quote) {
        store.saveQuote(ConversationSnapshot(id: conversation, companyId: quote.companyId, history: QuoteHistory(versions: [quote])))
    }

    func testNouveauDevisRecuEtEnregistre() async throws {
        let fixture = try Fixtures.quote("mo_seule_appartement_53m2")
        api.chatHandler = { _ in ChatResponse(assistantText: "J'ai préparé le devis.", intent: .new, quote: fixture) }
        let vm = makeVM()
        vm.draftText = "Rénovation 53 m², MO seule, 3 000 TTC"
        await vm.send()
        XCTAssertEqual(vm.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(vm.currentQuote, fixture)
        XCTAssertEqual(vm.receivedQuoteCount, 1)
        XCTAssertEqual(vm.draftText, "")
        XCTAssertEqual(store.load(conversation)?.history.current, fixture)
        XCTAssertEqual(api.chatRequests.first?.message.text, "Rénovation 53 m², MO seule, 3 000 TTC")
        XCTAssertNil(api.chatRequests.first?.quote)
    }

    func testModificationPuisAnnulation() async throws {
        let v1 = try Fixtures.quote("mo_seule_appartement_53m2")
        seed(v1)
        var v2 = v1
        v2.version = 2
        v2.price.amountTtc = 3500
        api.chatHandler = { request in
            XCTAssertEqual(request.quote, v1, "le devis courant est envoyé au serveur")
            return ChatResponse(assistantText: "C'est fait.", intent: .modify, quote: v2, changes: ["Prix : 3 000 → 3 500 € TTC"])
        }
        let vm = makeVM()
        await vm.send(shortcut: "Mets 3 500 TTC")
        XCTAssertEqual(vm.currentQuote?.price.amountTtc, 3500)
        XCTAssertTrue(vm.canUndo)

        vm.undo()
        let restored = try XCTUnwrap(vm.currentQuote)
        XCTAssertEqual(restored.price.amountTtc, 3000)
        XCTAssertEqual(restored.version, 3, "l'annulation crée une nouvelle version")
        XCTAssertEqual(vm.history.versions.count, 3, "on ne détruit pas l'historique")
        XCTAssertEqual(vm.messages.last?.payload?.changes.map(FR.plain), ["Prix : 3 500 → 3 000 € TTC"])
    }

    func testErreurPuisReessayer() async throws {
        api.chatHandler = { _ in throw APIError.unreachable }
        let vm = makeVM()
        vm.draftText = "Peinture salon"
        await vm.send()
        XCTAssertEqual(vm.errorMessage, APIError.unreachable.errorDescription)
        XCTAssertTrue(vm.canRetry)
        XCTAssertFalse(vm.isSending)

        let fixture = try Fixtures.quote("incomplet_sans_prix")
        api.chatHandler = { _ in ChatResponse(assistantText: "Voici le devis.", intent: .new, quote: fixture) }
        await vm.retry()
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.canRetry)
        XCTAssertEqual(vm.messages.map(\.role), [.user, .assistant], "le message n'est pas dupliqué")
        XCTAssertEqual(api.chatRequests.count, 2)
    }

    func testServeurNonConfigure() async {
        let vm = ChatViewModel(conversationId: conversation, defaultCompanyId: "levix", store: store, apiProvider: { nil })
        vm.draftText = "test"
        await vm.send()
        XCTAssertEqual(vm.errorMessage, APIError.notConfigured.errorDescription)
    }

    func testImagesCompresseesEtPlafond() async throws {
        let vm = makeVM()
        vm.addImages(Array(repeating: Data([0xFF, 0xD8, 0xFF]), count: 7))
        XCTAssertEqual(vm.pendingImages.count, 6)
        XCTAssertEqual(vm.errorMessage, "6 images maximum par message.")
        api.chatHandler = { request in
            XCTAssertEqual(request.message.images.count, 6)
            XCTAssertNil(request.message.text)
            return ChatResponse(assistantText: "Que faut-il faire ?", intent: .question)
        }
        await vm.send()
        XCTAssertEqual(vm.messages.first?.imageFileNames.count, 6)
        XCTAssertTrue(vm.pendingImages.isEmpty)
    }

    func testValidationAttribueLeNumeroDeLEntreprise() async throws {
        let draft = try Fixtures.quote("mo_seule_appartement_53m2")
        seed(draft)
        store.setCounter(NumberCounter(companyId: "levix", nextNumber: 26, year: 2026))
        let vm = makeVM()
        vm.validate()
        XCTAssertEqual(vm.currentQuote?.number, "26/26")
        XCTAssertEqual(vm.currentQuote?.status, .validated)
        XCTAssertEqual(store.counter(for: "levix").nextNumber, 27)
    }

    // Scénario 6 : changement d'entreprise → prochain numéro de la nouvelle entreprise, avec détection de doublon.
    func testChangementEntrepriseNumeroEtDoublon() async throws {
        let validated = try Fixtures.quote("fenetre_bois") // SAR BAT, 07/26, validé
        seed(validated)
        // Un autre devis LEVIX porte déjà 01/26 dans l'historique local.
        var other = try Fixtures.quote("mo_seule_appartement_53m2")
        other.number = "01/26"
        store.saveQuote(ConversationSnapshot(id: UUID(), companyId: "levix", history: QuoteHistory(versions: [other])))

        var moved = validated
        moved.companyId = "levix"
        moved.number = nil // le serveur remet le numéro à null
        moved.version = validated.version + 1
        api.chatHandler = { _ in ChatResponse(assistantText: "Je passe sur LEVIX.", intent: .modify, quote: moved) }
        let vm = makeVM(company: "sar_bat")
        await vm.send(shortcut: "Passe sur LEVIX")
        XCTAssertEqual(vm.currentQuote?.companyId, "levix")
        XCTAssertEqual(vm.currentQuote?.number, "02/26", "01/26 existe déjà pour LEVIX : il est sauté")
        XCTAssertEqual(vm.notice?.contains("01/26"), true)
        XCTAssertEqual(store.counter(for: "levix").nextNumber, 3)
        XCTAssertEqual(vm.messages.last?.payload?.quote?.number, "02/26")
    }

    func testChangementEntrepriseSurBrouillonSansNumero() async throws {
        let draft = try Fixtures.quote("mo_seule_appartement_53m2")
        seed(draft)
        var moved = draft
        moved.companyId = "sar_bat"
        moved.version = 2
        api.chatHandler = { _ in ChatResponse(assistantText: "ok", intent: .modify, quote: moved) }
        let vm = makeVM()
        await vm.send(shortcut: "Passe sur SAR BAT")
        XCTAssertNil(vm.currentQuote?.number, "un brouillon reçoit son numéro à la validation")
        XCTAssertEqual(vm.companyId, "sar_bat")
    }

    func testDoublonSignaleALaValidation() async throws {
        var mine = try Fixtures.quote("mo_seule_appartement_53m2")
        mine.number = "05/26"
        seed(mine)
        var other = try Fixtures.quote("incomplet_sans_prix")
        other.companyId = "levix"
        other.number = "05/26"
        store.saveQuote(ConversationSnapshot(id: UUID(), companyId: "levix", history: QuoteHistory(versions: [other])))
        let vm = makeVM()
        vm.validate()
        XCTAssertEqual(vm.notice?.contains("05/26 existe déjà"), true)
    }

    func testSaisieManuelle() async throws {
        let v1 = try Fixtures.quote("incomplet_sans_prix")
        seed(v1)
        let vm = makeVM(company: "id_bat")
        var edited = v1
        edited.price.amountTtc = 9800
        edited.client.name = "  M. Exemple  "
        edited.siteAddress = ""
        vm.applyManualEdit(edited)
        let q = try XCTUnwrap(vm.currentQuote)
        XCTAssertEqual(q.version, 2)
        XCTAssertEqual(q.client.name, "M. Exemple")
        XCTAssertNil(q.siteAddress)
        XCTAssertEqual(q.missing, ["Adresse du chantier"])
        XCTAssertEqual(vm.messages.last?.payload?.changes.first.map(FR.plain), "Prix : à définir → 9 800 € TTC")
        // Aucune modification réelle → pas de nouvelle version
        vm.applyManualEdit(q)
        XCTAssertEqual(vm.history.versions.count, 2)
    }

    func testExportPDFAvecNomPropreEtBrouillon() async throws {
        let q = try Fixtures.quote("fenetre_bois")
        seed(q)
        let vm = makeVM(company: "sar_bat")
        let url = try await vm.exportPDF()
        XCTAssertEqual(url.lastPathComponent, "Devis_SAR_BAT_M_B_Exemple_Remplacement_d_une_fenetre_bois.pdf")
        XCTAssertEqual(try Data(contentsOf: url), api.renderedData)
        XCTAssertEqual(api.renderRequests.first?.1, true)
        XCTAssertNil(api.renderRequests.first?.0.coverPhotoB64)
    }

    func testPageDeGardeEnvoyeeAuRendu() async throws {
        var q = try Fixtures.quote("fenetre_bois")
        q.options.coverPhoto = true
        seed(q)
        let vm = makeVM(company: "sar_bat")
        vm.setCoverPhoto(Data([0xFF, 0xD8, 0xFF, 0x01]))
        _ = try await vm.exportDOCX()
        XCTAssertEqual(api.renderRequests.first?.0.coverPhotoB64, Data([0xFF, 0xD8, 0xFF, 0x01]).base64EncodedString())
    }

    func testResumeHistoriqueEnvoye() async throws {
        api.chatHandler = { _ in ChatResponse(assistantText: "Quel prix ?", intent: .question) }
        let vm = makeVM()
        await vm.send(shortcut: "Peinture salon")
        await vm.send(shortcut: "2 800 TTC")
        let summary = try XCTUnwrap(api.chatRequests.last?.historySummary)
        XCTAssertTrue(summary.contains("Utilisateur : Peinture salon"))
        XCTAssertTrue(summary.contains("Assistant : Quel prix ?"))
        XCTAssertFalse(summary.contains("2 800 TTC"), "le message en cours n'est pas dans le résumé")
    }

    func testRechargementDepuisLeStockage() async throws {
        let fixture = try Fixtures.quote("peinture_acompte")
        api.chatHandler = { _ in ChatResponse(assistantText: "ok", intent: .new, quote: fixture) }
        let vm = makeVM(company: "m_bat")
        await vm.send(shortcut: "Peinture appartement")
        let reloaded = makeVM(company: "levix")
        XCTAssertEqual(reloaded.currentQuote, fixture)
        XCTAssertEqual(reloaded.companyId, "m_bat")
        XCTAssertEqual(reloaded.messages.count, 2)
    }
}
