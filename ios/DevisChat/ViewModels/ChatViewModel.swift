import Foundation
import Observation

/// Raccourcis proposés au-dessus du clavier.
enum ChatShortcut: String, CaseIterable, Identifiable {
    case price, labourOnly, complete, noTable, changeCompany, addLot, clientMessage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .price: return "Prix…"
        case .labourOnly: return "Version MO seule"
        case .complete: return "Version complète"
        case .noTable: return "Sans tableau"
        case .changeCompany: return "Changer d'entreprise"
        case .addLot: return "Ajouter un lot"
        case .clientMessage: return "Message client"
        }
    }

    /// Texte envoyé directement, ou nil si l'utilisateur doit compléter (prix, lot, entreprise).
    var message: String? {
        switch self {
        case .labourOnly: return "Passe en version main-d'œuvre seule"
        case .complete: return "Passe en version complète"
        case .noTable: return "Enlève le tableau de prix"
        case .clientMessage: return "Prépare le message client"
        case .price, .changeCompany, .addLot: return nil
        }
    }

    /// Début de phrase placé dans le champ de saisie pour les raccourcis à compléter.
    var prefill: String? {
        switch self {
        case .price: return "Mets le prix à "
        case .addLot: return "Ajoute "
        default: return nil
        }
    }
}

/// Conversation d'un devis : envoi des messages, versions, numéro, export PDF/Word.
@MainActor
@Observable
final class ChatViewModel {
    let conversationId: UUID
    private(set) var messages: [ChatMessage] = []
    private(set) var history = QuoteHistory()
    private(set) var companyId: String
    private(set) var coverPhotoFileName: String?
    var draftText = ""
    private(set) var pendingImages: [Data] = []
    private(set) var isSending = false
    var errorMessage: String?
    private(set) var canRetry = false
    /// Avertissements (doublon de numéro, champs manquants à la validation…).
    var notice: String?
    /// Incrémenté à chaque devis reçu : déclenche le retour haptique dans la vue.
    private(set) var receivedQuoteCount = 0

    private struct PendingSend {
        var text: String
        var images: [Data]
        var summary: String?
    }

    private var lastFailed: PendingSend?
    private let store: ConversationStore
    private let apiProvider: @MainActor () -> QuoteAPI?
    private let imageProcessor: ImageProcessing
    private let companies: @MainActor () -> [Company]
    private let currentYear: () -> Int

    init(
        conversationId: UUID,
        defaultCompanyId: String,
        store: ConversationStore,
        apiProvider: @escaping @MainActor () -> QuoteAPI?,
        imageProcessor: ImageProcessing = PassthroughImageProcessor(),
        companies: @escaping @MainActor () -> [Company] = { Company.fallback },
        currentYear: @escaping () -> Int = { QuoteNumbering.currentYear() }
    ) {
        self.conversationId = conversationId
        self.store = store
        self.apiProvider = apiProvider
        self.imageProcessor = imageProcessor
        self.companies = companies
        self.currentYear = currentYear
        if let snapshot = store.load(conversationId) {
            messages = snapshot.messages
            history = snapshot.history
            companyId = snapshot.history.current?.companyId ?? (snapshot.companyId.isEmpty ? defaultCompanyId : snapshot.companyId)
            coverPhotoFileName = snapshot.coverPhotoFileName
        } else {
            companyId = defaultCompanyId
        }
    }

    // MARK: État dérivé

    var currentQuote: Quote? { history.current }
    var canUndo: Bool { history.canUndo }
    var companyLabel: String { Company.label(for: companyId, in: companies()) }
    var canSend: Bool {
        !isSending && (!draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty)
    }

    func isLatest(_ quote: Quote) -> Bool {
        quote.version == currentQuote?.version && quote.id == currentQuote?.id
    }

    // MARK: Images

    func addImages(_ raw: [Data]) {
        for data in raw {
            guard pendingImages.count < ImageSizing.maxImages else {
                errorMessage = ImageError.tooMany(max: ImageSizing.maxImages).errorDescription
                return
            }
            do {
                pendingImages.append(try imageProcessor.jpegForUpload(data))
            } catch {
                errorMessage = ImageError.unreadable.errorDescription
            }
        }
    }

    func removePendingImage(at index: Int) {
        guard pendingImages.indices.contains(index) else { return }
        pendingImages.remove(at: index)
    }

    func imageData(named name: String) -> Data? {
        store.imageData(named: name)
    }

    // MARK: Envoi

