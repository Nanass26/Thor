import Foundation
import Observation

/// Stockage du jeton (Trousseau dans l'app : KeychainStore ; mémoire dans les tests).
protocol TokenStore: AnyObject {
    func readToken() -> String?
    func saveToken(_ token: String)
}

final class InMemoryTokenStore: TokenStore {
    private var token: String?
    init(token: String? = nil) { self.token = token }
    func readToken() -> String? { token }
    func saveToken(_ token: String) { self.token = token }
}

/// Réglages de l'app : URL du serveur (UserDefaults), jeton (Trousseau, jamais UserDefaults),
/// entreprise par défaut, liste des entreprises reçue du serveur.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private let tokenStore: TokenStore

    private(set) var serverURL: String
    private(set) var token: String
    private(set) var defaultCompanyId: String
    private(set) var companies: [Company]
    private(set) var hasSeenPrivacyNotice: Bool
    let isDemo: Bool

    static let privacyNotice = "Les captures sont envoyées à l'IA pour lire la demande ; elles ne sont pas conservées par le serveur."

    private enum Key {
        static let serverURL = "serverURL"
        static let defaultCompany = "defaultCompanyId"
        static let companies = "companiesCache"
        static let privacy = "hasSeenPrivacyNotice"
    }

    init(defaults: UserDefaults = .standard, tokenStore: TokenStore, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        isDemo = arguments.contains("-DEMO")
        if isDemo {
            // Mode démo (simulateur) : serveur local et jeton « demo ».
            defaults.set(ServerConfig.demo.baseURL.absoluteString, forKey: Key.serverURL)
            tokenStore.saveToken(ServerConfig.demo.token)
        }
        serverURL = defaults.string(forKey: Key.serverURL) ?? ""
        token = tokenStore.readToken() ?? ""
        defaultCompanyId = defaults.string(forKey: Key.defaultCompany) ?? "levix"
        if let data = defaults.data(forKey: Key.companies),
           let cached = try? JSONDecoder().decode([Company].self, from: data), !cached.isEmpty {
            companies = cached
        } else {
            companies = Company.fallback
        }
        hasSeenPrivacyNotice = defaults.bool(forKey: Key.privacy)
    }

    var config: ServerConfig? {
        Self.makeConfig(url: serverURL, token: token)
    }

    nonisolated static func makeConfig(url: String, token: String) -> ServerConfig? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), let scheme = parsed.scheme, ["http", "https"].contains(scheme),
              parsed.host != nil, !token.isEmpty else { return nil }
        return ServerConfig(baseURL: parsed, token: token)
    }

    func makeAPI() -> QuoteAPI? {
        config.map { URLSessionQuoteAPI(config: $0) }
    }

    func update(serverURL: String, token: String, defaultCompanyId: String) {
        self.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.defaultCompanyId = defaultCompanyId
        defaults.set(self.serverURL, forKey: Key.serverURL)
        defaults.set(defaultCompanyId, forKey: Key.defaultCompany)
        tokenStore.saveToken(self.token)
    }

    func updateCompanies(_ list: [Company]) {
        guard !list.isEmpty else { return }
        companies = list
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: Key.companies)
        }
        if !list.contains(where: { $0.id == defaultCompanyId }), let first = list.first {
            defaultCompanyId = first.id
            defaults.set(first.id, forKey: Key.defaultCompany)
        }
    }

    func markPrivacyNoticeSeen() {
        hasSeenPrivacyNotice = true
        defaults.set(true, forKey: Key.privacy)
    }

    func label(for companyId: String) -> String {
        Company.label(for: companyId, in: companies)
    }
}
