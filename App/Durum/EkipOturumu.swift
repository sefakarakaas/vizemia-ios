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
    /// Ayarlar (panel: loadSettings). Son adımdan sonra saklama süresi ve
    /// "yakında silinecek" uyarısının gün sayısı (settings/general).
    private(set) var saklamaGun = 60
    private(set) var uyariGun = 7
    private(set) var evrakAyari = EvrakAyari(belge: nil)
    private(set) var epostaAyari = EpostaAyari(belge: nil)
    private(set) var smsAyari = SmsAyari(belge: nil)
    /// Kasa bildirimi (Ayarlar → Kasa ve raporlar → servis adresi): ödeme girilince ekibe haber.
    private(set) var kasaServisUrl = ""
    /// Ayarlar → Kasa ve raporlar: gider kategorileri, döviz büroları, rapor saati.
    private(set) var kasaAyari = KasaAyari()
    /// Ayarlar → Genel: firmanın telefonu, e-postası, web adresi, adresi (firma cevap mailinin altbilgisi).
    private(set) var firmaIletisimi = FirmaIletisimi()
    /// Ayarlar → Randevu konumları (harita bağlantıları) ve otomatik bildirim ayarı.
    private(set) var konumlar = KonumAyari(belge: nil)
    private(set) var bildirimAyari = BildirimAyari(belge: nil)
    /// Ayarlar → Ülke formları (settings/forms → countries): kapalı / zorunlu alanlar, ek sorular.
    private(set) var ulkeFormlari: [String: UlkeFormu] = [:]

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
            statuler = OrnekEkip.statuler
            smsAyari = SmsAyari(belge: ["enabled": .mantik(true)])
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
            async let evrak = f.belge("settings/checklist")
            async let eposta = f.belge("settings/eposta")
            async let sms = f.belge("settings/sms")
            async let kasa = f.belge("settings/kasa")
            async let konum = f.belge("settings/konumlar")
            async let bildirim = f.belge("settings/bildirim")
            async let formlar = f.belge("settings/forms")
            guard let e = try await emp else { durum = .yetkisiz; return }
            let c = Calisan(uid: o.uid, belge: e, izinBelgesi: try? await izin)
            guard c.aktif else { durum = .yetkisiz; calisan = c; return }
            calisan = c
            AnahtarZinciri.yaz(c, servis: EkipOturumu.servis, hesap: "calisan")
            if let g = try? await genel {
                if let d = g["idleMinutes"]?.tamDegeri, d >= 1 { bosDakika = d }
                if let d = g["retentionDays"]?.tamDegeri, d >= 1 { saklamaGun = d }
                if let d = g["warnDays"]?.tamDegeri, d >= 1 { uyariGun = d }
                firmaIletisimi = FirmaIletisimi(genel: g)
            }
            evrakAyari = EvrakAyari(belge: try? await evrak)
            epostaAyari = EpostaAyari(belge: try? await eposta)
            smsAyari = SmsAyari(belge: try? await sms)
            konumlar = KonumAyari(belge: (try? await konum) ?? nil)
            bildirimAyari = BildirimAyari(belge: (try? await bildirim) ?? nil)
            let ulkeler = ((try? await formlar) ?? nil)?["countries"]?.haritaDegeri ?? [:]
            ulkeFormlari = ulkeler.compactMapValues { $0.haritaDegeri.map { UlkeFormu(alanlar: $0) } }
            let kasaBelgesi: [String: FSDeger]? = (try? await kasa) ?? nil
            kasaAyari = KasaAyari(alanlar: kasaBelgesi)
            let k = kasaBelgesi?["servisUrl"]?.metinDegeri?.trimmingCharacters(in: .whitespaces) ?? ""
            kasaServisUrl = k.range(of: "^https://script\\.google\\.com/macros/s/[\\w-]+/exec$", options: .regularExpression) != nil ? k : ""
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

    /// Ödeme kaydı ekibe bildirilsin (panel: kasa-servis.js → kasaBildir). Cevap beklenmez.
    func kasaBildir(_ id: String) {
        guard !kasaServisUrl.isEmpty, let u = URL(string: kasaServisUrl) else { return }
        var i = URLRequest(url: u)
        i.httpMethod = "POST"
        i.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        i.httpBody = try? JSONSerialization.data(withJSONObject: ["tur": "kasa", "id": id])
        URLSession.shared.dataTask(with: i).resume()
    }

    /// Elle gönderilen mailleri hemen yollatır (panel: epostaHemenGonder): servis
    /// kuyruktakileri kendisi okur, günlük sınıra uyar. Servis adresi yoksa ya da
    /// ulaşılamazsa mail kaybolmaz; zamanlanmış görev 15 dakika içinde gönderir.
    /// - Returns: servis adresi var ve istek gönderildi mi
    func epostaHemen() async -> Bool {
        guard !kasaServisUrl.isEmpty, let u = URL(string: kasaServisUrl) else { return false }
        var i = URLRequest(url: u)
        i.httpMethod = "POST"
        i.timeoutInterval = 20
        i.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        i.httpBody = try? JSONSerialization.data(withJSONObject: ["tur": "eposta"])
        return (try? await URLSession.shared.data(for: i)) != nil
    }

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
