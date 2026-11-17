import XCTest
@testable import VizeMiaCekirdek

final class EkipTests: XCTestCase {
    func testKullaniciAdi() {
        XCTAssertEqual(KimlikIstemci.temizAd("  Sefa "), "sefa")
        XCTAssertEqual(KimlikIstemci.temizAd("ayse.yilmaz"), "ayse.yilmaz")
        XCTAssertNil(KimlikIstemci.temizAd("se"))
        XCTAssertNil(KimlikIstemci.temizAd("şefa"))
        XCTAssertNil(KimlikIstemci.temizAd("sefa@x.com"))
    }

    func testFirebaseHatalari() {
        let h = { (m: String) in KimlikIstemci.hata(kod: 400, ["error": ["message": m]]) }
        XCTAssertEqual(h("INVALID_LOGIN_CREDENTIALS"), .bilgilerYanlis)
        XCTAssertEqual(h("EMAIL_NOT_FOUND"), .bilgilerYanlis)
        XCTAssertEqual(h("USER_DISABLED"), .hesapKapali)
        XCTAssertEqual(h("TOO_MANY_ATTEMPTS_TRY_LATER : Access temporarily disabled"), .cokDeneme)
        XCTAssertEqual(h("TOKEN_EXPIRED"), .oturumBitti)
        XCTAssertEqual(h("BASKA"), .sunucu("BASKA"))
    }

    func testOturumEskime() {
        let o = KimlikIstemci.Oturum(uid: "u", belirtec: "b", yenileme: "y", bitis: an("2026-11-17T10:00:00Z"))
        XCTAssertFalse(o.eskidi(an("2026-11-17T09:50:00Z")))
        XCTAssertTrue(o.eskidi(an("2026-11-17T09:56:00Z")))
    }

    func testCalisanIzinleri() {
        let izin: [String: FSDeger] = ["roles": .harita(["writer": .dizi([.metin("lead.view"), .metin("lead.manage")]), "reader": .dizi([.metin("lead.view")])])]
        let yazar = Calisan(uid: "u1", belge: ["username": .metin("sefa"), "displayName": .metin("Sefa Karakaş"), "role": .metin("writer"), "active": .mantik(true)], izinBelgesi: izin)
        XCTAssertTrue(yazar.yapabilir("lead.manage"))
        XCTAssertFalse(yazar.yapabilir("kasa.view"))
        XCTAssertEqual(yazar.ilkAd, "Sefa")
        XCTAssertEqual(yazar.rolAdi, "Operasyon")
        let yonetici = Calisan(uid: "u2", belge: ["username": .metin("admin"), "role": .metin("admin"), "active": .mantik(true)], izinBelgesi: izin)
        XCTAssertTrue(yonetici.yapabilir("kasa.view"))
        XCTAssertEqual(yonetici.ilkAd, "admin")   // ad yoksa kullanıcı adı
        let pasif = Calisan(uid: "u3", belge: ["role": .metin("admin"), "active": .mantik(false)], izinBelgesi: izin)
        XCTAssertFalse(pasif.yapabilir("lead.view"))
        // Ayar belgesi yoksa panelin varsayılan izinleri.
        let varsayilan = Calisan(uid: "u4", belge: ["role": .metin("reader"), "active": .mantik(true)], izinBelgesi: nil)
        XCTAssertTrue(varsayilan.yapabilir("support.view"))
        XCTAssertFalse(varsayilan.yapabilir("lead.manage"))
    }

    func ornekTalepler() -> [Talep] {
        [
            Talep(tur: .geriArama, kimlik: "a", alanlar: ["name": .metin("Ali Veli"), "phone": .metin("+905321112233"), "mode": .metin("saat"),
                  "date": .metin("2026-11-17"), "times": .dizi([.metin("10:00"), .metin("10:30")]), "status": .metin("new"), "countryName": .metin("Almanya")]),
            Talep(tur: .basvuru, kimlik: "b", alanlar: ["firstName": .metin("AYSE"), "lastName": .metin("OZTURK"), "phone": .metin("+905499072523"),
                  "callbackMode": .metin("hemen"), "callbackDate": .metin("2026-11-17"), "callbackTimes": .dizi([.metin("11:00")]), "status": .metin("new")]),
            Talep(tur: .geriArama, kimlik: "c", alanlar: ["name": .metin("Can"), "mode": .metin("saat"), "date": .metin("2026-11-15"),
                  "times": .dizi([.metin("09:00")]), "status": .metin("new")]),
            Talep(tur: .geriArama, kimlik: "d", alanlar: ["name": .metin("Deniz"), "mode": .metin("saat"), "date": .metin("2026-11-18"),
                  "times": .dizi([.metin("14:00")]), "status": .metin("called")]),
            Talep(tur: .geriArama, kimlik: "e", alanlar: ["name": .metin("Ece"), "date": .metin("2026-11-16"), "status": .metin("new"), "silindi": .mantik(true)]),
        ]
    }

