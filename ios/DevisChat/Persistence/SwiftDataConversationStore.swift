import Foundation
import SwiftData

/// Stockage local réel (SwiftData + fichiers image dans Application Support).
@MainActor
final class SwiftDataConversationStore: ConversationStore {
    private let context: ModelContext
    private let imagesDirectory: URL

    init(context: ModelContext, imagesDirectory: URL? = nil) {
        self.context = context
        self.imagesDirectory = imagesDirectory ?? Self.defaultImagesDirectory()
    }

    static func defaultImagesDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: Lecture

    private func record(_ id: UUID) -> QuoteRecord? {
        let target = id
        var descriptor = FetchDescriptor<QuoteRecord>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func messageRecords(_ id: UUID) -> [MessageRecord] {
        let target = id
        let descriptor = FetchDescriptor<MessageRecord>(
            predicate: #Predicate { $0.quoteId == target },
            sortBy: [SortDescriptor(\MessageRecord.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func load(_ id: UUID) -> ConversationSnapshot? {
        guard let rec = record(id) else { return nil }
        let decoder = JSONCoding.decoder()
        let versions = rec.versions.compactMap { try? decoder.decode(Quote.self, from: $0) }
        let messages = messageRecords(id).map { m in
            ChatMessage(
                id: m.id,
                conversationId: m.quoteId,
                role: ChatMessage.Role(rawValue: m.role) ?? .assistant,
                text: m.text,
                createdAt: m.createdAt,
                imageFileNames: m.imageFileNames,
                payload: m.payload.flatMap { try? decoder.decode(ChatResponse.self, from: $0) }
            )
        }
        return ConversationSnapshot(id: id, companyId: rec.companyId, history: QuoteHistory(versions: versions),
                                    messages: messages, coverPhotoFileName: rec.coverPhotoFileName)
    }

    // MARK: Écriture

    private func recordOrCreate(_ id: UUID, companyId: String) -> QuoteRecord {
        if let existing = record(id) { return existing }
        let created = QuoteRecord(id: id, companyId: companyId)
        context.insert(created)
        return created
    }

    func saveQuote(_ snapshot: ConversationSnapshot) {
        let rec = recordOrCreate(snapshot.id, companyId: snapshot.companyId)
        let encoder = JSONCoding.encoder()
        rec.versions = snapshot.history.versions.compactMap { try? encoder.encode($0) }
        rec.currentVersion = rec.versions.last
        rec.companyId = snapshot.companyId
        rec.coverPhotoFileName = snapshot.coverPhotoFileName
        if let quote = snapshot.history.current {
            rec.title = quote.title.isEmpty ? "Devis sans titre" : quote.title
            rec.number = quote.number
            rec.status = quote.status.rawValue
            rec.priceTTC = quote.price.amountTtc
            rec.missingCount = quote.missing.count
        }
        rec.updatedAt = Date()
        try? context.save()
    }

    func append(_ message: ChatMessage) {
        let rec = recordOrCreate(message.conversationId, companyId: "")
        if rec.currentVersion == nil, message.role == .user, rec.title == "Nouveau devis" {
            // Titre provisoire : début de la première demande.
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            rec.title = text.isEmpty ? "Demande avec captures" : String(text.prefix(50))
        }
        rec.updatedAt = Date()
        let payload = message.payload.flatMap { try? JSONCoding.encoder().encode($0) }
        context.insert(MessageRecord(id: message.id, quoteId: message.conversationId, role: message.role.rawValue,
                                     text: message.text, createdAt: message.createdAt,
                                     imageFileNames: message.imageFileNames, payload: payload))
        try? context.save()
    }

    func numberedQuotes() -> [NumberedQuote] {
        let descriptor = FetchDescriptor<QuoteRecord>(predicate: #Predicate { $0.number != nil })
        let records = (try? context.fetch(descriptor)) ?? []
        let decoder = JSONCoding.decoder()
        return records.compactMap { rec in
            guard let data = rec.currentVersion, let quote = try? decoder.decode(Quote.self, from: data),
                  let number = quote.number else { return nil }
            return NumberedQuote(quoteId: quote.id, companyId: quote.companyId, number: number, title: quote.title)
        }
    }

    func counter(for companyId: String) -> NumberCounter {
        let target = companyId
        var descriptor = FetchDescriptor<CounterRecord>(predicate: #Predicate { $0.companyId == target })
        descriptor.fetchLimit = 1
        if let rec = (try? context.fetch(descriptor))?.first {
            return NumberCounter(companyId: rec.companyId, nextNumber: rec.nextNumber, year: rec.year)
        }
        return NumberCounter(companyId: companyId, nextNumber: 1, year: QuoteNumbering.currentYear())
    }

    func setCounter(_ counter: NumberCounter) {
        let target = counter.companyId
        var descriptor = FetchDescriptor<CounterRecord>(predicate: #Predicate { $0.companyId == target })
        descriptor.fetchLimit = 1
        if let rec = (try? context.fetch(descriptor))?.first {
            rec.nextNumber = counter.nextNumber
            rec.year = counter.year
        } else {
            context.insert(CounterRecord(companyId: counter.companyId, nextNumber: counter.nextNumber, year: counter.year))
        }
        try? context.save()
    }

    // MARK: Images

    func storeImage(_ data: Data) throws -> String {
        let name = UUID().uuidString + ".jpg"
        try data.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }

    func imageData(named name: String) -> Data? {
        try? Data(contentsOf: imagesDirectory.appendingPathComponent(name))
    }

    // MARK: Suppression (balayage dans la liste)

    func deleteConversation(_ id: UUID) {
        for message in messageRecords(id) {
            for name in message.imageFileNames {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
            }
            context.delete(message)
        }
        if let rec = record(id) {
            if let cover = rec.coverPhotoFileName {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(cover))
            }
            context.delete(rec)
        }
        try? context.save()
    }
}
