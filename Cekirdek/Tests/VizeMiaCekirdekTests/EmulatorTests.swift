import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import VizeMiaCekirdek

/// Formların gerçek güvenlik kurallarından geçtiğini Firestore emülatöründe dener.
///
/// Yalnız `FIRESTORE_EMULATOR_HOST` tanımlıyken çalışır (ör. localhost:8080);
/// emülatör VizeMia deposundaki firestore.rules ile başlatılmış olmalıdır:
///   npx firebase-tools emulators:exec --only firestore --project demo-vizemia "swift test"
/// Canlı veritabanına hiçbir şey yazmaz.
final class EmulatorTests: XCTestCase {
    var istemci: FirestoreIstemci!

    override func setUpWithError() throws {
        guard let host = ProcessInfo.processInfo.environment["FIRESTORE_EMULATOR_HOST"], !host.isEmpty else {
            throw XCTSkip("Emülatör yok; FIRESTORE_EMULATOR_HOST tanımlı değil.")
        }
        istemci = FirestoreIstemci(taban: URL(string: "http://\(host)/v1")!, proje: "demo-vizemia")
    }

    func ornek() -> BasvuruFormu {
        var f = BasvuruFormu()
        f.ad = "Ayşe"; f.soyad = "Öztürk"; f.telefon = "0549 907 25 23"
        f.ulke = "fransa"; f.ulkeAdi = "Fransa"; f.vizeTuru = "turistik"; f.kvkk = true
        return f
    }

    func testBasvuruKuraldanGeciyor() async throws {
        let arama = AramaSecimi(mod: .saat, gun: "2026-11-17", dilimler: [600, 630])
        let kimlik = try await istemci.ekle(koleksiyon: "applicationRequests", alanlar: ornek().alanlar(arama: arama))
        XCTAssertEqual(kimlik.count, 20)
    }

    func testHemenAraVePasaportluBasvuru() async throws {
        var f = ornek()
        f.ulke = "almanya"; f.ulkeAdi = "Almanya"; f.eposta = "ayse@ornek.com"; f.kampanya = true
        f.seyahat = "2027-06-01"; f.mesaj = "Yazın gideceğim."
        f.pasaportNo = "U12345678"; f.tckn = "10000000146"; f.dogum = "1990-05-01"; f.gecerlilik = "2030-01-01"
        try await istemci.ekle(koleksiyon: "applicationRequests", alanlar: f.alanlar(arama: AramaSecimi(mod: .hemen)))
    }

    func testBozukBasvuruReddediliyor() async throws {
        var alanlar = ornek().alanlar(arama: AramaSecimi(mod: .hemen))
        alanlar["phone"] = .metin("05499072523")   // +90 ile başlamıyor
        do {
            try await istemci.ekle(koleksiyon: "applicationRequests", alanlar: alanlar)
            XCTFail("kural reddetmeliydi")
        } catch {
            XCTAssertEqual(error as? FirestoreHatasi, .izinYok)
        }
    }

    func testDestekKuraldanGeciyor() async throws {
        var d = DestekFormu()
        d.ad = "Ayşe"; d.eposta = "ayse@ornek.com"; d.konu = "Randevu"; d.mesaj = "Randevum ne zaman?"; d.onay = true
        d.takipKodu = "2026-091234"
        try await istemci.ekle(koleksiyon: "support", alanlar: d.alanlar)
    }

    func testTakipOkuma() async throws {
        // Olmayan kayıt: nil. Kimlik biçimi bozuksa kural reddeder.
        let yok = try await istemci.belge("takip/\(Takip.kimlik(kod: "2026-091234", pasaport: "U12345678"))")
        XCTAssertNil(yok)
        do {
            _ = try await istemci.belge("takip/kisa")
            XCTFail("kural reddetmeliydi")
        } catch {
            XCTAssertEqual(error as? FirestoreHatasi, .izinYok)
        }
    }
}
