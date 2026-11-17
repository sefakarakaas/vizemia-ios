import XCTest
@testable import VizeMiaCekirdek

/// Panelin kurallarıyla aynı sonuçlar (site deposu: tests/basvuru-akisi.test.mjs,
/// tests/takip-asama.test.mjs, tests/eposta.test.mjs örnekleri).
final class BasvuruAkisiTests: XCTestCase {
    /// panel/js/config.js → DEFAULT_STATUSES (sırası belgedeki gibi; order yok).
    static let varsayilan: [Statu] = [
        st("potansiyel", "Potansiyel Müşteri", "Görüşme aşamasında", silme: 60, aramaMin: 7, aramaMax: 14),
        st("randevu-takip", "Randevu Takipte", "Randevunuz takip ediliyor", gerekenler: ["odeme"]),
        st("evrak-bekleniyor", "Evrak Bekleniyor"), st("eksik-evrak", "Eksik Evrak Bildirildi"),
        st("evrak-tamam", "Evraklar Tamamlandı"), st("form-dolduruldu", "Başvuru Formu Dolduruldu"),
        st("randevu", "Randevu Alındı"), st("biyometri", "Biyometri Verildi"),
        st("konsoloslukta", "Konsoloslukta İşlemde", gerekenler: ["fis"]),
        st("sonuc-onay", "Sonuçlandı — Onay", "Sonuçlandı"), st("sonuc-ret", "Sonuçlandı — Ret", "Sonuçlandı"),
        st("teslim", "Pasaport Teslim Edildi", son: true),
    ]

    static func st(_ id: String, _ ad: String, _ musteri: String = "", silme: Int? = nil, aramaMin: Int? = nil,
                   aramaMax: Int? = nil, gerekenler: [String] = [], son: Bool = false, sira: Int? = nil) -> Statu {
        var a: [String: FSDeger] = ["name": .metin(ad), "publicName": .metin(musteri), "isFinal": .mantik(son),
                                    "gerekenler": .dizi(gerekenler.map { .metin($0) })]
        if let silme { a["silmeGun"] = .tam(silme) }
        if let aramaMin { a["aramaMin"] = .tam(aramaMin) }
        if let aramaMax { a["aramaMax"] = .tam(aramaMax) }
        if let sira { a["order"] = .tam(sira) }
        return Statu(kimlik: id, alanlar: a)
    }

    static func basvuru(_ a: [String: FSDeger] = [:]) -> Basvuru {
        Basvuru(kimlik: "app1", alanlar: [
            "trackingCode": .metin("2026-091234"), "firstName": .metin("AYŞE NUR"), "lastName": .metin("ÖZTÜRK"),
            "country": .metin("almanya"), "countryName": .metin("Almanya"), "statusId": .metin("potansiyel"),
            "statusName": .metin("Potansiyel Müşteri"),
        ].merging(a) { $1 })
    }

    static let calisan = Calisan(uid: "u1", belge: ["username": .metin("sefa"), "displayName": .metin("Sefa Karakaş"),
                                                     "role": .metin("admin"), "active": .mantik(true)], izinBelgesi: nil)

    func s(_ id: String) -> Statu { Self.varsayilan.first { $0.id == id }! }

    // MARK: Takip sayfasının aşamaları

    func testVarsayilanAsamalar() {
        let r = TakipBelgesi.asamasi(statuler: Self.varsayilan, statuId: "potansiyel")
        XCTAssertEqual(r?.asamalar, ["Görüşme", "Randevu takibi", "Evraklar", "Randevu alındı", "Parmak izi", "Konsoloslukta", "Sonuç", "Teslim"])
        XCTAssertEqual(r?.asama, 0)
        XCTAssertEqual(TakipBelgesi.asamasi(statuler: Self.varsayilan, statuId: "eksik-evrak")?.asama, 2)
        XCTAssertEqual(TakipBelgesi.asamasi(statuler: Self.varsayilan, statuId: "form-dolduruldu")?.asama, 2)
        XCTAssertEqual(TakipBelgesi.asamasi(statuler: Self.varsayilan, statuId: "sonuc-ret")?.asama, 6)
        XCTAssertEqual(TakipBelgesi.asamasi(statuler: Self.varsayilan, statuId: "teslim")?.asama, 7)
    }

    func testAsamaSirasiAyarlardan() {
        let ids = ["potansiyel", "randevu-takip", "randevu", "evrak-bekleniyor", "eksik-evrak", "evrak-tamam",
                   "form-dolduruldu", "biyometri", "konsoloslukta", "sonuc-onay", "sonuc-ret", "teslim"]
        let st = ids.enumerated().map { i, id in Self.st(id, id, son: id == "teslim", sira: i) }
        let r = TakipBelgesi.asamasi(statuler: st.reversed(), statuId: "randevu")
        XCTAssertEqual(Array(r!.asamalar.prefix(4)), ["Görüşme", "Randevu takibi", "Randevu alındı", "Evraklar"])
        XCTAssertEqual(r?.asama, 2)
        XCTAssertEqual(TakipBelgesi.asamasi(statuler: st, statuId: "evrak-tamam")?.asama, 3)
    }

