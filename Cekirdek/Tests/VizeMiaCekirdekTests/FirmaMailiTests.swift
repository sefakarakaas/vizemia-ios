import XCTest
@testable import VizeMiaCekirdek

/// Firma cevap maili: beklenen çıktı sitenin firma-mail.js'inden üretildi (Ornekler/firma-yanit.json).
final class FirmaMailiTests: XCTestCase {
    func testSiteyleAyni() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Ornekler/firma-yanit.json")
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String])
        var g = FirmaIletisimi()
        g.telefon = "0549 907 25 23"; g.eposta = "iletisim@vizemia.com"; g.web = "vizemia.com"; g.adres = "Yenimahalle/Ankara"
        let m = FirmaMailMetni.yanit(konu: "  Teşekkürler <3 ",
                                     govde: "Merhaba,\r\n\nFiyat & süre:\n• Schengen: 5 gün\n- ABD: 2 ay\nSaygılarımla,\nSefa\n\n\n\"Son\"", genel: g)
        XCTAssertEqual(m.konu, j["konu"])
        XCTAssertEqual(m.govde, j["govde"])
        XCTAssertEqual(m.metin, j["metin"])
        XCTAssertEqual(m.html, j["html"])
        XCTAssertEqual(FirmaMailMetni.yanitKonusu("Vize hizmeti"), j["k1"])
        XCTAssertEqual(FirmaMailMetni.yanitKonusu("RE: x"), j["k2"])
        XCTAssertEqual(FirmaMailMetni.yanitKonusu(""), j["k3"])
    }
}
