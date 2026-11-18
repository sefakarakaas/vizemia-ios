import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import VizeMiaCekirdek

/// Çalışan girişi ve talep işlemleri, sitenin GERÇEK güvenlik kurallarıyla.
/// Yalnız Firestore ve Auth emülatörleri açıkken çalışır:
///   npx firebase-tools emulators:exec --only firestore,auth --project demo-vizemia "swift test"
final class EkipEmulatorTests: XCTestCase {
    var fs: String = ""
    var authTaban: String = ""
    let proje = "demo-vizemia"

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let f = env["FIRESTORE_EMULATOR_HOST"], let a = env["FIREBASE_AUTH_EMULATOR_HOST"] else {
            throw XCTSkip("Emülatör yok.")
        }
        fs = f; authTaban = a
    }

    var kimlik: KimlikIstemci {
        KimlikIstemci(kimlikTaban: "http://\(authTaban)/identitytoolkit.googleapis.com/v1",
                      belirtecTaban: "http://\(authTaban)/securetoken.googleapis.com/v1")
    }

    func istemci(_ b: String?) -> FirestoreIstemci {
        FirestoreIstemci(taban: URL(string: "http://\(fs)/v1")!, proje: proje, belirtec: b)
    }

    /// Auth emülatöründe kullanıcı açar; uid döner.
    func hesapAc(_ ad: String, _ sifre: String) async throws -> String {
        var i = URLRequest(url: URL(string: "http://\(authTaban)/identitytoolkit.googleapis.com/v1/accounts:signUp?key=x")!)
        i.httpMethod = "POST"
        i.setValue("application/json", forHTTPHeaderField: "Content-Type")
        i.httpBody = try JSONSerialization.data(withJSONObject: ["email": "\(ad)@panel.vizemia.local", "password": sifre, "returnSecureToken": true])
        let (v, _) = try await Ag.gonder(i, oturum: .shared)
        let j = try JSONSerialization.jsonObject(with: v) as! [String: Any]
        return j["localId"] as! String
    }

    func testGirisOkumaVeDurumDegistirme() async throws {
        let ek = String(Int.random(in: 1000...9999))
        let yonetici = istemci("owner")   // emülatörde kuralları atlayan belirteç: örnek veri için
        let uid = try await hesapAc("sefa\(ek)", "gizli-sifre-1")
        let okurUid = try await hesapAc("okur\(ek)", "gizli-sifre-2")
        try await yonetici.belgeYaz("employees/\(uid)", alanlar: [
            "username": .metin("sefa\(ek)"), "displayName": .metin("Sefa Karakaş"), "role": .metin("writer"), "active": .mantik(true)])
        try await yonetici.belgeYaz("employees/\(okurUid)", alanlar: [
            "username": .metin("okur\(ek)"), "displayName": .metin("Okur"), "role": .metin("reader"), "active": .mantik(true)])
        try await yonetici.belgeYaz("settings/permissions", alanlar: ["roles": .harita([
            "writer": .dizi(Calisan.varsayilanIzinler["writer"]!.map { .metin($0) }),
            "reader": .dizi(Calisan.varsayilanIzinler["reader"]!.map { .metin($0) }),
        ])])
        try await yonetici.belgeYaz("callback/cb\(ek)", alanlar: [
            "name": .metin("Ali Veli"), "phone": .metin("+905321112233"), "email": .metin(""), "country": .metin("almanya"),
            "countryName": .metin("Almanya"), "mode": .metin("saat"), "date": .metin("2026-11-17"), "times": .dizi([.metin("10:00")]),
            "message": .metin(""), "channels": .harita(["wa": .mantik(true), "sms": .mantik(false), "email": .mantik(false)]),
            "consent": .mantik(true), "status": .metin("new"), "createdAt": .zaman(Date())])
        try await yonetici.belgeYaz("support/sp\(ek)", alanlar: [
            "name": .metin("Ayşe"), "email": .metin("a@b.co"), "subject": .metin("Soru"), "message": .metin("Merhaba"),
            "consent": .mantik(true), "status": .metin("new"), "createdAt": .zaman(Date())])

        // Yanlış şifre
        do {
            _ = try await kimlik.giris(kullaniciAdi: "sefa\(ek)", sifre: "yanlis")
            XCTFail("girmemeliydi")
        } catch let h as KimlikIstemci.Hata {
            XCTAssertEqual(h, .bilgilerYanlis)
        }

        // Giriş, yenileme
        var o = try await kimlik.giris(kullaniciAdi: "  SEFA\(ek) ", sifre: "gizli-sifre-1")
        XCTAssertEqual(o.uid, uid)
        o = try await kimlik.yenile(o)
        XCTAssertEqual(o.uid, uid)
        let ben = istemci(o.belirtec)

        // Çalışan kaydı ve izinler
        let emp = try await ben.belge("employees/\(uid)")
        let izin = try await ben.belge("settings/permissions")
        let calisan = Calisan(uid: uid, belge: try XCTUnwrap(emp), izinBelgesi: izin)
        XCTAssertEqual(calisan.ilkAd, "Sefa")
        XCTAssertTrue(calisan.yapabilir("lead.manage"))

        // Açık talepler (panelle aynı sorgu)
        let liste = try await ben.sorgu(koleksiyon: "callback", kosullar: [.icinde("status", Talep.acikDurumlar.map { .metin($0) })],
                                        sirala: ("createdAt", .azalan))
        let talep = try XCTUnwrap(liste.map { Talep(tur: .geriArama, kimlik: $0.kimlik, alanlar: $0.alanlar) }.first { $0.kimlik == "cb\(ek)" })
        XCTAssertEqual(talep.ad, "Ali Veli")

        // Durum değiştir + işlem kaydı (kurallar handledAt == request.time, handledBy == uid istiyor)
        try await ben.guncelle(talep.yol, alanlar: Talep.durumAlanlari(durum: "called", icNot: "Açmadı", uid: uid), zamanAlanlari: ["handledAt"])
        try await ben.ekle(koleksiyon: "audit", alanlar: IslemKaydi.alanlar(eylem: "callback.update", hedef: talep.kimlik, ayrinti: "called", calisan: calisan), zamanAlani: "at")
        let sonraBelge = try await ben.belge(talep.yol)
        let sonra = try XCTUnwrap(sonraBelge)
        XCTAssertEqual(sonra["status"], .metin("called"))
        XCTAssertEqual(sonra["internalNote"], .metin("Açmadı"))
        XCTAssertNotNil(sonra["handledAt"]?.zamanDegeri)

        // İptal (sebep zorunlu alan)
        try await ben.guncelle(talep.yol, alanlar: Talep.durumAlanlari(durum: "cancelled", icNot: "", iptalSebebi: "Mükerrer talep", uid: uid), zamanAlanlari: ["handledAt"])

        // Destek talebi
        let destek = try await ben.sorgu(koleksiyon: "support", kosullar: [.esit("status", .metin("new"))], sirala: ("createdAt", .azalan))
        XCTAssertTrue(destek.contains { $0.kimlik == "sp\(ek)" })
        try await ben.guncelle("support/sp\(ek)", alanlar: DestekTalebi.durumAlanlari(durum: "open", icNot: "Arandı", uid: uid), zamanAlanlari: ["handledAt"])

        // İzleyici (reader) okuyabilir ama değiştiremez
        let okur = istemci(try await kimlik.giris(kullaniciAdi: "okur\(ek)", sifre: "gizli-sifre-2").belirtec)
        _ = try await okur.belge(talep.yol)
        do {
            try await okur.guncelle(talep.yol, alanlar: Talep.durumAlanlari(durum: "reached", icNot: "", uid: okurUid), zamanAlanlari: ["handledAt"])
            XCTFail("izleyici değiştirememeliydi")
        } catch {
            XCTAssertEqual(error as? FirestoreHatasi, .izinYok)
        }

        // Girişsiz okuma reddedilir
        do {
            _ = try await istemci(nil).belge(talep.yol)
            XCTFail("girişsiz okunmamalıydı")
        } catch {
            XCTAssertEqual(error as? FirestoreHatasi, .izinYok)
        }
    }
}

