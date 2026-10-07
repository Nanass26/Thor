import Foundation

/// Historique des versions d'un devis. On ne détruit jamais une version :
/// « Annuler » recopie la version précédente comme nouvelle version courante.
struct QuoteHistory: Equatable, Sendable {
    private(set) var versions: [Quote]

    init(versions: [Quote] = []) {
        self.versions = versions
    }

    var current: Quote? { versions.last }

    var canUndo: Bool { versions.count >= 2 }

    mutating func push(_ quote: Quote) {
        versions.append(quote)
    }

    /// Recopie l'avant-dernière version comme nouvelle version courante (numéro de version croissant).
    @discardableResult
    mutating func undo() -> Quote? {
        guard versions.count >= 2, let current else { return nil }
        var restored = versions[versions.count - 2]
        restored.version = current.version + 1
        restored.missing = QuoteRules.computeMissing(restored)
        versions.append(restored)
        return restored
    }
}
