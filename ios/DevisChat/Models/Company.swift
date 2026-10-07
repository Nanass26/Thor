import Foundation

/// Profil d'entreprise tel que renvoyé par /v1/companies (libellés seulement : les infos légales restent sur le serveur).
struct Company: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    var tagline: String

    /// Liste de secours tant que le serveur n'a pas été joint (identifiants prévus dans le brief).
    static let fallback: [Company] = [
        Company(id: "levix", label: "LEVIX", tagline: "DESIGN & BUILD"),
        Company(id: "sar_bat", label: "SAR BAT", tagline: ""),
        Company(id: "sb_concept", label: "SB CONCEPT", tagline: ""),
        Company(id: "m_bat", label: "M BAT", tagline: ""),
        Company(id: "id_bat", label: "ID BAT", tagline: ""),
    ]

    static func label(for id: String, in companies: [Company]) -> String {
        companies.first { $0.id == id }?.label ?? id
    }
}
