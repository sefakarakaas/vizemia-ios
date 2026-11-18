import XCTest
@testable import VizeMiaCekirdek

/// MRZ okuma ve onarımları (site deposu: tests/mrz-parse.test.mjs ile aynı örnekler).
/// Gerçek pasaport verisi yok: MRZ'ler test içinde üretiliyor (KVKK).
final class MrzTests: XCTestCase {
    static func tckn(_ ilk9: String) -> String {
        let d = ilk9.compactMap { Int(String($0)) }
        var tek = 0, cift = 0
        for i in stride(from: 0, to: 9, by: 2) { tek += d[i] }
        for i in stride(from: 1, to: 8, by: 2) { cift += d[i] }
        let d10 = ((tek * 7 - cift) % 10 + 10) % 10
        let t = d.reduce(0, +) + d10
        return ilk9 + String(d10) + String(t % 10)
    }

    static func mrz(soyad: String = "OZTURK", ad: String = "MERYEM", no: String = "U12345678", dogum: String = "900115",
                    cins: String = "F", gecer: String = "300115", tckn: String = MrzTests.tckn("123456789")) -> (String, String) {
        let pad = { (s: String, n: Int) in s.count >= n ? String(s.prefix(n)) : s + String(repeating: "<", count: n - s.count) }
        let l1 = pad("P<TUR\(soyad)<<\(ad)", 44)
        let n = pad(no, 9)
        let bas = n + Mrz.kontrolHanesi(n) + "TUR" + dogum + Mrz.kontrolHanesi(dogum) + cins + gecer + Mrz.kontrolHanesi(gecer)
        let kisisel = pad(tckn, 14)
        let govde = bas + kisisel + Mrz.kontrolHanesi(kisisel)
        let k = Array(govde)
        let l2 = govde + Mrz.kontrolHanesi(String(k[0..<10]) + String(k[13..<20]) + String(k[21..<43]))
        return (l1, l2)
    }

    func testKusursuz() {
        let (l1, l2) = Self.mrz()
        XCTAssertEqual(l2.count, 44)
        let p = Mrz.coz(l1, l2)
        XCTAssertEqual(p.hatalar, [])
        XCTAssertEqual(p.alanlar.pasaportNo, "U12345678")
        XCTAssertEqual(p.alanlar.soyad, "OZTURK")
        XCTAssertEqual(p.alanlar.ad, "MERYEM")
        XCTAssertEqual(p.alanlar.dogum, "1990-01-15")
        XCTAssertEqual(p.alanlar.gecerlilik, "2030-01-15")
        XCTAssertEqual(p.alanlar.cinsiyet, "F")
        XCTAssertEqual(p.alanlar.tckn, Self.tckn("123456789"))
    }

    func testKuyrukOnarimi() {
        let (l1, l2) = Self.mrz()
        let k = Array(l2)
        let eksik = String(k[0..<39]) + String(k[40...])
        var p = Mrz.coz(l1, eksik)
        XCTAssertEqual(p.hatalar, [], "eksik '<' onarılmalı")
        XCTAssertEqual(p.alanlar.tckn, Self.tckn("123456789"))
        XCTAssertFalse(p.notlar.isEmpty, "onarım bildirilmeli")
        let fazla = String(k[0..<39]) + "<" + String(k[39...])
        p = Mrz.coz(l1, fazla)
        XCTAssertEqual(p.hatalar, [], "fazla '<' onarılmalı")
    }

    func testPasaportNoOnarimi() {
        let (l1, l2) = Self.mrz(no: "U12345678")
        var p = Mrz.coz(l1, "V" + String(l2.dropFirst()))
        XCTAssertEqual(p.alanlar.pasaportNo, "U12345678")
        XCTAssertTrue(p.notlar.contains { $0.contains("düzeltildi") })
        for (no, yanlis) in [("U12345678", "0"), ("S12345678", "8"), ("L12345678", "1"), ("G12345678", "6")] {
            let (a, b) = Self.mrz(no: no)
            p = Mrz.coz(a, yanlis + String(b.dropFirst()))
            XCTAssertEqual(p.alanlar.pasaportNo, no, "\(yanlis) → \(no.prefix(1)) kurtarılamadı")
        }
        // Belirsiz okumayı uydurmaz.
        let k = Array(l2)
        p = Mrz.coz(l1, String(k[0..<4]) + "X" + String(k[5...]))
        XCTAssertNotEqual(p.alanlar.pasaportNo, "U12345678")
        XCTAssertFalse(p.hatalar.isEmpty)
    }