    func testSonradanEklenenStatu() {
        let st = ["potansiyel", "randevu-takip", "ozel-bekleme", "konsoloslukta", "arsiv"].enumerated()
            .map { i, id in Self.st(id, id, son: id == "arsiv", sira: i) }
        let r = TakipBelgesi.asamasi(statuler: st, statuId: "ozel-bekleme")
        XCTAssertEqual(r?.asamalar, ["Görüşme", "Randevu takibi", "Konsoloslukta"])
        XCTAssertEqual(r?.asama, 1)
        XCTAssertEqual(TakipBelgesi.asamasi(statuler: st, statuId: "arsiv")?.asama, 2)
        XCTAssertNil(TakipBelgesi.asamasi(statuler: [], statuId: "potansiyel"))
        XCTAssertNil(TakipBelgesi.asamasi(statuler: Self.varsayilan, statuId: "olmayan"))
    }

    func testTakipBelgesi() {
        let b = Self.basvuru()
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let n = BasvuruNotu(id: "n1", metin: "Evraklarınız geldi", musteriyeGorunur: true, yazan: "Sefa", zaman: t)
        let a = TakipBelgesi.alanlar(basvuru: b, statu: s("randevu-takip"), statuler: Self.varsayilan, notlar: [n])
        XCTAssertEqual(a["statusName"], .metin("Randevunuz takip ediliyor"), "müşteriye görünen ad")
        XCTAssertEqual(a["statusColor"], .metin("#1e2c4d"), "renk yoksa lacivert")
        XCTAssertEqual(a["firstName"], .metin("AYŞE NUR"))
        XCTAssertEqual(a["asama"], .tam(1))
        XCTAssertEqual(a["notes"], .dizi([.harita(["text": .metin("Evraklarınız geldi"), "at": .zaman(t)])]))
        // Kuralın izin verdiği alanlar (firestore.rules → validTakip; updatedAt sunucu saatiyle ayrıca).
        XCTAssertTrue(Set(a.keys).isSubset(of: ["countryName", "firstName", "statusName", "statusDescription",
                                                 "statusColor", "isFinal", "notes", "asamalar", "asama"]))
        let cok = (0..<40).map { BasvuruNotu(id: "\($0)", metin: "n", musteriyeGorunur: true, yazan: "", zaman: t) }
        XCTAssertEqual(TakipBelgesi.alanlar(basvuru: b, statu: nil, statuler: [], notlar: cok)["notes"]?.diziDegeri?.count, 30)
    }

    // MARK: Statü geçişi

    func testStatuGecisi() {
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let gun = 86_400.0
        var g = Self.basvuru().statuGecisi(s("potansiyel"), saklamaGun: 60, simdi: t0)
        XCTAssertEqual(g.alanlar["deleteAfter"], .zaman(t0.addingTimeInterval(60 * gun)))
        XCTAssertEqual(g.zaman, ["statusAt"])
        g = Self.basvuru(["deleteAfter": .zaman(t0)]).statuGecisi(s("randevu-takip"), saklamaGun: 60, simdi: t0)
        XCTAssertEqual(g.alanlar["deleteAfter"], .bos, "randevu takipte süresiz")
        XCTAssertNil(g.alanlar["finalAt"])
        g = Self.basvuru().statuGecisi(s("teslim"), saklamaGun: 90, simdi: t0)
        XCTAssertEqual(g.zaman, ["statusAt", "finalAt"])
        XCTAssertEqual(g.alanlar["deleteAfter"], .zaman(t0.addingTimeInterval(90 * gun)))
        let sonda = Self.basvuru(["finalAt": .zaman(t0), "deleteAfter": .zaman(t0)])
        g = sonda.statuGecisi(s("teslim"), saklamaGun: 60, simdi: t0)
        XCTAssertEqual(Set(g.alanlar.keys), ["statusId", "statusName"], "zaten son adımdaysa saklama tarihi değişmez")
        g = sonda.statuGecisi(s("evrak-bekleniyor"), saklamaGun: 60, simdi: t0)
        XCTAssertEqual(g.alanlar["finalAt"], .bos)
        XCTAssertEqual(g.alanlar["deleteAfter"], .bos)
    }

    func testGecisEngelleri() {
        let hepsi = Self.st("x", "Konsoloslukta", gerekenler: ["fis", "takipKodu", "randevu", "evrak", "odeme"])
        XCTAssertEqual(hepsi.gerekenler, ["odeme", "evrak", "randevu", "takipKodu", "fis"], "sabit sıra")
        let b = Self.basvuru()
        XCTAssertEqual(b.gecisEngelleri(s("potansiyel")), [])
        XCTAssertEqual(b.gecisEngelleri(hepsi, evrakTamam: false, randevuVar: false),
                       ["ödeme bilgisi", "evrak kontrol listesi", "randevu kağıdı", "konsolosluk takip kodu"])
        let tamam = Self.basvuru(["odemeSayisi": .tam(2), "konsTakipKodu": .metin("IST1")])
        XCTAssertEqual(tamam.gecisEngelleri(hepsi, evrakTamam: true, randevuVar: true, fisVar: true), [])
        XCTAssertEqual(tamam.gecisEngelleri(hepsi), [], "bilinmeyen (nil) denetlenmez")
        XCTAssertEqual(b.gecisEngelleri(s("konsoloslukta"), fisVar: false), ["pasaport teslim fişi"])
        XCTAssertEqual(Basvuru.gecisMesaji(hepsi, ["randevu kağıdı"]),
                       "\"Konsoloslukta\" statüsüne geçmeden önce tamamlayın: randevu kağıdı.")
        let eski = Statu(kimlik: "e", alanlar: ["name": .metin("E"), "odemeGerekli": .mantik(true)])
        XCTAssertEqual(eski.gerekenler, ["odeme"], "eski kayıtta odemeGerekli")
    }

