import XCTest
@testable import VizeMiaCekirdek

final class BildirimGoreviTests: XCTestCase {
    func kayit(_ ek: [String: FSDeger] = [:]) -> BildirimGorevi {
        var a: [String: FSDeger] = [
            "appId": .metin("a1"), "trackingCode": .metin("2026-111234"), "kind": .metin("randevu-alindi"), "status": .metin("planned"),
            "channels": .harita(["wa": .mantik(true), "sms": .mantik(false), "email": .mantik(true)]),
            "name": .metin("Ayşe"), "country": .metin("almanya"), "countryName": .metin("Almanya"),
            "appointmentDate": .metin("2026-11-23"), "docDeadline": .metin("2026-11-20"), "reminderDays": .tam(15),
            "randevuSaati": .metin("09:30"), "randevuMerkezi": .metin("iDATA"), "randevuSehri": .metin("İstanbul"),
            "phone": .metin("+905321112233"), "waStatus": .metin("pending"),
        ]
        a.merge(ek) { $1 }
        return BildirimGorevi(kimlik: "b1", alanlar: a)
    }

    func testMetin() {
        let b = kayit()
        let m = BildirimMetni.kur(b, ayar: BildirimAyari(belge: nil))
        XCTAssertTrue(m.metin.hasPrefix("🎉 Müjde Ayşe!\nAlmanya vize randevunuz alındı. ✈️\n📅 Tarih: 23 Kasım 2026 Pazartesi\n🕘 Saat: 09:30\n🏢 Randevu merkezi: iDATA\n📍 Şehir: İstanbul\n"))
        XCTAssertTrue(m.metin.contains("Randevunuza 15 gün kala"))
        XCTAssertEqual(m.konu, "Almanya vize randevunuz alındı 🎉")
        XCTAssertEqual(b.kanalMetni, "WhatsApp, E-posta")

        // Ülke grubunun şablonu genelin yerine geçer; bilinmeyen yer tutucu olduğu gibi kalır.
        let ayar = BildirimAyari(belge: ["gruplar": .dizi([.harita([
            "id": .metin("g_schengen1"), "ulkeler": .dizi([.metin("almanya")]),
            "templates": .harita(["randevu-alindi": .harita(["text": .metin("Merhaba {isim}, {randevu} · {bilinmeyen} · {form}")])]),
        ])])])
        XCTAssertEqual(BildirimMetni.kur(b, ayar: ayar).metin,
                       "Merhaba Ayşe, 23 Kasım 2026 Pazartesi · {bilinmeyen} · https://vizemia.com/form?kod=2026-111234")
    }

    func testWaGorevi() {
        // "randevu alındı" 30 dk beklemedeyken görev açılmaz; "şimdi gönder" ya da gönderim sonrası açılır.
        XCTAssertFalse(kayit().waGorevi)
        XCTAssertTrue(kayit(["force": .mantik(true)]).waGorevi)
        XCTAssertTrue(kayit(["status": .metin("sent")]).waGorevi)
        XCTAssertTrue(kayit(["kind": .metin("evrak-hatirlatma")]).waGorevi)
        XCTAssertFalse(kayit(["status": .metin("cancelled"), "force": .mantik(true)]).waGorevi)
        XCTAssertFalse(kayit(["waStatus": .metin("sent"), "status": .metin("sent")]).waGorevi)
        XCTAssertTrue(kayit().bana("u1"))
        XCTAssertFalse(kayit(["assignedTo": .metin("u2")]).bana("u1"))
    }

    func testWaBaglantisi() {
        let u = BildirimMetni.waBaglantisi(telefon: "+90 532 111 22 33", metin: "A&B = 1+1 ✓\nyeni")
        XCTAssertEqual(u?.absoluteString, "https://wa.me/905321112233?text=A%26B%20%3D%201%2B1%20%E2%9C%93%0Ayeni")
        XCTAssertNil(BildirimMetni.waBaglantisi(telefon: "", metin: "x"))
    }
}

