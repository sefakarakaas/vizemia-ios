import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import VizeMiaCekirdek

/// Başvuru ayrıntısındaki işlemler, sitenin GERÇEK güvenlik kurallarıyla
/// (statü + takip + mail + SMS tek yazımda, evrak, arama, notlar).
/// Yalnız emülatörler açıkken çalışır (EkipEmulatorTests ile aynı komut).
final class BasvuruEmulatorTests: XCTestCase {
    struct Emulator {
        var fs: String
        var auth: String
        var kimlik: KimlikIstemci {
            KimlikIstemci(kimlikTaban: "http://\(auth)/identitytoolkit.googleapis.com/v1",
                          belirtecTaban: "http://\(auth)/securetoken.googleapis.com/v1")
        }
        func istemci(_ b: String?) -> FirestoreIstemci {
            FirestoreIstemci(taban: URL(string: "http://\(fs)/v1")!, proje: "demo-vizemia", belirtec: b)
        }
        func hesapAc(_ ad: String, _ sifre: String) async throws -> String {
            var i = URLRequest(url: URL(string: "http://\(auth)/identitytoolkit.googleapis.com/v1/accounts:signUp?key=x")!)
            i.httpMethod = "POST"
            i.setValue("application/json", forHTTPHeaderField: "Content-Type")
            i.httpBody = try JSONSerialization.data(withJSONObject: ["email": "\(ad)@panel.vizemia.local", "password": sifre, "returnSecureToken": true])
            let (v, _) = try await Ag.gonder(i, oturum: .shared)
            let j = try JSONSerialization.jsonObject(with: v) as! [String: Any]
            return j["localId"] as! String
        }
    }
    var e: Emulator!

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let f = env["FIRESTORE_EMULATOR_HOST"], let a = env["FIREBASE_AUTH_EMULATOR_HOST"] else {
            throw XCTSkip("Emülatör yok.")
        }
        e = Emulator(fs: f, auth: a)
    }

    func statuBelgesi(_ ad: String, musteri: String, son: Bool = false, gerekenler: [String] = [], sira: Int, silme: Int? = nil) -> [String: FSDeger] {
        var a: [String: FSDeger] = [
            "name": .metin(ad), "publicName": .metin(musteri), "publicDescription": .metin(""), "color": .metin("#2f6f8c"),
            "order": .tam(sira), "isFinal": .mantik(son), "notifyCustomer": .mantik(true),
            "gerekenler": .dizi(gerekenler.map { .metin($0) }),
        ]
        if let silme { a["silmeGun"] = .tam(silme) }
        return a
    }

    func testStatuNotEvrakArama() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("danisman\(ek)", "gizli-sifre-1")
        let okurUid = try await e.hesapAc("izleyici\(ek)", "gizli-sifre-2")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("danisman\(ek)"), "displayName": .metin("Sefa Karakaş"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("employees/\(okurUid)", alanlar: [
            "username": .metin("izleyici\(ek)"), "displayName": .metin("İzleyici"), "role": .metin("reader"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi(Calisan.varsayilanIzinler["writer"]!.map { .metin($0) }),
            "reader": .dizi(Calisan.varsayilanIzinler["reader"]!.map { .metin($0) }),
        ])])
        let st: [(String, [String: FSDeger])] = [
            ("potansiyel", statuBelgesi("Potansiyel Müşteri", musteri: "Görüşme aşamasında", sira: 10, silme: 60)),
            ("randevu-takip", statuBelgesi("Randevu Takipte", musteri: "Randevunuz takip ediliyor", gerekenler: ["odeme"], sira: 20)),
            ("evrak-bekleniyor", statuBelgesi("Evrak Bekleniyor", musteri: "Evraklarınız bekleniyor", sira: 30)),
            ("teslim", statuBelgesi("Pasaport Teslim Edildi", musteri: "Pasaportunuz teslim edildi", son: true, sira: 40)),
        ]
        for (id, a) in st { try await owner.belgeYaz("statuses/\(id)", alanlar: a) }
        let statuler = st.map { Statu(kimlik: $0.0, alanlar: $0.1) }
        let durum = { (id: String) in statuler.first { $0.id == id }! }

        let appId = "app\(ek)"
        let takipId = String(repeating: "b", count: 60) + ek
        try await owner.belgeYaz("applications/\(appId)", alanlar: [
            "trackingCode": .metin("2026-11\(ek)"), "year": .tam(2026), "month": .tam(11),
            "country": .metin("almanya"), "countryName": .metin("Almanya"), "firstName": .metin("AYŞE"), "lastName": .metin("YILMAZ"),
            "passportLast3": .metin("678"), "statusId": .metin("potansiyel"), "statusName": .metin("Potansiyel Müşteri"),
            "checklist": .harita(["pasaport": .mantik(true)]), "finalAt": .bos, "deleteAfter": .bos, "legalHold": .mantik(false),
            "openedAt": .zaman(Date()), "createdAt": .zaman(Date()), "createdBy": .metin(uid),
            "updatedAt": .zaman(Date()), "updatedBy": .metin(uid), "reviewNote": .metin("Telefon eksik"),
        ])
        try await owner.belgeYaz("applications/\(appId)/private/keys", alanlar: [
            "takipId": .metin(takipId), "passportHash": .metin(String(repeating: "c", count: 64)),
            "updatedAt": .zaman(Date()), "updatedBy": .metin(uid)])
        try await owner.belgeYaz("applications/\(appId)/private/data", alanlar: [
            "form": .harita(["phone": .metin("0532 111 22 33"), "email": .metin("Ayse@Ornek.com")]),
            "updatedAt": .zaman(Date()), "updatedBy": .metin(uid)])

        let o = try await e.kimlik.giris(kullaniciAdi: "danisman\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _g1 = try await ben.belge("employees/\(uid)")
        let calisan = Calisan(uid: uid, belge: try XCTUnwrap(_g1),
                              izinBelgesi: try await ben.belge("settings/permissions"))
        func basvuru() async throws -> Basvuru {
            let _g2 = try await ben.belge("applications/\(appId)")
            return Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_g2))
        }

        // Okuma: ayrıntıdaki alt koleksiyonlar ve hassas belge.
        let _g3 = try await ben.belge("applications/\(appId)/private/keys")
        let anahtar = try XCTUnwrap(_g3)
        XCTAssertEqual(anahtar["takipId"]?.metinDegeri, takipId)
        let form = try await ben.belge("applications/\(appId)/private/data")
        let iletisim = MusteriIletisimi(form: form?["form"]?.haritaDegeri)
        XCTAssertTrue(iletisim.epostaAcik)

        // 1) Ödemesiz "Randevu Takipte": kural da reddediyor (uygulama önce kendisi uyarır).
        var b = try await basvuru()
        XCTAssertEqual(b.gecisEngelleri(durum("randevu-takip")), ["ödeme bilgisi"])
        let red = BasvuruIslemi.statu(b, hedef: durum("randevu-takip"), statuler: statuler, musteriNotu: "", acikNotlar: [],
                                      takipId: takipId, calisan: calisan, saklamaGun: 60, eposta: nil, sms: nil, smsGonder: false, iletisim: nil)
        do { try await ben.isle(red.yazimlar); XCTFail("ödemesiz geçmemeli") } catch {
            XCTAssertEqual(error as? FirestoreHatasi, .izinYok)
        }

        // 2) Statü + müşteri notu + takip sayfası + statü maili + SMS, tek yazımda.
        let mailAyari = EpostaAyari(belge: ["statuSablonlari": .harita(["evrak-bekleniyor": .harita([
            "aktif": .mantik(true), "konu": .metin("{ulke} başvurunuz"), "metin": .metin("Sayın {adSoyad}, durum: {statu}")])])])
        let r = BasvuruIslemi.statu(b, hedef: durum("evrak-bekleniyor"), statuler: statuler, musteriNotu: "Evrak listesini ilettik.",
                                    acikNotlar: [], takipId: takipId, calisan: calisan, saklamaGun: 60, eposta: mailAyari,
                                    sms: SmsAyari(belge: ["enabled": .mantik(true)]), smsGonder: true, iletisim: iletisim)
        XCTAssertTrue(r.eposta && r.sms)
        try await ben.isle(r.yazimlar)
        b = try await basvuru()
        XCTAssertEqual(b.statuId, "evrak-bekleniyor")
        XCTAssertNotNil(b.statuZamani)
        XCTAssertNil(b.silinecek, "evrak bekleniyor süresiz")
        let _g4 = try await owner.belge("takip/\(takipId)")
        let takip = try XCTUnwrap(_g4)
        XCTAssertEqual(takip["statusName"], .metin("Evraklarınız bekleniyor"))
        XCTAssertEqual(takip["notes"]?.diziDegeri?.count, 1)
        XCTAssertEqual(takip["asamalar"]?.diziDegeri?.count, 4)
        let mailler = try await owner.sorgu(koleksiyon: "eposta", kosullar: [.esit("appId", .metin(appId))])
        XCTAssertEqual(mailler.first?.alanlar["to"], .metin("ayse@ornek.com"))
        XCTAssertEqual(mailler.first?.alanlar["text"], .metin("Sayın Ayşe Yılmaz, durum: Evraklarınız bekleniyor"))
        let smsler = try await owner.sorgu(koleksiyon: "sms", kosullar: [.esit("appId", .metin(appId))])
        XCTAssertEqual(smsler.first?.alanlar["to"], .metin("+905321112233"))
        let gecmis = try await ben.sorgu(koleksiyon: "log", sirala: ("at", .azalan), ust: "applications/\(appId)")
        XCTAssertEqual(gecmis.map { GecmisSatiri(kimlik: $0.kimlik, alanlar: $0.alanlar) }.first?.metin, "Potansiyel Müşteri → Evrak Bekleniyor")

        // 3) Evrak (tireli kimlik) — yalnız o anahtar değişir.
        try await ben.isle(BasvuruIslemi.evrak(b, Evrak(id: "eski-pasaport", ad: "Eski pasaport", kosullu: false), geldi: true, calisan: calisan))
        b = try await basvuru()
        XCTAssertEqual(b.evraklar, ["pasaport": true, "eski-pasaport": true])

        // 4) Tekrar arama: "Arandı".
        try await ben.isle(BasvuruIslemi.arandi(b, not: "Evrakları hafta sonu getirecek", calisan: calisan))
        b = try await basvuru()
        XCTAssertNotNil(b.sonArama)

        // 5) Müşteriye görünür not: takip sayfası yenilenir (önceki notla birlikte).
        let notlar = try await ben.sorgu(koleksiyon: "notes", sirala: ("at", .azalan), ust: "applications/\(appId)")
            .map { BasvuruNotu(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        try await ben.isle(BasvuruIslemi.not(b, metin: "Randevu tarihiniz netleşti.", musteriyeGorunur: true, statu: durum(b.statuId),
                                             statuler: statuler, acikNotlar: notlar.filter(\.musteriyeGorunur), takipId: takipId,
                                             calisan: calisan, sms: nil, smsGonder: false, iletisim: nil))
        let _g5 = try await owner.belge("takip/\(takipId)")
        let takip2 = try XCTUnwrap(_g5)
        XCTAssertEqual(takip2["notes"]?.diziDegeri?.first?.haritaDegeri?["text"], .metin("Randevu tarihiniz netleşti."))
        XCTAssertEqual(takip2["notes"]?.diziDegeri?.count, 2)

        // 6) Üst not: ekle, kendi notunu sil.
        try await ben.isle(BasvuruIslemi.ustNotEkle(b, metin: "Yalnız öğleden sonra aranmalı", calisan: calisan))
        let ust = try await ben.sorgu(koleksiyon: "ustNotlar", sirala: ("at", .azalan), ust: "applications/\(appId)")
            .map { UstNot(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        XCTAssertEqual(ust.first?.metin, "Yalnız öğleden sonra aranmalı")
        try await ben.isle(BasvuruIslemi.ustNotSil(b, try XCTUnwrap(ust.first), calisan: calisan))

        // 7) "Kontrol ettim".
        try await ben.isle(BasvuruIslemi.kontrolEdildi(b, calisan: calisan))
        b = try await basvuru()
        XCTAssertEqual(b.kontrolNotu, "")

        // 8) Son adım: finalAt ve saklama süresi.
        try await ben.isle(BasvuruIslemi.statu(b, hedef: durum("teslim"), statuler: statuler, musteriNotu: "", acikNotlar: [],
                                               takipId: takipId, calisan: calisan, saklamaGun: 60, eposta: mailAyari, sms: nil,
                                               smsGonder: false, iletisim: iletisim).yazimlar)
        b = try await basvuru()
        XCTAssertNotNil(b.sonAdimZamani)
        XCTAssertNotNil(b.silinecek)

        // 9) İzleyici statü değiştiremez.
        let okur = e.istemci(try await e.kimlik.giris(kullaniciAdi: "izleyici\(ek)", sifre: "gizli-sifre-2").belirtec)
        let okurCalisan = Calisan(uid: okurUid, belge: ["role": .metin("reader"), "active": .mantik(true)], izinBelgesi: nil)
        do {
            try await okur.isle(BasvuruIslemi.statu(b, hedef: durum("evrak-bekleniyor"), statuler: statuler, musteriNotu: "",
                                                    acikNotlar: [], takipId: takipId, calisan: okurCalisan, saklamaGun: 60,
                                                    eposta: nil, sms: nil, smsGonder: false, iletisim: nil).yazimlar)
            XCTFail("izleyici değiştirememeli")
        } catch {
            XCTAssertEqual(error as? FirestoreHatasi, .izinYok)
        }
    }
}