    // MARK: Evrak listesi

    func testEvrakListesi() {
        let katalog = EvrakKatalogu(etiketler: ["pasaport": "Pasaport", "banka": "Banka dökümü", "ds160-onay": "DS-160",
                                                "emekli-belgesi": "Emekli belgesi", "eski": "Eski evrak"],
                                    genel: ["pasaport", "banka", "emekli-belgesi"], kosullu: ["emekli-belgesi"],
                                    ulkeler: ["abd": ["pasaport", "ds160-onay"]])
        let bos = EvrakAyari(belge: nil)
        XCTAssertEqual(bos.liste(ulke: "almanya", katalog: katalog, isaretli: [:]).map(\.id), ["pasaport", "banka", "emekli-belgesi"])
        XCTAssertEqual(bos.liste(ulke: "almanya", katalog: katalog, isaretli: [:]).map(\.kosullu), [false, false, true])
        XCTAssertEqual(bos.liste(ulke: "abd", katalog: katalog, isaretli: ["eski": true, "banka": false]).map(\.id),
                       ["pasaport", "ds160-onay", "eski"], "listede olmayan işaretli evrak sona")
        let ayar = EvrakAyari(belge: [
            "items": .dizi([.harita(["id": .metin("pasaport"), "label": .metin("Pasaport (aslı)")])]),
            "byCountry": .harita(["abd": .dizi([.harita(["id": .metin("banka"), "label": .metin("Banka")])])]),
        ])
        XCTAssertEqual(ayar.liste(ulke: "abd", katalog: katalog, isaretli: [:]).map(\.ad), ["Banka"], "ayardaki ülke listesi önce")
        XCTAssertEqual(ayar.liste(ulke: "almanya", katalog: katalog, isaretli: [:]).map(\.ad), ["Pasaport (aslı)"])
    }

    // MARK: Müşteriye bildirim

    func testEpostaSablonu() {
        XCTAssertEqual(MusteriBildirimi.adDuzelt("AYŞE NUR"), "Ayşe Nur")
        XCTAssertEqual(MusteriBildirimi.adDuzelt("İSMAİL IŞIK"), "İsmail Işık")
        XCTAssertEqual(MusteriBildirimi.adDuzelt("GÜL ÖZTÜRK-YILMAZ"), "Gül Öztürk-Yılmaz")
        let d = MusteriBildirimi.epostaDegerleri(Self.basvuru(), statu: "Sonuçlandı")
        XCTAssertEqual(MusteriBildirimi.doldur("Sayın {adSoyad}, {ülke} — {takipLinki} {bilinmeyen}", d),
                       "Sayın Ayşe Nur Öztürk, Almanya — https://vizemia.com/takip?kod=2026-091234 {bilinmeyen}")
        XCTAssertTrue(MusteriBildirimi.epostaGecerli(" Ali@Ornek.com "))
        XCTAssertFalse(MusteriBildirimi.epostaGecerli("ali@ornek"))
    }

    func testStatuEpostasiYalnizAcikSablonda() {
        let b = Self.basvuru()
        let iletisim = MusteriIletisimi(form: ["email": .metin("ayse@ornek.com"), "phone": .metin("0532 111 22 33")])
        XCTAssertTrue(iletisim.epostaAcik && iletisim.smsAcik, "tercih yoksa hepsi açık")
        let kapali = EpostaAyari(belge: nil)
        XCTAssertNil(MusteriBildirimi.statuEpostasi(b, hedef: s("sonuc-onay"), ayar: kapali, iletisim: iletisim, calisan: Self.calisan))
        let acik = EpostaAyari(belge: ["statuSablonlari": .harita(["sonuc-onay": .harita([
            "aktif": .mantik(true), "konu": .metin("{ulke} vize başvurunuz"), "metin": .metin("Sayın {adSoyad}, {statu}."),
        ])])])
        let m = MusteriBildirimi.statuEpostasi(b, hedef: s("sonuc-onay"), ayar: acik, iletisim: iletisim, calisan: Self.calisan)
        XCTAssertEqual(m?["subject"], .metin("Almanya vize başvurunuz"))
        XCTAssertEqual(m?["text"], .metin("Sayın Ayşe Nur Öztürk, Sonuçlandı."))
        XCTAssertEqual(m?["tur"], .metin("statu"))
        let istemiyor = MusteriIletisimi(form: ["email": .metin("ayse@ornek.com"),
                                               "channels": .harita(["wa": .mantik(true), "sms": .mantik(false), "email": .mantik(false)])])
        XCTAssertNil(MusteriBildirimi.statuEpostasi(b, hedef: s("sonuc-onay"), ayar: acik, iletisim: istemiyor, calisan: Self.calisan))
        XCTAssertFalse(istemiyor.smsAcik)
    }