    func send() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        guard !isSending, !text.isEmpty || !images.isEmpty else { return }
        draftText = ""
        pendingImages = []
        await start(text: text, images: images)
    }

    func send(shortcut text: String) async {
        guard !isSending else { return }
        await start(text: text, images: [])
    }

    func retry() async {
        guard let pending = lastFailed, !isSending else { return }
        await perform(pending)
    }

    private func start(text: String, images: [Data]) async {
        let summary = HistorySummary.make(from: messages)
        var fileNames: [String] = []
        for data in images {
            if let name = try? store.storeImage(data) { fileNames.append(name) }
        }
        let userMessage = ChatMessage(conversationId: conversationId, role: .user, text: text, imageFileNames: fileNames)
        messages.append(userMessage)
        store.append(userMessage)
        await perform(PendingSend(text: text, images: images, summary: summary))
    }

    private func perform(_ pending: PendingSend) async {
        guard let api = apiProvider() else {
            errorMessage = APIError.notConfigured.errorDescription
            lastFailed = pending
            canRetry = true
            return
        }
        isSending = true
        errorMessage = nil
        canRetry = false
        let request = ChatRequest(
            message: MessageIn(text: pending.text.isEmpty ? nil : pending.text, images: pending.images.map { $0.base64EncodedString() }),
            quote: currentQuote,
            companyId: companyId,
            historySummary: pending.summary
        )
        do {
            let response = try await api.chat(request)
            lastFailed = nil
            handle(response)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Erreur inattendue. Réessaie."
            lastFailed = pending
            canRetry = true
        }
        isSending = false
    }

    private func handle(_ response: ChatResponse) {
        var payload = response
        if var quote = response.quote {
            let previous = currentQuote
            if let previous {
                if previous.companyId != quote.companyId {
                    // Changement d'entreprise : un devis déjà numéroté reçoit le prochain numéro de la nouvelle entreprise.
                    quote.number = nil
                    if previous.status != .draft { assignNumber(&quote) }
                } else if quote.number == nil, let number = previous.number {
                    quote.number = number
                }
            }
            history.push(quote)
            companyId = quote.companyId
            payload.quote = quote
            receivedQuoteCount += 1
            saveQuote()
        }
        appendAssistant(text: response.assistantText, payload: payload)
    }

    private func appendAssistant(text: String, payload: ChatResponse?) {
        let message = ChatMessage(conversationId: conversationId, role: .assistant, text: text, payload: payload)
        messages.append(message)
        store.append(message)
    }

    private func saveQuote() {
        store.saveQuote(ConversationSnapshot(id: conversationId, companyId: companyId, history: history, coverPhotoFileName: coverPhotoFileName))
    }

    // MARK: Numérotation

    private func assignNumber(_ quote: inout Quote) {
        let assignment = QuoteNumbering.assign(
            counter: store.counter(for: quote.companyId),
            currentYear: currentYear(),
            existing: store.numberedQuotes(),
            quoteId: quote.id
        )
        quote.number = assignment.number
        store.setCounter(assignment.counter)
        if !assignment.skipped.isEmpty {
            let label = Company.label(for: quote.companyId, in: companies())
            notice = "Numéro déjà utilisé pour \(label) (\(assignment.skipped.joined(separator: ", "))) : le devis prend le n° \(assignment.number)."
        }
    }

    /// Valide le devis : attribue un numéro s'il n'en a pas (compteur de l'entreprise) et avertit des doublons.
    func validate() {
        guard var quote = currentQuote else { return }
        if let number = quote.number {
            let dups = QuoteNumbering.duplicates(companyId: quote.companyId, number: number, in: store.numberedQuotes(), excluding: quote.id)
            if let first = dups.first {
                notice = "Attention : le n° \(number) existe déjà pour \(companyLabel) (« \(first.title) »)."
            }
        } else {
            assignNumber(&quote)
        }
        quote.status = .validated
        quote.version += 1
        quote.missing = QuoteRules.computeMissing(quote)
        history.push(quote)
        saveQuote()
        let changes = ["Statut : Brouillon → Validé", "Numéro : \(quote.number ?? "—")"]
        appendAssistant(
            text: "Devis validé (n° \(quote.number ?? "—")).",
            payload: ChatResponse(assistantText: "Devis validé.", intent: .modify, quote: quote, changes: changes)
        )
    }

    // MARK: Modifications locales

    /// Enregistre une saisie manuelle (éditeur) comme nouvelle version.
    func applyManualEdit(_ edited: Quote) {
        guard let previous = currentQuote else { return }
        var quote = QuoteRules.normalized(edited)
        var comparable = quote
        comparable.version = previous.version
        guard comparable != previous else { return }
        quote.version = previous.version + 1
        if quote.companyId != previous.companyId {
            quote.number = nil
            if previous.status != .draft { assignNumber(&quote) }
        }
        history.push(quote)
        companyId = quote.companyId
        saveQuote()
        let changes = LocalChanges.describe(from: previous, to: quote, companies: companies())
        appendAssistant(
            text: "Modifications enregistrées (version \(quote.version)).",
            payload: ChatResponse(assistantText: "Modifications enregistrées.", intent: .modify, quote: quote, changes: changes)
        )
    }

    /// Annule la dernière modification en recopiant la version précédente (l'historique est conservé).
    func undo() {
        guard let before = currentQuote, let restored = history.undo() else { return }
        companyId = restored.companyId
        saveQuote()
        let changes = LocalChanges.describe(from: before, to: restored, companies: companies())
        appendAssistant(
            text: "Dernière modification annulée.",
            payload: ChatResponse(assistantText: "Dernière modification annulée.", intent: .modify, quote: restored, changes: changes)
        )
    }

    func setCoverPhoto(_ data: Data) {
        do {
            let jpeg = try imageProcessor.jpegForUpload(data)
            coverPhotoFileName = try store.storeImage(jpeg)
            saveQuote()
        } catch {
            errorMessage = ImageError.unreadable.errorDescription
        }
    }

    // MARK: Export

    func renderRequest(for quote: Quote) -> RenderRequest {
        var cover: String?
        if quote.options.coverPhoto, let name = coverPhotoFileName, let data = store.imageData(named: name) {
            cover = data.base64EncodedString()
        }
        return RenderRequest(quote: quote, coverPhotoB64: cover)
    }

    func exportPDF() async throws -> URL {
        try await export(ext: "pdf")
    }

    func exportDOCX() async throws -> URL {
        try await export(ext: "docx")
    }

    private func export(ext: String) async throws -> URL {
        guard let quote = currentQuote else { throw APIError.invalidResponse }
        guard let api = apiProvider() else { throw APIError.notConfigured }
        let request = renderRequest(for: quote)
        // Bandeau « BROUILLON » automatique s'il manque des informations.
        let data = ext == "pdf" ? try await api.renderPDF(request, draft: true) : try await api.renderDOCX(request, draft: true)
        let name = FileNaming.quoteFileName(quote: quote, companyLabel: companyLabel, ext: ext)
        return try FileExporter.write(data, fileName: name)
    }
}

