import Foundation

// Miroir Codable du modèle serveur (server/app/models.py), qui reste la source de vérité.
// Les clés JSON sont en snake_case : conversion automatique via JSONCoding (ChatPayloads.swift).
// Les champs absents sont encodés en `null` explicite, exactement comme le serveur.

enum QuoteStatus: String, Codable, CaseIterable, Sendable {
    case draft, validated, sent

    var label: String {
        switch self {
        case .draft: return "Brouillon"
        case .validated: return "Validé"
        case .sent: return "Envoyé"
        }
    }
}

enum QuoteMode: String, Codable, CaseIterable, Sendable {
    case complet
    case mainOeuvreSeule = "main_oeuvre_seule"

    var label: String {
        switch self {
        case .complet: return "Complet (fourniture + pose)"
        case .mainOeuvreSeule: return "Main-d’œuvre seule"
        }
    }
}

struct ClientInfo: Codable, Equatable, Sendable {
    var name: String?
    var email: String?
    var phone: String?

    init(name: String? = nil, email: String? = nil, phone: String? = nil) {
        self.name = name
        self.email = email
        self.phone = phone
    }

    enum CodingKeys: String, CodingKey { case name, email, phone }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(email, forKey: .email)
        try c.encode(phone, forKey: .phone)
    }
}

struct Lot: Codable, Equatable, Sendable {
    var title: String
    var bullets: [String]?
    var paragraph: String?

    init(title: String, bullets: [String]? = nil, paragraph: String? = nil) {
        self.title = title
        self.bullets = bullets
        self.paragraph = paragraph
    }

    enum CodingKeys: String, CodingKey { case title, bullets, paragraph }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(bullets, forKey: .bullets)
        try c.encode(paragraph, forKey: .paragraph)
    }
}

struct Price: Codable, Equatable, Sendable {
    var amountTtc: Int?
    var vatRate: Double?

    init(amountTtc: Int? = nil, vatRate: Double? = nil) {
        self.amountTtc = amountTtc
        self.vatRate = vatRate
    }

    enum CodingKeys: String, CodingKey { case amountTtc, vatRate }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(amountTtc, forKey: .amountTtc)
        try c.encode(vatRate, forKey: .vatRate)
    }

    static let allowedVatRates: [Double] = [5.5, 10, 20]
}

struct PaymentStep: Codable, Equatable, Sendable {
    var label: String
    var percent: Double?
    var amountTtc: Int?

    enum CodingKeys: String, CodingKey { case label, percent, amountTtc }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(percent, forKey: .percent)
        try c.encode(amountTtc, forKey: .amountTtc)
    }
}

struct QuoteOptions: Codable, Equatable, Sendable {
    var showPriceTable: Bool = false
    var showSignatures: Bool = false
    var coverPhoto: Bool = false
}

struct Quote: Codable, Equatable, Identifiable, Sendable {
    var schemaVersion: Int = 1
    var id: String
    var version: Int = 1
    var status: QuoteStatus = .draft
    var companyId: String
    var number: String?
    var date: String // AAAA-MM-JJ
    var client: ClientInfo = ClientInfo()
    var siteAddress: String?
    var title: String = ""
    var intro: String?
    var lots: [Lot] = []
    var mode: QuoteMode = .complet
    var price: Price = Price()
    var duration: String?
    var startDelay: String?
    var validityDays: Int = 30
    var nota: String?
    var paymentSchedule: [PaymentStep] = []
    var options: QuoteOptions = QuoteOptions()
    var missing: [String] = []

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, version, status, companyId, number, date, client, siteAddress, title, intro
        case lots, mode, price, duration, startDelay, validityDays, nota, paymentSchedule, options, missing
    }

    init(id: String = UUID().uuidString.lowercased(), companyId: String, date: String) {
        self.id = id
        self.companyId = companyId
        self.date = date
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try c.decode(String.self, forKey: .id)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        status = try c.decodeIfPresent(QuoteStatus.self, forKey: .status) ?? .draft
        companyId = try c.decode(String.self, forKey: .companyId)
        number = try c.decodeIfPresent(String.self, forKey: .number)
        date = try c.decode(String.self, forKey: .date)
        client = try c.decodeIfPresent(ClientInfo.self, forKey: .client) ?? ClientInfo()
        siteAddress = try c.decodeIfPresent(String.self, forKey: .siteAddress)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        intro = try c.decodeIfPresent(String.self, forKey: .intro)
        lots = try c.decodeIfPresent([Lot].self, forKey: .lots) ?? []
        mode = try c.decodeIfPresent(QuoteMode.self, forKey: .mode) ?? .complet
        price = try c.decodeIfPresent(Price.self, forKey: .price) ?? Price()
        duration = try c.decodeIfPresent(String.self, forKey: .duration)
        startDelay = try c.decodeIfPresent(String.self, forKey: .startDelay)
        validityDays = try c.decodeIfPresent(Int.self, forKey: .validityDays) ?? 30
        nota = try c.decodeIfPresent(String.self, forKey: .nota)
        paymentSchedule = try c.decodeIfPresent([PaymentStep].self, forKey: .paymentSchedule) ?? []
        options = try c.decodeIfPresent(QuoteOptions.self, forKey: .options) ?? QuoteOptions()
        missing = try c.decodeIfPresent([String].self, forKey: .missing) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        try c.encode(version, forKey: .version)
        try c.encode(status, forKey: .status)
        try c.encode(companyId, forKey: .companyId)
        try c.encode(number, forKey: .number)
        try c.encode(date, forKey: .date)
        try c.encode(client, forKey: .client)
        try c.encode(siteAddress, forKey: .siteAddress)
        try c.encode(title, forKey: .title)
        try c.encode(intro, forKey: .intro)
        try c.encode(lots, forKey: .lots)
        try c.encode(mode, forKey: .mode)
        try c.encode(price, forKey: .price)
        try c.encode(duration, forKey: .duration)
        try c.encode(startDelay, forKey: .startDelay)
        try c.encode(validityDays, forKey: .validityDays)
        try c.encode(nota, forKey: .nota)
        try c.encode(paymentSchedule, forKey: .paymentSchedule)
        try c.encode(options, forKey: .options)
        try c.encode(missing, forKey: .missing)
    }

    /// Le devis est incomplet tant qu'il reste des champs obligatoires à remplir.
    var isIncomplete: Bool { !missing.isEmpty }
}