    func testSms() {
        XCTAssertEqual(MusteriBildirimi.e164("0532 123 45 67"), "+905321234567")
        XCTAssertEqual(MusteriBildirimi.e164("5321234567"), "+905321234567")
        XCTAssertEqual(MusteriBildirimi.e164("90 532 123 45 67"), "+905321234567")
        XCTAssertEqual(MusteriBildirimi.e164("+49 151 1234567"), "+491511234567")
        XCTAssertEqual(MusteriBildirimi.e164("123"), "")
        XCTAssertEqual(MusteriBildirimi.ascii("Şükrü Çağlayan İĞNE ölçü"), "Sukru Caglayan IGNE olcu")
        let ayar = SmsAyari(belge: ["enabled": .mantik(true)])
        let m = MusteriBildirimi.sms(Self.basvuru(), sablon: ayar.statuSablonu, statu: "Randevunuz takip ediliyor", not: "",
                                     ayar: ayar, telefon: "0532 123 45 67", calisan: Self.calisan)
        XCTAssertEqual(m?["text"], .metin("Sayin AYSE NUR, Almanya vize basvurunuzun durumu: Randevunuz takip ediliyor. Takip: https://vizemia.com/takip?kod=2026-091234"))
        XCTAssertEqual(m?["to"], .metin("+905321234567"))
        XCTAssertNil(MusteriBildirimi.sms(Self.basvuru(), sablon: "x", statu: "", not: "", ayar: SmsAyari(belge: nil),
                                          telefon: "05321234567", calisan: Self.calisan), "SMS kapalı")
    }

    // MARK: Yazım gövdeleri

    func testAlanYolu() {
        XCTAssertEqual(FirestoreIstemci.alanYolu(["checklist", "eski-pasaport"]), "checklist.`eski-pasaport`")
        XCTAssertEqual(FirestoreIstemci.alanYolu(["statusId"]), "statusId")
        let f = FirestoreIstemci()
        let g = f.yazimGovdesi(.guncelle(yol: "applications/a", alanlar: ["updatedBy": .metin("u")],
                                         ic: ["checklist": ["eski-pasaport": .mantik(true)]], zaman: ["updatedAt"]))
        XCTAssertEqual((g["updateMask"] as? [String: Any])?["fieldPaths"] as? [String], ["updatedBy", "checklist.`eski-pasaport`"])
        XCTAssertNotNil(g["updateTransforms"])
        let s = f.yazimGovdesi(.yaz(yol: "takip/x", alanlar: [:]))
        XCTAssertNil(s["currentDocument"], "set: ön koşul yok")
        XCTAssertNil(s["updateTransforms"])
    }

    func testStatuYazimlari() {
        let b = Self.basvuru()
        let r = BasvuruIslemi.statu(b, hedef: s("randevu-takip"), statuler: Self.varsayilan, musteriNotu: "  Ödemeniz alındı ",
                                    acikNotlar: [], takipId: String(repeating: "a", count: 64), calisan: Self.calisan,
                                    saklamaGun: 60, eposta: nil, sms: nil, smsGonder: false, iletisim: nil)
        let yollar = r.yazimlar.map { y -> String in
            switch y {
            case let .guncelle(yol, _, _, _), let .olustur(yol, _, _), let .yaz(yol, _, _), let .sil(yol),
                 let .diziyeEkle(yol, _, _), let .diziden(yol, _, _): return yol
            }
        }
        XCTAssertEqual(yollar.count, 5)
        XCTAssertEqual(yollar[0], "applications/app1")
        XCTAssertTrue(yollar[1].hasPrefix("applications/app1/log/"))
        XCTAssertTrue(yollar[2].hasPrefix("applications/app1/notes/"))
        XCTAssertEqual(yollar[3], "takip/" + String(repeating: "a", count: 64))
        XCTAssertTrue(yollar[4].hasPrefix("audit/"))
        // Statü aynı, not yok: yalnız takip sayfası yenilenir.
        let ayni = BasvuruIslemi.statu(b, hedef: s("potansiyel"), statuler: Self.varsayilan, musteriNotu: "",
                                       acikNotlar: [], takipId: "t", calisan: Self.calisan, saklamaGun: 60,
                                       eposta: nil, sms: nil, smsGonder: false, iletisim: nil)
        XCTAssertEqual(ayni.yazimlar.count, 1)
    }
}

final class BasvuruListesiTests: XCTestCase {
    func b(_ id: String, _ ad: String, grup: String = "", grupAdi: String = "", ulke: String = "Almanya", son3: String = "123") -> Basvuru {
        Basvuru(kimlik: id, alanlar: ["firstName": .metin(ad), "lastName": .metin("Yılmaz"), "countryName": .metin(ulke),
                                      "trackingCode": .metin("2026-11\(id.suffix(4))"), "grupId": .metin(grup),
                                      "grupAdi": .metin(grupAdi), "passportLast3": .metin(son3)])
    }

    func testTakipKoduVePasaport() {
        XCTAssertEqual(BasvuruListesi.takipKodu("2026 029825"), "2026-029825")
        XCTAssertEqual(BasvuruListesi.takipKodu("2026-119825"), "2026-119825")
        XCTAssertNil(BasvuruListesi.takipKodu("2026-139825"), "ay 13 olamaz")
        XCTAssertTrue(BasvuruListesi.pasaportGibi("U 1234 5678"))
        XCTAssertFalse(BasvuruListesi.pasaportGibi("Ali"))
        // panel/js/util.js → passportHash: sha256("vizemia-pasaport|" + büyük harf, boşluksuz)
        XCTAssertEqual(BasvuruListesi.pasaportOzeti("u12 345-678"), Ozet.sha256Hex("vizemia-pasaport|U12345678"))
    }

