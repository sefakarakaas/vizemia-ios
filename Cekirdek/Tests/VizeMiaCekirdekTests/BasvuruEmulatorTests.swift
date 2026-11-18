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
}
