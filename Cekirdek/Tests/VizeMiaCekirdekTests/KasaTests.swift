import XCTest
@testable import VizeMiaCekirdek

/// Kasa: site deposundaki tests/kasa.test.mjs ile aynı örnekler.
final class KasaTests: XCTestCase {
    static func h(_ tur: String, _ kapsam: String, _ kategori: String, _ tutar: Double?, _ para: String, _ yontem: String, _ tarih: String,
                  iptal: Bool = false, hedef: Double? = nil, hedefPara: String = "", buro: String = "", rutin: (String, String)? = nil) -> KasaHareketi {
        var a: [String: FSDeger] = ["tur": .metin(tur), "kapsam": .metin(kapsam), "kategori": .metin(kategori), "paraBirimi": .metin(para),
                                    "yontem": .metin(yontem), "tarih": .metin(tarih), "iptal": .mantik(iptal)]
        a["tutar"] = tutar.map { FSDeger.ondalik($0) } ?? .bos
        if let hedef { a["hedefTutar"] = .ondalik(hedef); a["hedefParaBirimi"] = .metin(hedefPara); a["buro"] = .metin(buro) }
        if let r = rutin { a["rutinId"] = .metin(r.0); a["rutinVade"] = .metin(r.1) }
        return KasaHareketi(kimlik: UUID().uuidString, alanlar: a)
    }

    static let hareketler: [KasaHareketi] = [
        h("gelir", "musteri", "Müşteri ödemesi", 1500, "TRY", "nakit", "2026-10-27"),
        h("gelir", "musteri", "Müşteri ödemesi", 80, "EUR", "kart", "2026-10-27"),
        h("gelir", "musteri", "Müşteri ödemesi", nil, "TRY", "havale", "2026-10-27"),
        h("gider", "musteri", "Fotokopi", 25.5, "TRY", "nakit", "2026-10-27"),
        h("gider", "genel", "Market alışverişi", 340, "TRY", "kart", "2026-10-26"),
        h("gider", "genel", "Market alışverişi", 999, "TRY", "nakit", "2026-10-26", iptal: true),
        h("cevrim", "genel", "Döviz çevrimi", 50, "EUR", "nakit", "2026-10-27", hedef: 2425, hedefPara: "TRY", buro: "Kızılay Döviz"),
    ]

    func testAyarlar() {
        let a = KasaAyari(alanlar: nil)
        XCTAssertEqual(a.raporSaati, "20:00")
        XCTAssertTrue(a.genelGiderler.contains("Market alışverişi"))
        let b = KasaAyari(alanlar: ["raporSaati": .metin("25:00"), "musteriGiderleri": .dizi([.metin(" Fotokopi "), .metin("Fotokopi"), .metin("")]),
                                    "genelGiderler": .dizi([])])
        XCTAssertEqual(b.raporSaati, "20:00")
        XCTAssertEqual(b.musteriGiderleri, ["Fotokopi"])
        XCTAssertEqual(b.genelGiderler, KasaAyari.varsayilanGenelGiderler, "boş liste varsayılana döner")
    }

    func testHarcamaDogrulama() {
        var g = KasaGirdisi()
        g.kategori = "Market alışverişi"; g.tutar = 120; g.tarih = "2026-10-27"
        XCTAssertEqual(KasaKurali.giderHatalari(g, bugun: "2026-10-27", kategoriler: KasaAyari.varsayilanGenelGiderler), [])
        var x = g; x.tutar = 0
        XCTAssertFalse(KasaKurali.giderHatalari(x, bugun: "2026-10-27").isEmpty)
        x = g; x.tarih = "2026-10-28"
        XCTAssertFalse(KasaKurali.giderHatalari(x, bugun: "2026-10-27").isEmpty, "ileri tarih")
        x = g; x.kategori = "Uydurma"
        XCTAssertFalse(KasaKurali.giderHatalari(x, bugun: "2026-10-27", kategoriler: ["Kırtasiye"]).isEmpty)
        x = g; x.kapsam = "musteri"
        XCTAssertFalse(KasaKurali.giderHatalari(x, bugun: "2026-10-27").isEmpty, "müşteri seçilmeli")
        x = g; x.yontem = "cek"
        XCTAssertFalse(KasaKurali.giderHatalari(x, bugun: "2026-10-27").isEmpty)
    }