    func testSuzmeVeGrup() {
        let l = [b("a0001", "İsmail"), b("a0002", "Ayşe", grup: "g1", grupAdi: "Yılmaz ailesi"), b("a0003", "Can", son3: "9X1"),
                 b("a0004", "Ece", grup: "g1", ulke: "Fransa"), b("a0005", "Tek", grup: "g2")]
        XCTAssertEqual(BasvuruListesi.suz(l, "ismail").map(\.kimlik), ["a0001"], "Türkçe küçük harf")
        XCTAssertEqual(BasvuruListesi.suz(l, "9x1").map(\.kimlik), ["a0003"])
        XCTAssertEqual(BasvuruListesi.suz(l, "2026-110003").map(\.kimlik), ["a0003"])
        let g = BasvuruListesi.grupla(l)
        XCTAssertEqual(g.map(\.id), ["a0001", "grup:g1", "a0003", "a0005"], "tek üyeli grup tek satır")
        if case let .grup(_, ad, uyeler) = g[1] {
            XCTAssertEqual(ad, "Yılmaz ailesi")
            XCTAssertEqual(BasvuruListesi.grupUlkesi(uyeler), "Karışık ülke")
        } else { XCTFail() }
    }
}

final class GomuluEvrakTests: XCTestCase {
    /// Uygulamayla gelen kopyada evrak kataloğu var (site eskiyse ekip ekranı boş kalmasın).
    func testGomuluKatalog() throws {
        let a: Akis = try XCTUnwrap(IcerikKaynagi.gomulu(.uygulama))
        let e = try XCTUnwrap(a.evrak)
        XCTAssertEqual(e.genel.first, "pasaport")
        XCTAssertTrue(e.kosullu.contains("emekli-belgesi"))
        XCTAssertNotNil(e.ulkeler["abd"])
        XCTAssertFalse(a.sayfalar.isEmpty)
    }
}

final class BasvuruEkleriTests: XCTestCase {
    func testOdemeHatalari() {
        let bugun = "2026-11-17"
        XCTAssertEqual(OdemeKurali.hatalar(tarih: bugun, tutar: nil, paraBirimi: "TRY", yontem: "havale", onayKodu: "", aciklama: "", bugun: bugun), [])
        XCTAssertEqual(OdemeKurali.hatalar(tarih: "2026-11-18", tutar: 10, paraBirimi: "TRY", yontem: "kart", onayKodu: "", aciklama: "", bugun: bugun),
                       ["Ödeme tarihi ileri bir tarih olamaz."])
        XCTAssertEqual(OdemeKurali.hatalar(tarih: "", tutar: -5, paraBirimi: "JPY", yontem: "x", onayKodu: "a;b", aciklama: "", bugun: bugun).count, 5)
        XCTAssertEqual(OdemeKurali.tutarDegeri(4500), .tam(4500))
        XCTAssertEqual(OdemeKurali.tutarDegeri(12.345), .ondalik(12.35))
        XCTAssertEqual(OdemeKurali.sayiYazi(2250.5), "2250.5")
        XCTAssertEqual(OdemeKurali.tutarOku("2.250,50"), 2250.5)
        XCTAssertEqual(OdemeKurali.tutarOku("2250,5"), 2250.5)
        XCTAssertEqual(OdemeKurali.tutarOku("2250.5"), 2250.5)
        XCTAssertEqual(OdemeKurali.tutarOku("1.000.000"), 1_000_000)
        XCTAssertNil(OdemeKurali.tutarOku(" "))
        XCTAssertNil(OdemeKurali.tutarOku("abc"))
    }

    func testIleriStatuVeKodlar() {
        let st = BasvuruAkisiTests.varsayilan.enumerated().map { i, s in
            Statu(kimlik: s.id, alanlar: ["name": .metin(s.ad), "order": .tam(i * 10), "isFinal": .mantik(s.son)])
        }
        let b = BasvuruAkisiTests.basvuru()   // potansiyel
        XCTAssertEqual(b.ileriStatu(st, hedefId: "randevu-takip")?.id, "randevu-takip")
        let ileride = BasvuruAkisiTests.basvuru(["statusId": .metin("konsoloslukta")])
        XCTAssertNil(ileride.ileriStatu(st, hedefId: "randevu-takip"), "yalnız ileri")
        XCTAssertNil(b.ileriStatu(st, hedefId: "teslim"), "son adıma kendiliğinden geçilmez")
        XCTAssertEqual(KonsoloslukKodu.temizle(" ist 2026/55 "), "IST2026/55")
        XCTAssertTrue(KonsoloslukKodu.gecerli("IST2026/55"))
        XCTAssertFalse(KonsoloslukKodu.gecerli("A1"))
        XCTAssertEqual(Dosya.adTemizle("a/b:c?.pdf"), "a-b-c-.pdf")
        XCTAssertEqual(Dosya.adTemizle("   "), "belge")
        XCTAssertEqual(Dosya.boyutYazi(2_400_000), "2,4 MB")
        XCTAssertEqual(Dosya.boyutYazi(610_000), "610 KB")
        XCTAssertTrue(Dosya.sorun(mime: "image/gif", boyut: 10).hasPrefix("Yalnız PDF"))
        XCTAssertEqual(Dosya.sorun(mime: "image/jpeg", boyut: 10), "")
    }

