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

    func testOdemeBelgeKonsolosluk() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("odeme\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("odeme\(ek)"), "displayName": .metin("Ezgi Danışman"), "role": .metin("writer"), "active": .mantik(true)])
        // Ödeme izni olan danışman (panelde Ayarlar → Rol izinleri'nden verilir).
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi((Calisan.varsayilanIzinler["writer"]! + ["app.payment"]).map { .metin($0) }),
        ])])
        let st: [(String, [String: FSDeger])] = [
            ("potansiyel", statuBelgesi("Potansiyel Müşteri", musteri: "Görüşme", sira: 10, silme: 60)),
            ("randevu-takip", statuBelgesi("Randevu Takipte", musteri: "Randevunuz takip ediliyor", gerekenler: ["odeme"], sira: 20)),
            ("konsoloslukta", statuBelgesi("Konsoloslukta İşlemde", musteri: "Konsoloslukta", gerekenler: ["fis", "takipKodu"], sira: 60)),
        ]
        for (id, a) in st { try await owner.belgeYaz("statuses/\(id)", alanlar: a) }
        let statuler = st.map { Statu(kimlik: $0.0, alanlar: $0.1) }
        let appId = "odm\(ek)"
        let takipId = String(repeating: "d", count: 60) + ek
        try await owner.belgeYaz("applications/\(appId)", alanlar: [
            "trackingCode": .metin("2026-12\(ek)"), "year": .tam(2026), "month": .tam(12),
            "country": .metin("italya"), "countryName": .metin("İtalya"), "firstName": .metin("CAN"), "lastName": .metin("ER"),
            "passportLast3": .metin("111"), "statusId": .metin("potansiyel"), "statusName": .metin("Potansiyel Müşteri"),
            "checklist": .harita([:]), "finalAt": .bos, "deleteAfter": .bos, "legalHold": .mantik(false),
            "openedAt": .zaman(Date()), "createdAt": .zaman(Date()), "createdBy": .metin(uid),
            "updatedAt": .zaman(Date()), "updatedBy": .metin(uid),
        ])
        let o = try await e.kimlik.giris(kullaniciAdi: "odeme\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let calisan = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        XCTAssertTrue(calisan.yapabilir("app.payment"))
        func adim(_ no: Int, _ y: [FirestoreIstemci.Yazim]) async throws {
            do { try await ben.isle(y) } catch { XCTFail("adım \(no): \(error)"); throw error }
        }
        func basvuru() async throws -> Basvuru {
            let a = try await ben.belge("applications/\(appId)")
            return Basvuru(kimlik: appId, alanlar: try XCTUnwrap(a))
        }

        // 1) Fiyat
        var b = try await basvuru()
        try await adim(1, BasvuruIslemi.fiyat(b, tutar: 4500, paraBirimi: "TRY", aciklama: "Hizmet bedeli", calisan: calisan))
        let fiyatBelgesi = try await ben.belge("applications/\(appId)/private/fiyat")
        XCTAssertEqual(Fiyat(alanlar: fiyatBelgesi)?.tutar, 4500)

        // 2) Dekontlu ödeme (1,9 MB → 3 parça) + kasa geliri + otomatik "Randevu Takipte".
        let dekont = HazirDosya(ad: "dekont.jpg", mime: "image/jpeg", bayt: Data((0..<1_900_000).map { UInt8($0 % 251) }))
        let girdi = BasvuruIslemi.OdemeGirdisi(tarih: Tr.bugun(), tutar: 2250.5, paraBirimi: "TRY", yontem: "havale",
                                               onayKodu: "EFT-123", aciklama: "Kapora")
        let r = BasvuruIslemi.odeme(b, girdi, dekont: dekont, statuler: statuler, statuDegistirir: true, takipId: takipId,
                                    acikNotlar: [], saklamaGun: 60, calisan: calisan)
        XCTAssertEqual(r.statu?.id, "randevu-takip")
        try await adim(2, r.yazimlar)
        b = try await basvuru()
        XCTAssertEqual(b.odemeSayisi, 1)
        XCTAssertEqual(b.statuId, "randevu-takip")
        let kasa = try await owner.belge("kasa/\(r.odemeId)")
        XCTAssertEqual(kasa?["tutar"], .ondalik(2250.5))
        XCTAssertEqual(kasa?["tur"], .metin("gelir"))
        let odemeler = try await ben.sorgu(koleksiyon: "odemeler", sirala: ("at", .azalan), ust: "applications/\(appId)")
            .map { Odeme(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        let odeme = try XCTUnwrap(odemeler.first)
        XCTAssertEqual(odeme.tutar, 2250.5)
        let dosyaId = try XCTUnwrap(odeme.dosyaId)
        let bilgiBelgesi = try await ben.belge("applications/\(appId)/dosyalar/\(dosyaId)")
        let bilgi = DosyaBilgisi(kimlik: dosyaId, alanlar: try XCTUnwrap(bilgiBelgesi))
        XCTAssertEqual(bilgi.parca, 3)
        var parcalar: [[String: FSDeger]?] = []
        for yol in bilgi.parcaYollari(ust: "applications/\(appId)") { parcalar.append(try await ben.belge(yol)) }
        XCTAssertEqual(Dosya.birlestir(parcalar), dekont.bayt, "baytlar aynen geri gelmeli")

        // 3) Dekontsuz ödeme, sonra dekont (statü zaten ileride: geçiş yok).
        let r2 = BasvuruIslemi.odeme(b, BasvuruIslemi.OdemeGirdisi(tarih: Tr.bugun(), tutar: nil, paraBirimi: "EUR", yontem: "nakit",
                                                                   onayKodu: "", aciklama: ""),
                                     dekont: nil, statuler: statuler, statuDegistirir: true, takipId: takipId, acikNotlar: [],
                                     saklamaGun: 60, calisan: calisan)
        XCTAssertNil(r2.statu)
        try await adim(3, r2.yazimlar)
        b = try await basvuru()
        let ikinciBelge = try await ben.belge("applications/\(appId)/odemeler/\(r2.odemeId)")
        let ikinci = Odeme(kimlik: r2.odemeId, alanlar: try XCTUnwrap(ikinciBelge))
        XCTAssertEqual(ikinci.dekontDurumu, "Dekont girilmedi")
        try await adim(4, BasvuruIslemi.sonradanDekont(b, ikinci, dekont: HazirDosya(ad: "slip.pdf", mime: "application/pdf",
                                                                                     bayt: Data("%PDF-1.4 ornek".utf8)), calisan: calisan))
        let ikinciSonraBelge = try await ben.belge("applications/\(appId)/odemeler/\(r2.odemeId)")
        XCTAssertNotNil(ikinciSonraBelge?["dosyaId"]?.metinDegeri)

        // 4) Pasaport teslim fişi; takip kodu yokken konsolosluğa geçilmez, kod girilince geçilir.
        try await adim(5, BasvuruIslemi.belge(b, tur: "takip", dosya: HazirDosya(ad: "fis.jpg", mime: "image/jpeg",
                                                                                   bayt: Data(repeating: 7, count: 1000)), calisan: calisan))
        var s = BasvuruIslemi.fisSonrasi(b, statuler: statuler, takipId: takipId, acikNotlar: [], evrakTamam: true, saklamaGun: 60, calisan: calisan)
        XCTAssertTrue(s.engel.contains("konsolosluk takip kodu"))
        try await adim(6, BasvuruIslemi.konsolosluk(b, kod: " ist 2026/55 ", calisan: calisan))
        b = try await basvuru()
        XCTAssertEqual(b.konsTakipKodu, "IST2026/55")
        s = BasvuruIslemi.fisSonrasi(b, statuler: statuler, takipId: takipId, acikNotlar: [], evrakTamam: true, saklamaGun: 60, calisan: calisan)
        XCTAssertEqual(s.statu?.id, "konsoloslukta")
        try await adim(7, s.yazimlar)
        b = try await basvuru()
        XCTAssertEqual(b.statuId, "konsoloslukta")

        // 5) Diğer belge ekle ve sil.
        try await adim(8, BasvuruIslemi.belge(b, tur: "diger", dosya: HazirDosya(ad: "davet.pdf", mime: "application/pdf",
                                                                                   bayt: Data(repeating: 1, count: 2000)), calisan: calisan))
        let belgeler = try await ben.sorgu(koleksiyon: "dosyalar", kosullar: [.esit("tur", .metin("diger"))], ust: "applications/\(appId)")
            .map { DosyaBilgisi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        let diger = try XCTUnwrap(belgeler.first)
        try await adim(9, BasvuruIslemi.belgeSil(b, diger, calisan: calisan))
        // Silinmiş belgeyi çalışan okuyamaz (kural belgenin türüne bakıyor); yönetici gözüyle bakılır.
        let silinen = try await owner.belge("applications/\(appId)/dosyalar/\(diger.id)")
        XCTAssertNil(silinen)
    }

    func testRandevuKagidiVeBildirimPlani() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("randevu\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("randevu\(ek)"), "displayName": .metin("Sefa Karakaş"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi((Calisan.varsayilanIzinler["writer"]! + ["app.payment"]).map { .metin($0) }),
        ])])
        let appId = "rnd\(ek)"
        try await owner.belgeYaz("applications/\(appId)", alanlar: [
            "trackingCode": .metin("2026-10\(ek)"), "year": .tam(2026), "month": .tam(10),
            "country": .metin("abd"), "countryName": .metin("ABD"), "firstName": .metin("ECE"), "lastName": .metin("SU"),
            "passportLast3": .metin("222"), "statusId": .metin("randevu"), "statusName": .metin("Randevu Alındı"),
            "checklist": .harita([:]), "finalAt": .bos, "deleteAfter": .bos, "legalHold": .mantik(false),
            "openedAt": .zaman(Date()), "createdAt": .zaman(Date()), "createdBy": .metin(uid),
            "updatedAt": .zaman(Date()), "updatedBy": .metin(uid),
        ])
        // Daha önce planlanmış bir hatırlatma (randevu değişince iptal edilmeli).
        try await owner.belgeYaz("bildirimler/eski\(ek)", alanlar: [
            "appId": .metin(appId), "trackingCode": .metin("2026-10\(ek)"), "kind": .metin("evrak-hatirlatma"),
            "sendAt": .zaman(Date().addingTimeInterval(86_400)), "status": .metin("planned"),
            "channels": .harita(["wa": .mantik(true), "sms": .mantik(false), "email": .mantik(false)]),
            "name": .metin("ECE SU"), "countryName": .metin("ABD"), "appointmentDate": .metin("2026-12-01"),
            "docDeadline": .metin("2026-11-28"), "reminderDays": .tam(15), "phone": .metin("+905321112233"),
            // Panelin buildBildirim'i bu alanları hep yazar (kural waStatus'a bakıyor).
            "country": .metin("abd"), "email": .bos, "waStatus": .metin("pending"), "attempts": .tam(0), "sentAt": .bos,
            "force": .mantik(false), "assignedTo": .metin(uid), "assignedName": .metin("Sefa Karakaş"),
            "createdAt": .zaman(Date()), "createdBy": .metin(uid), "updatedAt": .zaman(Date()), "updatedBy": .metin(uid),
        ])
        let o = try await e.kimlik.giris(kullaniciAdi: "randevu\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let calisan = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        let _a = try await ben.belge("applications/\(appId)")
        let b = Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_a))

        let s = RandevuTests.secenekler
        let r = RandevuGirdisi(tarih: Tr.gunEkle(Tr.bugun(), 40), saat: "09:00", merkez: "Büyükelçilik", sehir: "",
                               yer: "ABD Büyükelçiliği (Ankara)", ulke: "abd")
        XCTAssertEqual(RandevuKurali.hatalar(r, s, bugun: Tr.bugun()), [])
        let k = RandevuKurali.kayit(r, s, konumlar: KonumAyari(belge: nil))
        try await ben.isle(BasvuruIslemi.randevuBelgesi(b, r, kayit: k, dosya: HazirDosya(ad: "randevu.pdf", mime: "application/pdf",
                                                                                         bayt: Data("%PDF-1.4".utf8)), calisan: calisan))
        let _s = try await ben.belge("applications/\(appId)")
        let sonra = Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_s))
        XCTAssertEqual(sonra.randevuSaati, "09:00")
        XCTAssertEqual(sonra.randevuYeri, "ABD Büyükelçiliği (Ankara)")
        XCTAssertEqual(sonra.randevuSehri, "Ankara")

        // Bildirim planı: var olanları oku, planlıyı iptal et, yenileri yaz (tek yazım).
        let mevcut = try await ben.sorgu(koleksiyon: "bildirimler", kosullar: [.esit("appId", .metin(appId))], sinir: 50)
            .map { BildirimKaydi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        XCTAssertEqual(mevcut.count, 1)
        let iletisim = MusteriIletisimi(form: ["phone": .metin("0532 111 22 33"), "email": .metin("ece@ornek.com")])
        let p = BildirimPlani.planla(sonra, randevu: r, kayit: k, iletisim: iletisim, ayar: BildirimAyari(belge: nil),
                                     mevcut: mevcut, calisan: calisan)
        XCTAssertEqual(p.yazilan, ["randevu-alindi", "evrak-hatirlatma"])
        try await ben.isle(p.yazimlar)
        let tumu = try await owner.sorgu(koleksiyon: "bildirimler", kosullar: [.esit("appId", .metin(appId))], sinir: 50)
        XCTAssertEqual(tumu.filter { $0.alanlar["status"] == .metin("planned") }.count, 2)
        XCTAssertEqual(tumu.first { $0.kimlik == "eski\(ek)" }?.alanlar["status"], .metin("cancelled"))
        let yeni = try XCTUnwrap(tumu.first { $0.alanlar["kind"] == .metin("randevu-alindi") })
        XCTAssertEqual(yeni.alanlar["randevuYeri"], .metin("ABD Büyükelçiliği (Ankara)"))
        XCTAssertEqual(yeni.alanlar["email"], .metin("ece@ornek.com"))

        // Bildirimler ekranı: "Şimdi gönder", "Gönderdim", "İptal et" (sitenin kurallarıyla).
        var g = BildirimGorevi(kimlik: yeni.kimlik, alanlar: yeni.alanlar)
        XCTAssertFalse(g.waGorevi, "randevu alındı: 30 dk beklemede görev açılmaz")
        try await ben.isle(BasvuruIslemi.bildirimSimdi(g, calisan: calisan))
        let _g1 = try await ben.belge("bildirimler/\(g.id)")
        g = BildirimGorevi(kimlik: g.id, alanlar: try XCTUnwrap(_g1))
        XCTAssertTrue(g.zorla)
        XCTAssertTrue(g.waGorevi)
        XCTAssertFalse(BildirimMetni.kur(g, ayar: BildirimAyari(belge: nil)).metin.isEmpty)
        try await ben.isle(BasvuruIslemi.waGonderildi(g, calisan: calisan))
        let _g2 = try await ben.belge("bildirimler/\(g.id)")
        g = BildirimGorevi(kimlik: g.id, alanlar: try XCTUnwrap(_g2))
        XCTAssertEqual(g.waDurum, "sent")
        XCTAssertNotNil(g.waZaman)
        let hat = try XCTUnwrap(tumu.first { $0.alanlar["kind"] == .metin("evrak-hatirlatma") && $0.alanlar["status"] == .metin("planned") })
        let h = BildirimGorevi(kimlik: hat.kimlik, alanlar: hat.alanlar)
        try await ben.isle(BasvuruIslemi.bildirimIptal(h, calisan: calisan))
        let _h = try await ben.belge("bildirimler/\(h.id)")
        let iptal = BildirimGorevi(kimlik: h.id, alanlar: try XCTUnwrap(_h))
        XCTAssertEqual(iptal.durum, "cancelled")
        XCTAssertEqual(iptal.iptalSebebi, "Sefa Karakaş iptal etti")
        XCTAssertFalse(iptal.waGorevi, "iptal edilenin WhatsApp görevi de düşer")
    }

    func testYeniBasvuruVeDuzenleme() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("yeni\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("yeni\(ek)"), "displayName": .metin("Ezgi Danışman"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi(Calisan.varsayilanIzinler["writer"]!.map { .metin($0) }),
        ])])
        let st: [(String, [String: FSDeger])] = [
            ("potansiyel", statuBelgesi("Potansiyel Müşteri", musteri: "Görüşme aşamasında", sira: 10, silme: 60)),
            ("randevu-takip", statuBelgesi("Randevu Takipte", musteri: "Randevunuz takip ediliyor", gerekenler: ["odeme"], sira: 20)),
        ]
        for (id, a) in st { try await owner.belgeYaz("statuses/\(id)", alanlar: a) }
        let statuler = st.map { Statu(kimlik: $0.0, alanlar: $0.1) }
        let o = try await e.kimlik.giris(kullaniciAdi: "yeni\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let calisan = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        let bugun = Tr.bugun()

        // 1) Pasaportlu yeni başvuru; aynı kod daha önce alınmışsa kural reddeder (çakışma), yeni kodla geçer.
        let pasaport = "U\(ek)5678"
        let veri: [String: FSDeger] = ["firstName": .metin("ALİ"), "lastName": .metin("VELİ"), "passportNo": .metin(pasaport),
                                       "phone": .metin("+905321112233")]
        let kod = "2026-11\(ek)"
        try await owner.belgeYaz("trackingCodes/\(kod)", alanlar: ["appId": .metin("baskasi"), "createdAt": .zaman(Date())])
        let carpisan = try XCTUnwrap(BasvuruIslemi.olustur(veri: veri, ulkeId: "almanya", ulke: nil, randevu: "", acilis: bugun, bugun: bugun,
                                                           statuler: statuler, calisan: calisan, kod: kod))
        do { try await ben.isle(carpisan.yazimlar); XCTFail("aynı kod iki kez alınmamalı") } catch {
            // "Yoksa oluştur" ön koşulu: kod alınmışsa 409 (kural da reddederdi).
            XCTAssertTrue(BasvuruIslemi.kodCakismasi(error))
        }
        let yeni = try XCTUnwrap(BasvuruIslemi.olustur(veri: veri, ulkeId: "almanya", ulke: nil, randevu: Tr.gunEkle(bugun, 30),
                                                       acilis: bugun, bugun: bugun, statuler: statuler, calisan: calisan))
        try await ben.isle(yeni.yazimlar)
        let _a = try await ben.belge("applications/\(yeni.kimlik)")
        let b = Basvuru(kimlik: yeni.kimlik, alanlar: try XCTUnwrap(_a))
        XCTAssertEqual(b.statuId, "potansiyel")
        XCTAssertEqual(b.pasaportSon3, "678")
        XCTAssertNotNil(b.silinecek, "potansiyel: 60 gün sonra silinir")
        XCTAssertNotNil(b.randevu)
        // Müşteri takip sorgusuyla aynı anahtar: kod + pasaport.
        let takip = try await owner.belge("takip/\(Takip.kimlik(kod: yeni.takipKodu, pasaport: pasaport))")
        XCTAssertEqual(takip?["statusName"], .metin("Görüşme aşamasında"))
        let dizin = try await ben.belge("lookup/\(BasvuruListesi.pasaportOzeti(pasaport))")
        XCTAssertEqual(dizin?["apps"], .dizi([.metin(yeni.kimlik)]))

        // 2) Pasaportsuz başvuru (yalnız ad, soyad, telefon).
        let pasaportsuz = try XCTUnwrap(BasvuruIslemi.olustur(veri: ["firstName": .metin("AYŞE"), "lastName": .metin("KAYA"),
                                                                     "phone": .metin("+905320000000")],
                                                              ulkeId: "italya", ulke: nil, randevu: "", acilis: Tr.gunEkle(bugun, -2),
                                                              bugun: bugun, statuler: statuler, calisan: calisan))
        try await ben.isle(pasaportsuz.yazimlar)

        // 3) Düzenle: pasaport değişti → yeni takip anahtarı, eski takip belgesi silinir, dizin güncellenir.
        let eskiAnahtarBelgesi = try await ben.belge("applications/\(yeni.kimlik)/private/keys")
        let eskiAnahtar = (eskiAnahtarBelgesi?["takipId"]?.metinDegeri ?? "", eskiAnahtarBelgesi?["passportHash"]?.metinDegeri ?? "")
        var yeniVeri = veri
        let yeniPasaport = "Y\(ek)9999"
        yeniVeri["passportNo"] = .metin(yeniPasaport)
        yeniVeri["lastName"] = .metin("VELİOĞLU")
        let alanlar = [FormAlani(key: "lastName", label: "Soyisim", group: "kisisel"), FormAlani(key: "passportNo", label: "Pasaport no", group: "pasaport")]
        try await ben.isle(BasvuruIslemi.duzenle(b, eskiForm: veri, yeniVeri: yeniVeri, alanlar: alanlar, ulkeId: "almanya", ulke: nil,
                                                 randevu: Tr.gunEkle(bugun, 30), acilis: "", eskiAnahtar: eskiAnahtar, statuler: statuler,
                                                 acikNotlar: [], calisan: calisan))
        let eskiTakip = try await owner.belge("takip/\(eskiAnahtar.0)")
        XCTAssertNil(eskiTakip, "eski takip belgesi silindi")
        let yeniTakip = try await owner.belge("takip/\(Takip.kimlik(kod: yeni.takipKodu, pasaport: yeniPasaport))")
        XCTAssertNotNil(yeniTakip)
        let eskiDizin = try await ben.belge("lookup/\(eskiAnahtar.1)")
        XCTAssertEqual(eskiDizin?["apps"], .dizi([]))
        let _d = try await ben.belge("applications/\(yeni.kimlik)")
        let duzenlenmis = Basvuru(kimlik: yeni.kimlik, alanlar: try XCTUnwrap(_d))
        XCTAssertEqual(duzenlenmis.soyad, "VELİOĞLU")
        XCTAssertEqual(duzenlenmis.pasaportSon3, "999")
        XCTAssertEqual(duzenlenmis.randevu, b.randevu, "randevu günü aynı: saat korunur")

        // 4) Pasaport kontrolü: önce otomatik, sonra danışman onayı (üzerine yazar; onaylayan bilgisi eklenir).
        try await ben.isle(BasvuruIslemi.pasaportKontrolu(duzenlenmis, durum: .otomatik, bakilanlar: ["İsim", "Soyisim"],
                                                          uyusmayanlar: [], calisan: calisan))
        let _p1 = try await ben.belge("applications/\(yeni.kimlik)/private/passport")
        var pk = PasaportKontrolu(alanlar: try XCTUnwrap(_p1))
        XCTAssertEqual(pk.durum, .otomatik)
        XCTAssertEqual(pk.onaylayan, "")
        XCTAssertNotNil(pk.zaman)
        try await ben.isle(BasvuruIslemi.pasaportKontrolu(duzenlenmis, durum: .danisman, bakilanlar: ["İsim", "Soyisim", "Pasaport no"],
                                                          uyusmayanlar: ["Soyisim"], calisan: calisan))
        let _p2 = try await ben.belge("applications/\(yeni.kimlik)/private/passport")
        pk = PasaportKontrolu(alanlar: try XCTUnwrap(_p2))
        XCTAssertEqual(pk.durumAdi, "Danışman onayladı")
        XCTAssertEqual(pk.uyusmayanlar, ["Soyisim"])
        XCTAssertEqual(pk.onaylayan, "Ezgi Danışman")
        XCTAssertNotNil(pk.onayZamani)
    }

    /// Kasa: harcama (fişli), müşteri harcaması (geçmişe de), döviz çevrimi, rutin ödeme ve vadesi, iptal.
    func testKasa() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("kasa\(ek)", "gizli-sifre-1")
        let yon = try await e.hesapAc("yonetici\(ek)", "gizli-sifre-2")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("kasa\(ek)"), "displayName": .metin("Kasa Sorumlusu"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("employees/\(yon)", alanlar: [
            "username": .metin("yonetici\(ek)"), "displayName": .metin("Sefa"), "role": .metin("admin"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi((Calisan.varsayilanIzinler["writer"]! + ["kasa.view", "kasa.gider", "kasa.rutin"]).map { .metin($0) }),
        ])])
        let appId = "ksa\(ek)"
        try await owner.belgeYaz("applications/\(appId)", alanlar: [
            "trackingCode": .metin("2026-13\(ek)"), "firstName": .metin("CAN"), "lastName": .metin("ER"), "statusId": .metin("potansiyel"),
        ])
        let o = try await e.kimlik.giris(kullaniciAdi: "kasa\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        let bugun = Tr.bugun()

        // 1) Genel harcama, fişli (fiş 2 parça).
        var g = KasaGirdisi()
        g.kategori = "Kırtasiye"; g.tutar = 120.5; g.tarih = bugun; g.aciklama = "Kalem"
        let fis = HazirDosya(ad: "fis.jpg", mime: "image/jpeg", bayt: Data(repeating: 7, count: Dosya.parcaBoyutu + 10))
        let k1 = KasaIslemi.kaydet(g, fis: fis, calisan: c)
        try await ben.isle(k1.yazimlar)
        let _h1 = try await ben.belge("kasa/\(k1.id)")
        let h1 = KasaHareketi(kimlik: k1.id, alanlar: try XCTUnwrap(_h1))
        XCTAssertEqual(h1.tutar, 120.5)
        XCTAssertFalse(h1.fisId.isEmpty)

        // 2) Müşteri harcaması başvuru ekranından: geçmişe de yazılır.
        let _b = try await ben.belge("applications/\(appId)")
        let b = Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_b))
        var mg = KasaGirdisi()
        mg.kapsam = "musteri"; mg.kategori = "Fotokopi"; mg.tutar = 25; mg.tarih = bugun
        mg.appId = appId; mg.takipKodu = b.takipKodu; mg.musteriAd = b.adSoyad
        try await ben.isle(KasaIslemi.kaydet(mg, fis: nil, basvuru: b, calisan: c).yazimlar)
        let musteri = try await ben.sorgu(koleksiyon: "kasa", kosullar: [.esit("appId", .metin(appId)), .esit("kapsam", .metin("musteri"))], sinir: 10)
        XCTAssertEqual(musteri.count, 1)

        // 3) Döviz çevrimi.
        var cv = KasaGirdisi()
        cv.tur = "cevrim"; cv.kategori = "Döviz çevrimi"; cv.tutar = 50; cv.paraBirimi = "EUR"; cv.hedefTutar = 2425; cv.hedefParaBirimi = "TRY"
        cv.buro = "Kızılay  Döviz"; cv.tarih = bugun
        try await ben.isle(KasaIslemi.kaydet(cv, fis: nil, calisan: c).yazimlar)

        // 4) Rutin ödeme ve bugünkü vadesi "ödendi"; aynı vade ikinci kez yazılamaz.
        var r = RutinOdeme()
        r.ad = "Kira"; r.kategori = "Kira"; r.tutar = 20000; r.siklik = "aylik"; r.gun = 1; r.baslangic = bugun
        let rk = KasaIslemi.rutinKaydet(r, calisan: c)
        try await ben.isle(rk.yazimlar)
        var v = KasaGirdisi()
        v.kategori = "Kira"; v.tutar = 20000; v.yontem = "havale"; v.tarih = bugun; v.aciklama = "Kira · vade"
        v.rutinId = rk.id; v.rutinVade = bugun
        let vid = RutinOdeme.kasaId(rk.id, bugun)
        try await ben.isle(KasaIslemi.kaydet(v, fis: nil, kimlik: vid, calisan: c).yazimlar)
        do { try await ben.isle(KasaIslemi.kaydet(v, fis: nil, kimlik: vid, calisan: c).yazimlar); XCTFail("vade iki kez ödenmemeli") } catch {}
        var durdur = r; durdur.id = rk.id; durdur.aktif = false
        try await ben.isle(KasaIslemi.rutinKaydet(durdur, kaydaYaz: false, calisan: c).yazimlar)

        // 5) İptal: yalnız yönetici.
        do { try await ben.isle(KasaIslemi.iptal(h1, neden: "yanlış", calisan: c)); XCTFail("yönetici değil") } catch {}
        let yo = try await e.kimlik.giris(kullaniciAdi: "yonetici\(ek)", sifre: "gizli-sifre-2")
        let yIst = e.istemci(yo.belirtec)
        let _y = try await yIst.belge("employees/\(yon)")
        let yc = Calisan(uid: yon, belge: try XCTUnwrap(_y), izinBelgesi: nil)
        try await yIst.isle(KasaIslemi.iptal(h1, neden: "İki kez girildi", calisan: yc))
        let _h1b = try await ben.belge("kasa/\(k1.id)")
        let iptalli = KasaHareketi(kimlik: k1.id, alanlar: try XCTUnwrap(_h1b))
        XCTAssertTrue(iptalli.iptal)
        XCTAssertEqual(iptalli.iptalAd, "Sefa")

        // Rapor sorgusu: bugünün hareketleri.
        let l = try await ben.sorgu(koleksiyon: "kasa", kosullar: [.enAz("tarih", .metin(bugun)), .enCok("tarih", .metin(bugun))],
                                    sirala: ("tarih", .azalan), sinir: 100)
        let oz = KasaOzeti(l.map { KasaHareketi(kimlik: $0.kimlik, alanlar: $0.alanlar) })
        XCTAssertEqual(oz.sayi.iptal, 1)
        XCTAssertEqual(oz.kasa["EUR"], -50)
    }

    /// E-posta: başvurudan tek müşteriye, serbest adrese, sıradakini iptal; izinsiz yazım reddedilir.
    func testMusteriMesaji() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("msj\(ek)", "gizli-sifre-1")
        let lead = try await e.hesapAc("lead\(ek)", "gizli-sifre-2")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("msj\(ek)"), "displayName": .metin("Aleyna Yıldız"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("employees/\(lead)", alanlar: [
            "username": .metin("lead\(ek)"), "displayName": .metin("Okur"), "role": .metin("reader"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi((Calisan.varsayilanIzinler["writer"]! + ["eposta.send", "app.status", "lead.manage"]).map { .metin($0) }),
            "reader": .dizi(Calisan.varsayilanIzinler["reader"]!.map { .metin($0) }),
        ])])
        let appId = "msj\(ek)"
        try await owner.belgeYaz("applications/\(appId)", alanlar: [
            "trackingCode": .metin("2026-15\(ek)"), "firstName": .metin("AYŞE"), "lastName": .metin("KAYA"),
            "countryName": .metin("İtalya"), "statusId": .metin("potansiyel"),
        ])
        let o = try await e.kimlik.giris(kullaniciAdi: "msj\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        let _b = try await ben.belge("applications/\(appId)")
        let b = Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_b))

        // Hazır mesaj doldurma: WhatsApp yer tutucuları da dolar.
        let d = MusteriMesaji.degerler(b, statu: "", benimAdim: c.gorunenAd)
        let sablonlar = WaSablonu.liste(belge: nil)
        XCTAssertEqual(sablonlar.map(\.id), ["ulasilamadi", "randevu-hatirlatma", "form-linki", "armut-bilgi", "armut-evrak"])
        let metin = MusteriBildirimi.doldur(try XCTUnwrap(sablonlar.first { $0.id == "form-linki" }).metin, d)
        XCTAssertTrue(metin.contains("https://vizemia.com/form?kod=2026-15\(ek)"))
        XCTAssertEqual(EpostaIslemi.bosYerTutucular(metin), [])
        XCTAssertEqual(MusteriBildirimi.doldur("{benim_ilk_adim}", d), "Aleyna")

        // WhatsApp teyidi (mesajKaydi) ve elle SMS: sitenin kurallarıyla.
        let t = WaTeyidi(appId: appId, telefon: "0532 123 45 67", ad: "Ayşe Kaya", metin: metin, sablon: "form-linki")
        try await ben.isle(try XCTUnwrap(MusteriMesaji.waTeyidi(t, gonderildi: true, calisan: c)))
        try await ben.isle(try XCTUnwrap(MusteriMesaji.waTeyidi(t, gonderildi: false, calisan: c)))
        let acik = SmsAyari(belge: ["enabled": .mantik(true)])
        XCTAssertNil(MusteriMesaji.sms(b, telefon: "0532 123 45 67", metin: "x", ayar: SmsAyari(belge: nil), calisan: c))
        try await ben.isle(try XCTUnwrap(MusteriMesaji.sms(b, telefon: "05321234567", metin: "Sayın Ayşe, evraklarınız geldi.", ayar: acik, calisan: c)))

        let w = try await ben.sorgu(koleksiyon: "mesajKaydi", kosullar: [.esit("appId", .metin(appId))], sinir: 50)
        let s = try await ben.sorgu(koleksiyon: "sms", kosullar: [.esit("appId", .metin(appId))], sinir: 50)
        let gecmis = MesajSatiri.birlestir(w.map { MesajSatiri(whatsapp: $0.kimlik, alanlar: $0.alanlar) }
                                            + s.map { MesajSatiri(sms: $0.kimlik, alanlar: $0.alanlar) })
        XCTAssertEqual(gecmis.count, 3)
        XCTAssertEqual(Set(gecmis.map(\.durum)), ["Gönderildi", "Gönderilmedi", "Sırada"])
        let smsMetni = try XCTUnwrap(gecmis.first { $0.kanal == .sms }).metin
        XCTAssertEqual(smsMetni, "Sayin Ayse, evraklariniz geldi.")
        XCTAssertEqual(s.first?.alanlar["tur"]?.metinDegeri, "elle")

        // Hazır mesajları düzenleme (lead.manage): silinen sonradan-eklenen geri gelmez.
        var yeni = sablonlar.filter { $0.id != "armut-evrak" }
        yeni.append(WaSablonu(id: WaSablonu.geciciKimlik(), baslik: "Teşekkür", metin: "Teşekkürler {ad}"))
        try await ben.isle(WaSablonu.kaydet(yeni, calisan: c))
        let okunan = WaSablonu.liste(belge: try await ben.belge("settings/wa"))
        XCTAssertEqual(okunan.count, 5)
        XCTAssertFalse(okunan.contains { $0.id == "armut-evrak" })
        XCTAssertEqual(okunan.last?.baslik, "Teşekkür")
        XCTAssertEqual(okunan.last?.id, "tesekkur")

        // Talepten açılan WhatsApp (lead.manage): kayıt talebe bağlı.
        try await owner.belgeYaz("callback/cb\(ek)", alanlar: ["name": .metin("Mehmet Can"), "phone": .metin("05321234567"),
                                                             "times": .dizi([.metin("10:00"), .metin("10:30")]), "status": .metin("new")])
        let _tl = try await ben.belge("callback/cb\(ek)")
        let talep = Talep(tur: .geriArama, kimlik: "cb\(ek)", alanlar: try XCTUnwrap(_tl))
        let tm = WaSablonu.doldur(WaSablonu.varsayilanlar[1].metin, WaSablonu.degerler(talep: talep, benimAdim: c.gorunenAd))
        XCTAssertTrue(tm.hasPrefix("Merhaba Mehmet, "))
        XCTAssertTrue(tm.contains("10:00–11:00 aralığında"))
        let tt = WaTeyidi(talepId: talep.kimlik, talepKol: "callback", telefon: talep.telefon, ad: talep.ad, metin: tm, sablon: "randevu-hatirlatma")
        try await ben.isle(try XCTUnwrap(MusteriMesaji.waTeyidi(tt, gonderildi: true, calisan: c)))

        // Yetkisi olmayan (reader) WhatsApp kaydı yazamaz.
        let o2 = try await e.kimlik.giris(kullaniciAdi: "lead\(ek)", sifre: "gizli-sifre-2")
        let okur = e.istemci(o2.belirtec)
        let _c2 = try await okur.belge("employees/\(lead)")
        let c2 = Calisan(uid: lead, belge: try XCTUnwrap(_c2), izinBelgesi: try await okur.belge("settings/permissions"))
        do {
            try await okur.isle(try XCTUnwrap(MusteriMesaji.waTeyidi(t, gonderildi: true, calisan: c2)))
            XCTFail("okur yazabildi")
        } catch let h as FirestoreHatasi { XCTAssertEqual(h, .izinYok) }
    }

    func testMusteriFormu() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("frm\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("frm\(ek)"), "displayName": .metin("Aleyna Yıldız"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi((Calisan.varsayilanIzinler["writer"]! + ["app.edit", "app.status", "app.sensitive"]).map { .metin($0) }),
        ])])
        let appId = "frm\(ek)"
        let takipId = String(repeating: "d", count: 60) + ek
        try await owner.belgeYaz("applications/\(appId)", alanlar: [
            "trackingCode": .metin("2026-11\(ek)"), "year": .tam(2026), "month": .tam(11),
            "firstName": .metin("AYSE"), "lastName": .metin("KAYA"), "passportLast3": .metin("567"),
            "country": .metin("italya"), "countryName": .metin("İtalya"),
            "statusId": .metin("potansiyel"), "statusName": .metin("Potansiyel"), "checklist": .harita([:]),
            "openedAt": .zaman(Date()), "createdAt": .zaman(Date()), "createdBy": .metin(uid),
        ])
        try await owner.belgeYaz("applications/\(appId)/private/data", alanlar: ["form": .harita([
            "firstName": .metin("AYSE"), "passportNo": .metin("U1234567"), "phone": .metin("0532 123 45 67"),
            "email": .metin("ayse@ornek.com"), "maritalStatus": .metin("bekar"),
        ])])
        let o = try await e.kimlik.giris(kullaniciAdi: "frm\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        let _b = try await ben.belge("applications/\(appId)")
        let b = Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_b))
        let _f = try await ben.belge("applications/\(appId)/private/data")
        let form = try XCTUnwrap(_f?["form"]?.haritaDegeri)

        let alanlar = [
            FormAlani(key: "firstName", label: "İsim", group: "kisisel", required: true),
            FormAlani(key: "nationalId", label: "T.C. kimlik no", group: "kisisel"),
            FormAlani(key: "birthPlace", label: "Doğum yeri", group: "kisisel", type: "province"),
            FormAlani(key: "maritalStatus", label: "Medeni hâl", group: "kisisel",
                      options: [FormSecenegi(value: "", label: "Seçiniz"), FormSecenegi(value: "bekar", label: "Bekâr")]),
            FormAlani(key: "district", label: "İlçe", group: "adres", type: "district"),
        ]
        let sorular = MusteriFormu.sorular(alanlar, iller: ["Adana", "Ankara"])
        XCTAssertEqual(sorular.compactMap { $0.haritaDegeri?["key"]?.metinDegeri }, ["firstName", "birthPlace", "maritalStatus", "district"])
        XCTAssertEqual(sorular[2].haritaDegeri?["options"]?.diziDegeri?.count, 1)
        XCTAssertEqual(sorular[3].haritaDegeri?["help"]?.metinDegeri, "İlçe adını yazın.")

        // İlk hazırlık: SMS 'form' türüyle sıraya girer, geçmiş + işlem kaydı.
        let h = MusteriFormu.hazirla(b, form: form, takipId: takipId, onceki: nil, sorular: sorular, sms: true,
                                     smsAyari: SmsAyari(belge: ["enabled": .mantik(true)]), calisan: c)
        XCTAssertFalse(h.smsAlinamadi)
        try await ben.isle(h.yazimlar)
        let _k = try await ben.belge("formlar/\(takipId)")
        var kayit = MusteriFormuKaydi(alanlar: try XCTUnwrap(_k))
        XCTAssertEqual(kayit.durum, "gonderildi")
        XCTAssertEqual(kayit.onDolgu, ["firstName": "AYSE", "maritalStatus": "bekar"])
        XCTAssertEqual(kayit.doluluk().dolu, 2)
        XCTAssertEqual(kayit.doluluk().toplam, 4)
        let sms = try await ben.sorgu(koleksiyon: "sms", kosullar: [.esit("appId", .metin(appId))], sinir: 5)
        XCTAssertEqual(sms.first?.alanlar["tur"]?.metinDegeri, "form")
        XCTAssertTrue(sms.first?.alanlar["text"]?.metinDegeri?.contains("form?kod=2026-11\(ek)") == true)

        // Müşteri doldurdu ve soru sordu (sahibin eliyle; müşteri yazımı sitenin işi).
        try await owner.belgeYaz("formlar/\(takipId)", alanlar: (try XCTUnwrap(_k)).merging([
            "answers": .harita(["birthPlace": .metin("Ankara"), "district": .metin("Çankaya"), "uydurma": .metin("x"),
                                "kvkk_riza": .metin("2026-11-18T08:00:00.000Z")]),
            "questionsAsked": .dizi([.harita(["field": .metin("district"), "text": .metin("Mahalle de mi?"), "at": .metin("2026-11-18T08:01:00.000Z")])]),
            "status": .metin("tamamlandi"),
        ]) { $1 })
        let _k2 = try await ben.belge("formlar/\(takipId)")
        kayit = MusteriFormuKaydi(alanlar: try XCTUnwrap(_k2))
        XCTAssertEqual(kayit.doluluk().dolu, 4)
        XCTAssertNotNil(kayit.rizaZamani)
        XCTAssertEqual(kayit.acikSorular, 1)

        // Cevap; sonra yenileme cevaplara ve soruya dokunmaz, durumu geri almaz.
        try await ben.isle(try XCTUnwrap(MusteriFormu.cevapla(takipId: takipId, kayit: kayit, sira: 0, metin: "Yalnız ilçe yeter.", calisan: c)))
        let h2 = MusteriFormu.hazirla(b, form: form, takipId: takipId, onceki: kayit, sorular: sorular, sms: false,
                                      smsAyari: SmsAyari(belge: nil), calisan: c)
        try await ben.isle(h2.yazimlar)
        let _k3 = try await ben.belge("formlar/\(takipId)")
        kayit = MusteriFormuKaydi(alanlar: try XCTUnwrap(_k3))
        XCTAssertEqual(kayit.durum, "tamamlandi")
        XCTAssertEqual(kayit.musteriSorulari.first?.cevap, "Yalnız ilçe yeter.")
        XCTAssertEqual(kayit.cevaplar["birthPlace"], "Ankara")

        // Aktarma: yalnız bilinen ve farklı alanlar.
        let l = kayit.aktarilacaklar(alanlar: alanlar, form: form)
        XCTAssertEqual(l.map(\.key), ["birthPlace", "district"])
        try await ben.isle(MusteriFormu.aktar(b, l, calisan: c))
        let _f2 = try await ben.belge("applications/\(appId)/private/data")
        let form2 = try XCTUnwrap(_f2?["form"]?.haritaDegeri)
        XCTAssertEqual(form2["district"]?.metinDegeri, "Çankaya")
        XCTAssertEqual(form2["passportNo"]?.metinDegeri, "U1234567")
        XCTAssertTrue(kayit.aktarilacaklar(alanlar: alanlar, form: form2).isEmpty)

        // Kapat, sonra yenileyince yeniden "gönderildi".
        try await ben.isle(MusteriFormu.kapat(takipId: takipId, calisan: c))
        let _k4 = try await ben.belge("formlar/\(takipId)")
        kayit = MusteriFormuKaydi(alanlar: try XCTUnwrap(_k4))
        XCTAssertEqual(kayit.durum, "kapandi")
        try await ben.isle(MusteriFormu.hazirla(b, form: form2, takipId: takipId, onceki: kayit, sorular: sorular, sms: false,
                                                smsAyari: SmsAyari(belge: nil), calisan: c).yazimlar)
        let _k5 = try await ben.belge("formlar/\(takipId)")
        XCTAssertEqual(MusteriFormuKaydi(alanlar: try XCTUnwrap(_k5)).durum, "gonderildi")

        // Gönderim kuralı: "süreç başladıktan 7 gün sonra" → bildirim planlanır.
        let kural = FormGonderimKurali(mod: "baslangic-sonra", gun: 7)
        let simdi = Date()
        var b2 = b
        b2.acilis = simdi
        let r = MusteriFormu.kuralKaydet(b2, kural: kural, iletisim: MusteriIletisimi(form: form2), ayar: BildirimAyari(belge: nil),
                                         mevcut: [], calisan: c, simdi: simdi)
        XCTAssertTrue(r.durum.hasPrefix("Süreç başladıktan 7 gün sonra — "))
        try await ben.isle(r.yazimlar)
        let bl = try await ben.sorgu(koleksiyon: "bildirimler", kosullar: [.esit("appId", .metin(appId))], sinir: 5)
        XCTAssertEqual(bl.first?.alanlar["kind"]?.metinDegeri, "form-linki")
        let _b3 = try await ben.belge("applications/\(appId)")
        XCTAssertEqual(Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_b3)).formGonderim, kural)
        XCTAssertEqual(MusteriFormu.kuralKaydet(b2, kural: .varsayilan, iletisim: MusteriIletisimi(form: form2), ayar: BildirimAyari(belge: nil),
                                                mevcut: [], calisan: c).durum, "Elle — danışman gönderir — elle gönderilecek.")
    }

    func testGrup() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("grp\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("grp\(ek)"), "displayName": .metin("Ezgi Danışman"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi(Calisan.varsayilanIzinler["writer"]!.map { .metin($0) }),
        ])])
        let st: [(String, [String: FSDeger])] = [("potansiyel", statuBelgesi("Potansiyel Müşteri", musteri: "Görüşme", sira: 10, silme: 60))]
        for (id, a) in st { try await owner.belgeYaz("statuses/\(id)", alanlar: a) }
        let statuler = st.map { Statu(kimlik: $0.0, alanlar: $0.1) }
        let o = try await e.kimlik.giris(kullaniciAdi: "grp\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        let bugun = Tr.bugun()
        func ac(_ ad: String, _ soyad: String, grup: GrupTohumu? = nil) async throws -> Basvuru {
            let veri: [String: FSDeger] = ["firstName": .metin(ad), "lastName": .metin(soyad), "entryDate": .metin(Tr.gunEkle(bugun, 40)),
                                           "phone": .metin("+905321112233")]
            let y = try XCTUnwrap(BasvuruIslemi.olustur(veri: veri, ulkeId: "italya", ulke: nil, randevu: "", acilis: bugun, bugun: bugun,
                                                        statuler: statuler, calisan: c, grup: grup))
            try await ben.isle(y.yazimlar)
            let _a = try await ben.belge("applications/\(y.kimlik)")
            return Basvuru(kimlik: y.kimlik, alanlar: try XCTUnwrap(_a))
        }
        func oku(_ b: Basvuru) async throws -> Basvuru {
            let _a = try await ben.belge("applications/\(b.kimlik)")
            return Basvuru(kimlik: b.kimlik, alanlar: try XCTUnwrap(_a))
        }

        // "Gruba kişi ekle": ilk kişi grupsuzdu → yeni başvuruyla aynı yazımda gruba alınır.
        let ilk = try await ac("AYŞE", "ÖZTÜRK")
        let _f = try await ben.belge("applications/\(ilk.kimlik)/private/data")
        let tohum = GrupTohumu(ilk, form: try XCTUnwrap(_f?["form"]?.haritaDegeri), randevu: "")
        XCTAssertEqual(tohum.ad, "Öztürk grubu")
        XCTAssertEqual(tohum.degerler.keys.sorted(), ["entryDate"])
        XCTAssertEqual(tohum.iletisim["phone"], "+905321112233")
        let ikinci = try await ac("MEHMET", "ÖZTÜRK", grup: tohum)
        let ilk2 = try await oku(ilk)
        XCTAssertEqual(ilk2.grupId, ikinci.grupId)
        XCTAssertTrue(GrupIsi.gecerliId(ikinci.grupId))

        // Mevcut başvuruyu takip koduyla gruba ekle; başka gruptakini taşımadan önce sor.
        let ucuncu = try await ac("CAN", "KAYA")
        guard case let .tamam(y, ad) = GrupIsi.bagla(ilk2, hedef: ucuncu, calisan: c) else { return XCTFail() }
        XCTAssertEqual(ad, "Öztürk grubu")
        try await ben.isle(y)
        let dorduncu = try await ac("ALİ", "VELİ")
        let besinci = try await ac("ZEYNEP", "VELİ")
        guard case let .tamam(y2, _) = GrupIsi.bagla(dorduncu, hedef: besinci, calisan: c) else { return XCTFail() }
        try await ben.isle(y2)
        let besinci2 = try await oku(besinci)
        XCTAssertEqual(GrupIsi.bagla(ilk2, hedef: besinci2, calisan: c), .tasinsinMi(grupAdi: "Veli grubu"))
        XCTAssertEqual(GrupIsi.bagla(ilk2, hedef: ilk2, calisan: c), .hata("Bu zaten açık olan başvuru."))

        // Adı değiştir (bütün üyelerde), sonra çıkar: iki kişilik grupta kalan da çıkar.
        let uyeler = try await ben.sorgu(koleksiyon: "applications", kosullar: [.esit("grupId", .metin(ilk2.grupId))], sinir: 50)
            .map { Basvuru(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        XCTAssertEqual(uyeler.count, 3)
        try await ben.isle(try XCTUnwrap(GrupIsi.adDegistir(ilk2, uyeler: uyeler, ad: "  Öztürk   ailesi ", calisan: c)))
        let ucuncu2 = try await oku(ucuncu)
        XCTAssertEqual(ucuncu2.grupAdi, "Öztürk ailesi")
        let dorduncu2 = try await oku(dorduncu)
        try await ben.isle(GrupIsi.cikar(dorduncu2, digerleri: [besinci2], calisan: c))
        let besinci3 = try await oku(besinci), dorduncu3 = try await oku(dorduncu)
        XCTAssertEqual(besinci3.grupId, "")
        XCTAssertEqual(dorduncu3.grupAdi, "")
    }

    func testSaklamaVeSilme() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("adm\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("adm\(ek)"), "displayName": .metin("Sefa Yönetici"), "role": .metin("admin"), "active": .mantik(true)])
        let appId = "sil\(ek)"
        let yol = "applications/\(appId)"
        let takipId = String(repeating: "e", count: 60) + ek
        let ozet = String(repeating: "f", count: 60) + ek
        try await owner.belgeYaz(yol, alanlar: [
            "trackingCode": .metin("2026-11\(ek)"), "year": .tam(2026), "month": .tam(11),
            "firstName": .metin("AYŞE NUR"), "lastName": .metin("KAYA"), "passportLast3": .metin("567"),
            "country": .metin("italya"), "countryName": .metin("İtalya"),
            "statusId": .metin("potansiyel"), "statusName": .metin("Potansiyel"), "checklist": .harita([:]),
            "deleteAfter": .zaman(Date().addingTimeInterval(86_400 * 30)), "legalHold": .mantik(false),
            "openedAt": .zaman(Date()), "createdAt": .zaman(Date()), "createdBy": .metin(uid),
        ])
        try await owner.belgeYaz("\(yol)/private/data", alanlar: ["form": .harita([
            "phone": .metin("0532 123 45 67"), "email": .metin("Ayse@Ornek.com"), "passportNo": .metin("U1234567"), "kampanyaIzni": .mantik(true)])])
        try await owner.belgeYaz("\(yol)/private/keys", alanlar: ["takipId": .metin(takipId), "passportHash": .metin(ozet)])
        try await owner.belgeYaz("\(yol)/private/fiyat", alanlar: ["tutar": .tam(4500), "paraBirimi": .metin("TRY"), "aciklama": .metin("Hizmet")])
        try await owner.belgeYaz("\(yol)/log/l1", alanlar: ["type": .metin("created"), "text": .metin("Başvuru oluşturuldu"), "byName": .metin("Ezgi"),
                                                       "at": .zaman(Date().addingTimeInterval(-60))])
        try await owner.belgeYaz("\(yol)/log/l2", alanlar: ["type": .metin("status"), "text": .metin("Statü"), "statusName": .metin("Potansiyel"),
                                                       "byName": .metin("Ezgi"), "at": .zaman(Date())])
        try await owner.belgeYaz("\(yol)/notes/n1", alanlar: ["text": .metin("iç not")])
        try await owner.belgeYaz("\(yol)/dosyalar/d1", alanlar: ["tur": .metin("odeme"), "parca": .tam(2)])
        try await owner.belgeYaz("\(yol)/dosyaIcerik/d1_0", alanlar: ["veri": .metin("x")])
        try await owner.belgeYaz("\(yol)/dosyaIcerik/d1_1", alanlar: ["veri": .metin("y")])
        try await owner.belgeYaz("\(yol)/odemeler/o1", alanlar: ["tarih": .metin("2026-11-10"), "tutar": .tam(2000), "paraBirimi": .metin("TRY"),
                                                            "yontem": .metin("nakit"), "dosyaId": .metin("d1"), "byName": .metin("Ezgi"), "at": .zaman(Date())])
        try await owner.belgeYaz("\(yol)/odemeler/o2", alanlar: ["tarih": .metin("2026-11-12"), "tutar": .ondalik(500.5), "paraBirimi": .metin("TRY"),
                                                            "byName": .metin("Ezgi"), "at": .zaman(Date())])
        try await owner.belgeYaz("takip/\(takipId)", alanlar: ["code": .metin("2026-11\(ek)")])
        try await owner.belgeYaz("formlar/\(takipId)", alanlar: ["appId": .metin(appId)])
        try await owner.belgeYaz("lookup/\(ozet)", alanlar: ["apps": .dizi([.metin(appId), .metin("baska")])])
        try await owner.belgeYaz("bildirimler/b\(ek)", alanlar: ["appId": .metin(appId), "kind": .metin("form-linki")])
        try await owner.belgeYaz("kasa/k\(ek)", alanlar: ["appId": .metin(appId), "kapsam": .metin("musteri"), "tur": .metin("gider"),
                                                       "tarih": .metin("2026-11-11"), "tutar": .tam(300), "paraBirimi": .metin("TRY"), "kategori": .metin("Fotokopi")])

        let o = try await e.kimlik.giris(kullaniciAdi: "adm\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: nil)
        let _b = try await ben.belge(yol)
        let b = Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_b))

        // Saklama: gerekçesiz olmaz; gün boşsa mevcut tarih kalır.
        XCTAssertNil(BasvuruSilme.saklama(b, gun: "", bekletme: true, gerekce: " ", calisan: c))
        try await ben.isle(try XCTUnwrap(BasvuruSilme.saklama(b, gun: "2027-01-15", bekletme: true, gerekce: "İtiraz süreci", calisan: c)))
        let _b2 = try await ben.belge(yol)
        let b2 = Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_b2))
        XCTAssertTrue(b2.bekletiliyor)
        XCTAssertEqual(b2.silinecek.map { Tr.bugun($0) }, "2027-01-15")

        // Sil: uygulamanın okuduğu gibi topla, tek yazımda arşivle ve sil.
        let _ham = try await ben.belge(yol)
        let _veri = try await ben.belge("\(yol)/private/data")
        let okunan = BasvuruSilme.Okunan(
            basvuru: try XCTUnwrap(_ham),
            form: _veri?["form"]?.haritaDegeri ?? [:],
            anahtar: (takipId, ozet),
            loglar: try await ben.sorgu(koleksiyon: "log", sinir: 300, ust: yol),
            notlar: try await ben.sorgu(koleksiyon: "notes", sinir: 150, ust: yol).map(\.kimlik),
            ustNotlar: try await ben.sorgu(koleksiyon: "ustNotlar", sinir: 50, ust: yol).map(\.kimlik),
            dosyalar: try await ben.sorgu(koleksiyon: "dosyalar", sinir: 40, ust: yol).map { ($0.kimlik, $0.alanlar["parca"]?.tamDegeri ?? 1) },
            odemeler: try await ben.sorgu(koleksiyon: "odemeler", sinir: 50, ust: yol),
            fiyat: try await ben.belge("\(yol)/private/fiyat"),
            giderler: try await ben.sorgu(koleksiyon: "kasa", kosullar: [.esit("appId", .metin(appId)), .esit("kapsam", .metin("musteri"))], sinir: 200).map(\.alanlar),
            bildirimler: try await ben.sorgu(koleksiyon: "bildirimler", kosullar: [.esit("appId", .metin(appId))], sinir: 50).map(\.kimlik))
        try await ben.isle(BasvuruSilme.sil(appId, okunan, calisan: c))
        let silinen = try await ben.belge(yol)
        XCTAssertNil(silinen)
        let takip = try await owner.belge("takip/\(takipId)")
        XCTAssertNil(takip)
        let lookup = try await owner.belge("lookup/\(ozet)")
        XCTAssertEqual(lookup?["apps"]?.diziDegeri?.compactMap { $0.metinDegeri }, ["baska"])
        let _k = try await ben.belge("musteriArsivi/\(appId)")
        let k = ArsivKaydi(kimlik: appId, alanlar: try XCTUnwrap(_k))
        XCTAssertEqual(k.adSoyad, "AYŞE NUR KAYA")
        XCTAssertEqual(try XCTUnwrap(_k)["telefon"]?.metinDegeri, "+905321234567")
        XCTAssertEqual(try XCTUnwrap(_k)["eposta"]?.metinDegeri, "ayse@ornek.com")
        XCTAssertEqual(try XCTUnwrap(_k)["anahtarlar"]?.diziDegeri?.compactMap { $0.metinDegeri },
                       ["ayşe", "nur", "kaya", "ayşe nur kaya", "+905321234567", "ayse@ornek.com"])
        XCTAssertEqual(try XCTUnwrap(_k)["odemeToplam"]?.haritaDegeri?["TRY"], .ondalik(2500.5))
        XCTAssertEqual(try XCTUnwrap(_k)["giderToplam"]?.haritaDegeri?["TRY"], .tam(300))
        XCTAssertEqual(try XCTUnwrap(_k)["islemler"]?.diziDegeri?.first?.haritaDegeri?["tur"]?.metinDegeri, "retention")
        XCTAssertEqual(try XCTUnwrap(_k)["odemeler"]?.diziDegeri?.first?.haritaDegeri?["tarih"]?.metinDegeri, "2026-11-12")
    }

    func testStatuVeEvrakAyari() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("sta\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("sta\(ek)"), "displayName": .metin("Sefa Yönetici"), "role": .metin("admin"), "active": .mantik(true)])
        let o = try await e.kimlik.giris(kullaniciAdi: "sta\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: nil)
        func statuler() async throws -> [Statu] {
            try await ben.sorgu(koleksiyon: "statuses", sinir: 100).map { Statu(kimlik: $0.kimlik, alanlar: $0.alanlar) }
                .filter { $0.id.hasSuffix(ek) || $0.ad.hasSuffix(ek) }.sorted { $0.sira < $1.sira }
        }

        // Yeni statü: arama aralığı tek uçluysa tamamlanır, son adımda silme süresi olmaz.
        var g = StatuGirdisi(nil)
        g.ad = "Evrak Bekleniyor \(ek)"; g.aramaMin = 14; g.silmeGun = 60; g.gerekenler = ["odeme", "uydurma"]
        let k1 = try XCTUnwrap(StatuAyari.kaydet(g, mevcut: nil, statuler: [], calisan: c))
        XCTAssertEqual(k1.id, "evrak-bekleniyor-\(ek)")
        try await ben.isle(k1.yazimlar)
        var g2 = StatuGirdisi(nil)
        g2.ad = "Teslim \(ek)"; g2.son = true; g2.silmeGun = 30
        let l1 = try await statuler()
        let k2 = try XCTUnwrap(StatuAyari.kaydet(g2, mevcut: nil, statuler: l1, calisan: c))
        try await ben.isle(k2.yazimlar)
        var l = try await statuler()
        XCTAssertEqual(l.map(\.id), [k1.id, k2.id])
        XCTAssertEqual(l[0].aramaMax, 14)
        XCTAssertEqual(l[0].gerekenler, ["odeme"])
        XCTAssertNil(l[1].silmeGun)
        XCTAssertTrue(l[1].bildirir)

        // Düzenle ve sıra değiştir.
        var g3 = StatuGirdisi(l[0]); g3.musteriAdi = "Evraklarınız bekleniyor"; g3.bildir = false
        XCTAssertTrue(StatuAyari.musteriyeGorunenDegisti(l[0], g3))
        try await ben.isle(try XCTUnwrap(StatuAyari.kaydet(g3, mevcut: l[0], statuler: l, calisan: c)).yazimlar)
        try await ben.isle(StatuAyari.yerDegistir(l[0], l[1], calisan: c))
        l = try await statuler()
        XCTAssertEqual(l.map(\.id), [k2.id, k1.id])
        XCTAssertFalse(l[1].bildirir)

        // Kullanımdaki statüyü sil: başvuru taşınır, müşteri sayfası notlarıyla tazelenir.
        let appId = "st\(ek)"
        let takipId = String(repeating: "a", count: 60) + ek
        try await owner.belgeYaz("applications/\(appId)", alanlar: [
            "trackingCode": .metin("2026-11\(ek)"), "year": .tam(2026), "month": .tam(11),
            "firstName": .metin("AYSE"), "lastName": .metin("KAYA"), "passportLast3": .metin("567"),
            "country": .metin("italya"), "countryName": .metin("İtalya"),
            "statusId": .metin(k1.id), "statusName": .metin(g.ad), "checklist": .harita([:]),
            "openedAt": .zaman(Date()), "createdAt": .zaman(Date()), "createdBy": .metin(uid),
        ])
        let notlar: FSDeger = .dizi([.harita(["text": .metin("Evraklarınız geldi"), "at": .metin("2026-11-10")])])
        try await owner.belgeYaz("takip/\(takipId)", alanlar: ["countryName": .metin("İtalya"), "firstName": .metin("AYSE"), "statusName": .metin("x"),
                                                         "statusDescription": .metin(""), "statusColor": .metin("#000"), "isFinal": .mantik(false),
                                                         "notes": notlar, "updatedAt": .zaman(Date())])
        let _b = try await ben.belge("applications/\(appId)")
        let b = Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_b))
        let silinen = try XCTUnwrap(l.first { $0.id == k1.id }), hedef = try XCTUnwrap(l.first { $0.id == k2.id })
        try await ben.isle(StatuAyari.tasi(b, takipId: takipId, notlar: notlar, hedef: hedef, statuler: l, saklamaGun: 60, calisan: c)
                           + StatuAyari.sil(silinen, ayrinti: "\(silinen.ad) → \(hedef.ad) (1 başvuru)", calisan: c))
        let _b2 = try await ben.belge("applications/\(appId)")
        let b2 = Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_b2))
        XCTAssertEqual(b2.statuId, k2.id)
        XCTAssertNotNil(b2.sonAdimZamani)
        let _t = try await owner.belge("takip/\(takipId)")
        XCTAssertEqual(_t?["statusName"]?.metinDegeri, "Teslim \(ek)")
        XCTAssertEqual(_t?["notes"], notlar)
        let kalan = try await statuler()
        XCTAssertEqual(kalan.map(\.id), [k2.id])

        // Evrak listesi: genel + ülkeye özel; boş ülke listesi kaldırılır.
        try await ben.isle(EvrakListesiAyari.kaydet(
            genel: [Evrak(id: "pasaport", ad: "Pasaport"), Evrak(id: "", ad: "Banka Dökümü"), Evrak(id: "x", ad: "  ")],
            ulkeler: ["italya": [Evrak(id: "otel", ad: "Otel rezervasyonu")], "fransa": []], kapsam: "italya", calisan: c))
        let ayar = EvrakAyari(belge: try await ben.belge("settings/checklist"))
        XCTAssertEqual(ayar.genel?.map(\.id), ["pasaport", "banka-dokumu"])
        XCTAssertEqual(ayar.ulkeler.keys.sorted(), ["italya"])
    }

    func testBildirimTercihi() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("tr\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("tr\(ek)"), "displayName": .metin("Ezgi"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi((Calisan.varsayilanIzinler["writer"]! + ["app.edit", "app.sensitive", "app.status"]).map { .metin($0) }),
        ])])
        let appId = "tr\(ek)"
        let randevu = Tr.tarih(Tr.gunEkle(Tr.bugun(), 30))!
        try await owner.belgeYaz("applications/\(appId)", alanlar: [
            "trackingCode": .metin("2026-11\(ek)"), "year": .tam(2026), "month": .tam(11),
            "firstName": .metin("AYSE"), "lastName": .metin("KAYA"), "passportLast3": .metin("567"),
            "country": .metin("italya"), "countryName": .metin("İtalya"),
            "statusId": .metin("potansiyel"), "statusName": .metin("Potansiyel"), "checklist": .harita([:]),
            "appointmentAt": .zaman(randevu),
            "openedAt": .zaman(Date()), "createdAt": .zaman(Date()), "createdBy": .metin(uid),
        ])
        try await owner.belgeYaz("applications/\(appId)/private/data", alanlar: ["form": .harita([
            "phone": .metin("+905321234567"), "email": .metin("ayse@ornek.com"), "passportNo": .metin("U1"),
            "channels": .harita(["wa": .mantik(true), "sms": .mantik(true), "email": .mantik(true)])])])
        let o = try await e.kimlik.giris(kullaniciAdi: "tr\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        let _b = try await ben.belge("applications/\(appId)")
        let b = Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_b))
        let _f = try await ben.belge("applications/\(appId)/private/data")
        let form = _f?["form"]?.haritaDegeri
        // Önce üç kanalla planlanmış randevu bildirimleri (sitenin kurallarına uygun kayıtlar).
        let gun = Tr.bugun(randevu)
        let ilk = BildirimPlani.planla(b, randevu: RandevuGirdisi(tarih: gun, saat: "", merkez: "", sehir: "", yer: "", ulke: "italya"),
                                       kayit: RandevuKurali.Kayit(saat: "", merkez: "", sehir: "", yer: "", harita: ""),
                                       iletisim: MusteriIletisimi(form: form), ayar: BildirimAyari(belge: nil), mevcut: [], calisan: c)
        try await ben.isle(ilk.yazimlar)

        let yeni = Kanallar(wa: false, sms: true, email: false)
        XCTAssertEqual(BildirimTercihi.hatalar(Kanallar(email: true), eposta: "yanlis", telefon: "x"), ["E-posta açık: geçerli bir e-posta adresi girin."])
        XCTAssertTrue(BildirimTercihi.degisti(form, yeni, eposta: "ayse@ornek.com"))
        XCTAssertFalse(BildirimTercihi.degisti(form, Kanallar(), eposta: " AYSE@ornek.com"))
        try await ben.isle(BildirimTercihi.kaydet(b, yeni, eposta: "Ayse.Kaya@Ornek.com", epostaDegisti: true, calisan: c))
        let _f2 = try await ben.belge("applications/\(appId)/private/data")
        let form2 = try XCTUnwrap(_f2?["form"]?.haritaDegeri)
        XCTAssertEqual(BildirimTercihi.oku(form2).kanallar, yeni)
        XCTAssertEqual(form2["email"]?.metinDegeri, "ayse.kaya@ornek.com")
        XCTAssertEqual(form2["passportNo"]?.metinDegeri, "U1")

        // Planlı bildirim yeni tercihle yeniden kurulur (yalnız SMS).
        let mevcut = try await ben.sorgu(koleksiyon: "bildirimler", kosullar: [.esit("appId", .metin(appId))], sinir: 50)
            .map { BildirimKaydi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        let p = BildirimTercihi.yenidenPlanla(b, iletisim: MusteriIletisimi(form: form2), ayar: BildirimAyari(belge: nil), mevcut: mevcut,
                                              formKurali: .varsayilan, calisan: c)
        XCTAssertEqual(p.adet, 2)
        try await ben.isle(p.yazimlar)
        let sonra = try await ben.sorgu(koleksiyon: "bildirimler", kosullar: [.esit("appId", .metin(appId))], sinir: 50)
        let planli = sonra.filter { $0.alanlar["status"]?.metinDegeri == "planned" }
        XCTAssertEqual(planli.count, 2)
        XCTAssertTrue(planli.allSatisfy { $0.alanlar["channels"]?.haritaDegeri?["sms"] == .mantik(true) && $0.alanlar["channels"]?.haritaDegeri?["wa"] == .mantik(false) })
    }

    func testMektupKaydi() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("mk\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("mk\(ek)"), "displayName": .metin("Ezgi"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi((Calisan.varsayilanIzinler["writer"]! + ["app.sensitive"]).map { .metin($0) }),
        ])])
        let appId = "mk\(ek)"
        try await owner.belgeYaz("applications/\(appId)", alanlar: ["firstName": .metin("AYSE")])
        let o = try await e.kimlik.giris(kullaniciAdi: "mk\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        var b = MektupBilgileri(); b.adSoyad = "Ayşe Kaya"; b.eslikEdenler = [.init(ad: "Ali Kaya", yakinlik: "eşim", pasaport: "U1")]
        try await ben.isle(Mektup.kaydet(appId, bilgiler: b, not: "not", secilenler: ["amac-turistik"], tr: ["a", "b"], en: ["c"], pdf: true, calisan: c))
        try await ben.isle(Mektup.kaydet(appId, bilgiler: b, not: "not 2", secilenler: [], tr: ["a"], en: [], calisan: c))
        let _m = try await ben.belge("applications/\(appId)/private/mektup")
        let m = try XCTUnwrap(_m)
        XCTAssertEqual(MektupBilgileri(alanlar: try XCTUnwrap(m["bilgiler"]?.haritaDegeri)), b)
        XCTAssertEqual(m["not"]?.metinDegeri, "not 2")
    }

    func testTopluEposta() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("tp\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("tp\(ek)"), "displayName": .metin("Ezgi"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi((Calisan.varsayilanIzinler["writer"]! + ["eposta.send", "eposta.kampanya"]).map { .metin($0) }),
        ])])
        let o = try await e.kimlik.giris(kullaniciAdi: "tp\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        let adaylar = [
            TopluAday(eposta: " Ayse@Ornek.com ", ad: "AYŞE", soyad: "KAYA", ulke: "İtalya", kampanyaIzni: true, kaynak: "arsiv"),
            TopluAday(eposta: "ayse@ornek.com", ad: "Ayşe", soyad: "Kaya", ulke: "", kampanyaIzni: true, kaynak: "talep"),
            TopluAday(eposta: "yok", ad: "X", soyad: "", ulke: "", kampanyaIzni: true, kaynak: "talep"),
            TopluAday(eposta: "izinsiz@ornek.com", ad: "Can", soyad: "", ulke: "", kampanyaIzni: false, kaynak: "talep"),
            TopluAday(eposta: "cikti@ornek.com", ad: "Ece", soyad: "", ulke: "", kampanyaIzni: true, kaynak: "talep"),
        ]
        let s = TopluEposta.aliciSec(adaylar, kampanya: true, ayrilanlar: ["cikti@ornek.com"])
        XCTAssertEqual(s.alicilar.map(\.eposta), ["ayse@ornek.com"])
        XCTAssertEqual(s.atlanan, TopluEposta.Atlanan(epostaYok: 1, izinYok: 1, ayrildi: 1, tekrar: 1))
        XCTAssertEqual(TopluEposta.aliciSec(adaylar, kampanya: false, ayrilanlar: []).alicilar.count, 3)
        let kid = TopluEposta.kampanyaId()
        let k = try XCTUnwrap(TopluEposta.kuyruk(s.alicilar, konu: "{ulke} için fırsat", metin: "Merhaba {ad},", kampanya: true, kampanyaId: kid, calisan: c))
        XCTAssertEqual(k.adet, 1)
        for g in k.gruplar { try await ben.isle(g) }
        let l = try await ben.sorgu(koleksiyon: "eposta", kosullar: [.esit("kampanyaId", .metin(kid))], sinir: 10)
        XCTAssertEqual(l.first?.alanlar["subject"]?.metinDegeri, "İtalya için fırsat")
        XCTAssertEqual(l.first?.alanlar["text"]?.metinDegeri, "Merhaba Ayşe,")
        XCTAssertEqual(l.first?.alanlar["tur"]?.metinDegeri, "kampanya")
        XCTAssertNil(TopluEposta.kuyruk(s.alicilar, konu: " ", metin: "x", kampanya: false, kampanyaId: kid, calisan: c))
        XCTAssertEqual(TopluEposta.adBol("Mehmet Ali Yılmaz").ad, "Mehmet Ali")
    }

    func testElleSosyalPost() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("sp\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("sp\(ek)"), "displayName": .metin("Ezgi"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi((Calisan.varsayilanIzinler["writer"]! + ["social.view", "social.upload"]).map { .metin($0) }),
        ])])
        let o = try await e.kimlik.giris(kullaniciAdi: "sp\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        let jpg = Data([0xff, 0xd8, 0xff, 0xe0, 0, 1, 2, 3])
        XCTAssertEqual(ElleSosyalPost.gorselTuru(jpg), "image/jpeg")
        XCTAssertNil(ElleSosyalPost.gorselTuru(Data([1, 2, 3])))
        XCTAssertEqual(ElleSosyalPost.bosSira([1, 2, 10, 11]), 12)
        let tarih = "2030-0\(Int(ek.prefix(1))! % 9 + 1)-1\(ek.suffix(1))"
        guard case .failure(let h) = ElleSosyalPost.olustur(tarih: tarih, sira: 10, no: 5, tur: "haber", konu: "", kaynak: "", instagram: "x",
                                                            x: "", whatsapp: "", gorseller: [.init(tur: "image/jpeg", bayt: jpg)], calisan: c) else { return XCTFail() }
        XCTAssertEqual(h.mesaj, "Konu boş olamaz (panelde kartın başlığı olur).")
        guard case .success(let r) = ElleSosyalPost.olustur(tarih: tarih, sira: 10, no: 5, tur: "haber", konu: "Almanya vize kolaylığı", kaynak: "Bakanlık",
                                                            instagram: "Açıklama #vize", x: "X metni", whatsapp: "",
                                                            gorseller: [.init(tur: "image/jpeg", bayt: jpg), .init(tur: "image/jpeg", bayt: jpg)], calisan: c) else { return XCTFail() }
        XCTAssertEqual(r.id, "\(tarih)-10")
        try await ben.isle(r.yazimlar)
        let _p = try await ben.belge("posts/\(r.id)")
        let p = try XCTUnwrap(_p)
        XCTAssertEqual(p["dosya"]?.metinDegeri, "VizeMia-Post-005-\(tarih)-haber")
        XCTAssertEqual(p["kanallar"]?.haritaDegeri?.keys.sorted(), ["instagram", "x"])
        let g = try await ben.belge("posts/\(r.id)/gorseller/VizeMia-Post-005-\(tarih)-haber-2.jpg")
        XCTAssertEqual(g?["veri"], .bayt(jpg))
        guard case .success(let r2) = ElleSosyalPost.olustur(tarih: tarih, sira: 3, no: 6, tur: "haber", konu: "k", kaynak: "", instagram: "i",
                                                             x: "", whatsapp: "", gorseller: [.init(tur: "image/jpeg", bayt: jpg)], calisan: c) else {
            return // 10'dan küçük sıra çekirdekte de reddedilir
        }
        XCTFail("sıra 3 kabul edildi: \(r2.id)")
    }

    func testEposta() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("mail\(ek)", "gizli-sifre-1")
        let okur = try await e.hesapAc("okur\(ek)", "gizli-sifre-2")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("mail\(ek)"), "displayName": .metin("Ezgi Danışman"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("employees/\(okur)", alanlar: [
            "username": .metin("okur\(ek)"), "displayName": .metin("Okur"), "role": .metin("reader"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi((Calisan.varsayilanIzinler["writer"]! + ["eposta.send"]).map { .metin($0) }),
            "reader": .dizi(Calisan.varsayilanIzinler["reader"]!.map { .metin($0) }),
        ])])
        let appId = "eps\(ek)"
        try await owner.belgeYaz("applications/\(appId)", alanlar: [
            "trackingCode": .metin("2026-14\(ek)"), "firstName": .metin("AYŞE NUR"), "lastName": .metin("KAYA"),
            "countryName": .metin("Almanya"), "statusId": .metin("potansiyel"),
        ])
        let o = try await e.kimlik.giris(kullaniciAdi: "mail\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        let _b = try await ben.belge("applications/\(appId)")
        let b = Basvuru(kimlik: appId, alanlar: try XCTUnwrap(_b))

        let sablon = try XCTUnwrap(EpostaAyari(belge: nil).sablonlar.first { $0.id == "evrak-hatirlatma" })
        let d = MusteriBildirimi.epostaDegerleri(b, statu: "")
        let konu = MusteriBildirimi.doldur(sablon.konu, d), metin = MusteriBildirimi.doldur(sablon.metin, d)
        XCTAssertEqual(konu, "Almanya vize başvurunuz için evraklarınız")
        XCTAssertTrue(metin.hasPrefix("Sayın Ayşe Nur Kaya,"))
        XCTAssertEqual(EpostaIslemi.bosYerTutucular(metin), [])
        try await ben.isle(try XCTUnwrap(EpostaIslemi.tekli(b, eposta: " Ayse@Ornek.com ", konu: konu, metin: metin, calisan: c)))
        let l = try await ben.sorgu(koleksiyon: "eposta", kosullar: [.esit("appId", .metin(appId))], sinir: 10)
        XCTAssertEqual(l.count, 1)
        let m = EpostaKaydi(kimlik: l[0].kimlik, alanlar: l[0].alanlar)
        XCTAssertEqual(m.alici, "ayse@ornek.com")
        XCTAssertEqual(m.durumYazisi, "Sırada")

        let sd = EpostaIslemi.serbestDegerler(ad: "mehmet ali yılmaz")
        XCTAssertEqual(sd["adSoyad"], "Mehmet Ali Yılmaz")
        try await ben.isle(try XCTUnwrap(EpostaIslemi.serbest(alici: "kurum@ornek.org", konu: "Bilgi", metin: "Merhaba", calisan: c)))
        XCTAssertNil(EpostaIslemi.serbest(alici: "yanlis", konu: "x", metin: "y", calisan: c))

        try await ben.isle(EpostaIslemi.iptal(m, calisan: c))
        let _m2 = try await ben.belge("eposta/\(m.id)")
        let iptal = EpostaKaydi(kimlik: m.id, alanlar: try XCTUnwrap(_m2))
        XCTAssertEqual(iptal.durumYazisi, "İptal (panelden iptal)")
        do { try await ben.isle(EpostaIslemi.iptal(iptal, calisan: c)); XCTFail("iptal edilen yeniden iptal edilemez") } catch {}

        // İzinsiz (okur) mail yazamaz.
        let oo = try await e.kimlik.giris(kullaniciAdi: "okur\(ek)", sifre: "gizli-sifre-2")
        let okIst = e.istemci(oo.belirtec)
        do { try await okIst.isle(try XCTUnwrap(EpostaIslemi.serbest(alici: "a@b.co", konu: "x", metin: "y", calisan: c))); XCTFail("izin yok") } catch {}
    }

    /// Firmaya cevap: kayıtlı firmanın adresine (kural adresi firmadan karşılaştırır).
    func testFirmaCevap() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("firma\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("firma\(ek)"), "displayName": .metin("Sefa Karakaş"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi((Calisan.varsayilanIzinler["writer"]! + ["firma.view", "firma.send"]).map { .metin($0) }),
        ])])
        let firmaId = String(repeating: "a", count: 60) + ek
        try await owner.belgeYaz("firmalar/\(firmaId)", alanlar: [
            "ad": .metin("Örnek Makine A.Ş."), "eposta": .metin("info@ornekmakine.com"), "bolge": .metin("OSTİM"),
            "iysKayit": .mantik(true), "engelli": .mantik(false),
        ])
        let o = try await e.kimlik.giris(kullaniciAdi: "firma\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        var g = FirmaIletisimi(); g.telefon = "0549 907 25 23"
        let y = try XCTUnwrap(FirmaMaili.cevap(firmaId: firmaId, firma: "Örnek Makine A.Ş.", eposta: "info@ornekmakine.com",
                                               konu: "Ynt: Vize", govde: "Merhaba,\n\nBilgi ekte.", genel: g, calisan: c))
        try await ben.isle(y)
        let l = try await ben.sorgu(koleksiyon: "firmaYanitlari", kosullar: [.esit("firmaId", .metin(firmaId))], sinir: 5)
        XCTAssertEqual(l.map { FirmaMaili(kimlik: $0.kimlik, tur: "yanit", alanlar: $0.alanlar).durumAdi }, ["Kuyrukta"])
        // Başka adrese cevap yazılamaz.
        let yanlis = try XCTUnwrap(FirmaMaili.cevap(firmaId: firmaId, firma: "x", eposta: "baska@ornek.com", konu: "a", govde: "b", genel: g, calisan: c))
        do { try await ben.isle(yanlis); XCTFail("adres firmanınki olmalı") } catch {}
    }

    /// Süreç adımları (siteMetin/surec): 3–6 adım; okur değiştiremez.
    func testSurecAdimlari() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("surec\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("surec\(ek)"), "displayName": .metin("Ezgi"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi(Calisan.varsayilanIzinler["writer"]!.map { .metin($0) }),
        ])])
        let o = try await e.kimlik.giris(kullaniciAdi: "surec\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        var s = SurecAdimlari.varsayilan
        s.adimlar.removeLast()
        s.baslik = "4 adımda başvuru"
        XCTAssertEqual(s.hatalar, [])
        try await ben.isle(s.yazimlar(calisan: c))
        let _b = try await ben.belge("siteMetin/surec")
        XCTAssertEqual(SurecAdimlari(belge: _b), s)
        var az = s
        az.adimlar = Array(az.adimlar.prefix(2))
        XCTAssertFalse(az.hatalar.isEmpty)
        do { try await ben.isle(az.yazimlar(calisan: c)); XCTFail("en az 3 adım") } catch {}
    }

    /// Blog / SSS: yayınla, slaytı olan içeriği güncelle (görsel korunur), sil.
    func testIcerik() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("icerik\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("icerik\(ek)"), "displayName": .metin("Ezgi"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi(Calisan.varsayilanIzinler["writer"]!.map { .metin($0) }),
        ])])
        let o = try await e.kimlik.giris(kullaniciAdi: "icerik\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))

        var i = Icerik()
        i.baslik = "Schengen Vizesi: Nasıl Başvurulur?"
        i.metin = "## Adımlar\n- Randevu\n- Evrak"
        i.durum = "published"
        XCTAssertEqual(i.hatalar, [])
        try await ben.isle(IcerikIslemi.kaydet(i, yeni: true, yayinlayabilir: true, slayt: nil, calisan: c))
        let _a = try await ben.belge("content/\(i.id)")
        var kayitli = Icerik(kimlik: i.id, alanlar: try XCTUnwrap(_a))
        XCTAssertEqual(kayitli.slug, "schengen-vizesi-nasil-basvurulur")
        XCTAssertNotNil(kayitli.yayinTarihi)

        // Panelde slayt eklenmiş (havuz fotoğrafıyla); uygulamada başlık değişince slayt da güncellenir.
        try await owner.belgeYaz("vitrin/icerik-\(i.id)", alanlar: [
            "ust": .metin("Blog"), "baslik": .metin("Eski"), "metin": .metin("Kısa"), "dugme": .metin("Yazıyı oku"),
            "link": .metin("/blog/schengen-vizesi-nasil-basvurulur"), "gorsel": .metin(""), "havuzFoto": .metin("almanya-1"),
            "odak": .metin(""), "ulke": .metin(""), "baslangic": .bos, "bitis": .bos, "sira": .tam(50), "durum": .metin("yayinda"),
            "createdAt": .zaman(Date()), "createdBy": .metin(uid), "updatedAt": .zaman(Date()), "updatedBy": .metin(uid),
        ])
        let slayt = try await ben.belge("vitrin/icerik-\(i.id)")
        kayitli.baslik = "Schengen vizesi rehberi"
        kayitli.slug = "schengen-rehberi"
        try await ben.isle(IcerikIslemi.kaydet(kayitli, yeni: false, yayinlayabilir: true, slayt: slayt, calisan: c))
        let _s = try await ben.belge("vitrin/icerik-\(i.id)")
        let s2 = try XCTUnwrap(_s)
        XCTAssertEqual(s2["baslik"], .metin("Schengen vizesi rehberi"))
        XCTAssertEqual(s2["link"], .metin("/blog/schengen-rehberi"))
        XCTAssertEqual(s2["havuzFoto"], .metin("almanya-1"), "görsel korunur")
        XCTAssertEqual(s2["metin"], .metin("Kısa"))
        let _a2 = try await ben.belge("content/\(i.id)")
        let k2 = Icerik(kimlik: i.id, alanlar: try XCTUnwrap(_a2))
        XCTAssertEqual(k2.yayinTarihi, kayitli.yayinTarihi, "ilk yayın tarihi korunur")

        // Slug çakışması sorgusu (uygulama kaydetmeden önce bakar).
        let ayni = try await ben.sorgu(koleksiyon: "content", kosullar: [.esit("slug", .metin("schengen-rehberi"))], sinir: 5)
        XCTAssertEqual(ayni.map(\.kimlik), [i.id])

        try await ben.isle(IcerikIslemi.sil(k2, slaytVar: true, calisan: c))
        let silinen = try await owner.belge("content/\(i.id)")
        XCTAssertNil(silinen)
    }

    /// Vitrin ve fotoğraf havuzu: slayt ekle / düzenle / sil, yüklenen görseli havuza ekle, görünen alanı değiştir.
    func testVitrinVeHavuz() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("vitrin\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("vitrin\(ek)"), "displayName": .metin("Ezgi"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi(Calisan.varsayilanIzinler["writer"]!.map { .metin($0) }),
        ])])
        let o = try await e.kimlik.giris(kullaniciAdi: "vitrin\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))

        var s = VitrinSlayti()
        s.baslik = "Noel'i Almanya'da geçirmek ister misin?"
        s.ust = "Almanya · Aralık"
        s.ulke = "almanya"
        s.durum = "yayinda"
        s.bitis = Tr.gunEkle(Tr.bugun(), 30)
        XCTAssertEqual(s.hatalar, [])
        try await ben.isle(VitrinIslemi.kaydet(s, yayinlayabilir: true, calisan: c))
        let _s1 = try await ben.belge("vitrin/\(s.id)")
        var k = VitrinSlayti(kimlik: s.id, alanlar: try XCTUnwrap(_s1))
        XCTAssertEqual(k.durumYazisi().tur, "yayinda")
        k.havuzFoto = "almanya-rothenburg"
        k.odak = "20% 80%"
        k.link = ""
        try await ben.isle(VitrinIslemi.kaydet(k, yayinlayabilir: true, calisan: c))

        // Kendi görseliyle yeni slayt; görsel havuza da eklenir.
        var g = VitrinSlayti()
        g.baslik = "Yaz kampanyası"
        g.gorsel = FotoHavuzu.veriAdresi(jpeg: Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]))
        try await ben.isle(VitrinIslemi.kaydet(g, yayinlayabilir: false, havuzaEkle: true, calisan: c))
        let _g = try await ben.belge("vitrin/\(g.id)")
        XCTAssertEqual(VitrinSlayti(kimlik: g.id, alanlar: try XCTUnwrap(_g)).durum, "taslak", "yetki yoksa taslak")
        let havuz = try await ben.sorgu(koleksiyon: "fotoHavuzu", sinir: 10).map { FotoHavuzu.Eklenen(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        let eklenen = try XCTUnwrap(havuz.first { $0.gorsel == g.gorsel })
        XCTAssertEqual(eklenen.ad, "Yaz kampanyası")
        try await ben.isle(FotoHavuzu.odakGuncelle(eklenen, odak: "70% 30%", calisan: c))
        let _h = try await ben.belge("fotoHavuzu/\(eklenen.id)")
        XCTAssertEqual(FotoHavuzu.Eklenen(kimlik: eklenen.id, alanlar: try XCTUnwrap(_h)).odak, "70% 30%")
        try await ben.isle(FotoHavuzu.sil(eklenen, calisan: c))
        try await ben.isle(VitrinIslemi.sil(k, calisan: c))
        let silinen = try await owner.belge("vitrin/\(k.id)")
        XCTAssertNil(silinen)
    }

    /// Sosyal medya: kanal işareti (yalnız o kanal), Instagram isteği, silme (görselleriyle), post isteği.
    func testSosyal() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("sosyal\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("sosyal\(ek)"), "displayName": .metin("Ezgi Danışman"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi((Calisan.varsayilanIzinler["writer"]! + ["social.instagram", "social.delete"]).map { .metin($0) }),
        ])])
        let gun = "2026-11-\(String(ek.suffix(2)).count == 2 ? "1" + String(ek.suffix(1)) : "10")"
        func post(_ sira: Int) -> [String: FSDeger] {
            [
                "tarih": .metin(gun), "sira": .tam(sira), "tur": .metin("bilgi"), "no": .tam(sira), "dosya": .metin("VizeMia-Post-\(sira)"),
                "konu": .metin("Schengen ipucu \(sira)"), "kaynak": .metin(""), "olusturma": .zaman(Date()),
                "kanallar": .harita([
                    "instagram": .harita(["metin": .metin("IG metni"), "gorseller": .dizi([.harita(["dosya": .metin("g\(sira)-1.jpg")])]),
                                          "durum": .metin("bekliyor"), "paylasildi_tarih": .bos, "paylasan": .bos]),
                    "x": .harita(["metin": .metin("X metni"), "gorseller": .dizi([]), "durum": .metin("bekliyor"),
                                  "paylasildi_tarih": .bos, "paylasan": .bos]),
                ]),
            ]
        }
        let id1 = "\(gun)-1", id2 = "\(gun)-2"
        try await owner.belgeYaz("posts/\(id1)", alanlar: post(1))
        try await owner.belgeYaz("posts/\(id2)", alanlar: post(2))
        try await owner.belgeYaz("posts/\(id2)/gorseller/g2-1.jpg", alanlar: ["dosya": .metin("g2-1.jpg"), "tur": .metin("image/jpeg"), "veri": .bayt(Data([1, 2, 3]))])
        let o = try await e.kimlik.giris(kullaniciAdi: "sosyal\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        func oku(_ id: String) async throws -> SosyalPost {
            let a = try await ben.belge("posts/\(id)")
            return SosyalPost(kimlik: id, alanlar: try XCTUnwrap(a))
        }

        var p1 = try await oku(id1)
        XCTAssertEqual(p1.gorseller("x"), ["g1-1.jpg"], "X'in görseli yoksa Instagram'ınki")
        try await ben.isle(SosyalIslemi.isaret(p1, kanal: "x", paylasildi: true, calisan: c))
        p1 = try await oku(id1)
        XCTAssertEqual(p1.durum("x"), "paylasildi")
        XCTAssertEqual(p1.kanallar["x"]?.paylasan, "Ezgi Danışman")
        XCTAssertNotNil(p1.kanallar["x"]?.paylasildiTarih)
        XCTAssertEqual(p1.kanallar["x"]?.metin, "X metni", "öteki alanlar yerinde")
        XCTAssertEqual(p1.durum("instagram"), "bekliyor")
        XCTAssertEqual(p1.rozetler("instagram"), ["X"])
        try await ben.isle(SosyalIslemi.isaret(p1, kanal: "x", paylasildi: false, calisan: c))
        p1 = try await oku(id1)
        XCTAssertEqual(p1.durum("x"), "bekliyor")
        XCTAssertNil(p1.kanallar["x"]?.paylasildiTarih)

        XCTAssertTrue(p1.otomatikIstenebilir("instagram"))
        try await ben.isle(SosyalIslemi.instagramIstegi(p1, calisan: c))
        p1 = try await oku(id1)
        XCTAssertTrue(p1.otomatikSuruyor("instagram"))
        XCTAssertTrue(p1.elleKilitli("instagram"))
        do { try await ben.isle(SosyalIslemi.isaret(p1, kanal: "instagram", paylasildi: true, calisan: c)); XCTFail("otomatik sürerken elle işaret yok") } catch {}
        do { try await ben.isle(SosyalIslemi.sil(p1, gorseller: [], videoParcalari: [], calisan: c)); XCTFail("gönderilirken silinemez") } catch {}

        let p2 = try await oku(id2)
        let g = try await ben.sorgu(koleksiyon: "gorseller", sinir: 20, ust: "posts/\(id2)")
        XCTAssertEqual(g.first?.alanlar["veri"]?.baytDegeri, Data([1, 2, 3]))
        try await ben.isle(SosyalIslemi.sil(p2, gorseller: g.map(\.kimlik), videoParcalari: [], calisan: c))
        let silinen = try await owner.belge("posts/\(id2)")
        XCTAssertNil(silinen)

        XCTAssertEqual(PostIstegi.hata(metin: "x", hedefTarih: "2020-01-01", bugun: Tr.bugun()), "Geçmiş bir tarih seçilemez.")
        try await ben.isle(SosyalIslemi.istek(metin: "Almanya randevu açıldı postu", hedefTarih: "", calisan: c))
        let istekler = try await ben.sorgu(koleksiyon: "postIstekleri", kosullar: [.esit("isteyenUid", .metin(uid))], sinir: 5)
            .map { PostIstegi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        XCTAssertEqual(istekler.count, 1)
        try await ben.isle(SosyalIslemi.istekIptal(istekler[0], calisan: c))
        let _i = try await ben.belge("postIstekleri/\(istekler[0].id)")
        XCTAssertEqual(PostIstegi(kimlik: istekler[0].id, alanlar: try XCTUnwrap(_i)).durum, "iptal")
    }

    /// Kullanıcılar (yalnız yönetici): ekle, güncelle, kendini düşüremez, sil; işlem kayıtları.
    func testKullanicilar() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let yon = try await e.hesapAc("yon\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(yon)", alanlar: [
            "username": .metin("yon\(ek)"), "displayName": .metin("Sefa"), "role": .metin("admin"), "active": .mantik(true)])
        let o = try await e.kimlik.giris(kullaniciAdi: "yon\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(yon)")
        let c = Calisan(uid: yon, belge: try XCTUnwrap(_c), izinBelgesi: nil)

        let uid = "Uid\(ek)abcdefghijklmnopqrstu"
        let r = CalisanKaydi.ekle(uid: uid, kullaniciAdi: "ayse.\(ek)", ad: "Ayşe Kaya", eposta: "Ayse@Vizemia.com", rol: "writer", mevcut: [], calisan: c)
        XCTAssertNil(r.hata)
        try await ben.isle(r.yazimlar)
        XCTAssertNotNil(CalisanKaydi.ekle(uid: "kisa", kullaniciAdi: "x", ad: "", eposta: "", rol: "writer", mevcut: [], calisan: c).hata)
        let _k = try await ben.belge("employees/\(uid)")
        var k = CalisanKaydi(kimlik: uid, alanlar: try XCTUnwrap(_k))
        XCTAssertEqual(k.eposta, "ayse@vizemia.com")
        XCTAssertTrue(k.talepBildirimi)
        k.rol = "reader"
        k.aktif = false
        try await ben.isle(CalisanKaydi.guncelle(k, calisan: c))
        let _k2 = try await ben.belge("employees/\(uid)")
        let k2 = CalisanKaydi(kimlik: uid, alanlar: try XCTUnwrap(_k2))
        XCTAssertEqual(k2.rol, "reader")
        XCTAssertFalse(k2.talepBildirimi, "izleyiciye bildirim gitmez")

        // Kilitlenme koruması: yönetici kendini düşüremez ve silemez.
        let _b = try await ben.belge("employees/\(yon)")
        var kendi = CalisanKaydi(kimlik: yon, alanlar: try XCTUnwrap(_b))
        kendi.rol = "writer"
        do { try await ben.isle(CalisanKaydi.guncelle(kendi, calisan: c)); XCTFail("kendini düşüremez") } catch {}
        do { try await ben.isle(CalisanKaydi.sil(kendi, calisan: c)); XCTFail("kendini silemez") } catch {}
        try await ben.isle(CalisanKaydi.sil(k2, calisan: c))

        let kayitlar = try await ben.sorgu(koleksiyon: "audit", sirala: ("at", .azalan), sinir: 20)
            .map { IslemSatiri(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        XCTAssertTrue(kayitlar.contains { $0.eylem == "user.delete" && $0.eylemAdi == "Kullanıcıyı sildi" })
        XCTAssertTrue(kayitlar.first { $0.eylem == "user.create" }?.eslesir("kullanıcı ekledi") ?? false)
    }

    /// Telefonla gelen talep ve Armut: inceleme durumu, iç not, Talepler'e aktarma (telefonlu / telefonsuz).
    func testElleTalepVeArmut() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let uid = try await e.hesapAc("armut\(ek)", "gizli-sifre-1")
        try await owner.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("armut\(ek)"), "displayName": .metin("Aleyna Yılmaz"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi(Calisan.varsayilanIzinler["writer"]!.map { .metin($0) }),
        ])])
        func armut(_ id: String, telefon: String) -> [String: FSDeger] {
            ["isId": .metin(id), "ad": .metin(telefon.isEmpty ? "" : "Mehmet Demir"), "telefon": .metin(telefon), "baslik": .metin("Schengen vizesi"),
             "kategori": .metin("Vize danışmanlığı"), "konum": .metin("Ankara"), "teklifTutari": .tam(2500), "paraBirimi": .metin("TRY"),
             "armutDurum": .metin("quoted"), "aciklama": .metin("Almanya, aile ziyareti"), "url": .metin("https://armut.com/is/\(id)"),
             "soruCevap": .dizi([.harita(["soru": .metin("Kaç kişi?"), "cevap": .metin("2")])]), "incelemeDurum": .metin("yeni"),
             "createdAt": .zaman(Date())]
        }
        try await owner.belgeYaz("armutTalepleri/armut_a\(ek)", alanlar: armut("a\(ek)", telefon: "+905321112233"))
        try await owner.belgeYaz("armutTalepleri/armut_b\(ek)", alanlar: armut("b\(ek)", telefon: ""))
        let o = try await e.kimlik.giris(kullaniciAdi: "armut\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(uid)")
        let c = Calisan(uid: uid, belge: try XCTUnwrap(_c), izinBelgesi: try await ben.belge("settings/permissions"))
        let bugun = Tr.bugun()
        let mesai = Mesai(calisma: [0: [540, 1080], 1: [540, 1080], 2: [540, 1080], 3: [540, 1080], 4: [540, 1080], 5: [540, 1080], 6: [540, 1080]], tatiller: [])

        // Telefonla gelen müşteri: yarın 10:30'da aranacak.
        var t = ElleTalep()
        t.ad = "  Ayşe   Kaya "; t.telefon = "0532 444 55 66"; t.sonra = true; t.tarih = Tr.gunEkle(bugun, 1); t.saat = "10:30"; t.onay = true
        let r = t.kayit(bugun: bugun, mesai: mesai)
        XCTAssertEqual(r.hatalar, [])
        try await ben.isle(ElleTalep.yazimlar(try XCTUnwrap(r.alanlar), calisan: c))
        var bos = ElleTalep()
        bos.ad = "A"
        XCTAssertEqual(bos.kayit(bugun: bugun, mesai: mesai).hatalar.count, 3, "ad, telefon, KVKK")

        let _a = try await ben.belge("armutTalepleri/armut_a\(ek)")
        let a = ArmutIsi(kimlik: "armut_a\(ek)", alanlar: try XCTUnwrap(_a))
        XCTAssertTrue(a.talepNotu.contains("Teklifimiz: 2.500 ₺ · Armut durumu: Teklif verildi"))
        try await ben.isle(ArmutIsi.durumYazimlari(a, "incelendi", calisan: c))
        try await ben.isle([ArmutIsi.guncelle(a, icNot: "Akşam aranacak", calisan: c)])
        var gorusme = ElleTalep()
        gorusme.onay = true
        let ak = ArmutIsi.aktar(a, talep: gorusme, bugun: bugun, mesai: mesai, calisan: c)
        XCTAssertEqual(ak.hatalar, [])
        try await ben.isle(ak.yazimlar)
        let _a2 = try await ben.belge("armutTalepleri/armut_a\(ek)")
        let a2 = ArmutIsi(kimlik: a.id, alanlar: try XCTUnwrap(_a2))
        XCTAssertEqual(a2.incelemeDurum, "aktarildi")
        XCTAssertEqual(a2.icNot, "Akşam aranacak")
        XCTAssertEqual(a2.aktaranKisi, "Aleyna Yılmaz (armut\(ek))")
        let _t = try await ben.belge("callback/\(a2.talepId)")
        let talep = try XCTUnwrap(_t)
        XCTAssertEqual(talep["status"], .metin("reached"))
        XCTAssertEqual(talep["armutIsId"], .metin("a\(ek)"))

        // Telefonu açılmamış iş: iletişim Armut'tan (telefon boş, kanal yok).
        let _b = try await ben.belge("armutTalepleri/armut_b\(ek)")
        let b = ArmutIsi(kimlik: "armut_b\(ek)", alanlar: try XCTUnwrap(_b))
        let bk = ArmutIsi.aktar(b, talep: gorusme, bugun: bugun, mesai: mesai, calisan: c)
        XCTAssertEqual(bk.hatalar, [])
        try await ben.isle(bk.yazimlar)

        // Müşteri arşivinden Talepler'e geri alma (kaynak: arsiv).
        let arsiv = ArsivKaydi(kimlik: "arsiv\(ek)", alanlar: ["ad": .metin("Ece"), "soyad": .metin("Su"), "telefon": .metin("+905321234567"),
                                                             "eposta": .metin("ece@ornek.com"), "takipKodu": .metin("2025-111111"), "sonStatu": .metin("Vize onaylandı")])
        let ga = arsiv.talebeAl(bugun: bugun, mesai: mesai, calisan: c)
        XCTAssertEqual(ga.hatalar, [])
        try await ben.isle(ga.yazimlar)
    }

    /// Ayarlar (yönetici): mesai ve tatil, genel (hesaplar korunur), izinler, kasa listeleri, bildirim ve SMS; çalışan yazamaz.
    func testAyarlar() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let owner = e.istemci("owner")
        let yon = try await e.hesapAc("ayar\(ek)", "gizli-sifre-1")
        let cal = try await e.hesapAc("cal\(ek)", "gizli-sifre-2")
        try await owner.belgeYaz("employees/\(yon)", alanlar: [
            "username": .metin("ayar\(ek)"), "displayName": .metin("Sefa"), "role": .metin("admin"), "active": .mantik(true)])
        try await owner.belgeYaz("employees/\(cal)", alanlar: [
            "username": .metin("cal\(ek)"), "displayName": .metin("Ezgi"), "role": .metin("writer"), "active": .mantik(true)])
        try await owner.belgeYaz("settings/general", alanlar: [
            "retentionDays": .tam(60), "firmaHesaplar": .dizi([.harita(["id": .metin("h1"), "platform": .metin("Instagram"), "kullaniciAdi": .metin("vizemiacom")])]),
        ])
        let o = try await e.kimlik.giris(kullaniciAdi: "ayar\(ek)", sifre: "gizli-sifre-1")
        let ben = e.istemci(o.belirtec)
        let _c = try await ben.belge("employees/\(yon)")
        let c = Calisan(uid: yon, belge: try XCTUnwrap(_c), izinBelgesi: nil)

        var m = Mesai.varsayilan
        m.calisma[6] = nil
        m.tatiller = ["2026-12-31", "2026-10-29"]
        XCTAssertEqual(Ayarlar.mesaiHatalari(m), [])
        XCTAssertEqual(Ayarlar.mesaiTekSatir(m), "Hafta içi 09:00–18:00")
        try await ben.isle(Ayarlar.mesaiYaz(m, calisan: c))
        let _m = try await ben.belge("settings/mesai")
        let okunan = Ayarlar.mesai(belge: _m)
        XCTAssertNil(okunan.calisma[6])
        XCTAssertEqual(okunan.calisma[1], [540, 1080])
        XCTAssertEqual(okunan.tatiller, ["2026-10-29", "2026-12-31"])
        var bozuk = m
        bozuk.calisma[2] = [600, 540]
        XCTAssertFalse(Ayarlar.mesaiHatalari(bozuk).isEmpty)

        var g = Ayarlar.Genel(belge: try await ben.belge("settings/general"))
        g.bosDakika = 45
        g.firmaTelefon = "0549 907 25 23"
        XCTAssertEqual(g.hatalar, [])
        try await ben.isle(Ayarlar.genelYaz(g, calisan: c))
        let _g = try await ben.belge("settings/general")
        XCTAssertEqual(_g?["idleMinutes"], .tam(45))
        XCTAssertNotNil(_g?["firmaHesaplar"], "sosyal medya hesapları korunur")

        var r = Ayarlar.rolIzinleri(belge: nil)
        r["intern"]?.insert("kasa.gider")
        try await ben.isle(Ayarlar.izinleriYaz(r, calisan: c))
        let _p = try await ben.belge("settings/permissions")
        XCTAssertTrue(Ayarlar.rolIzinleri(belge: _p)["intern"]?.contains("kasa.gider") ?? false)

        let k = Ayarlar.kasaListeleriYaz(musteri: ["Fotokopi", " Fotokopi "], genel: ["Market"], burolar: ["Kızılay Döviz"], raporSaati: "19:30", calisan: c)
        XCTAssertNil(k.hata)
        try await ben.isle(k.yazimlar)
        let _k = try await ben.belge("settings/kasa")
        XCTAssertEqual(KasaAyari(alanlar: _k).musteriGiderleri, ["Fotokopi"])
        XCTAssertNotNil(Ayarlar.kasaListeleriYaz(musteri: ["a"], genel: ["b"], burolar: [], raporSaati: "25:00", calisan: c).hata)
        try await ben.isle(Ayarlar.bildirimYaz(acik: false, pencereBas: 9, pencereSon: 21, calisan: c).yazimlar)
        try await ben.isle(Ayarlar.smsYaz(acik: true, calisan: c))
        let _b = try await ben.belge("settings/bildirim")
        XCTAssertEqual(BildirimAyari(belge: _b).acik, false)

        let co = try await e.kimlik.giris(kullaniciAdi: "cal\(ek)", sifre: "gizli-sifre-2")
        let calIst = e.istemci(co.belirtec)
        do { try await calIst.isle(Ayarlar.smsYaz(acik: false, calisan: c)); XCTFail("yalnız yönetici") } catch {}
    }
}
