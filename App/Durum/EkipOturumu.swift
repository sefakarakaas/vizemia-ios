import Foundation
import Observation
import LocalAuthentication
import VizeMiaCekirdek

/// Çalışan oturumu: panelin kullanıcı adı ve şifresiyle bir kez girilir,
/// oturum Anahtar Zinciri'nde saklanır. Panel 30 dakika işlem yapılmayınca
/// oturumu kapatıyor (Ayarlar → idleMinutes); uygulamada bunun yerine o süre
/// geçince ekip ekranları Face ID / cihaz şifresiyle kilitlenir: şifre yeniden
/// sorulmaz, ama telefonu eline alan biri pasaport bilgilerini göremez.
@MainActor
@Observable
final class EkipOturumu {
    enum Durum: Equatable {
        case yok
        case aciliyor
        case acik
        /// Hesap pasif ya da çalışan kaydı yok.
        case yetkisiz
    }

    private(set) var durum: Durum = .yok
    private(set) var calisan: Calisan?
    private(set) var statuler: [Statu] = []
    /// Face ID beklemede: ekip ekranları gizli.
    private(set) var kilitli = false
    /// Uygulamanın ekip görünümünde mi açılacağı (müşteri görünümüne geçilebilir).
    var ekipGorunumu = true

    private var oturum: KimlikIstemci.Oturum?
    private var arkaPlanaGecis: Date?
    private var bosDakika = 30
    private let kimlik = KimlikIstemci()

    private static let servis = "com.vizemia.app.ekip"

    var girisli: Bool { durum == .acik && calisan != nil }
    var statuSozlugu: [String: Statu] { Dictionary(statuler.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") {
            calisan = Calisan(uid: "ornek", belge: ["username": .metin("sefa"), "displayName": .metin("Sefa Karakaş"),
                                                    "role": .metin("admin"), "active": .mantik(true)], izinBelgesi: nil)
            durum = .acik
            return
        }
        #endif
        if let o = AnahtarZinciri.oku(KimlikIstemci.Oturum.self, servis: EkipOturumu.servis, hesap: "oturum") {
            oturum = o
            calisan = AnahtarZinciri.oku(Calisan.self, servis: EkipOturumu.servis, hesap: "calisan")
            durum = calisan == nil ? .aciliyor : .acik
            // Uygulama yeniden açıldı: kilitli başlar (Face ID).
            kilitli = calisan != nil
            Task { await yukle() }
        }
    }

    /// Kullanıcı adı ve şifreyle giriş.
    func giris(kullaniciAdi: String, sifre: String) async throws {
        durum = .aciliyor
        do {
            let o = try await kimlik.giris(kullaniciAdi: kullaniciAdi, sifre: sifre)
            oturum = o
            AnahtarZinciri.yaz(o, servis: EkipOturumu.servis, hesap: "oturum")
            kilitli = false
            ekipGorunumu = true
            await yukle()
            if durum == .yok { throw KimlikIstemci.Hata.oturumBitti }
        } catch {
            if durum == .aciliyor { durum = .yok }
            throw error
        }
    }

    func cikis() {
        oturum = nil
        calisan = nil
        statuler = []
        durum = .yok
        kilitli = false
        AnahtarZinciri.sil(servis: EkipOturumu.servis, hesap: "oturum")
        AnahtarZinciri.sil(servis: EkipOturumu.servis, hesap: "calisan")
    }

    /// Geçerli belirteçle Firestore istemcisi (gerekirse yeniler).
    func istemci() async throws -> FirestoreIstemci {
        guard var o = oturum else { throw KimlikIstemci.Hata.oturumBitti }
        if o.eskidi() {
            do {
                o = try await kimlik.yenile(o)
                oturum = o
                AnahtarZinciri.yaz(o, servis: EkipOturumu.servis, hesap: "oturum")
            } catch KimlikIstemci.Hata.oturumBitti {
                cikis()
                throw KimlikIstemci.Hata.oturumBitti
            }
        }
        return FirestoreIstemci(belirtec: o.belirtec)
    }

    /// Çalışan kaydını, izinleri, statüleri ve boşta kalma süresini okur.
    func yukle() async {
        guard let o = oturum else { return }
        do {
            let f = try await istemci()
            async let emp = f.belge("employees/\(o.uid)")
            async let izin = f.belge("settings/permissions")
            async let genel = f.belge("settings/general")
            guard let e = try await emp else { durum = .yetkisiz; return }
            let c = Calisan(uid: o.uid, belge: e, izinBelgesi: try? await izin)
            guard c.aktif else { durum = .yetkisiz; calisan = c; return }
            calisan = c
            AnahtarZinciri.yaz(c, servis: EkipOturumu.servis, hesap: "calisan")
            if let g = try? await genel, let d = g["idleMinutes"]?.tamDegeri, d >= 1 { bosDakika = d }
            durum = .acik
            if let s = try? await f.sorgu(koleksiyon: "statuses", sinir: 100) {
                statuler = s.map { Statu(kimlik: $0.kimlik, alanlar: $0.alanlar) }.sorted { $0.sira < $1.sira }
            }
        } catch KimlikIstemci.Hata.oturumBitti {
            cikis()
        } catch {
            // Bağlantı yok: saklanan çalışan kaydıyla devam edilir.
            if calisan != nil { durum = .acik } else if durum == .aciliyor { durum = .yok }
        }
    }

    func yapabilir(_ izin: String) -> Bool { calisan?.yapabilir(izin) ?? false }

    // MARK: - Face ID kilidi

    func arkaPlanaGecti() { arkaPlanaGecis = Date() }

    /// Uygulama öne geldi: boşta kalma süresi dolduysa kilitle.
    func oneGeldi() {
        guard girisli, let g = arkaPlanaGecis else { return }
        arkaPlanaGecis = nil
        if Date().timeIntervalSince(g) > Double(bosDakika) * 60 { kilitli = true }
    }

    func kilidiAc() async {
        let b = LAContext()
        b.localizedCancelTitle = "Vazgeç"
        var hata: NSError?
        guard b.canEvaluatePolicy(.deviceOwnerAuthentication, error: &hata) else {
            // Cihazda şifre/Face ID yok: kilit uygulanamaz.
            kilitli = false
            return
        }
        do {
            if try await b.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Ekip ekranlarını açmak için") {
                kilitli = false
            }
        } catch {
            // Vazgeçildi: kilitli kalır.
        }
    }
}
