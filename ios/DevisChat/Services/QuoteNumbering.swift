import Foundation

/// Compteur de numéros de devis pour une entreprise (persisté par CounterRecord).
struct NumberCounter: Equatable, Sendable {
    var companyId: String
    var nextNumber: Int
    var year: Int
}

/// Un devis numéroté de l'historique local (pour détecter les doublons).
struct NumberedQuote: Equatable, Sendable {
    var quoteId: String
    var companyId: String
    var number: String
    var title: String
}

/// Numérotation « NN/YY » par entreprise. Le numéro n'est JAMAIS attribué par le serveur ni par l'IA.
enum QuoteNumbering {
    static func format(_ n: Int, year: Int) -> String {
        String(format: "%02d/%02d", n, year % 100)
    }

    /// Devis de la même entreprise qui portent déjà ce numéro (hors devis `excluding`).
    static func duplicates(companyId: String, number: String, in existing: [NumberedQuote], excluding quoteId: String? = nil) -> [NumberedQuote] {
        existing.filter { $0.companyId == companyId && $0.number == number && $0.quoteId != quoteId }
    }

    struct Assignment: Equatable {
        var number: String
        var counter: NumberCounter
        /// Numéros sautés parce qu'ils existaient déjà (doublons évités) : à signaler à l'utilisateur.
        var skipped: [String]
    }

    /// Prochain numéro libre pour l'entreprise. Remet le compteur à 1 au changement d'année.
    static func assign(counter: NumberCounter, currentYear: Int, existing: [NumberedQuote], quoteId: String) -> Assignment {
        var n = counter.year == currentYear ? max(counter.nextNumber, 1) : 1
        var skipped: [String] = []
        var candidate = format(n, year: currentYear)
        while !duplicates(companyId: counter.companyId, number: candidate, in: existing, excluding: quoteId).isEmpty {
            skipped.append(candidate)
            n += 1
            candidate = format(n, year: currentYear)
        }
        let updated = NumberCounter(companyId: counter.companyId, nextNumber: n + 1, year: currentYear)
        return Assignment(number: candidate, counter: updated, skipped: skipped)
    }

    static func currentYear(_ now: Date = Date()) -> Int {
        Calendar(identifier: .gregorian).component(.year, from: now)
    }
}
