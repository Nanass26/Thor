import Foundation

/// Typographie française, alignée sur server/app/typo.py.
enum FR {
    static let nbsp = "\u{00A0}"   // espace insécable
    static let nnbsp = "\u{202F}"  // espace fine insécable (milliers)

    private static let months = [
        "janvier", "février", "mars", "avril", "mai", "juin",
        "juillet", "août", "septembre", "octobre", "novembre", "décembre",
    ]

    /// 6500 → « 6 500 » (fine insécable).
    static func number(_ value: Int) -> String {
        let digits = String(abs(value))
        var groups: [String] = []
        var rest = Substring(digits)
        while rest.count > 3 {
            groups.insert(String(rest.suffix(3)), at: 0)
            rest = rest.dropLast(3)
        }
        groups.insert(String(rest), at: 0)
        return (value < 0 ? "-" : "") + groups.joined(separator: nnbsp)
    }

    /// 3000 → « 3 000 € ».
    static func amount(_ value: Int) -> String {
        number(value) + nbsp + "€"
    }

    /// « 3 000 € TTC » ou « Prix à définir ».
    static func amountTTC(_ value: Int?) -> String {
        guard let value else { return "Prix à définir" }
        return amount(value) + nbsp + "TTC"
    }

    private static func shortDecimal(_ value: Double) -> String {
        if value.rounded() == value {
            return number(Int(value))
        }
        let cents = Int((value * 100).rounded())
        let whole = number(cents / 100)
        var frac = String(format: "%02d", abs(cents % 100))
        if frac.hasSuffix("0") { frac.removeLast() }
        return whole + "," + frac
    }

    /// 10 → « 10 % » ; 5.5 → « 5,5 % ».
    static func percent(_ value: Double) -> String {
        shortDecimal(value) + nbsp + "%"
    }

    /// 53 → « 53 m² ».
    static func surface(_ value: Double) -> String {
        shortDecimal(value) + nbsp + "m²"
    }

    /// « 2026-10-07 » → « 7 octobre 2026 » (« 1er » pour le premier du mois).
    static func date(iso: String) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return iso }
        let day = parts[2] == 1 ? "1er" : String(parts[2])
        return "\(day) \(months[parts[1] - 1]) \(parts[0])"
    }

    /// Date du jour au format AAAA-MM-JJ (calendrier grégorien, fuseau local).
    static func isoToday(_ now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    /// Remplace les espaces insécables par des espaces normaux (comparaisons, tests).
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: nbsp, with: " ").replacingOccurrences(of: nnbsp, with: " ")
    }
}
