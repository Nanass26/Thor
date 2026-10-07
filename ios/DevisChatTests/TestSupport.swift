import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import DevisChat

/// Accès aux devis d'exemple partagés avec les tests du serveur (shared/fixtures/).
enum Fixtures {
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["DEVISCHAT_FIXTURES"] {
            return URL(fileURLWithPath: override)
        }
        // …/ios/DevisChatTests/TestSupport.swift → racine du dépôt → shared/fixtures
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures")
    }

    static var names: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
    }

    static func quote(_ name: String) throws -> Quote {
        try JSONCoding.decoder().decode(Quote.self, from: data(name))
    }
}

/// Faux serveur pour les tests des view models.
final class FakeQuoteAPI: QuoteAPI, @unchecked Sendable {
    var chatHandler: (ChatRequest) throws -> ChatResponse = { _ in ChatResponse(assistantText: "ok", intent: .question) }
    var healthResult: Result<HealthResponse, APIError> = .success(HealthResponse(ok: true, mode: "mock", soffice: true, version: "0.1.0"))
    var companyList: [Company] = Company.fallback
    var renderedData = Data("%PDF-1.7 faux".utf8)
    private(set) var chatRequests: [ChatRequest] = []
    private(set) var renderRequests: [(RenderRequest, Bool)] = []

    func health() async throws -> HealthResponse { try healthResult.get() }
    func companies() async throws -> [Company] { companyList }

    func chat(_ request: ChatRequest) async throws -> ChatResponse {
        chatRequests.append(request)
        return try chatHandler(request)
    }

    func renderPDF(_ request: RenderRequest, draft: Bool) async throws -> Data {
        renderRequests.append((request, draft))
        return renderedData
    }

    func renderDOCX(_ request: RenderRequest, draft: Bool) async throws -> Data {
        renderRequests.append((request, draft))
        return Data("PK faux docx".utf8)
    }
}

/// URLProtocol factice : intercepte les requêtes de URLSession.
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest, Data?) throws -> (Int, Data))?
    static var lastRequest: URLRequest?
    static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.readStream(request.httpBodyStream)
        Self.lastRequest = request
        Self.lastBody = body
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        do {
            let (status, data) = try handler(request, body)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func readStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}
