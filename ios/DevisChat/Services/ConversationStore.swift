import Foundation

/// Un message du chat (côté app).
struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant }

    var id: UUID = UUID()
    var conversationId: UUID
    var role: Role
    var text: String
    var createdAt: Date = Date()
    var imageFileNames: [String] = []
    /// Réponse structurée du serveur associée (carte devis, fiche, conseils, message client).
    var payload: ChatResponse?
}

/// État complet d'une conversation (= un devis et ses versions).
struct ConversationSnapshot: Equatable, Sendable {
    var id: UUID
    var companyId: String
    var history: QuoteHistory = QuoteHistory()
    var messages: [ChatMessage] = []
    var coverPhotoFileName: String?
}

/// Stockage local (SwiftData dans l'app, mémoire dans les tests et les aperçus SwiftUI).
@MainActor
protocol ConversationStore: AnyObject {
    func load(_ id: UUID) -> ConversationSnapshot?
    /// Enregistre le devis (versions, titre, numéro, statut) de la conversation.
    func saveQuote(_ snapshot: ConversationSnapshot)
    func append(_ message: ChatMessage)
    func numberedQuotes() -> [NumberedQuote]
    func counter(for companyId: String) -> NumberCounter
    func setCounter(_ counter: NumberCounter)
    func storeImage(_ data: Data) throws -> String
    func imageData(named name: String) -> Data?
}

/// Implémentation en mémoire (tests, aperçus).
@MainActor
final class InMemoryConversationStore: ConversationStore {
    var snapshots: [UUID: ConversationSnapshot] = [:]
    var counters: [String: NumberCounter] = [:]
    var images: [String: Data] = [:]
    var defaultYear: Int

    init(defaultYear: Int = QuoteNumbering.currentYear()) {
        self.defaultYear = defaultYear
    }

    func load(_ id: UUID) -> ConversationSnapshot? { snapshots[id] }

    func saveQuote(_ snapshot: ConversationSnapshot) {
        var stored = snapshots[snapshot.id] ?? ConversationSnapshot(id: snapshot.id, companyId: snapshot.companyId)
        stored.companyId = snapshot.companyId
        stored.history = snapshot.history
        stored.coverPhotoFileName = snapshot.coverPhotoFileName
        snapshots[snapshot.id] = stored
    }

    func append(_ message: ChatMessage) {
        var stored = snapshots[message.conversationId] ?? ConversationSnapshot(id: message.conversationId, companyId: "")
        stored.messages.append(message)
        snapshots[message.conversationId] = stored
    }

    func numberedQuotes() -> [NumberedQuote] {
        snapshots.values.compactMap { snap in
            guard let q = snap.history.current, let number = q.number else { return nil }
            return NumberedQuote(quoteId: q.id, companyId: q.companyId, number: number, title: q.title)
        }
    }

    func counter(for companyId: String) -> NumberCounter {
        counters[companyId] ?? NumberCounter(companyId: companyId, nextNumber: 1, year: defaultYear)
    }

    func setCounter(_ counter: NumberCounter) {
        counters[counter.companyId] = counter
    }

    func storeImage(_ data: Data) throws -> String {
        let name = UUID().uuidString + ".jpg"
        images[name] = data
        return name
    }

    func imageData(named name: String) -> Data? { images[name] }
}
