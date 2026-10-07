import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Erreurs réseau typées, avec des messages en français pour l'utilisateur.
enum APIError: LocalizedError, Equatable {
    case notConfigured
    case unreachable
    case unauthorized(String)
    case quotaExceeded(String)
    case server(status: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Le serveur n'est pas configuré : renseigne son adresse et le jeton dans les Réglages."
        case .unreachable:
            return "Serveur injoignable. Vérifie que le Mac est allumé, sur le même Wi-Fi, et que le serveur tourne."
        case .unauthorized(let message):
            return message.isEmpty ? "Jeton refusé : vérifie le jeton dans les Réglages." : message
        case .quotaExceeded(let message):
            return message.isEmpty ? "Plafond quotidien d'appels à l'IA atteint. Réessaie demain." : message
        case .server(_, let message):
            return message.isEmpty ? "Erreur du serveur. Réessaie dans un instant." : message
        case .invalidResponse:
            return "Réponse du serveur illisible. Vérifie que l'app et le serveur sont à jour."
        }
    }
}

struct ServerConfig: Equatable, Sendable {
    var baseURL: URL
    var token: String

    static let demo = ServerConfig(baseURL: URL(string: "http://127.0.0.1:8000") ?? URL(fileURLWithPath: "/"), token: "demo")
}

/// Accès au serveur (protocole pour pouvoir le simuler dans les tests).
protocol QuoteAPI: Sendable {
    func health() async throws -> HealthResponse
    func companies() async throws -> [Company]
    func chat(_ request: ChatRequest) async throws -> ChatResponse
    func renderPDF(_ request: RenderRequest, draft: Bool) async throws -> Data
    func renderDOCX(_ request: RenderRequest, draft: Bool) async throws -> Data
}

final class URLSessionQuoteAPI: QuoteAPI, @unchecked Sendable {
    let config: ServerConfig
    private let session: URLSession

    static let chatTimeout: TimeInterval = 90
    static let renderTimeout: TimeInterval = 60
    static let shortTimeout: TimeInterval = 10

    init(config: ServerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: Routes

    func health() async throws -> HealthResponse {
        try decode(try await send(path: "/v1/health", method: "GET", body: nil, timeout: Self.shortTimeout))
    }

    func companies() async throws -> [Company] {
        try decode(try await send(path: "/v1/companies", method: "GET", body: nil, timeout: Self.shortTimeout))
    }

    func chat(_ request: ChatRequest) async throws -> ChatResponse {
        try decode(try await send(path: "/v1/chat", method: "POST", body: try encode(request), timeout: Self.chatTimeout))
    }

    func renderPDF(_ request: RenderRequest, draft: Bool) async throws -> Data {
        try await send(path: "/v1/render/pdf" + (draft ? "?draft=1" : ""), method: "POST", body: try encode(request), timeout: Self.renderTimeout)
    }

    func renderDOCX(_ request: RenderRequest, draft: Bool) async throws -> Data {
        try await send(path: "/v1/render/docx" + (draft ? "?draft=1" : ""), method: "POST", body: try encode(request), timeout: Self.renderTimeout)
    }

    // MARK: Transport

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONCoding.encoder().encode(value)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONCoding.decoder().decode(T.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    func makeRequest(path: String, method: String, body: Data?, timeout: TimeInterval) throws -> URLRequest {
        let base = config.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path), url.scheme == "http" || url.scheme == "https" else {
            throw APIError.notConfigured
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(path: String, method: String, body: Data?, timeout: TimeInterval) async throws -> Data {
        let request = try makeRequest(path: path, method: method, body: body, timeout: timeout)
        let (data, response) = try await perform(request)
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONCoding.decoder().decode(APIErrorBody.self, from: data))?.error ?? ""
            switch response.statusCode {
            case 401: throw APIError.unauthorized(message)
            case 429: throw APIError.quotaExceeded(message)
            default: throw APIError.server(status: response.statusCode, message: message)
            }
        }
        return data
    }

    /// dataTask + continuation : fonctionne de la même façon sur iOS et sous Linux (tests).
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if error != nil {
                    continuation.resume(throwing: APIError.unreachable)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: APIError.invalidResponse)
                    return
                }
                continuation.resume(returning: (data ?? Data(), http))
            }
            task.resume()
        }
    }
}