final class EkipIcerikTests: XCTestCase {
    func testSlug() {
        // panel/js/util.js → slugify ile aynı sonuçlar.
        XCTAssertEqual(Icerik.slug("Schengen Vizesi: Nasıl Başvurulur?"), "schengen-vizesi-nasil-basvurulur")
        XCTAssertEqual(Icerik.slug("  İtalya’da Öğrenci Vizesi — 2026 "), "italya-da-ogrenci-vizesi-2026")
        XCTAssertEqual(Icerik.slug("Çağrı & Şükrü"), "cagri-sukru")
        XCTAssertEqual(Icerik.slug("---"), "")
    }
}

final class FotoHavuzuTests: XCTestCase {
    func testOdak() {
        XCTAssertEqual(FotoHavuzu.odakYaz(33.4, 66.5), "33% 67%")
        XCTAssertEqual(FotoHavuzu.odakYaz(-5, 140), "0% 100%")
        XCTAssertTrue(FotoHavuzu.odakGecerli("0% 100%"))
        XCTAssertFalse(FotoHavuzu.odakGecerli("101% 5%"))
        XCTAssertFalse(FotoHavuzu.odakGecerli("50%  50%"))
        XCTAssertEqual(FotoHavuzu.odakOku("25% 75%").x, 0.25)
        XCTAssertEqual(FotoHavuzu.hazirlar.filter(\.oto).count, 36)
        let e = FotoHavuzu.Eklenen(kimlik: "x", alanlar: ["gorsel": .metin(FotoHavuzu.veriAdresi(jpeg: Data([1, 2, 3])))])
        XCTAssertEqual(e.bayt, Data([1, 2, 3]))
    }
}

/// Vitrin arka planı: beklenen sonuçlar sitenin foto-havuzu.js'inden üretildi.
final class VitrinArkaPlanTests: XCTestCase {
    func testSiteyleAyni() {
        var havuz = FotoHavuzu.kur([
            FotoHavuzu.Eklenen(kimlik: "abc123", alanlar: ["gorsel": .metin("E:abc123"), "ulke": .metin("almanya"), "odak": .metin("30% 40%")]),
            FotoHavuzu.Eklenen(kimlik: "genelx", alanlar: ["gorsel": .metin("E:genelx"), "ulke": .metin("")]),
        ])
        // Testte yollar JS'teki gibi kısaltılır.
        for i in havuz.indices where havuz[i].hazir { havuz[i].yol = "H:\(havuz[i].id)" }
        let s: [FotoHavuzu.SlaytGirdisi] = [
            .init(id: "Kx9aQ2", sira: 1), .init(id: "icerik-Zz81", ulke: "almanya", sira: 2), .init(id: "p0", ulke: "almanya", odak: "10% 90%", sira: 3),
            .init(id: "çğü-İ", ulke: "japonya", sira: 4), .init(id: "v1", havuzFoto: "varsayilan-randevu", sira: 5), .init(id: "g1", gorsel: "data:x", sira: 6),
            .init(id: "aa", ulke: "fransa", sira: 7), .init(id: "ab", ulke: "fransa", sira: 8),
        ]
        let r = FotoHavuzu.vitrinFotolari(s, havuz)
        XCTAssertEqual(r.map(\.gorsel), ["H:genel-gol", "E:abc123", "H:almanya-brandenburg", "H:genel-harita", "H:varsayilan-randevu", "data:x",
                                         "H:fransa-kopru", "H:fransa-eyfel"])
        XCTAssertEqual(r.map(\.odak), ["50% 50%", "30% 40%", "10% 90%", "50% 50%", "50% 50%", "50% 50%", "50% 50%", "60% 50%"])
        XCTAssertEqual(FotoHavuzu.sonrakiFoto(ulke: "fransa", havuz, simdiki: "fransa-kopru"), "fransa-eyfel-park")
        XCTAssertEqual(FotoHavuzu.sonrakiFoto(ulke: "", havuz, simdiki: "u-genelx"), "genel-ucak-kanadi")
        XCTAssertTrue(FotoHavuzu.ulkeFotosuVar("almanya", havuz))
        XCTAssertFalse(FotoHavuzu.ulkeFotosuVar("japonya", havuz))
    }
}