    func testAraliklar() {
        let bugun = "2026-10-28"  // çarşamba
        XCTAssertTrue(KasaKurali.aralik("bugun", bugun: bugun) == (bugun, bugun))
        XCTAssertTrue(KasaKurali.aralik("dun", bugun: bugun) == ("2026-10-27", "2026-10-27"))
        XCTAssertTrue(KasaKurali.aralik("hafta", bugun: bugun) == ("2026-10-26", bugun))
        XCTAssertTrue(KasaKurali.aralik("gecenHafta", bugun: bugun) == ("2026-10-19", "2026-10-25"))
        XCTAssertTrue(KasaKurali.aralik("ay", bugun: bugun) == ("2026-10-01", bugun))
        XCTAssertTrue(KasaKurali.aralik("gecenAy", bugun: "2026-03-10") == ("2026-02-01", "2026-02-28"))
        XCTAssertTrue(KasaKurali.aralik("gecenAy", bugun: "2026-01-05") == ("2025-12-01", "2025-12-31"))
        XCTAssertTrue(KasaKurali.aralik("ozel", bugun: bugun, ozelBas: "2026-10-20", ozelBit: "2026-10-01") == ("2026-10-01", "2026-10-20"))
        XCTAssertEqual(KasaKurali.gunler(bas: "2026-10-01", bit: "2026-10-31").count, 31)
    }

    func testRapor() {
        let o = KasaOzeti(Self.hareketler)
        XCTAssertEqual(o.gelir, ["TRY": 1500, "EUR": 80])
        XCTAssertEqual(o.gider, ["TRY": 365.5])
        XCTAssertEqual(o.net, ["TRY": 1134.5, "EUR": 80])
        XCTAssertEqual(o.cevrimCikan, ["EUR": 50])
        XCTAssertEqual(o.cevrimGiren, ["TRY": 2425])
        XCTAssertEqual(o.cevrimNet, ["EUR": -50, "TRY": 2425])
        XCTAssertEqual(o.kasa, ["TRY": 3559.5, "EUR": 30])
        XCTAssertEqual(o.nakit, ["TRY": 3899.5, "EUR": -50])
        XCTAssertEqual(o.giderKategori, ["Fotokopi": ["TRY": 25.5], "Market alışverişi": ["TRY": 340]])
        XCTAssertEqual(o.giderKapsam, ["musteri": ["TRY": 25.5], "genel": ["TRY": 340]])
        XCTAssertEqual(o.sayi, KasaOzeti.Sayilar(gelir: 3, gider: 2, cevrim: 1, iptal: 1, tutarsizGelir: 1))
        XCTAssertEqual(o.gunluk["2026-10-26"], KasaOzeti.Gun(gelir: [:], gider: ["TRY": 340], cevrim: [:]))
        XCTAssertEqual(o.gunluk["2026-10-27"]?.cevrim, ["EUR": -50, "TRY": 2425])
        XCTAssertEqual(KasaKurali.paraYazi(["EUR": 80, "TRY": 1500]), "1.500 TRY + 80 EUR")
        XCTAssertEqual(KasaKurali.paraYazi([:]), "0")
        XCTAssertEqual(KasaKurali.isaretli(o.kasa), "+3.559,5 TRY, +30 EUR")
        XCTAssertEqual(o.birimler, ["TRY", "EUR"])
    }

    func testCsvVeCevrim() {
        var iptalli = Self.hareketler[5]
        iptalli.iptalNot = "çift; giriş"
        let c = KasaCsv.metin([Self.hareketler[3], iptalli])
        XCTAssertTrue(c.hasPrefix("\u{FEFF}Tarih;Tür;"))
        XCTAssertNotNil(c.range(of: "Gider;Müşteri;Fotokopi;.*;-25,5;TRY", options: .regularExpression))
        XCTAssertTrue(c.contains("\"İptal: çift; giriş\""))

        let cv = Self.hareketler[6]
        XCTAssertEqual(KasaKurali.cevrimKuru(tutar: cv.tutar, paraBirimi: cv.paraBirimi, hedefTutar: cv.hedefTutar, hedefParaBirimi: cv.hedefParaBirimi),
                       "1 EUR = 48,5 TRY")
        XCTAssertEqual(KasaKurali.cevrimKuru(tutar: 4850, paraBirimi: "TRY", hedefTutar: 100, hedefParaBirimi: "USD"), "1 USD = 48,5 TRY")
        XCTAssertTrue(KasaCsv.metin([cv]).contains("Döviz çevrimi;Genel;Döviz çevrimi;;;;Nakit;-50;EUR;2425;TRY;Kızılay Döviz;"))
        var g = KasaGirdisi()
        g.tur = "cevrim"; g.kategori = "Döviz çevrimi"; g.tutar = 50; g.paraBirimi = "EUR"; g.hedefTutar = 2425; g.buro = "Kızılay Döviz"
        g.tarih = "2026-10-27"
        XCTAssertEqual(KasaKurali.cevrimHatalari(g, bugun: "2026-10-27"), [])
        var x = g; x.hedefTutar = nil
        XCTAssertFalse(KasaKurali.cevrimHatalari(x, bugun: "2026-10-27").isEmpty, "çevrim tutarı şart")
        x = g; x.buro = " "
        XCTAssertFalse(KasaKurali.cevrimHatalari(x, bugun: "2026-10-27").isEmpty, "büro şart")
        x = g; x.hedefParaBirimi = "EUR"
        XCTAssertFalse(KasaKurali.cevrimHatalari(x, bugun: "2026-10-27").isEmpty, "aynı birim olmaz")
    }

