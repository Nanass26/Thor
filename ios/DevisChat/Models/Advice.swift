import Foundation

/// Fiche lue dans les captures d'écran (jamais conservée par le serveur).
struct ClientSheet: Codable, Equatable, Sendable {
    var source: String?
    var clientName: String?
    var clientFirstName: String?
    var city: String?
    var postalCode: String?
    var jobSummary: String?
    var surfaceM2: Double?
    var rooms: [String] = []
    var constraints: [String] = []
    var deadline: String?
    var budgetHint: String?
    var snippets: [String] = []
    var observations: [String] = []
    var uncertain: [String] = []

    enum CodingKeys: String, CodingKey {
        case source, clientName, clientFirstName, city, postalCode, jobSummary, surfaceM2
        case rooms, constraints, deadline, budgetHint, snippets, observations, uncertain
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        clientName = try c.decodeIfPresent(String.self, forKey: .clientName)
        clientFirstName = try c.decodeIfPresent(String.self, forKey: .clientFirstName)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        postalCode = try c.decodeIfPresent(String.self, forKey: .postalCode)
        jobSummary = try c.decodeIfPresent(String.self, forKey: .jobSummary)
        surfaceM2 = try c.decodeIfPresent(Double.self, forKey: .surfaceM2)
        rooms = try c.decodeIfPresent([String].self, forKey: .rooms) ?? []
        constraints = try c.decodeIfPresent([String].self, forKey: .constraints) ?? []
        deadline = try c.decodeIfPresent(String.self, forKey: .deadline)
        budgetHint = try c.decodeIfPresent(String.self, forKey: .budgetHint)
        snippets = try c.decodeIfPresent([String].self, forKey: .snippets) ?? []
        observations = try c.decodeIfPresent([String].self, forKey: .observations) ?? []
        uncertain = try c.decodeIfPresent([String].self, forKey: .uncertain) ?? []
    }

    /// Lignes lisibles pour le bloc dépliable « Fiche lue dans la capture ».
    var displayLines: [(label: String, value: String)] {
        var lines: [(String, String)] = []
        let name = [clientFirstName, clientName].compactMap { $0 }.joined(separator: " ")
        if !name.isEmpty { lines.append(("Client", name)) }
        let place = [postalCode, city].compactMap { $0 }.joined(separator: " ")
        if !place.isEmpty { lines.append(("Lieu", place)) }
        if let jobSummary { lines.append(("Travaux", jobSummary)) }
        if let surfaceM2 { lines.append(("Surface", FR.surface(surfaceM2))) }
        if !rooms.isEmpty { lines.append(("Pièces", rooms.joined(separator: ", "))) }
        if !constraints.isEmpty { lines.append(("Contraintes", constraints.joined(separator: " ; "))) }
        if let deadline { lines.append(("Délai", deadline)) }
        if let budgetHint { lines.append(("Budget évoqué", budgetHint)) }
        for o in observations { lines.append(("Vu sur la photo", o)) }
        for u in uncertain { lines.append(("À confirmer", u)) }
        return lines
    }
}

struct PriceRange: Codable, Equatable, Sendable {
    var low: Int?
    var high: Int?
    var basis: String
    var comparableIds: [String] = []
    var note: String?

    enum CodingKeys: String, CodingKey { case low, high, basis, comparableIds, note }

    init(low: Int? = nil, high: Int? = nil, basis: String, comparableIds: [String] = [], note: String? = nil) {
        self.low = low
        self.high = high
        self.basis = basis
        self.comparableIds = comparableIds
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        low = try c.decodeIfPresent(Int.self, forKey: .low)
        high = try c.decodeIfPresent(Int.self, forKey: .high)
        basis = try c.decodeIfPresent(String.self, forKey: .basis) ?? "aucune"
        comparableIds = try c.decodeIfPresent([String].self, forKey: .comparableIds) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

struct Risk: Codable, Equatable, Sendable {
    var label: String
    var why: String
}

/// Conseils pour l'artisan : jamais écrits dans le devis.
struct Advice: Codable, Equatable, Sendable {
    var priceRange: PriceRange?
    var risks: [Risk] = []
    var questions: [String] = []

    enum CodingKeys: String, CodingKey { case priceRange, risks, questions }

    init(priceRange: PriceRange? = nil, risks: [Risk] = [], questions: [String] = []) {
        self.priceRange = priceRange
        self.risks = risks
        self.questions = questions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        priceRange = try c.decodeIfPresent(PriceRange.self, forKey: .priceRange)
        risks = try c.decodeIfPresent([Risk].self, forKey: .risks) ?? []
        questions = try c.decodeIfPresent([String].self, forKey: .questions) ?? []
    }

    static let disclaimer = "Indicatif — c'est toi qui décides du prix"
}