final class MusteriMesajiTests: XCTestCase {
    func testTelefon() {
        XCTAssertEqual(MusteriMesaji.telefonE164("0532 123 45 67"), "+905321234567")
        XCTAssertEqual(MusteriMesaji.telefonE164("5321234567"), "+905321234567")
        XCTAssertEqual(MusteriMesaji.telefonE164("90 212 123 45 67"), "+902121234567")
        XCTAssertEqual(MusteriMesaji.telefonE164("+49 151 2345678"), "+491512345678")
        XCTAssertEqual(MusteriMesaji.telefonE164("0632 123 45 67"), "")
        XCTAssertEqual(MusteriMesaji.telefonE164("12345"), "")
    }

    func testKanalDurumu() {
        XCTAssertTrue(MusteriMesaji.kanalDurumu(.eposta, eposta: "a@b.co", telefon: "", smsHazir: false, smsIzni: false).olur)
        XCTAssertEqual(MusteriMesaji.kanalDurumu(.sms, eposta: "", telefon: "05321234567", smsHazir: false, smsIzni: true).neden,
                       "SMS altyapısı kurulmadı")
        XCTAssertFalse(MusteriMesaji.kanalDurumu(.sms, eposta: "", telefon: "05321234567", smsHazir: true, smsIzni: false).olur)
        XCTAssertEqual(MusteriMesaji.kanalDurumu(.whatsapp, eposta: "", telefon: "", smsHazir: true, smsIzni: true).neden,
                       "Müşterinin telefon numarası yok ya da hatalı.")
        XCTAssertEqual(MusteriMesaji.waBaglantisi(telefon: "0532 123 45 67", metin: " Merhaba Ayşe ")?.absoluteString,
                       "https://wa.me/905321234567?text=Merhaba%20Ay%C5%9Fe")
    }
}

final class WaSablonuTests: XCTestCase {
    func testKimlikVeDoldurma() {
        XCTAssertEqual(WaSablonu.kimlik(baslik: "Evrak Hatırlatma!", olanlar: []), "evrak-hatirlatma")
        XCTAssertEqual(WaSablonu.kimlik(baslik: "Evrak hatırlatma", olanlar: ["evrak-hatirlatma"]), "evrak-hatirlatma-2")
        XCTAssertEqual(WaSablonu.kimlik(baslik: "  ", olanlar: []), "sablon")
        let d = WaSablonu.degerler(adSoyad: "Ayşe Nur Kaya", ulke: "İtalya", benimAdim: "Aleyna Yıldız")
        XCTAssertEqual(WaSablonu.doldur(" Merhaba {ad}, {benim_ilk_adim} ben. {yok}{ulke} ", d), "Merhaba Ayşe, Aleyna ben. İtalya")
        let l = WaSablonu.kaydet([WaSablonu(id: WaSablonu.geciciKimlik(), baslik: "Ulaşamadık", metin: "x")],
                                 calisan: Calisan(uid: "u", belge: ["role": .metin("admin"), "active": .mantik(true)], izinBelgesi: nil))
        guard case let .yaz(_, alanlar, _) = l[0] else { return XCTFail() }
        XCTAssertEqual(alanlar["templates"]?.diziDegeri?.first?.haritaDegeri?["id"]?.metinDegeri, "ulasamadik")
    }
}

