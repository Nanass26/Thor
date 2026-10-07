import Foundation
import XCTest
@testable import DevisChat

/// Les devis d'exemple (source unique partagée avec pytest) se décodent, se réencodent à l'identique,
/// et les règles locales donnent les mêmes résultats que le serveur.
final class FixturesTests: XCTestCase {
    func testAuMoinsSixFixtures() {
        XCTAssertGreaterThanOrEqual(Fixtures.names.count, 6, "fixtures introuvables dans \(Fixtures.directory.path)")
    }

    func testAllerRetourJSON() throws {
        for name in Fixtures.names {
            let quote = try Fixtures.quote(name)
            let encoded = try JSONCoding.encoder().encode(quote)
            let again = try JSONCoding.decoder().decode(Quote.self, from: encoded)
            XCTAssertEqual(quote, again, name)
        }
    }

    func testEncodageIdentiqueAuServeur() throws {
        // Mêmes clés snake_case et mêmes valeurs (null explicites compris) que le fichier d'origine.
        for name in Fixtures.names {
            let original = try JSONSerialization.jsonObject(with: Fixtures.data(name)) as? NSDictionary
            let encoded = try JSONCoding.encoder().encode(Fixtures.quote(name))
            let roundTrip = try JSONSerialization.jsonObject(with: encoded) as? NSDictionary
            XCTAssertNotNil(original)
            XCTAssertEqual(original, roundTrip, name)
        }
    }

    func testMissingIdentiqueAuServeur() throws {
        for name in Fixtures.names {
            let quote = try Fixtures.quote(name)
            XCTAssertEqual(QuoteRules.computeMissing(quote), quote.missing, name)
        }
    }

    func testValeursDuCasDeReference() throws {
        let q = try Fixtures.quote("mo_seule_appartement_53m2")
        XCTAssertEqual(q.mode, .mainOeuvreSeule)
        XCTAssertEqual(q.price.amountTtc, 3000)
        XCTAssertEqual(q.price.vatRate, 10)
        XCTAssertEqual(q.lots.count, 3)
        XCTAssertNil(q.number)
        XCTAssertEqual(q.missing, ["Nom du client", "Adresse du chantier"])
        let acompte = try Fixtures.quote("peinture_acompte")
        XCTAssertEqual(acompte.paymentSchedule.map(\.amountTtc), [2500, 2000])
    }

    func testHTEtTVA() throws {
        let split = QuoteRules.htAndVat(amountTtc: 3000, vatRate: 10)
        XCTAssertEqual(split?.ht, Decimal(string: "2727.27"))
        XCTAssertEqual(split?.vat, Decimal(string: "272.73"))
        XCTAssertEqual(QuoteRules.htAndVat(amountTtc: 6500, vatRate: 20)?.ht, Decimal(string: "5416.67"))
        XCTAssertEqual(QuoteRules.htAndVat(amountTtc: 1000, vatRate: 5.5)?.ht, Decimal(string: "947.87"))
        XCTAssertNil(QuoteRules.htAndVat(amountTtc: nil, vatRate: 10))
    }

    func testReponseDuChatDecodee() throws {
        let json = """
        {"assistant_text": "J'ai préparé le devis.", "intent": "new", "quote": \(String(decoding: try Fixtures.data("mo_seule_appartement_53m2"), as: UTF8.self)),
         "changes": [], "client_sheet": {"source": "allovoisins", "client_first_name": "Karim", "surface_m2": 50, "rooms": ["salon"],
         "constraints": [], "snippets": [], "observations": [], "uncertain": []},
         "advice": {"price_range": {"low": 4500, "high": 6500, "basis": "comparables", "comparable_ids": ["h06", "h07"], "note": "2 chantiers"},
         "risks": [{"label": "TVA à valider", "why": "attestation"}], "questions": []},
         "client_reply": null, "questions": ["Quel prix ?"]}
        """
        let r = try JSONCoding.decoder().decode(ChatResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.intent, .new)
        XCTAssertEqual(r.quote?.price.amountTtc, 3000)
        XCTAssertEqual(r.clientSheet?.clientFirstName, "Karim")
        XCTAssertEqual(r.clientSheet?.surfaceM2, 50)
        XCTAssertEqual(r.advice?.priceRange?.comparableIds, ["h06", "h07"])
        XCTAssertEqual(r.questions, ["Quel prix ?"])
    }
}
