import Foundation
import XCTest
@testable import DevisChat

final class NumberingTests: XCTestCase {
    func testFormat() {
        XCTAssertEqual(QuoteNumbering.format(26, year: 2026), "26/26")
        XCTAssertEqual(QuoteNumbering.format(7, year: 2026), "07/26")
        XCTAssertEqual(QuoteNumbering.format(123, year: 2027), "123/27")
    }

    func testCompteurParEntreprise() {
        let a = QuoteNumbering.assign(counter: NumberCounter(companyId: "levix", nextNumber: 26, year: 2026), currentYear: 2026, existing: [], quoteId: "q1")
        XCTAssertEqual(a.number, "26/26")
        XCTAssertEqual(a.counter, NumberCounter(companyId: "levix", nextNumber: 27, year: 2026))
        XCTAssertTrue(a.skipped.isEmpty)
    }

    func testRemiseAZeroAuChangementDAnnee() {
        let a = QuoteNumbering.assign(counter: NumberCounter(companyId: "levix", nextNumber: 41, year: 2026), currentYear: 2027, existing: [], quoteId: "q1")
        XCTAssertEqual(a.number, "01/27")
        XCTAssertEqual(a.counter.nextNumber, 2)
    }

    func testDoublonsEvitesEtSignales() {
        let existing = [
            NumberedQuote(quoteId: "a", companyId: "levix", number: "26/26", title: "A"),
            NumberedQuote(quoteId: "b", companyId: "levix", number: "27/26", title: "B"),
            NumberedQuote(quoteId: "c", companyId: "sar_bat", number: "28/26", title: "C"), // autre entreprise : pas un doublon
        ]
        let a = QuoteNumbering.assign(counter: NumberCounter(companyId: "levix", nextNumber: 26, year: 2026), currentYear: 2026, existing: existing, quoteId: "q1")
        XCTAssertEqual(a.number, "28/26")
        XCTAssertEqual(a.skipped, ["26/26", "27/26"])
        XCTAssertEqual(QuoteNumbering.duplicates(companyId: "levix", number: "26/26", in: existing).map(\.title), ["A"])
        XCTAssertTrue(QuoteNumbering.duplicates(companyId: "levix", number: "26/26", in: existing, excluding: "a").isEmpty)
    }
}

final class FormatTests: XCTestCase {
    func testMontantsEtPourcentages() {
        XCTAssertEqual(FR.amount(6500), "6\u{202F}500\u{00A0}€")
        XCTAssertEqual(FR.amount(33110), "33\u{202F}110\u{00A0}€")
        XCTAssertEqual(FR.amount(950), "950\u{00A0}€")
        XCTAssertEqual(FR.amountTTC(nil), "Prix à définir")
        XCTAssertEqual(FR.plain(FR.amountTTC(3500)), "3 500 € TTC")
        XCTAssertEqual(FR.percent(5.5), "5,5\u{00A0}%")
        XCTAssertEqual(FR.percent(10), "10\u{00A0}%")
        XCTAssertEqual(FR.surface(53), "53\u{00A0}m²")
    }

    func testDates() {
        XCTAssertEqual(FR.date(iso: "2026-10-07"), "7 octobre 2026")
        XCTAssertEqual(FR.date(iso: "2026-08-01"), "1er août 2026")
        XCTAssertEqual(FR.date(iso: "pas une date"), "pas une date")
        XCTAssertEqual(FR.isoToday(Date(timeIntervalSince1970: 0)).count, 10)
    }

    func testNomDeFichier() throws {
        var q = try Fixtures.quote("optique_complet_55m2")
        let name = FileNaming.quoteFileName(quote: q, companyLabel: "SB CONCEPT", ext: "pdf")
        XCTAssertTrue(name.hasPrefix("Devis_SB_CONCEPT_Optique_Exemple_client_fi_Amenagement_d_un_magasin"))
        XCTAssertTrue(name.hasSuffix(".pdf"))
        q.client.name = #"A/B:C*D?"E<F>|G"#
        let cleaned = FileNaming.quoteFileName(quote: q, companyLabel: "SB CONCEPT", ext: "pdf")
        XCTAssertTrue(cleaned.hasPrefix("Devis_SB_CONCEPT_A_B_C_D_E_F_G_"))
        XCTAssertFalse(cleaned.contains { #"/\:*?"<>|"#.contains($0) })
        q.client.name = nil
        XCTAssertTrue(FileNaming.quoteFileName(quote: q, companyLabel: "SB CONCEPT", ext: "docx").hasPrefix("Devis_SB_CONCEPT_Amenagement"))
    }

    func testTailleDesImages() {
        let big = ImageSizing.fitted(width: 4032, height: 3024)
        XCTAssertEqual(big.width, 1600)
        XCTAssertEqual(big.height, 1200)
        let portrait = ImageSizing.fitted(width: 1179, height: 2556)
        XCTAssertEqual(portrait.height, 1600)
        XCTAssertEqual(portrait.width, 738)
        let small = ImageSizing.fitted(width: 800, height: 600)
        XCTAssertEqual(small.width, 800, "jamais agrandie")
    }

    func testHistoriqueDesVersions() throws {
        let v1 = try Fixtures.quote("mo_seule_appartement_53m2")
        var h = QuoteHistory(versions: [v1])
        XCTAssertFalse(h.canUndo)
        XCTAssertNil(h.undo())
        var v2 = v1
        v2.version = 2
        v2.price.amountTtc = nil
        v2.missing = QuoteRules.computeMissing(v2)
        h.push(v2)
        let restored = try XCTUnwrap(h.undo())
        XCTAssertEqual(restored.price.amountTtc, 3000)
        XCTAssertEqual(restored.version, 3)
        XCTAssertEqual(restored.missing, v1.missing)
        XCTAssertEqual(h.versions.count, 3)
    }

    func testRechercheDansLaListe() async {
        await MainActor.run {
            let vm = QuoteListViewModel()
            let items = [
                QuoteSummary(id: UUID(), title: "Rénovation appartement", companyLabel: "LEVIX", number: "26/26", status: .draft, priceTTC: 3000, missingCount: 2, updatedAt: Date(timeIntervalSince1970: 10)),
                QuoteSummary(id: UUID(), title: "Fenêtre bois", companyLabel: "SAR BAT", number: "07/26", status: .validated, priceTTC: nil, missingCount: 1, updatedAt: Date(timeIntervalSince1970: 20)),
            ]
            XCTAssertEqual(vm.filter(items).map(\.title), ["Fenêtre bois", "Rénovation appartement"], "les plus récents d'abord")
            vm.searchText = "renovation"
            XCTAssertEqual(vm.filter(items).map(\.title), ["Rénovation appartement"])
            vm.searchText = "07/26"
            XCTAssertEqual(vm.filter(items).map(\.title), ["Fenêtre bois"])
            XCTAssertEqual(FR.plain(items[1].priceText), "Prix à définir")
        }
    }
}