final class GorusmeRehberiTests: XCTestCase {
    func testVarsayilanVeAyar() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "uygulama", withExtension: "json"))
        let akis = try JSONDecoder().decode(Akis.self, from: Data(contentsOf: url))
        let r = try XCTUnwrap(akis.rehber)
        XCTAssertEqual(r.kritikSoru.soru, "Davetiye gelecek mi?")
        XCTAssertNotNil(r.kategori(r.kritikSoru.hayir))
        XCTAssertEqual(r.ulkeAlanlari.first?.key, "merkez")
        XCTAssertFalse(r.ulkeler.isEmpty)

        let a = r.ayarla([
            "ilkSorular": .dizi([.metin(" Ad Soyad "), .metin("")]),
            "kritikSoru": .harita(["soru": .metin(""), "evet": .metin("Aile Ziyareti")]),
            "kategoriler": .dizi([.harita(["baslik": .metin("Öğrenci"), "metin": .metin("- a\n- **b** c\nd")]), .harita(["baslik": .metin("")])]),
            "ulkeler": .harita(["italya": .harita(["merkez": .metin("iDATA"), "x": .metin("y")]), "KÖTÜ": .harita([:])]),
        ])
        XCTAssertEqual(a.ilkSorular, ["Ad Soyad"])
        XCTAssertEqual(a.kritikSoru.soru, r.kritikSoru.soru)
        XCTAssertEqual(a.kritikSoru.evet, "Aile Ziyareti")
        XCTAssertEqual(a.kategoriler.map(\.baslik), ["Öğrenci"])
        XCTAssertEqual(a.bolumler, r.bolumler)
        XCTAssertEqual(Array(a.ulkeler.keys), ["italya"])
        XCTAssertEqual(a.ulkeler["italya"]?["merkez"], "iDATA")
        XCTAssertNil(a.ulkeler["italya"]?["x"])
        XCTAssertEqual(GorusmeRehberi.bloklar(a.kategoriler[0].metin), [
            .liste([[.init(metin: "a", kalin: false)], [.init(metin: "b", kalin: true), .init(metin: " c", kalin: false)]]),
            .paragraf([.init(metin: "d", kalin: false)]),
        ])
        XCTAssertEqual(GorusmeRehberi.konusma("Temsilci: Merhaba\nsade").map(\.kim), ["Temsilci", ""])
    }
}

final class MektupTests: XCTestCase {
    var gonca: MektupBilgileri {
        var b = MektupBilgileri()
        b.adSoyad = "Gonca Akkuş Kündem"; b.pasaportNo = "U33013536"
        b.hitapTr = ["İSVEÇ BÜYÜKELÇİLİĞİ", "VİZE DEPARTMANI", "ANKARA"]; b.hitapEn = ["EMBASSY OF SWEDEN", "VISA DEPARTMENT", "ANKARA"]
        b.tarih = "2026-10-05"; b.giris = "2027-03-05"; b.cikis = "2027-03-13"; b.amac = "aile ziyareti"; b.vizeTuru = "uzun-cok"
        b.eslikEdenler = [.init(ad: "Sadık Fırat Kündem", yakinlik: "eşim", pasaport: "U39894525")]
        b.davetEden = "Christin Maria Dahlgren"; b.davetYakinlik = "eşimin dayısının eşi"
        b.oncekiVize = "Daha önce İsveç için Schengen vizesi aldım."; b.meslek = "İngilizce öğretmeni"
        b.isyeri = "Ata Anaokulu Müdürlüğü Çocuk Kulübü"; b.masraf = "Tüm masrafları kendim karşılayacağım."
        return b
    }

    func veri() throws -> MektupVerisi {
        let a: Akis = try XCTUnwrap(IcerikKaynagi.gomulu(.uygulama))
        return try XCTUnwrap(a.mektup)
    }

