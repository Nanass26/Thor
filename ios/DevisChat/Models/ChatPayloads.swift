import Foundation

/// Encodeur / décodeur JSON partagés : les clés passent automatiquement de camelCase (Swift) à snake_case (serveur).
enum JSONCoding {
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

enum ChatIntent: String, Codable, Sendable {
    case new, modify, question
    case clientReplyOnly = "client_reply_only"
}

struct MessageIn: Codable, Equatable, Sendable {
    var text: String?
    var images: [String] // JPEG en base64
}

struct ChatRequest: Codable, Equatable, Sendable {
    var message: MessageIn
    var quote: Quote?
    var companyId: String
    var historySummary: String?
}

struct ChatResponse: Codable, Equatable, Sendable {
    var assistantText: String
    var intent: ChatIntent
    var quote: Quote?
    var changes: [String] = []
    var clientSheet: ClientSheet?
    var advice: Advice?
    var clientReply: String?
    var questions: [String] = []

    enum CodingKeys: String, CodingKey {
        case assistantText, intent, quote, changes, clientSheet, advice, clientReply, questions
    }

    init(assistantText: String, intent: ChatIntent, quote: Quote? = nil, changes: [String] = [],
         clientSheet: ClientSheet? = nil, advice: Advice? = nil, clientReply: String? = nil, questions: [String] = []) {
        self.assistantText = assistantText
        self.intent = intent
        self.quote = quote
        self.changes = changes
        self.clientSheet = clientSheet
        self.advice = advice
        self.clientReply = clientReply
        self.questions = questions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assistantText = try c.decode(String.self, forKey: .assistantText)
        intent = try c.decode(ChatIntent.self, forKey: .intent)
        quote = try c.decodeIfPresent(Quote.self, forKey: .quote)
        changes = try c.decodeIfPresent([String].self, forKey: .changes) ?? []
        clientSheet = try c.decodeIfPresent(ClientSheet.self, forKey: .clientSheet)
        advice = try c.decodeIfPresent(Advice.self, forKey: .advice)
        clientReply = try c.decodeIfPresent(String.self, forKey: .clientReply)
        questions = try c.decodeIfPresent([String].self, forKey: .questions) ?? []
    }
}

struct RenderRequest: Codable, Equatable, Sendable {
    var quote: Quote
    var coverPhotoB64: String?
}

struct HealthResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var mode: String?
    var soffice: Bool?
    var version: String?
}

struct APIErrorBody: Codable, Sendable {
    var error: String
}
