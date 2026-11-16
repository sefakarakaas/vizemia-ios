import XCTest
@testable import VizeMiaCekirdek

/// "2026-09-21T06:00:00Z" → Date
func an(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

final class OzetTests: XCTestCase {
    func testBilinenDegerler() {
        // Node'un crypto modülüyle üretildi.
        let ornekler: [(String, String)] = [
            ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            (String(repeating: "ğüşiöç", count: 40), "2b14d02049fcf1373a207dc53aade107b7901a61bba42bcc455b27a04f483a8a"),
        ]
        for (girdi, beklenen) in ornekler {
            XCTAssertEqual(Ozet.sha256Hex(girdi), beklenen)
            XCTAssertEqual(Ozet.hex(Ozet.saf(Array(girdi.utf8))), beklenen)
        }
    }
}

final class TakipTests: XCTestCase {
    func testKimlikSiteyleAyni() {
        // site/assets/takip-giris.js → takipIdFor('2026-091234', 'U12345678')
        XCTAssertEqual(Takip.kimlik(kod: "2026-091234", pasaport: "U12345678"),
                       "19dbd9c5463ef81e81f5062e76dc64db8a258b2cb2ae5a8212b77bb265e28a01")
    }

    func testPasaportTemizligi() {
        XCTAssertEqual(Takip.pasaportTemizle(" u12 345-678 "), "U12345678")
        XCTAssertTrue(Takip.pasaportGecerli("U12345678"))
        XCTAssertFalse(Takip.pasaportGecerli("U1234"))
        XCTAssertFalse(Takip.pasaportGecerli("Ü12345678"))
    }

    func testKodBicimi() {
        XCTAssertTrue(Takip.kodGecerli("2026-091234"))
        XCTAssertTrue(Takip.kodGecerli("2026-121234"))
        XCTAssertFalse(Takip.kodGecerli("2026-131234"))   // 13. ay yok
        XCTAssertFalse(Takip.kodGecerli("2026-001234"))
        XCTAssertFalse(Takip.kodGecerli("2026-09123"))
        XCTAssertFalse(Takip.kodGecerli("x2026-091234"))
        XCTAssertNil(Takip.hata(kod: "2026-091234", pasaport: "u12345678"))
        XCTAssertNotNil(Takip.hata(kod: "2026-091234", pasaport: "12"))
    }

    func testYapistirilanKod() {
        XCTAssertEqual(Takip.kodAyir("2026-091234")?.yil, "2026")
        XCTAssertEqual(Takip.kodAyir("Kodunuz: 2026 091234")?.kalan, "091234")
        XCTAssertNil(Takip.kodAyir("091234"))
    }

    func testKayitOkuma() throws {
        let json = """
        {"fields": {
          "countryName": {"stringValue": "Almanya"}, "firstName": {"stringValue": "AYSE"},
          "statusName": {"stringValue": "Randevu alındı"}, "statusDescription": {"stringValue": "Randevunuz 3 Aralık."},
          "statusColor": {"stringValue": "#14a9b0"}, "isFinal": {"booleanValue": false},
          "asamalar": {"arrayValue": {"values": [{"stringValue": "Evrak"}, {"stringValue": "Randevu"}, {"stringValue": "Sonuç"}]}},
          "asama": {"integerValue": "1"},
          "notes": {"arrayValue": {"values": [{"mapValue": {"fields": {"text": {"stringValue": "Sigorta eksik"}, "at": {"timestampValue": "2026-11-05T09:41:16.458Z"}}}}]}},
          "updatedAt": {"timestampValue": "2026-11-06T10:00:00Z"}
        }}
        """
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let k = TakipKaydi(belge: FSDeger.alanlar(o["fields"]))
        XCTAssertEqual(k.ustSatir, "Almanya vize başvurusu · Sayın Ayse")
        XCTAssertEqual(k.durum, "Randevu alındı")
        XCTAssertEqual(k.renk, "#14a9b0")
        XCTAssertEqual(k.notlar.count, 1)
        XCTAssertEqual(k.notlar[0].metin, "Sigorta eksik")
        XCTAssertNotNil(k.notlar[0].tarih)
        XCTAssertEqual(k.guncelleme, an("2026-11-06T10:00:00Z"))
        let i = try XCTUnwrap(k.ilerleme)
        XCTAssertEqual(i.oran, 0.5)
        XCTAssertEqual(i.ozet, "2. aşama: Randevu · Sıradaki: Sonuç")
        XCTAssertTrue(i.gecti(0))
        XCTAssertFalse(i.gecti(1))
    }

    func testGecersizRenkVeAsama() {
        let k = TakipKaydi(belge: [
            "statusColor": .metin("red; background:url(x)"),
            "asamalar": .dizi([.metin("A"), .metin("B")]), "asama": .tam(5),
        ])
        XCTAssertNil(k.renk)
        XCTAssertNil(k.ilerleme)   // sıra aşama sayısından büyük
        XCTAssertNil(TakipKaydi(belge: [:]).ilerleme)
    }

    func testSelamlama() {
        XCTAssertEqual(Selamlama.metin(saat: 5), "Günaydın")
        XCTAssertEqual(Selamlama.metin(saat: 11), "Günaydın")
        XCTAssertEqual(Selamlama.metin(saat: 12), "İyi günler")
        XCTAssertEqual(Selamlama.metin(saat: 17), "İyi günler")
        XCTAssertEqual(Selamlama.metin(saat: 18), "İyi akşamlar")
        XCTAssertEqual(Selamlama.metin(saat: 22), "İyi geceler")
        XCTAssertEqual(Selamlama.metin(saat: 3), "İyi geceler")
        XCTAssertEqual(Selamlama.cumle(saat: 8, ad: "AHMET"), "Günaydın, Ahmet")
        XCTAssertEqual(Selamlama.cumle(saat: 8, ad: "  "), "Günaydın")
    }

    func testAdGosterimi() {
        // Panel adı Latin büyük harfle yazıyor.
        XCTAssertEqual(Selamlama.ad("AHMET"), "Ahmet")
        XCTAssertEqual(Selamlama.ad("AYSE NUR"), "Ayse Nur")
        XCTAssertEqual(Selamlama.ad("ALI"), "Ali")
        XCTAssertEqual(Selamlama.ad("MEHMET-ALI"), "Mehmet-Ali")
        // Almanya başvurusunda Ö/Ü kalıyor.
        XCTAssertEqual(Selamlama.ad("GÜL"), "Gül")
        XCTAssertEqual(Selamlama.ad("ÖZGE"), "Özge")
        // Türkçe harfle yazılmışsa Türkçe kuralı.
        XCTAssertEqual(Selamlama.ad("İBRAHİM"), "İbrahim")
        XCTAssertEqual(Selamlama.ad("IŞIK"), "Işık")
        // Zaten küçük harf içeriyorsa dokunulmaz.
        XCTAssertEqual(Selamlama.ad(" Ayşe "), "Ayşe")
        XCTAssertEqual(Selamlama.ad(""), "")
    }

    func testDegisiklikBildirimi() {
        let asamalar = ["Görüşme", "Randevu takibi", "Randevu alındı", "Evraklar"]
        let once = TakipKaydi(ulke: "Almanya", ad: "AHMET", durum: "Randevunuz takip ediliyor",
                              aciklama: "Uygun randevu tarihlerini takip ediyoruz.", asamalar: asamalar, asama: 1)
        // Değişiklik yok: bildirim yok.
        XCTAssertNil(once.bildirim(onceki: once))
        // Yeni aşama: panelde müşteri için yazılan metin gider.
        var sonra = once
        sonra.durum = "Randevunuz alındı"; sonra.aciklama = "Randevu bilgileriniz size iletildi."; sonra.asama = 2
        XCTAssertEqual(sonra.bildirim(onceki: once), TakipBildirimi(
            baslik: "Almanya vize başvurunuz", govde: "Randevunuz alındı. Randevu bilgileriniz size iletildi."))
        // Aynı aşamada yalnız durum değişti (eksik evrak): yine haber verilir.
        var eksik = sonra
        eksik.durum = "Eksik evrak var"; eksik.aciklama = ""
        XCTAssertEqual(eksik.bildirim(onceki: sonra)?.govde, "Eksik evrak var.")
        // Yalnız yeni not: notun içeriği bildirime yazılmaz (kilit ekranında görünür).
        var notlu = sonra
        notlu.notlar = [TakipKaydi.Not(id: 0, metin: "Sigorta poliçeniz eksik.")]
        XCTAssertEqual(notlu.bildirim(onceki: sonra)?.govde, "Size yeni bir not iletildi. Görmek için dokunun.")
        XCTAssertNil(sonra.bildirim(onceki: notlu))   // not silindi: haber verilmez
        // Yalnız güncelleme saati değişti: haber verilmez.
        var saat = sonra
        saat.guncelleme = an("2026-11-16T10:00:00Z")
        XCTAssertNil(saat.bildirim(onceki: sonra))
        // Ülke yoksa başlık genel.
        var ulkesiz = sonra
        ulkesiz.ulke = ""
        XCTAssertEqual(ulkesiz.bildirim(onceki: once)?.baslik, "Vize başvurunuz")
    }

    func testKayitSaklanipGeriOkunuyor() throws {
        let k = TakipKaydi(ulke: "Almanya", ad: "AHMET", durum: "Randevunuz alındı", aciklama: "Açıklama", renk: "#5a4f9c",
                           bitti: false, notlar: [TakipKaydi.Not(id: 0, metin: "Not", tarih: an("2026-11-05T09:41:16Z"))],
                           asamalar: ["A", "B", "C"], asama: 1, guncelleme: an("2026-11-06T10:00:00Z"))
        let geri = try JSONDecoder().decode(TakipKaydi.self, from: JSONEncoder().encode(k))
        XCTAssertEqual(geri, k)
        XCTAssertEqual(geri.ilerleme?.simdi, 1)
    }

    func testDenemeSiniri() {
        var s = DenemeSiniri()
        let t = an("2026-11-16T09:00:00Z")
        for i in 0..<8 { XCTAssertFalse(s.asildi(simdi: t.addingTimeInterval(Double(i)))) }
        XCTAssertTrue(s.asildi(simdi: t.addingTimeInterval(9)))
        // 10 dakika sonra yeniden serbest.
        XCTAssertFalse(s.asildi(simdi: t.addingTimeInterval(700)))
    }
}

/// VizeMia deposundaki tests/mesai.test.mjs ile aynı örnekler.
final class MesaiTests: XCTestCase {
    let m = Mesai.varsayilan

    func testTurkiyeSaati() {
        let t = Mesai.trSimdi(an("2026-09-21T06:00:00Z"))
        XCTAssertEqual(t, Mesai.An(iso: "2026-09-21", gun: 1, dakika: 540))
        // Gece yarısı: UTC 22:30 → Türkiye'de ertesi gün 01:30.
        let g = Mesai.trSimdi(an("2026-09-21T22:30:00Z"))
        XCTAssertEqual(g, Mesai.An(iso: "2026-09-22", gun: 2, dakika: 90))
    }

    func testAcikMi() {
        XCTAssertFalse(m.acikMi(an("2026-09-21T05:59:00Z")))  // 08:59
        XCTAssertTrue(m.acikMi(an("2026-09-21T06:00:00Z")))   // 09:00
        XCTAssertTrue(m.acikMi(an("2026-09-21T14:59:00Z")))   // 17:59
        XCTAssertFalse(m.acikMi(an("2026-09-21T15:00:00Z")))  // 18:00 — kapanış anı kapalı
        XCTAssertFalse(m.acikMi(an("2026-09-26T06:30:00Z")))  // Cmt 09:30
        XCTAssertTrue(m.acikMi(an("2026-09-26T07:00:00Z")))   // Cmt 10:00
        XCTAssertFalse(m.acikMi(an("2026-09-26T11:00:00Z")))  // Cmt 14:00
        XCTAssertFalse(m.acikMi(an("2026-09-27T09:00:00Z")))  // Pazar
    }

    func testSonrakiAcilis() {
        XCTAssertEqual(m.sonrakiAcilis(an("2026-09-21T04:00:00Z")).metin, "bugün 09:00")
        XCTAssertEqual(m.sonrakiAcilis(an("2026-09-21T17:00:00Z")).metin, "yarın 09:00")
        // Cumartesi kapanıştan sonra: pazar kapalı, pazartesiye atlar.
        let s = m.sonrakiAcilis(an("2026-09-26T12:00:00Z"))
        XCTAssertEqual(s.gun, 1)
        XCTAssertEqual(s.metin, "Pazartesi 09:00")
        XCTAssertEqual(m.sonrakiAcilis(an("2026-09-27T09:00:00Z")).metin, "yarın 09:00")
    }

    func testMesaiMetni() {
        XCTAssertEqual(m.metin(), "Hafta içi 09:00–18:00, Cumartesi 10:00–14:00")
        var d = m
        d.calisma[5] = [540, 1020]
        XCTAssertEqual(d.metin(), "Pazartesi 09:00–18:00, Salı 09:00–18:00, Çarşamba 09:00–18:00, Perşembe 09:00–18:00, Cuma 09:00–17:00, Cumartesi 10:00–14:00")
    }

    func testDisiMesaji() {
        XCTAssertNil(m.disiMesaji(an("2026-09-21T07:00:00Z")))
        let d = m.disiMesaji(an("2026-09-21T15:01:00Z"))
        XCTAssertEqual(d?.sonraki, "yarın 09:00")
        XCTAssertTrue(d?.metin.contains("Hafta içi 09:00–18:00") ?? false)
        // Gece yarısını geçince "yarın" değil "bugün".
        XCTAssertEqual(m.disiMesaji(an("2026-09-21T22:30:00Z"))?.sonraki, "bugün 09:00")
    }

    func testPanelAyari() throws {
        let json = #"{"gunler": {"0": null, "1": [540, 1020], "2": [545, 1080], "3": [1080, 540], "6": null}, "tatiller": ["2026-10-29", "bozuk"]}"#
        let ayar = try JSONDecoder().decode(MesaiAyari.self, from: Data(json.utf8))
        let p = Mesai(ayar: ayar)
        XCTAssertEqual(p.calisma[1], [540, 1020])       // kapanış 17:00
        XCTAssertEqual(p.calisma[2], [540, 1080])       // 09:05 yarım saate oturmuyor: varsayılan kalır
        XCTAssertEqual(p.calisma[3], [540, 1080])       // ters aralık: varsayılan kalır
        XCTAssertNil(p.calisma[6])                      // cumartesi kapatıldı
        XCTAssertEqual(p.tatiller, ["2026-10-29"])
        XCTAssertFalse(p.acikMi(an("2026-09-21T14:30:00Z")))   // Pzt 17:30
        // Tatil günü saat ne olursa olsun kapalı; açılış tatili atlar.
        XCTAssertFalse(p.acikMi(an("2026-10-29T08:00:00Z")))
        XCTAssertEqual(p.sonrakiAcilis(an("2026-10-28T16:00:00Z")).metin, "Cuma 09:00")
        XCTAssertEqual(Mesai(ayar: nil), Mesai.varsayilan)
    }

    func testCanliMesaiDosyasi() throws {
        // Sitedeki mesai.json biçimi.
        let json = #"{"gunler":{"0":null,"1":[540,1080],"2":[540,1080],"3":[540,1080],"4":[540,1080],"5":[540,1080],"6":[600,840]},"tatiller":[]}"#
        XCTAssertEqual(Mesai(ayar: try JSONDecoder().decode(MesaiAyari.self, from: Data(json.utf8))), Mesai.varsayilan)
    }

    func testDilimler() {
        // Pazartesi 10:10 → bugün en erken 11:30 (bir saat sonrası, 11:10'dan büyük ilk dilim).
        let simdi = an("2026-09-21T07:10:00Z")
        let bugun = m.dilimler("2026-09-21", simdi: simdi)
        XCTAssertEqual(bugun.first, 11 * 60 + 30)
        XCTAssertEqual(bugun.last, 17 * 60 + 30)
        XCTAssertEqual(m.dilimler("2026-09-22", simdi: simdi).count, 18)
        XCTAssertEqual(m.dilimler("2026-09-26", simdi: simdi), [600, 630, 660, 690, 720, 750, 780, 810])
        XCTAssertEqual(m.dilimler("2026-09-27", simdi: simdi), [])   // pazar
        let gunler = m.uygunGunler(simdi: simdi)
        XCTAssertEqual(gunler.count, 14)
        XCTAssertEqual(gunler.first, "2026-09-21")
        XCTAssertFalse(gunler.contains("2026-09-27"))
        // Kapanışa yakın: bugün dilim kalmadı, liste yarından başlar.
        XCTAssertEqual(m.uygunGunler(simdi: an("2026-09-21T14:10:00Z")).first, "2026-09-22")
    }

    func testGruplarVeOzet() {
        let g = Mesai.gruplar(m.dilimler("2026-09-22", simdi: an("2026-09-21T07:10:00Z")))
        XCTAssertEqual(g.map { $0.ad }, ["Öğleden önce", "Öğle", "Öğleden sonra"])
        XCTAssertEqual(g.map { $0.aralik }, ["09:00–12:00", "12:00–14:00", "14:00–18:00"])
        XCTAssertEqual(Mesai.aralikOzeti([540, 570, 600, 840]), "09:00–10:30, 14:00–14:30")
        XCTAssertEqual(Mesai.aralikOzeti([]), "henüz seçim yok")
        XCTAssertEqual(Mesai.gunMetni("2026-09-21"), "21 Eyl Pzt")
    }

    func testAramaSecimi() {
        // "Hemen": o anki yarım saatlik dilim (Pzt 10:47 → 10:30).
        let hemen = AramaSecimi(mod: .hemen).yuk(simdi: an("2026-09-21T07:47:00Z"))
        XCTAssertEqual(hemen, AramaSecimi.Yuk(mod: "hemen", tarih: "2026-09-21", saatler: ["10:30"]))
        XCTAssertNil(AramaSecimi(mod: .hemen).hata)
        var s = AramaSecimi(mod: .saat, gun: "2026-09-22")
        XCTAssertNotNil(s.hata)
        s.dilimler = [600, 540, 570]
        XCTAssertNil(s.hata)
        XCTAssertEqual(s.yuk().saatler, ["09:00", "09:30", "10:00"])
        XCTAssertEqual(s.metin, "22 Eyl Sal, 09:00–10:30 aralığında sizi arayacağız")
    }

    func testTarihYardimcilari() {
        XCTAssertEqual(Tr.gunNo("2026-09-21"), 1)
        XCTAssertEqual(Tr.gunNo("2026-09-27"), 0)
        XCTAssertEqual(Tr.gunEkle("2026-12-31", 1), "2027-01-01")
        XCTAssertEqual(Tr.gunEkle("2026-03-29", 1), "2026-03-30")
        XCTAssertNil(Tr.tarih("2026-02-31"))
        XCTAssertNil(Tr.tarih("26-2-3"))
        XCTAssertEqual(Tr.uzunTarih("2026-11-12"), "12 Kasım 2026")
        XCTAssertEqual(Tr.bugun(an("2026-09-21T22:30:00Z")), "2026-09-22")
        XCTAssertEqual(Tr.tarihSaat(an("2026-11-06T10:05:00Z")), "6 Kasım 2026 13:05")
    }
}

final class HarfTests: XCTestCase {
    func testLatinBuyuk() {
        XCTAssertEqual(Harf.latinBuyuk("Karakaş"), "KARAKAS")
        XCTAssertEqual(Harf.latinBuyuk("ışık İnci çağ"), "ISIK INCI CAG")
        XCTAssertEqual(Harf.latinBuyuk("Öztürk"), "OZTURK")
        XCTAssertEqual(Harf.latinBuyuk("Öztürk", ulke: "almanya"), "ÖZTÜRK")
        XCTAssertEqual(Harf.latinBuyuk("Çağrı Şen", ulke: "almanya"), "CAGRI SEN")
        XCTAssertEqual(Harf.latinBuyuk("José Müller-Ångström"), "JOSE MULLER-ANGSTROM")
        // Ayrık yazılmış "o + iki nokta" da tek harf sayılır.
        XCTAssertEqual(Harf.latinBuyuk("o\u{0308}z", ulke: "almanya"), "ÖZ")
    }

    func testAdSoyadSuzgeci() {
        XCTAssertEqual(Harf.adSoyad("Ayşe-Nur 2. O'Neil", ulke: "fransa"), "AYSE-NUR  ONEIL")
        XCTAssertEqual(Harf.adSoyad("Gül", ulke: "almanya"), "GÜL")
        XCTAssertEqual(Harf.harfRakam("u 12345-678ş"), "U12345678S")
    }

    func testTelefon() {
        XCTAssertEqual(Harf.telefonHaneleri("0549 907 25 23"), "5499072523")
        XCTAssertEqual(Harf.telefonHaneleri("+90 (549) 907-25-23"), "5499072523")
        XCTAssertEqual(Harf.telefonHaneleri("5499072523"), "5499072523")
        XCTAssertEqual(Harf.telefonHaneleri("0312 555 44 33"), "3125554433")
        XCTAssertNil(Harf.telefonHaneleri("549 907 25"))
        XCTAssertNil(Harf.telefonHaneleri("0849 907 25 23"))
    }

    func testEposta() {
        XCTAssertEqual(Harf.eposta("  Ayşe.YILDIZ@Örnek.com "), "ayse.yildiz@ornek.com")
        XCTAssertTrue(Harf.epostaGecerli("a@b.co"))
        XCTAssertFalse(Harf.epostaGecerli("a@b.c"))
        XCTAssertFalse(Harf.epostaGecerli("a b@c.com"))
    }

    func testTckn() {
        XCTAssertTrue(Harf.tcknGecerli("10000000146"))
        XCTAssertFalse(Harf.tcknGecerli("10000000147"))
        XCTAssertFalse(Harf.tcknGecerli("00000000000"))
        XCTAssertFalse(Harf.tcknGecerli("1234"))
    }
}

final class BasvuruTests: XCTestCase {
    let bugun = "2026-11-16"
    let arama = AramaSecimi(mod: .saat, gun: "2026-11-17", dilimler: [600, 630])

    func ornek() -> BasvuruFormu {
        var f = BasvuruFormu()
        f.ad = "Ayşe"; f.soyad = "Öztürk"; f.telefon = "0549 907 25 23"
        f.ulke = "fransa"; f.ulkeAdi = "Fransa"; f.vizeTuru = "turistik"; f.kvkk = true
        return f
    }

    func testTamFormGeciyor() {
        XCTAssertNil(ornek().hata(arama: arama, bugun: bugun))
    }

    func testAlanListesiKuraldakiyleAyni() {
        // firestore.rules → applicationRequests → hasOnly listesi (createdAt sunucuda eklenir).
        let kural: Set<String> = ["firstName", "lastName", "passportNo", "nationalId", "birthDate", "expiryDate",
            "phone", "email", "country", "countryName", "visaType", "travelDate", "callbackMode", "callbackDate",
            "callbackTimes", "message", "channels", "consent", "status", "kampanyaIzni", "kampanyaIzniSurum"]
        XCTAssertEqual(Set(ornek().alanlar(arama: arama).keys), kural)
    }

    func testYuk() {
        var f = ornek()
        f.eposta = " Ayşe@Örnek.com "
        f.kampanya = true
        f.mesaj = "  Yazın gideceğim.  "
        let a = f.alanlar(arama: arama)
        XCTAssertEqual(a["firstName"], .metin("AYSE"))
        XCTAssertEqual(a["lastName"], .metin("OZTURK"))
        XCTAssertEqual(a["phone"], .metin("+905499072523"))
        XCTAssertEqual(a["email"], .metin("ayse@ornek.com"))
        XCTAssertEqual(a["callbackMode"], .metin("saat"))
        XCTAssertEqual(a["callbackDate"], .metin("2026-11-17"))
        XCTAssertEqual(a["callbackTimes"], .dizi([.metin("10:00"), .metin("10:30")]))
        XCTAssertEqual(a["channels"], .harita(["wa": .mantik(true), "sms": .mantik(true), "email": .mantik(true)]))
        XCTAssertEqual(a["kampanyaIzni"], .mantik(true))
        XCTAssertEqual(a["kampanyaIzniSurum"], .metin("v1"))
        XCTAssertEqual(a["message"], .metin("Yazın gideceğim."))
        XCTAssertEqual(a["passportNo"], .metin(""))
        XCTAssertEqual(a["status"], .metin("new"))
    }

    func testEpostaYoksaEpostaKanaliKapali() {
        let a = ornek().alanlar(arama: arama)
        XCTAssertEqual(a["channels"], .harita(["wa": .mantik(true), "sms": .mantik(true), "email": .mantik(false)]))
        var f = ornek()
        f.kanallar = Kanallar(wa: false, sms: false, email: true)   // adres yok → hiçbiri açık değil
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .kanal)
    }

    func testAlmanyadaOUKaliyor() {
        var f = ornek()
        f.ulke = "almanya"; f.ulkeAdi = "Almanya"
        XCTAssertEqual(f.alanlar(arama: arama)["lastName"], .metin("ÖZTÜRK"))
        XCTAssertNil(f.hata(arama: arama, bugun: bugun))
    }

    func testHatalar() {
        var f = ornek(); f.ad = "123"
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .ad)
        f = ornek(); f.soyad = "-"
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .soyad)   // kural ilk karakterin harf olmasını istiyor
        f = ornek(); f.telefon = "123"
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .telefon)
        f = ornek(); f.eposta = "ayse@"
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .eposta)
        f = ornek(); f.ulke = ""
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .ulke)
        f = ornek(); f.vizeTuru = "calisma"
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .vizeTuru)
        f = ornek(); f.seyahat = "2026-11-15"
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .seyahat)
        f = ornek()
        XCTAssertEqual(f.hata(arama: AramaSecimi(mod: .saat, gun: "2026-11-17"), bugun: bugun)?.alan, .arama)
        f = ornek(); f.kvkk = false
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .kvkk)
    }

    func testPasaportYaHepYaHic() {
        var f = ornek()
        f.pasaportNo = "U12345678"
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .dogum)
        f.dogum = "1990-05-01"; f.gecerlilik = "2025-01-01"
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .gecerlilik)
        f.gecerlilik = "2030-01-01"; f.tckn = "10000000147"
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .tckn)
        f.tckn = "10000000146"
        XCTAssertNil(f.hata(arama: arama, bugun: bugun))
        let a = f.alanlar(arama: arama)
        XCTAssertEqual(a["passportNo"], .metin("U12345678"))
        XCTAssertEqual(a["birthDate"], .metin("1990-05-01"))
        f.pasaportNo = "12345678"
        XCTAssertEqual(f.hata(arama: arama, bugun: bugun)?.alan, .pasaportNo)
    }

    func testDestek() {
        var d = DestekFormu()
        XCTAssertNotNil(d.hata)
        d.ad = "Ayşe"; d.eposta = "Ayşe@örnek.com"; d.konu = "Randevu"; d.mesaj = "Merhaba, randevum ne zaman?"
        XCTAssertEqual(d.hata, "Devam etmek için onay kutusunu işaretleyin.")
        d.onay = true
        XCTAssertNil(d.hata)
        // firestore.rules → support → hasOnly listesi (createdAt sunucuda eklenir).
        XCTAssertEqual(Set(d.alanlar.keys), ["name", "email", "phone", "trackingCode", "subject", "message", "consent", "status"])
        XCTAssertEqual(d.alanlar["email"], .metin("ayse@ornek.com"))
    }
}

