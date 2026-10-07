import Foundation
import Observation

/// Ligne de la liste des devis (indépendante du stockage).
struct QuoteSummary: Identifiable, Equatable {
    var id: UUID
    var title: String
    var companyLabel: String
    var number: String?
    var status: QuoteStatus
    var priceTTC: Int?
    var missingCount: Int
    var updatedAt: Date

    var priceText: String { FR.amountTTC(priceTTC) }
}

@MainActor
@Observable
final class QuoteListViewModel {
    var searchText = ""

    /// Recherche simple : titre, entreprise ou numéro, sans tenir compte des accents ni de la casse.
    func filter(_ items: [QuoteSummary]) -> [QuoteSummary] {
        let query = Self.fold(searchText)
        let sorted = items.sorted { $0.updatedAt > $1.updatedAt }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { item in
            let haystack = Self.fold([item.title, item.companyLabel, item.number ?? ""].joined(separator: " "))
            return haystack.contains(query)
        }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