    func testTalepOkumaVeSira() {
        let t = ornekTalepler()
        XCTAssertEqual(t[1].ad, "AYSE OZTURK")
        XCTAssertEqual(t[1].yol, "applicationRequests/b")
        XCTAssertTrue(t[1].acil)
        XCTAssertEqual(t[0].durumAdi, "Aranacak")
        XCTAssertEqual(t[1].durumAdi, "Yeni")
        XCTAssertEqual(Talep.sirala(t).map { $0.kimlik }, ["b", "c", "e", "a", "d"])
        XCTAssertTrue(t[2].gecikti(bugun: "2026-11-17"))
        XCTAssertFalse(t[3].gecikti(bugun: "2026-11-19"))   // ulaşılamadı: gecikme sayılmaz
        XCTAssertFalse(t[4].acik)
        XCTAssertEqual(t[0].whatsappNumarasi, "905321112233")
    }

    func testAramaMetni() {
        let t = ornekTalepler()
        XCTAssertEqual(t[0].aramaMetni(bugun: "2026-11-17"), "Bugün 10:00–11:00")
        XCTAssertEqual(t[1].aramaMetni(bugun: "2026-11-17"), "Hemen aranmak istiyor")
        XCTAssertEqual(t[3].aramaMetni(bugun: "2026-11-17"), "Yarın 14:00–14:30")
        XCTAssertEqual(t[2].aramaMetni(bugun: "2026-11-17"), "15 Kas Paz 09:00–09:30")
    }

    func testOzet() {
        let o = TalepOzeti(ornekTalepler(), bugun: "2026-11-17")
        XCTAssertEqual(o, { var x = TalepOzeti([], bugun: ""); x.acil = 1; x.bugun = 1; x.geciken = 1; x.acik = 4; return x }())
    }

    func testDurumAlanlariKuraldakiyleAyni() {
        let a = Talep.durumAlanlari(durum: "called", icNot: "  sesli mesaj bırakıldı ", uid: "u1")
        XCTAssertEqual(Set(a.keys), ["status", "internalNote", "handledBy"])
        XCTAssertEqual(a["internalNote"], .metin("sesli mesaj bırakıldı"))
        let i = Talep.durumAlanlari(durum: "cancelled", icNot: "", iptalSebebi: "Mükerrer talep", uid: "u1")
        XCTAssertEqual(i["cancelReason"], .metin("Mükerrer talep"))
        let k = IslemKaydi.alanlar(eylem: "callback.update", hedef: "abc", ayrinti: "called",
                                   calisan: Calisan(uid: "u1", belge: ["username": .metin("sefa"), "role": .metin("writer"), "active": .mantik(true)], izinBelgesi: nil))
        XCTAssertEqual(Set(k.keys), ["action", "target", "detail", "by", "byName"])
        XCTAssertEqual(k["byName"], .metin("sefa"))
    }