final class FirestoreTests: XCTestCase {
    func testEklemeGovdesi() throws {
        let g = FirestoreIstemci.eklemeGovdesi(ad: "projects/p/databases/(default)/documents/support/abc",
                                              alanlar: ["consent": .mantik(true), "n": .tam(3), "l": .dizi([.metin("09:00")])],
                                              zamanAlani: "createdAt")
        let veri = try JSONSerialization.data(withJSONObject: g, options: [.sortedKeys])
        let metin = String(decoding: veri, as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
        XCTAssertEqual(metin, #"{"writes":[{"currentDocument":{"exists":false},"update":{"fields":{"consent":{"booleanValue":true},"l":{"arrayValue":{"values":[{"stringValue":"09:00"}]}},"n":{"integerValue":"3"}},"name":"projects/p/databases/(default)/documents/support/abc"},"updateTransforms":[{"fieldPath":"createdAt","setToServerValue":"REQUEST_TIME"}]}]}"#)
    }

    func testKimlikVeAdres() {
        let k = FirestoreIstemci.yeniKimlik()
        XCTAssertTrue(k.eslesir("^[A-Za-z0-9]{20}$"))
        XCTAssertNotEqual(k, FirestoreIstemci.yeniKimlik())
        let i = FirestoreIstemci()
        XCTAssertEqual(i.adres("\(i.kok):commit").absoluteString,
                       "https://firestore.googleapis.com/v1/projects/vieze-941cf/databases/(default)/documents:commit")
    }

    func testZaman() {
        XCTAssertEqual(FSDeger.zamanOku("2026-11-05T09:41:16.458Z")?.timeIntervalSince1970 ?? 0, 1793871676.458, accuracy: 0.001)
        XCTAssertEqual(FSDeger.zamanOku("2026-11-05T09:41:16Z"), an("2026-11-05T09:41:16Z"))
        // Nanosaniyeli zaman da okunuyor (kesir okunamazsa atılıyor).
        XCTAssertEqual(FSDeger.zamanOku("2026-11-05T09:41:16.123456789Z")?.timeIntervalSince1970 ?? 0, 1793871676, accuracy: 0.2)
        XCTAssertNil(FSDeger.zamanOku("dün"))
    }
}

final class MarkdownTests: XCTestCase {
    func testBloklar() {
        let md = "Giriş **kalın** metin.\n\n## Başlık\n- bir\n- [iki](/takip)\n1. ilk\n2. ikinci\nSon [dış](https://example.org/a_b) bağlantı."
        XCTAssertEqual(Markdown.coz(md), [
            .paragraf([.duz("Giriş "), .kalin("kalın"), .duz(" metin.")]),
            .baslik(seviye: 2, [.duz("Başlık")]),
            .liste(sirali: false, [[.duz("bir")], [.bag(metin: "iki", adres: "/takip")]]),
            .liste(sirali: true, [[.duz("ilk")], [.duz("ikinci")]]),
            .paragraf([.duz("Son "), .bag(metin: "dış", adres: "https://example.org/a_b"), .duz(" bağlantı.")]),
        ])
    }

    func testGuvenliOlmayanBaglantiMetinKalir() {
        // Site yalnız https ve site içi yolu bağlantı yapıyor; javascript: düz metin kalır.
        XCTAssertEqual(Markdown.satirIci("[x](javascript:alert(1))"), [.duz("[x](javascript:alert(1))")])
        XCTAssertEqual(Markdown.duzMetin("**Kısaca:** [takip](/takip) sayfası"), "Kısaca: takip sayfası")
    }
}

final class HedefTests: XCTestCase {
    let yollar: Set<String> = ["/almanya-vizesi", "/blog/vize-reddi-sonrasi"]

    func testSiteYollari() {
        XCTAssertEqual(Hedef.coz("/", sayfaYollari: yollar), .anaSayfa)
        XCTAssertEqual(Hedef.coz("/basvuru?ulke=almanya", sayfaYollari: yollar), .basvuru(ulke: "almanya"))
        XCTAssertEqual(Hedef.coz("/basvuru", sayfaYollari: yollar), .basvuru(ulke: ""))
        XCTAssertEqual(Hedef.coz("/destek?kod=2026-091234", sayfaYollari: yollar), .destek(kod: "2026-091234"))
        XCTAssertEqual(Hedef.coz("/takip", sayfaYollari: yollar), .takip(kod: ""))
        XCTAssertEqual(Hedef.coz("https://vizemia.com/takip?kod=2026-091234", sayfaYollari: yollar), .takip(kod: "2026-091234"))
        XCTAssertEqual(Hedef.coz("/harclar", sayfaYollari: yollar), .harclar)
        XCTAssertEqual(Hedef.coz("/blog/vize-reddi-sonrasi", sayfaYollari: yollar), .sayfa(yol: "/blog/vize-reddi-sonrasi"))
        XCTAssertEqual(Hedef.coz("https://vizemia.com/almanya-vizesi", sayfaYollari: yollar), .sayfa(yol: "/almanya-vizesi"))
        XCTAssertEqual(Hedef.coz("/gizlilik", sayfaYollari: yollar), .dis(URL(string: "https://vizemia.com/gizlilik")!))
        XCTAssertEqual(Hedef.coz("https://www.gov.uk/x", sayfaYollari: yollar), .dis(URL(string: "https://www.gov.uk/x")!))
        XCTAssertNil(Hedef.coz("#surec", sayfaYollari: yollar))
        XCTAssertNil(Hedef.coz("javascript:alert(1)", sayfaYollari: yollar))
        XCTAssertEqual(Hedef.gorsel("/assets/img/a.webp")?.absoluteString, "https://vizemia.com/assets/img/a.webp")
        XCTAssertNil(Hedef.gorsel("//kotu.example/a.png"))
    }
}

final class KurTests: XCTestCase {
    let k = KurVerisi(tarih: "2026-10-12", kaynak: "TCMB", kurlar: ["EUR": 55.2068, "USD": 49.3358, "GBP": 65.4274, "CAD": 34.6432])

    func testCeviri() {
        XCTAssertEqual(k.cevir(miktar: 90, kaynak: "EUR"), KurVerisi.Sonuc(tutar: "4.968,61 ₺", oran: "1 € = 55,2068 ₺"))
        XCTAssertEqual(k.cevir(miktar: 185, kaynak: "USD")?.tutar, "9.127,12 ₺")
        XCTAssertEqual(k.cevir(miktar: 10000, kaynak: "TRY")?.tutar, "181,14 €  /  202,69 $")
        XCTAssertNil(k.cevir(miktar: -1, kaynak: "EUR"))
        XCTAssertNil(KurVerisi(kurlar: ["EUR": 55]).cevir(miktar: 1, kaynak: "EUR"))
        XCTAssertEqual(k.bilgi, "TCMB döviz satış kuru, 12 Ekim 2026")
    }

    func testSayiBicimi() {
        XCTAssertEqual(Sayi.para(1234567.891), "1.234.567,89")
        XCTAssertEqual(Sayi.para(0), "0,00")
        XCTAssertEqual(Sayi.kur(50.283), "50,283")
        XCTAssertEqual(Sayi.kur(50), "50,00")
        XCTAssertEqual(Sayi.oku("1.250,50"), 1250.5)
        XCTAssertEqual(Sayi.oku("1250.5"), 1250.5)
        XCTAssertNil(Sayi.oku("abc"))
    }
}

final class IcerikTests: XCTestCase {
    func testGomuluAkisOkunuyor() throws {
        let a: Akis = try XCTUnwrap(IcerikKaynagi.gomulu(.uygulama))
        XCTAssertEqual(a.surum, 1)
        XCTAssertEqual(a.ulkeRehberleri.count, 10)
        XCTAssertGreaterThanOrEqual(a.yazilar.count, 7)
        XCTAssertGreaterThan(a.tumUlkeler.count, 100)
        XCTAssertEqual(a.ulke("isvicre")?.ad, "İsviçre")
        XCTAssertEqual(a.surec?.adimlar.count, 5)
        XCTAssertEqual(a.harclar.map { $0.id }, ["schengen", "ingiltere", "abd", "kanada"])
        XCTAssertGreaterThanOrEqual(a.sss.count, 8)
        XCTAssertTrue(a.servisUrl.hasPrefix("https://script.google.com/"))
        XCTAssertEqual(Mesai(ayar: a.mesai), Mesai.varsayilan)
        XCTAssertNotNil(a.sayfa("/hakkimizda"))
    }

    func testHerBlokTaniniyorVeHerBaglantiCozuluyor() throws {
        let a: Akis = try XCTUnwrap(IcerikKaynagi.gomulu(.uygulama))
        let yollar = Set(a.sayfalar.map { $0.yol })
        var baglanti = 0
        func denetle(_ md: String, _ sayfa: String) {
            for b in Markdown.coz(md) {
                let parcalar: [MdParca]
                switch b {
                case .baslik(_, let p), .paragraf(let p): parcalar = p
                case .liste(_, let l): parcalar = l.flatMap { $0 }
                }
                for p in parcalar {
                    if case .bag(_, let adres) = p {
                        baglanti += 1
                        XCTAssertNotNil(Hedef.coz(adres, sayfaYollari: yollar), "\(sayfa): \(adres)")
                    }
                }
            }
        }
        for s in a.sayfalar {
            XCTAssertFalse(s.bloklar.isEmpty, s.yol)
            if !s.ulke.isEmpty { XCTAssertNotNil(a.ulke(s.ulke), "\(s.yol): \(s.ulke)") }
            for b in s.bloklar {
                switch b {
                case .bilinmeyen: XCTFail("\(s.yol): tanınmayan blok")
                case .metin(let md), .ozet(let md): denetle(md, s.yol)
                case .tablo(_, let satirlar, let not):
                    XCTAssertTrue(satirlar.allSatisfy { $0.count == 2 }); denetle(not, s.yol)
                case .karsilastirma(_, let sutunlar, let satirlar, let not):
                    XCTAssertTrue(satirlar.allSatisfy { $0.count == sutunlar.count }); denetle(not, s.yol)
                case .acilir(_, let ogeler): for o in ogeler { denetle(o.md, s.yol) }
                case .kaynaklar(let k): XCTAssertTrue(k.allSatisfy { $0.count == 2 && $0[1].hasPrefix("https://") })
                case .cta: break
                }
            }
        }
        for q in a.sss { denetle(q.cevap, "sss") }
        XCTAssertGreaterThan(baglanti, 20)
    }

    func testEksikAlanlarVarsayilanlaOkunuyor() throws {
        // Site ileride alan ekleyebilir, tür ekleyebilir; eksik alan uygulamayı düşürmemeli.
        let json = #"{"surum": 1, "yeniAlan": 5, "sayfalar": [{"tur": "yazi", "yol": "/blog/x", "baslik": "X", "bloklar": [{"tur": "video", "adres": "…"}, {"tur": "metin", "md": "Merhaba"}]}]}"#
        let a = try JSONDecoder().decode(Akis.self, from: Data(json.utf8))
        XCTAssertEqual(a.iletisim.telefon, "+905499072523")
        XCTAssertNil(a.surec)
        XCTAssertEqual(a.sayfalar[0].bloklar, [.bilinmeyen, .metin("Merhaba")])
    }

    func testVitrin() throws {
        let d: VitrinDosyasi = try XCTUnwrap(IcerikKaynagi.gomulu(.vitrin))
        XCTAssertGreaterThan(d.slaytlar.count, 3)
        let json = #"{"slaytlar": [{"id": "a", "baslik": "A", "sira": 2, "link": "javascript:x"}, {"id": "b", "baslik": "B", "sira": 1, "bitis": "2026-11-01"}, {"id": "c", "baslik": "C", "sira": 3, "ulke": "almanya", "odak": "30% 80%"}, {"id": "d", "baslik": " "}, {"id": "e", "baslik": "E", "sira": 1, "baslangic": "2026-12-01", "link": "/takip"}]}"#
        let s = try JSONDecoder().decode(VitrinDosyasi.self, from: Data(json.utf8)).slaytlar
        XCTAssertEqual(Vitrin.gosterilecekler(s, bugun: "2026-11-16").map { $0.id }, ["a", "c"])
        XCTAssertEqual(Vitrin.gosterilecekler(s, bugun: "2026-11-16", ulke: "Almanya").map { $0.id }, ["c", "a"])
        XCTAssertEqual(Vitrin.gosterilecekler(s, bugun: "2026-10-30").map { $0.id }, ["b", "a", "c"])
        XCTAssertEqual(Vitrin.gosterilecekler(s, bugun: "2026-12-01").map { $0.id }, ["e", "a", "c"])
        XCTAssertEqual(Vitrin.gosterilecekler(s, bugun: "2026-11-16")[0].link, "")
        XCTAssertEqual(s[2].odakNoktasi.x, 0.3)
        XCTAssertEqual(s[0].odakNoktasi.y, 0.5)
    }

    func testGomuluKur() throws {
        let k: KurVerisi = try XCTUnwrap(IcerikKaynagi.gomulu(.kur))
        XCTAssertTrue(k.gecerli)
    }
}