    func testMetindenOkuma() {
        let (l1, l2) = Self.mrz(soyad: "YILMAZ", ad: "ALI<CAN")
        // Fotoğrafta başka yazılar da var; OCR satırları boşluklu ve küçük harfli olabilir.
        let metin = "TÜRKİYE CUMHURİYETİ\nPASAPORT\n\(l1.lowercased())\n\(l2)\n"
        let s = Mrz.oku(metin)
        XCTAssertEqual(s?.alanlar.soyad, "YILMAZ")
        XCTAssertEqual(s?.alanlar.ad, "ALI CAN")
        XCTAssertEqual(s?.tamam, true)
        let k = Mrz.karsilastir(s!.alanlar, form: ["firstName": "ALI CAN", "passportNo": "U 12345678"])
        XCTAssertEqual(k.first { $0.key == "firstName" }?.uyuyor, true)
        XCTAssertEqual(k.first { $0.key == "passportNo" }?.uyuyor, true, "boşluk farkı sayılmaz")
        XCTAssertEqual(k.first { $0.key == "birthDate" }?.eksik, true)
        XCTAssertEqual(Mrz.formDegerleri(s!.alanlar)["passportExpires"], "2030-01-15")
    }

    func testFormlaDegerlendirme() throws {
        let (l1, l2) = Self.mrz()
        let form = ["firstName": "Meryem", "lastName": "ÖZTÜRK", "passportNo": "U12345678", "birthDate": "1990-01-15",
                    "passportExpires": "2030-01-15", "sex": "F", "nationalId": Self.tckn("123456789")]
        let simdi = Date(timeIntervalSince1970: 1_790_000_000)
        // Panel gibi: "ÖZTÜRK" A-Z dışı harfleri atınca "ZTRK" olur; MRZ "OZTURK" → uyuşmaz, danışman bakar.
        let d = try XCTUnwrap(PasaportDegerlendirmesi.degerlendir(metin: "\(l1)\n\n\(l2)\n", form: form, simdi: simdi))
        XCTAssertTrue(d.yanlisUzunluk.isEmpty)
        XCTAssertEqual(d.uyusmayanlar, ["Soyisim"])
        XCTAssertFalse(d.hepsiUyuyor)

        var duz = form
        duz["lastName"] = "OZTURK"
        duz["nationalId"] = ""
        let tam = try XCTUnwrap(PasaportDegerlendirmesi.degerlendir(metin: "\(l1)\n\(l2)", form: duz, simdi: simdi))
        // Formda boş T.C. kimlik: MRZ'de varsa "eksik ama okunmuş" → otomatik onay olmaz.
        XCTAssertFalse(tam.hepsiUyuyor)
        XCTAssertEqual(tam.uyusmayanlar, ["T.C. kimlik no"])
        duz["nationalId"] = Self.tckn("123456789")
        XCTAssertTrue(try XCTUnwrap(PasaportDegerlendirmesi.degerlendir(metin: "\(l1)\n\(l2)", form: duz, simdi: simdi)).hepsiUyuyor)

        let kisa = try XCTUnwrap(PasaportDegerlendirmesi.degerlendir(metin: "\(l1)\n\(l2.dropLast())", form: duz, simdi: simdi))
        XCTAssertEqual(kisa.yanlisUzunluk.map(\.uzunluk), [43])
        XCTAssertTrue(kisa.guvenilmez)
        XCTAssertFalse(kisa.hepsiUyuyor)
        XCTAssertNil(PasaportDegerlendirmesi.degerlendir(metin: l1, form: duz))
    }

    func testPasaporttanDoldurma() {
        let (l1, l2) = Self.mrz()
        let gelen = Mrz.formDegerleri(Mrz.coz(l1, l2, simdi: Date(timeIntervalSince1970: 1_790_000_000)).alanlar)
        let sorulan: Set<String> = ["firstName", "lastName", "passportNo", "birthDate", "passportExpires", "passportIssued", "sex"]
        let r = PasaporttanDoldurma.uygula(gelen, degerler: ["firstName": "MERYEM", "lastName": "YILMAZ"], sorulan: sorulan)
        XCTAssertEqual(r.dolan, ["Pasaport no", "Doğum tarihi", "Geçerlilik tarihi", "Cinsiyet"])
        XCTAssertEqual(r.celiskiler.map(\.key), ["lastName"])
        XCTAssertEqual(r.degerler["lastName"], "YILMAZ", "çelişen alan sorulmadan değişmez")
        XCTAssertNil(r.degerler["nationalId"], "bu ülkede sorulmayan alana dokunulmaz")
        XCTAssertNil(r.degerler["passportIssued"], "veriliş tarihi MRZ'de yok, tahmin edilmez")
        let z = PasaporttanDoldurma.uygula(["lastName": "OZTURK"], degerler: r.degerler, sorulan: sorulan, zorla: true)
        XCTAssertEqual(z.degerler["lastName"], "OZTURK")
        XCTAssertEqual(z.dolan, ["Soyisim"])
    }
}