    func testParcalama() {
        let c = BasvuruAkisiTests.calisan
        let r = Dosya.ekle(ust: "applications/a", tur: "odeme", dosya: HazirDosya(ad: "d.jpg", mime: "image/jpeg",
                                                                                  bayt: Data(count: 1_800_001)), calisan: c, kimlik: "abcdefgh12")
        XCTAssertEqual(r.yazimlar.count, 4, "3 parça + bilgi")
        if case let .olustur(yol, alanlar, _) = r.yazimlar[2] {
            XCTAssertEqual(yol, "applications/a/dosyaIcerik/abcdefgh12_2")
            XCTAssertEqual(alanlar["veri"]?.baytDegeri?.count, 1)
        } else { XCTFail() }
        if case let .olustur(yol, alanlar, zaman) = r.yazimlar[3] {
            XCTAssertEqual(yol, "applications/a/dosyalar/abcdefgh12")
            XCTAssertEqual(alanlar["parca"], .tam(3))
            XCTAssertEqual(zaman, ["at"])
        } else { XCTFail() }
    }
}

/// Randevu kağıdı ve bildirim planı (site deposu: tests/bildirim.test.mjs, tests/basvuru-akisi.test.mjs örnekleri).
final class RandevuTests: XCTestCase {
    static let secenekler = RandevuSecenekleri(
        merkezler: ["VFS Global", "iDATA", "Konsolosluk", "Büyükelçilik"], temsilcilikTurleri: ["Konsolosluk", "Büyükelçilik"],
        sehirler: ["Ankara", "İstanbul", "Bursa"], sikSehirSayisi: 2, saatler: ["09:00", "10:30"],
        temsilcilikler: [
            Temsilcilik(ulke: "abd", tur: "Büyükelçilik", ad: "ABD Büyükelçiliği (Ankara)", sehir: "Ankara", harita: "https://www.google.com/maps/search/?api=1&query=abd"),
            Temsilcilik(ulke: "abd", tur: "Konsolosluk", ad: "ABD Başkonsolosluğu (İstanbul)", sehir: "İstanbul", harita: "https://www.google.com/maps/search/?api=1&query=abd2"),
        ],
        merkezHaritalari: ["VFS Global|Ankara": "https://www.google.com/maps/search/?api=1&query=vfs"])

    func tr(_ d: Date) -> String {
        let p = Tr.takvim.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return "\(Tr.iso(yil: p.year!, ay: p.month!, gun: p.day!)) \(p.hour! < 10 ? "0" : "")\(p.hour!):\(p.minute! < 10 ? "0" : "")\(p.minute!)"
    }
    func an(_ s: String) -> Date { FSDeger.zamanOku(s)! }

    func testRandevuHatalariVeKayit() {
        let s = Self.secenekler
        var r = RandevuGirdisi(tarih: "2026-12-01", saat: "10:30", merkez: "VFS Global", sehir: "Ankara", yer: "", ulke: "abd")
        XCTAssertEqual(RandevuKurali.hatalar(r, s, bugun: "2026-11-17"), [])
        XCTAssertEqual(RandevuKurali.kayit(r, s, konumlar: KonumAyari(belge: nil)).harita, "https://www.google.com/maps/search/?api=1&query=vfs")
        let ayarli = KonumAyari(belge: ["merkez": .harita(["VFS Global|Ankara": .metin("https://maps.app.goo.gl/abc"),
                                                          "iDATA|Bursa": .metin("http://kotu")])])
        XCTAssertEqual(RandevuKurali.kayit(r, s, konumlar: ayarli).harita, "https://maps.app.goo.gl/abc", "ayardaki bağlantı önce")
        XCTAssertNil(ayarli.merkez["iDATA|Bursa"], "geçersiz bağlantı alınmaz")
        r.tarih = "2026-11-16"; r.saat = "11:00"; r.sehir = ""
        XCTAssertEqual(RandevuKurali.hatalar(r, s, bugun: "2026-11-17"),
                       ["Randevu tarihi geçmiş bir gün olamaz.", "Randevu saatini seçin.", "Randevu şehrini seçin."])
        r = RandevuGirdisi(tarih: "2026-12-01", saat: "09:00", merkez: "Konsolosluk", sehir: "", yer: "ABD Büyükelçiliği (Ankara)", ulke: "abd")
        XCTAssertEqual(RandevuKurali.hatalar(r, s, bugun: "2026-11-17"), ["Hangi konsolosluk olduğunu seçin."], "tür tutmalı")
        r.yer = "ABD Başkonsolosluğu (İstanbul)"
        XCTAssertEqual(RandevuKurali.hatalar(r, s, bugun: "2026-11-17"), [])
        let k = RandevuKurali.kayit(r, s, konumlar: KonumAyari(belge: nil))
        XCTAssertEqual(k.sehir, "İstanbul", "temsilcilikte şehir listeden")
        XCTAssertEqual(k.yer, "ABD Başkonsolosluğu (İstanbul)")
        XCTAssertEqual(RandevuKurali.an("2026-12-01", "09:00"), an("2026-12-01T06:00:00Z"))
    }

