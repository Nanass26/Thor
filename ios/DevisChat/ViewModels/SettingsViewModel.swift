import Foundation
import Observation

/// Écran Réglages : serveur, jeton, entreprise par défaut, prochain numéro par entreprise.
@MainActor
@Observable
final class SettingsViewModel {
    var serverURL: String
    var token: String
    var defaultCompanyId: String
    /// Prochain numéro modifiable, par identifiant d'entreprise.
    var nextNumbers: [String: Int] = [:]
    private(set) var connectionStatus: String?
    private(set) var connectionOK: Bool?
    private(set) var isTesting = false

    private let settings: AppSettings
    private let store: ConversationStore
    private let makeAPI: (ServerConfig) -> QuoteAPI
    private let currentYear: () -> Int

    init(settings: AppSettings, store: ConversationStore,
         makeAPI: @escaping (ServerConfig) -> QuoteAPI = { URLSessionQuoteAPI(config: $0) },
         currentYear: @escaping () -> Int = { QuoteNumbering.currentYear() }) {
        self.settings = settings
        self.store = store
        self.makeAPI = makeAPI
        self.currentYear = currentYear
        serverURL = settings.serverURL
        token = settings.token
        defaultCompanyId = settings.defaultCompanyId
        reloadCounters()
    }

    var companies: [Company] { settings.companies }

    func reloadCounters() {
        let year = currentYear()
        for company in settings.companies {
            let counter = store.counter(for: company.id)
            nextNumbers[company.id] = counter.year == year ? counter.nextNumber : 1
        }
    }

    /// Aperçu du prochain numéro, ex. « 27/26 ».
    func preview(for companyId: String) -> String {
        QuoteNumbering.format(nextNumbers[companyId] ?? 1, year: currentYear())
    }

    /// Avertissement si le prochain numéro choisi existe déjà dans l'historique local.
    func duplicateWarning(for companyId: String) -> String? {
        let number = preview(for: companyId)
        let dups = QuoteNumbering.duplicates(companyId: companyId, number: number, in: store.numberedQuotes())
        guard let first = dups.first else { return nil }
        return "Le n° \(number) existe déjà (« \(first.title) »)."
    }

    func save() {
        settings.update(serverURL: serverURL, token: token, defaultCompanyId: defaultCompanyId)
        let year = currentYear()
        for (companyId, next) in nextNumbers {
            store.setCounter(NumberCounter(companyId: companyId, nextNumber: max(1, next), year: year))
        }
    }

    /// Appelle /v1/health avec les valeurs saisies (sans les enregistrer) et récupère la liste des entreprises.
    func testConnection() async {
        guard let config = AppSettings.makeConfig(url: serverURL, token: token) else {
            connectionOK = false
            connectionStatus = "Adresse ou jeton invalide. Exemple d'adresse : http://mon-mac.local:8000"
            return
        }
        isTesting = true
        defer { isTesting = false }
        let api = makeAPI(config)
        do {
            let health = try await api.health()
            let mode = health.mode == "mock" ? "démo (sans IA)" : "réel (IA active)"
            let pdf = health.soffice == false ? " — attention : LibreOffice absent, pas de PDF" : ""
            connectionOK = true
            connectionStatus = "Connexion réussie : serveur en mode \(mode)\(pdf)."
            if let list = try? await api.companies() {
                settings.updateCompanies(list)
                reloadCounters()
            }
        } catch {
            connectionOK = false
            connectionStatus = (error as? LocalizedError)?.errorDescription ?? "Échec de la connexion."
        }
    }
}