    static func rutin(_ id: String, _ ad: String, _ kat: String, _ tutar: Double?, _ siklik: String, _ gun: Int, _ bas: String) -> RutinOdeme {
        var r = RutinOdeme(id: id)
        r.ad = ad; r.kategori = kat; r.tutar = tutar; r.siklik = siklik; r.gun = gun; r.baslangic = bas
        return r
    }
    static let kira = rutin("kira", "Kira", "Kira", 20000, "aylik", 31, "2026-01-01")
    static let temizlik = rutin("tmz", "Temizlik", "Temizlik", 1500, "haftalik", 5, "2026-10-01")
    static let sigorta = rutin("sig", "İşyeri sigortası", "Diğer", nil, "yillik", 29, "2024-02-29")

    func testRutinVadeleri() {
        XCTAssertEqual(Self.kira.vadeler(bas: "2026-01-15", bit: "2026-04-30"), ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"])
        XCTAssertEqual(Self.temizlik.vadeler(bas: "2026-10-01", bit: "2026-10-31"), ["2026-10-02", "2026-10-09", "2026-10-16", "2026-10-23", "2026-10-30"])
        XCTAssertEqual(Self.sigorta.vadeler(bas: "2025-01-01", bit: "2028-12-31"), ["2025-02-28", "2026-02-28", "2027-02-28", "2028-02-29"])
        var k = Self.kira; k.bitis = "2026-02-15"
        XCTAssertEqual(k.vadeler(bas: "2026-01-01", bit: "2026-12-31"), ["2026-01-31"])
        k = Self.kira; k.aktif = false
        XCTAssertEqual(k.vadeler(bas: "2026-01-01", bit: "2026-12-31"), [])
        XCTAssertEqual(Self.temizlik.yazi, "Her cuma")
        XCTAssertEqual(Self.kira.yazi, "Her ayın 31. günü")
        XCTAssertEqual(Self.kira.hatalar, [])
        var t = Self.temizlik; t.gun = 9
        XCTAssertFalse(t.hatalar.isEmpty)
        var o = Self.kira; o.tutar = nil; o.otomatik = true
        XCTAssertTrue(o.hatalar.contains { $0.contains("Otomatik") })
        XCTAssertEqual(RutinOdeme.kasaId("kira", "2026-10-31"), "r_kira_2026-10-31")
    }

    func testBekleyenRutinler() {
        let odenen = [Self.h("gider", "genel", "Temizlik", 1500, "TRY", "nakit", "2026-10-23", rutin: ("tmz", "2026-10-23")),
                      Self.h("gider", "genel", "Temizlik", 1500, "TRY", "nakit", "2026-10-16", iptal: true, rutin: ("tmz", "2026-10-16"))]
        let b = RutinOdeme.bekleyenler([Self.temizlik, Self.kira], odenenler: odenen, bugun: "2026-10-30", ileriGun: 3)
        XCTAssertEqual(b.geciken.map { "\($0.rutin.id) \($0.vade)" },
                       ["kira 2026-08-31", "kira 2026-09-30", "tmz 2026-10-02", "tmz 2026-10-09", "tmz 2026-10-16"])
        XCTAssertEqual(b.bugun.map(\.rutin.id), ["tmz"])
        XCTAssertEqual(b.yaklasan.map(\.vade), ["2026-10-31"])
    }
}
