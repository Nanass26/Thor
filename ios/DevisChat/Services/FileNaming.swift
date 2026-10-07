import Foundation

/// Noms de fichiers partagés : Devis_{entreprise}_{client}_{objet}.pdf, sans caractère interdit.
enum FileNaming {
    static func slug(_ text: String?, maxLength: Int) -> String {
        guard let text, !text.isEmpty else { return "" }
        let folded = text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        var out = ""
        var lastWasSeparator = false
        for scalar in folded.unicodeScalars {
            let isAllowed = scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar))
            if isAllowed {
                out.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator && !out.isEmpty {
                out.append("_")
                lastWasSeparator = true
            }
        }
        while out.hasSuffix("_") { out.removeLast() }
        if out.count > maxLength {
            out = String(out.prefix(maxLength))
            while out.hasSuffix("_") { out.removeLast() }
        }
        return out
    }

    static func quoteFileName(quote: Quote, companyLabel: String, ext: String) -> String {
        let parts = ["Devis", slug(companyLabel, maxLength: 20), slug(quote.client.name, maxLength: 25), slug(quote.title, maxLength: 40)]
        return parts.filter { !$0.isEmpty }.joined(separator: "_") + "." + ext
    }
}