    func testPencereVeZaman() {
        let pen = { (d: Date) in BildirimZamani.pencereye(d, bas: 9, son: 21) }
        XCTAssertEqual(tr(pen(an("2026-11-23T11:00:00Z"))), "2026-11-23 14:00")
        XCTAssertEqual(tr(pen(an("2026-11-23T18:00:00Z"))), "2026-11-24 09:00")
        XCTAssertEqual(tr(pen(an("2026-11-23T20:30:00Z"))), "2026-11-24 09:00")
        XCTAssertEqual(tr(pen(an("2026-11-23T00:00:00Z"))), "2026-11-23 09:00")
        let hemen = BildirimAyari.Sablon(acik: true, mod: "hemen", gun: 0, saat: nil)
        XCTAssertEqual(tr(BildirimZamani.plan(hemen, randevu: "2026-11-23", simdi: an("2026-11-05T12:00:00Z"), bas: 9, son: 21)), "2026-11-05 15:00")
        XCTAssertEqual(tr(BildirimZamani.plan(hemen, randevu: "2026-11-23", simdi: an("2026-11-05T21:30:00Z"), bas: 9, son: 21)), "2026-11-06 09:00")
        let once = BildirimAyari.Sablon(acik: true, mod: "oncesi", gun: 15, saat: 9)
        XCTAssertEqual(tr(BildirimZamani.plan(once, randevu: "2026-11-23", simdi: an("2026-10-01T09:00:00Z"), bas: 9, son: 21)), "2026-11-08 09:00")
        XCTAssertEqual(tr(BildirimZamani.plan(once, randevu: "2026-11-23", simdi: an("2026-11-13T12:00:00Z"), bas: 9, son: 21)), "2026-11-13 15:00", "geçtiyse hemen")
        XCTAssertEqual(tr(BildirimZamani.plan(once, randevu: "2026-11-23", simdi: an("2026-11-13T22:00:00Z"), bas: 9, son: 21)), "2026-11-14 09:00")
    }

    func testPlan() {
        let b = BasvuruAkisiTests.basvuru(["country": .metin("abd"), "countryName": .metin("ABD")])
        let r = RandevuGirdisi(tarih: "2026-12-20", saat: "09:00", merkez: "VFS Global", sehir: "Ankara", yer: "", ulke: "abd")
        let k = RandevuKurali.kayit(r, Self.secenekler, konumlar: KonumAyari(belge: nil))
        let iletisim = MusteriIletisimi(form: ["phone": .metin("0532 111 22 33"), "email": .metin("a@b.co"),
                                              "channels": .harita(["wa": .mantik(true), "sms": .mantik(false), "email": .mantik(true)])])
        let ayar = BildirimAyari(belge: ["gruplar": .dizi([.harita(["id": .metin("g_abc123"), "ulkeler": .dizi([.metin("abd")]),
            "templates": .harita(["evrak-hatirlatma": .harita(["offsetDays": .tam(10)])])])])])
        let simdi = an("2026-11-17T08:00:00Z")   // TR 11:00
        let p = BildirimPlani.planla(b, randevu: r, kayit: k, iletisim: iletisim, ayar: ayar,
                                     mevcut: [BildirimKaydi(kimlik: "x1", alanlar: ["kind": .metin("evrak-hatirlatma"), "status": .metin("planned")]),
                                              BildirimKaydi(kimlik: "x2", alanlar: ["kind": .metin("randevu-alindi"), "status": .metin("sent")]),
                                              BildirimKaydi(kimlik: "x3", alanlar: ["kind": .metin("form-linki"), "status": .metin("planned")])],
                                     calisan: BasvuruAkisiTests.calisan, simdi: simdi)
        XCTAssertEqual(p.iptal, 1, "form bağlantısına dokunulmaz")
        XCTAssertEqual(p.yazilan, ["randevu-alindi", "evrak-hatirlatma"], "randevu alındı yeni bilgilerle yeniden")
        guard case let .olustur(_, a, _) = p.yazimlar[1] else { return XCTFail() }
        XCTAssertEqual(a["channels"], .harita(["wa": .mantik(true), "sms": .mantik(false), "email": .mantik(true)]))
        XCTAssertEqual(a["phone"], .metin("+905321112233"))
        XCTAssertEqual(a["sendAt"], .zaman(simdi.addingTimeInterval(30 * 60)), "olaydan sonra en erken 30 dk")
        guard case let .olustur(_, h, _) = p.yazimlar[2] else { return XCTFail() }
        XCTAssertEqual(h["reminderDays"], .tam(10), "ülke grubunun şablonu")
        XCTAssertEqual(h["docDeadline"], .metin("2026-12-17"))
        if case let .zaman(d)? = h["sendAt"] { XCTAssertEqual(tr(d), "2026-12-10 09:00") } else { XCTFail() }
        let kanalsiz = BildirimPlani.planla(b, randevu: r, kayit: k, iletisim: MusteriIletisimi(form: ["phone": .metin("+49 151 1234567")]),
                                            ayar: BildirimAyari(belge: nil), mevcut: [], calisan: BasvuruAkisiTests.calisan, simdi: simdi)
        XCTAssertEqual(kanalsiz.atlanan, ["açık kanal yok"], "yabancı numaraya WhatsApp/SMS planlanmaz")
    }
}

/// Ekibin başvuru formu: sitenin gerçek şemasıyla (uygulamayla gelen kopya).
final class EkipFormuTests: XCTestCase {
    var sema: FormSemasi!

    override func setUpWithError() throws {
        let a: Akis = try XCTUnwrap(IcerikKaynagi.gomulu(.uygulama))
        sema = try XCTUnwrap(a.form)
    }

