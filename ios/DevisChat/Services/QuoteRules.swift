import Foundation

/// Règles métier calculées localement (mêmes résultats que le serveur).
enum QuoteRules {
    /// Champs obligatoires absents — même ordre et mêmes libellés que `compute_missing` côté serveur.
    static func computeMissing(_ q: Quote) -> [String] {
        var missing: [String] = []
        if isBlank(q.client.name) { missing.append("Nom du client") }
        if isBlank(q.siteAddress) { missing.append("Adresse du chantier") }
        if q.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append("Titre du devis") }
        if q.lots.isEmpty { missing.append("Description des travaux") }
        if q.price.amountTtc == nil { missing.append("Prix") }
        if q.price.vatRate == nil { missing.append("Taux de TVA") }
        if isBlank(q.duration) { missing.append("Durée des travaux") }
        return missing
    }

    /// (HT, TVA) arrondis au centime à partir du TTC, ou nil si le prix ou le taux manque.
    static func htAndVat(amountTtc: Int?, vatRate: Double?) -> (ht: Decimal, vat: Decimal)? {
        guard let amountTtc, let vatRate else { return nil }
        let ttc = Decimal(amountTtc)
        let divisor = 1 + Decimal(vatRate) / 100 // 5,5 / 10 / 20 sont exacts en binaire
        var raw = ttc / divisor
        var ht = Decimal()
        NSDecimalRound(&ht, &raw, 2, .plain)
        return (ht, ttc - ht)
    }

    static func isBlank(_ s: String?) -> Bool {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Nettoie une saisie manuelle : chaînes vides → nil, puis recalcule `missing`.
    static func normalized(_ q: Quote) -> Quote {
        var q = q
        func clean(_ s: String?) -> String? {
            guard let s else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        q.client.name = clean(q.client.name)
        q.client.email = clean(q.client.email)
        q.client.phone = clean(q.client.phone)
        q.siteAddress = clean(q.siteAddress)
        q.duration = clean(q.duration)
        q.startDelay = clean(q.startDelay)
        q.nota = clean(q.nota)
        q.missing = computeMissing(q)
        return q
    }
}
