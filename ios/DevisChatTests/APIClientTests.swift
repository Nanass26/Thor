import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import DevisChat

final class APIClientTests: XCTestCase {
    private var api: URLSessionQuoteAPI!

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
        guard let url = URL(string: "http://mon-mac.local:8000/") else { return XCTFail("URL invalide") }
        api = URLSessionQuoteAPI(config: ServerConfig(baseURL: url, token: "secret"), session: StubURLProtocol.session())
    }

    func testChatEnvoieJetonEtCorpsSnakeCase() async throws {
        let quote = try Fixtures.quote("mo_seule_appartement_53m2")
        StubURLProtocol.handler = { _, _ in
            (200, Data(#"{"assistant_text": "ok", "intent": "modify", "quote": null, "changes": ["Prix : 3 000 → 3 500 € TTC"], "questions": []}"#.utf8))
        }
        let request = ChatRequest(message: MessageIn(text: "Mets 3 500 TTC", images: ["AAAA"]), quote: quote, companyId: "levix", historySummary: nil)
        let response = try await api.chat(request)
        XCTAssertEqual(response.intent, .modify)
        XCTAssertEqual(response.changes.first, "Prix : 3 000 → 3 500 € TTC")

        let sent = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(sent.url?.absoluteString, "http://mon-mac.local:8000/v1/chat")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(sent.timeoutInterval, 90)
        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["company_id"] as? String, "levix")
        let sentQuote = try XCTUnwrap(json["quote"] as? [String: Any])
        XCTAssertNotNil(sentQuote["schema_version"])
        XCTAssertTrue(sentQuote["number"] is NSNull, "null explicite attendu, comme côté serveur")
        let message = try XCTUnwrap(json["message"] as? [String: Any])
        XCTAssertEqual(message["images"] as? [String], ["AAAA"])
    }

    func testErreursTypeesEnFrancais() async throws {
        let cases: [(Int, String, APIError)] = [
            (401, "Jeton refusé : vérifie le jeton dans les Réglages de l'app.", .unauthorized("Jeton refusé : vérifie le jeton dans les Réglages de l'app.")),
            (429, "Plafond quotidien atteint", .quotaExceeded("Plafond quotidien atteint")),
            (502, "L'IA est saturée", .server(status: 502, message: "L'IA est saturée")),
        ]
        for (status, message, expected) in cases {
            StubURLProtocol.handler = { _, _ in (status, Data(#"{"error": "\#(message)"}"#.utf8)) }
            do {
                _ = try await api.health()
                XCTFail("erreur attendue pour \(status)")
            } catch let error as APIError {
                XCTAssertEqual(error, expected)
                XCTAssertEqual(error.errorDescription, message)
            }
        }
    }

    func testServeurInjoignable() async {
        StubURLProtocol.handler = { _, _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await api.health()
            XCTFail("erreur attendue")
        } catch {
            XCTAssertEqual(error as? APIError, .unreachable)
            XCTAssertEqual((error as? APIError)?.errorDescription,
                           "Serveur injoignable. Vérifie que le Mac est allumé, sur le même Wi-Fi, et que le serveur tourne.")
        }
    }

    func testRenduPDFAvecBrouillon() async throws {
        StubURLProtocol.handler = { _, _ in (200, Data("%PDF-1.7".utf8)) }
        let data = try await api.renderPDF(RenderRequest(quote: try Fixtures.quote("fenetre_bois"), coverPhotoB64: nil), draft: true)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "%PDF-1.7")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.absoluteString, "http://mon-mac.local:8000/v1/render/pdf?draft=1")
    }

    func testEntreprisesEtReponseIllisible() async throws {
        StubURLProtocol.handler = { _, _ in (200, Data(#"[{"id": "levix", "label": "LEVIX", "tagline": "DESIGN & BUILD"}]"#.utf8)) }
        let list = try await api.companies()
        XCTAssertEqual(list, [Company(id: "levix", label: "LEVIX", tagline: "DESIGN & BUILD")])
        StubURLProtocol.handler = { _, _ in (200, Data("pas du json".utf8)) }
        do {
            _ = try await api.companies()
            XCTFail("erreur attendue")
        } catch {
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
    }

    func testConfigurationInvalide() {
        XCTAssertNil(AppSettings.makeConfig(url: "", token: "x"))
        XCTAssertNil(AppSettings.makeConfig(url: "mon-mac.local:8000", token: "x"))
        XCTAssertNil(AppSettings.makeConfig(url: "http://mon-mac.local:8000", token: ""))
        XCTAssertEqual(AppSettings.makeConfig(url: " http://mon-mac.local:8000 ", token: "x")?.baseURL.host, "mon-mac.local")
    }
}