/// Liste lisible des changements faits dans l'app (éditeur, annulation).
enum LocalChanges {
    static func describe(from a: Quote, to b: Quote, companies: [Company]) -> [String] {
        var out: [String] = []
        if a.companyId != b.companyId {
            out.append("Entreprise : \(Company.label(for: a.companyId, in: companies)) → \(Company.label(for: b.companyId, in: companies))")
        }
        if a.price.amountTtc != b.price.amountTtc {
            let old = a.price.amountTtc.map { FR.number($0) } ?? "à définir"
            let new = b.price.amountTtc.map { FR.number($0) + FR.nbsp + "€ TTC" } ?? "à définir"
            out.append("Prix : \(old) → \(new)")
        }
        if a.price.vatRate != b.price.vatRate {
            out.append("TVA : \(a.price.vatRate.map { FR.percent($0) } ?? "à définir") → \(b.price.vatRate.map { FR.percent($0) } ?? "à définir")")
        }
        if a.mode != b.mode { out.append("Mode : \(a.mode.label) → \(b.mode.label)") }
        if a.client != b.client { out.append("Coordonnées du client modifiées") }
        if a.siteAddress != b.siteAddress { out.append("Adresse du chantier : \(a.siteAddress ?? "—") → \(b.siteAddress ?? "—")") }
        if a.duration != b.duration { out.append("Durée des travaux : \(a.duration ?? "—") → \(b.duration ?? "—")") }
        if a.lots != b.lots { out.append("Lots modifiés") }
        if a.title != b.title { out.append("Titre : \(b.title)") }
        if a.options.showPriceTable != b.options.showPriceTable {
            out.append("Tableau de prix : \(a.options.showPriceTable ? "affiché" : "masqué") → \(b.options.showPriceTable ? "affiché" : "masqué")")
        }
        if a.options.showSignatures != b.options.showSignatures {
            out.append("Bloc signatures : \(a.options.showSignatures ? "affiché" : "masqué") → \(b.options.showSignatures ? "affiché" : "masqué")")
        }
        if a.options.coverPhoto != b.options.coverPhoto {
            out.append("Page de garde : \(a.options.coverPhoto ? "affichée" : "masquée") → \(b.options.coverPhoto ? "affichée" : "masquée")")
        }
        if a.number != b.number { out.append("Numéro : \(a.number ?? "—") → \(b.number ?? "—")") }
        if a.status != b.status { out.append("Statut : \(a.status.label) → \(b.status.label)") }
        return out
    }
}