    func testSorguYapisi() throws {
        let y = FirestoreIstemci.sorguYapisi(koleksiyon: "callback",
            kosullar: [.icinde("status", [.metin("new"), .metin("called")])], sirala: ("createdAt", .azalan), sinir: 200)
        let j = String(decoding: try JSONSerialization.data(withJSONObject: y, options: [.sortedKeys]), as: UTF8.self)
        XCTAssertEqual(j, #"{"from":[{"collectionId":"callback"}],"limit":200,"orderBy":[{"direction":"DESCENDING","field":{"fieldPath":"createdAt"}}],"where":{"fieldFilter":{"field":{"fieldPath":"status"},"op":"IN","value":{"arrayValue":{"values":[{"stringValue":"new"},{"stringValue":"called"}]}}}}}"#)
        let g = FirestoreIstemci.guncellemeGovdesi(ad: "x/y", alanlar: ["status": .metin("called"), "handledBy": .metin("u")], zamanAlanlari: ["handledAt"])
        let gj = String(decoding: try JSONSerialization.data(withJSONObject: g, options: [.sortedKeys]), as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
        XCTAssertTrue(gj.contains(#""updateMask":{"fieldPaths":["handledBy","status"]}"#))
        XCTAssertTrue(gj.contains(#""currentDocument":{"exists":true}"#))
        XCTAssertTrue(gj.contains(#"{"fieldPath":"handledAt","setToServerValue":"REQUEST_TIME"}"#))
    }

    func testSorguCevabi() {
        let j = #"[{"document":{"name":"projects/p/databases/(default)/documents/callback/abc","fields":{"name":{"stringValue":"Ali"}}},"readTime":"x"},{"readTime":"y"}]"#
        let b = FirestoreIstemci.sorguCevabi(Data(j.utf8))
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b[0].kimlik, "abc")
        XCTAssertEqual(b[0].alanlar["name"], .metin("Ali"))
    }

    func testTakvim() {
        let statu = Statu(kimlik: "potansiyel", alanlar: ["name": .metin("Potansiyel Müşteri"), "aramaMin": .tam(7), "aramaMax": .tam(14), "order": .tam(1)])
        XCTAssertTrue(statu.tekrarAranir)
        let randevulu = Basvuru(kimlik: "r1", alanlar: ["firstName": .metin("MURAT"), "lastName": .metin("T"), "countryName": .metin("Fransa"),
                                "appointmentAt": .zaman(an("2026-11-20T07:00:00Z")), "randevuSaati": .metin("10:00"), "randevuYeri": .metin("VFS")])
        let tekrar = Basvuru(kimlik: "t1", alanlar: ["firstName": .metin("ELIF"), "statusId": .metin("potansiyel"),
                             "statusAt": .zaman(an("2026-11-05T09:00:00Z"))])
        let simdi = an("2026-11-17T09:00:00Z")
        let d = tekrar.aramaDurumu(statu, simdi: simdi)
        XCTAssertEqual(d?.durum, .ara)
        XCTAssertEqual(Basvuru.aramaEtiketi(d), "Aranmalı (2 gün içinde)")
        let isler = TakvimIsi.olustur(talepler: ornekTalepler(), randevular: [randevulu], tekrarlar: [tekrar],
                                      statuler: ["potansiyel": statu], bugun: "2026-11-17", simdi: simdi)
        XCTAssertEqual(isler.filter { $0.tur == .arama }.count, 4)   // silinen dışarıda
        let r = isler.first { $0.tur == .randevu }
        XCTAssertEqual(r?.gun, "2026-11-20")
        XCTAssertEqual(r?.alt, "Fransa · VFS")
        let t = isler.first { $0.tur == .tekrar }
        XCTAssertEqual(t?.gun, "2026-11-17")
        XCTAssertEqual(t?.alt, "Potansiyel Müşteri · 12.11–19.11 arası")
        XCTAssertTrue(isler.first { $0.id == "talep:callback/c" }?.gecikti ?? false)
        let bugunkuler = TakvimIsi.sirala(isler.filter { $0.gun == "2026-11-17" })
        XCTAssertEqual(bugunkuler.map { $0.baslik }, ["Ali Veli", "AYSE OZTURK", "ELIF"])
    }

    func testAyIzgarasi() {
        let g = TakvimIsi.ayIzgarasi(yil: 2026, ay: 11)
        XCTAssertEqual(g.count, 42)
        XCTAssertEqual(g.first, "2026-10-26")   // Kasım 2026 Pazar başlıyor; ızgara Pazartesi
        XCTAssertTrue(g.contains("2026-11-30"))
    }

    func testDestek() {
        let d = DestekTalebi(kimlik: "s1", alanlar: ["name": .metin("Ayşe"), "subject": .metin("Randevu"), "status": .metin("open")])
        XCTAssertEqual(d.durumAdi, "İşlemde")
        XCTAssertEqual(Set(DestekTalebi.durumAlanlari(durum: "closed", icNot: "", uid: "u").keys), ["status", "internalNote", "handledBy"])
    }
}