    func testPromptVeEksikler() throws {
        let v = try veri()
        let c = try XCTUnwrap(v.cumleler.first { $0.id == "coklu-90-180" }).metin
        let p = Mektup.prompt(gonca, ulkeAdi: "İsveç", not: "Eşinin dayısının ailesiyle yakın ilişki.", cumleler: [c], ayar: v.ayar, vizeTurleri: v.vizeTurleri)
        for parca in ["Gonca Akkuş Kündem", "U33013536", "U39894525", "Sadık Fırat Kündem", "Christin Maria Dahlgren", "eşimin dayısının eşi",
                      "05 Mart 2027 – 13 Mart 2027", "05 March 2027", "İsveç", "Uzun süreli ve çok girişli", "180 günde 90 gün",
                      "Türkiye Cumhuriyeti", "Eşinin dayısının", "tam 8 paragraf", "40–50 kelime", "[TR]", "[EN]"] {
            XCTAssertTrue(p.contains(parca), parca)
        }
        XCTAssertEqual(Mektup.eksikler(gonca), [])
        var b = MektupBilgileri(); b.adSoyad = "Ali Veli"
        XCTAssertFalse(Mektup.prompt(b, ulkeAdi: "Fransa", not: "", cumleler: [], ayar: v.ayar, vizeTurleri: v.vizeTurleri).contains("Pasaport numarası:"))
        XCTAssertTrue(Mektup.eksikler(b).contains("Pasaport numarası"))
    }

    func testDoldurma() throws {
        let v = try veri()
        let form: [String: FSDeger] = ["firstName": .metin("GONCA"), "lastName": .metin("AKKUŞ KÜNDEM"), "passportNo": .metin("u33013536"),
                                       "entryDate": .metin("2027-03-05"), "exitDate": .metin("2027-03-13"), "travelPurpose": .metin("Aile_Arkadasi"),
                                       "entries": .metin("M"), "occupation": .metin("İNGİLİZCE ÖĞRETMENİ"), "costCoveredBy": .metin("Kendim"),
                                       "hostName": .metin("CHRISTIN MARIA DAHLGREN")]
        let b = Mektup.doldur(form: form, ulke: "isvec", kayit: nil, veri: v, bugun: "2026-10-05")
        XCTAssertEqual(b.adSoyad, "Gonca Akkuş Kündem")
        XCTAssertEqual(b.pasaportNo, "U33013536")
        XCTAssertEqual(b.amac, "aile / arkadaş ziyareti")
        XCTAssertEqual(b.vizeTuru, "cok")
        XCTAssertEqual(b.davetEden, "Christin Maria Dahlgren")
        XCTAssertEqual(b.meslek, "İngilizce Öğretmeni")
        XCTAssertEqual(b.hitapTr, ["İSVEÇ BÜYÜKELÇİLİĞİ", "VİZE DEPARTMANI", "ANKARA"])
        XCTAssertEqual(b.hitapEn, ["EMBASSY OF SWEDEN", "VISA DEPARTMENT", "ANKARA"])
        var k = MektupBilgileri(); k.pasaportNo = "ELLE123"
        XCTAssertEqual(Mektup.doldur(form: form, ulke: "isvec", kayit: k, veri: v, bugun: "2026-10-05").pasaportNo, "ELLE123")
        let geri = MektupBilgileri(alanlar: b.alanlar)
        XCTAssertEqual(geri, b)
    }

