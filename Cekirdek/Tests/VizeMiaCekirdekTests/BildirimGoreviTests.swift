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