extension EkipEmulatorTests {
    /// Şifre değiştirme: yanlış mevcut şifre reddedilir; değişince yeni şifreyle giriş olur.
    func testSifreDegistirme() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let a = env["FIREBASE_AUTH_EMULATOR_HOST"] else { throw XCTSkip("Emülatör yok.") }
        let k = KimlikIstemci(kimlikTaban: "http://\(a)/identitytoolkit.googleapis.com/v1", belirtecTaban: "http://\(a)/securetoken.googleapis.com/v1")
        let ad = "sifre\(Int.random(in: 1000...9999))"
        var i = URLRequest(url: URL(string: "http://\(a)/identitytoolkit.googleapis.com/v1/accounts:signUp?key=x")!)
        i.httpMethod = "POST"
        i.setValue("application/json", forHTTPHeaderField: "Content-Type")
        i.httpBody = try JSONSerialization.data(withJSONObject: ["email": "\(ad)@panel.vizemia.local", "password": "Eski-sifre-123", "returnSecureToken": true])
        _ = try await Ag.gonder(i, oturum: .shared)
        XCTAssertNotNil(KimlikIstemci.sifreHatasi("kisa"))
        XCTAssertNotNil(KimlikIstemci.sifreHatasi("uzunamaozelyok1A"))
        XCTAssertNil(KimlikIstemci.sifreHatasi("Yeni-Sifre-2026!"))
        do { _ = try await k.sifreDegistir(kullaniciAdi: ad, mevcut: "yanlis-sifre", yeni: "Yeni-Sifre-2026!"); XCTFail("mevcut şifre yanlış") }
        catch let h as KimlikIstemci.Hata { XCTAssertEqual(h, .bilgilerYanlis) }
        let o = try await k.sifreDegistir(kullaniciAdi: ad, mevcut: "Eski-sifre-123", yeni: "Yeni-Sifre-2026!")
        XCTAssertFalse(o.belirtec.isEmpty)
        let yeni = try await k.giris(kullaniciAdi: ad, sifre: "Yeni-Sifre-2026!")
        XCTAssertEqual(yeni.uid, o.uid)
    }
}