    func testCevapOku() {
        let tr = (1...8).map { "Türkçe paragraf \($0) için örnek metin, ülkeme dönüşüm kesindir." }
        let en = (1...8).map { "English paragraph \($0) sample text, I will return to Türkiye." }
        let temiz = Mektup.cevapOku("[TR]\n\(tr.joined(separator: "\n\n"))\n[EN]\n\(en.joined(separator: "\n\n"))", adSoyad: "", paragraf: 8)
        XCTAssertEqual(temiz.tr, tr); XCTAssertEqual(temiz.en, en); XCTAssertEqual(temiz.uyarilar, [])
        let kirli = (["İşte dilekçenin akıcı ve profesyonel hali:", "", "**[TR]**", "Sayın Yetkili,", ""]
            + tr.enumerated().map { "\($0.offset + 1). **\($0.element)**\n" }
            + ["Saygılarımla,", "", "Gonca Akkuş Kündem", "", "## [EN]", "Dear Sir/Madam,", ""]
            + en.enumerated().map { "Paragraph \($0.offset + 1): \($0.element)\n" }
            + ["Yours faithfully,", "Gonca Akkuş Kündem", "", "Umarım işinize yarar!"]).joined(separator: "\n")
        let r = Mektup.cevapOku(kirli, adSoyad: "Gonca Akkuş Kündem", paragraf: 8)
        XCTAssertEqual(r.tr, tr); XCTAssertEqual(r.en, en)
        let tek = Mektup.cevapOku(tr.joined(separator: "\n\n"), adSoyad: "", paragraf: 8)
        XCTAssertEqual(tek.tr.count, 8); XCTAssertEqual(tek.en.count, 0)
        XCTAssertTrue(tek.uyarilar.contains { $0.contains("işaret") })
        let az = Mektup.cevapOku("[TR]\n\(tr.prefix(6).joined(separator: "\n\n"))\n[EN]\n\(en.joined(separator: "\n\n"))", adSoyad: "", paragraf: 8)
        XCTAssertTrue(az.uyarilar.contains("Türkçe 6 paragraf (beklenen 8)."))
    }

    func testBicimVeYerlesim() {
        XCTAssertEqual(Mektup.dosyaAdi("Gonca Akkuş Kündem"), "GONCA AKKUŞ KÜNDEM DİLEKÇE.pdf")
        XCTAssertEqual(Mektup.dosyaAdi("ismail ışık"), "İSMAİL IŞIK DİLEKÇE.pdf")
        XCTAssertEqual(Mektup.tarihNoktali("2026-10-05"), "05.10.2026")
        XCTAssertEqual(Mektup.tarihEn("2026-10-05"), "05 October 2026")
        XCTAssertEqual(Mektup.ozelAd("İSMAİL IŞIK"), "İsmail Işık")
        XCTAssertEqual(Mektup.kelimeSay("  bir iki   üç "), 3)
        let olc: (String) -> Double = { Double($0.count) * 5 }
        let genislik = Mektup.Olcu.genislik - Mektup.Olcu.sol - Mektup.Olcu.sag
        let satirlar = Mektup.satirKir(String(repeating: "kelime ", count: 40), olc: olc, genislik: genislik)
        XCTAssertTrue(satirlar.allSatisfy { olc($0) <= genislik })
        let uzun = Array(repeating: Array(repeating: "kelime", count: 60).joined(separator: " "), count: 10)
        let s = Mektup.yerlesim(hitap: ["İSVEÇ BÜYÜKELÇİLİĞİ", "VİZE DEPARTMANI", "ANKARA"], tarih: "05.10.2026", selam: "Sayın Yetkili,",
                                paragraflar: uzun, kapanis: "Saygılarımla,", imza: "Gonca Akkuş Kündem", olc: olc)
        XCTAssertEqual(s[0].prefix(3).map { [$0.x, $0.y] }, [[71, 761], [71, 738], [71, 716]])
        let t = s[0].first { $0.metin == "05.10.2026" }!
        XCTAssertEqual(t.y, 693)
        XCTAssertEqual(t.x + olc("05.10.2026"), Mektup.Olcu.genislik - Mektup.Olcu.sag, accuracy: 0.01)
        XCTAssertEqual(s[0][5].y, 648)
        XCTAssertGreaterThanOrEqual(s.count, 2)
        XCTAssertEqual(s[1][0].y, 761)
        XCTAssertTrue(s.allSatisfy { $0.allSatisfy { $0.y >= 72 } })
        XCTAssertEqual(s.last?.last?.metin, "Gonca Akkuş Kündem")
    }
}