    func testAlanListesi() {
        let genel = sema.panelAlanlari("almanya", kayitli: [:])
        XCTAssertEqual(genel.first?.key, "firstName")
        XCTAssertTrue(genel.contains { $0.key == "passportNo" && $0.required })
        // ABD'nin hazır ayarı: AB aile üyesi soruları kapalı (kutucuk arkasında, zorunlu değil).
        let abd = sema.panelAlanlari("abd", kayitli: [:])
        let aile = abd.first { $0.key == "euFamSurname" }
        XCTAssertEqual(aile?.kapali, true)
        // Kayıtlı ayar hazırın üstüne yazar; ek soru "x_" önekiyle sona eklenir.
        let ayar = UlkeFormu(alanlar: [
            "hidden": .dizi([.metin("email")]), "required": .dizi([.metin("phone")]),
            "extra": .dizi([.harita(["key": .metin("isyeri"), "label": .metin("İşyeri adı"), "type": .metin("select"),
                                     "options": .dizi([.harita(["value": .metin("A"), "label": .metin("A")])])])]),
        ])
        let fr = sema.panelAlanlari("fransa", kayitli: ["fransa": ayar])
        XCTAssertEqual(fr.first { $0.key == "email" }?.kapali, true)
        XCTAssertEqual(fr.first { $0.key == "phone" }?.required, true)
        XCTAssertEqual(fr.last?.key, "x_isyeri")
        XCTAssertEqual(fr.last?.options.first?.label, "Seçiniz")
        // Hollanda: portal şablonunun sırası.
        XCTAssertGreaterThan(sema.panelAlanlari("hollanda", kayitli: [:]).count, genel.count)
        XCTAssertTrue(sema.ilceler("ANKARA").contains("Çankaya"))
        XCTAssertEqual(sema.iller(ilce: "çankaya"), ["ANKARA"])
    }

    func testDenetim() {
        let alanlar = sema.panelAlanlari("almanya", kayitli: [:])
        var d: [String: String] = ["firstName": "müller", "lastName": "straße", "passportNo": "u 12-345 678",
                                   "email": " Ali@Ornek.COM ", "nationalId": "12345678901", "birthProvince": "ANKARA",
                                   "passportIssued": "2020-02-29", "passportExpires": "2019-01-01"]
        var r = EkipFormu.topla(d, alanlar: alanlar, acikKapalilar: [], ulke: "almanya", acilis: "2026-11-17", bugun: "2026-11-17")
        XCTAssertEqual(r.veri["firstName"], .metin("MÜLLER"), "Almanya'da Ü kalır")
        XCTAssertEqual(r.veri["lastName"], .metin("STRASSE"), "ß → SS")
        XCTAssertEqual(r.veri["passportNo"], .metin("U12345678"))
        XCTAssertEqual(r.veri["email"], .metin("ali@ornek.com"))
        XCTAssertEqual(r.veri["birthPlace"], .metin("ANKARA"))
        XCTAssertTrue(r.sorunlar.contains("T.C. kimlik numarası geçersiz."))
        XCTAssertTrue(r.sorunlar.contains("Pasaport geçerlilik tarihi, veriliş tarihinden sonra olmalı."))
        d = ["firstName": "ali", "lastName": "veli"]
        r = EkipFormu.topla(d, alanlar: alanlar, acikKapalilar: [], ulke: "", acilis: "2026-11-18", bugun: "2026-11-17")
        XCTAssertTrue(r.sorunlar.contains("Pasaport numarası ya da telefon gerekli (pasaportu sonradan girebilirsiniz)."))
        XCTAssertTrue(r.sorunlar.contains("Ülke seçin."))
        XCTAssertTrue(r.sorunlar.contains("Oluşturma tarihi ileri bir tarih olamaz."))
        XCTAssertFalse(r.sorunlar.contains { $0.hasPrefix("Pasaport no zorunlu") }, "pasaport panelde isteğe bağlı")
        XCTAssertEqual(EkipFormu.yilKaydir("2020-02-29", 10), "2030-02-28")
        XCTAssertEqual(EkipFormu.yilKaydir("2030-05-07", -10), "2020-05-07")
        XCTAssertTrue(EkipFormu.takipKodu(FSDeger.zamanOku("2026-03-05T10:00:00Z")!).eslesir("^2026-03[0-9]{4}$"))
    }
}

final class TalepTohumTests: XCTestCase {
    func testTaleptenForma() {
        let t = Talep(tur: .geriArama, kimlik: "t1", alanlar: [
            "name": .metin("Şükrü Can Öztürk"), "phone": .metin("+905321112233"), "country": .metin("almanya"),
            "visaType": .metin("ziyaret"), "channels": .harita(["wa": .mantik(true), "sms": .mantik(false), "email": .mantik(false)]),
            "kampanyaIzni": .mantik(true), "kampanyaIzniSurum": .metin("v1"),
            "draft": .harita(["passportNo": .metin("U12345678"), "country": .metin("fransa"), "email": .metin("")]),
        ])
        let r = EkipFormu.tohum(t, ulkeler: ["almanya", "fransa"])
        XCTAssertEqual(r.ulke, "fransa", "taslaktaki ülke önce")
        // Panel gibi talebin kendi ülkesine göre (Almanya: Ö/Ü kalır, Ş → S).
        XCTAssertEqual(r.degerler["firstName"], "SÜKRÜ CAN")
        XCTAssertEqual(r.degerler["lastName"], "ÖZTÜRK")
        XCTAssertEqual(r.degerler["passportNo"], "U12345678")
        XCTAssertEqual(r.degerler["travelPurpose"], "Aile_Arkadasi")
        XCTAssertNil(r.degerler["email"], "boş değer taşınmaz")
        XCTAssertEqual(r.korunan["kampanyaIzni"], .mantik(true))
        XCTAssertNotNil(r.korunan["channels"])
        XCTAssertEqual(Talep.onayAlanlari(basvuruId: "app1", uid: "u")["status"], .metin("approved"))
    }
}
