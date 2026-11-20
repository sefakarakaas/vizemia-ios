import Foundation
import Observation
import LocalAuthentication
import UIKit
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
            if calisan != nil { bekleyenWa = AnahtarZinciri.oku(WaTeyidi.self, servis: EkipOturumu.servis, hesap: "waTeyidi") }
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
            if durum == .yok {
                // Şifre doğruydu ama çalışan kaydı okunamadı (kota, bağlantı…): asıl sebep
                // gösterilir; "oturum sona erdi" demek yanıltıcı olur.
                let h = sonYuklemeHatasi ?? KimlikIstemci.Hata.oturumBitti
                cikis()
                throw h
            }
        } catch {
            if durum == .aciliyor { durum = .yok }
            throw error
        }
    }

    /// Şifre değiştirme (panel: Şifremi değiştir). Yeni oturum saklanır. Hata metni döner (nil: tamam).
    func sifreDegistir(mevcut: String, yeni: String) async -> String? {
        guard let c = calisan else { return "Oturum bulunamadı." }
        if let h = KimlikIstemci.sifreHatasi(yeni) { return h }
        do {
            let o = try await kimlik.sifreDegistir(kullaniciAdi: c.kullaniciAdi, mevcut: mevcut, yeni: yeni)
            oturum = o
            AnahtarZinciri.yaz(o, servis: EkipOturumu.servis, hesap: "oturum")
            try? await istemci().isle([.olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                                                alanlar: IslemKaydi.alanlar(eylem: "password.change", hedef: "", ayrinti: "", calisan: c),
                                                zaman: ["at"])])
            return nil
        } catch let h as KimlikIstemci.Hata {
            return h == .bilgilerYanlis ? "Mevcut şifre hatalı." : h.mesaj
        } catch {
            return "Şifre değiştirilemedi."
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
        // Başka bir çalışan girerse öncekinin sorusu ona sorulmasın.
        bekleyenWa = nil
        waSablonlari = nil
        AnahtarZinciri.sil(servis: EkipOturumu.servis, hesap: "waTeyidi")
        // Çıkan çalışanın telefonuna artık ekip bildirimi gitmesin.
        Task { await AnlikBildirimMerkezi.ortak.ekip(istemci: nil, calisan: nil) }
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
    /// Son yükleme hatası (girişte kullanıcıya asıl sebebi göstermek için).
    private var sonYuklemeHatasi: Error?

    func yukle() async {
        guard let o = oturum else { return }
        sonYuklemeHatasi = nil
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
            // Anlık bildirim: bu telefon danışmanın konularıyla kaydolur (izin ilk girişte sorulur).
            Task {
                await AnlikBildirimMerkezi.ortak.izinIsteVeKaydol()
                await AnlikBildirimMerkezi.ortak.ekip(istemci: { [weak self] in
                    guard let self else { throw KimlikIstemci.Hata.oturumBitti }
                    return try await self.istemci()
                }, calisan: c)
            }
            if let s = try? await f.sorgu(koleksiyon: "statuses", sinir: 100) {
                statuler = s.map { Statu(kimlik: $0.kimlik, alanlar: $0.alanlar) }.sorted { $0.sira < $1.sira }
            }
        } catch KimlikIstemci.Hata.oturumBitti {
            cikis()
        } catch {
            sonYuklemeHatasi = error
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

    /// Elle bildirim istekleri hemen gönderilsin (Apps Script → Bildirim.gs). Servis
    /// yoksa ya da ulaşılamazsa istek 10 dakikalık zamanlayıcıda gider.
    func bildirimHemen() async -> Bool {
        guard !kasaServisUrl.isEmpty, let u = URL(string: kasaServisUrl) else { return false }
        var i = URLRequest(url: u)
        i.httpMethod = "POST"
        i.timeoutInterval = 20
        i.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        i.httpBody = try? JSONSerialization.data(withJSONObject: ["tur": "bildirim"])
        return (try? await URLSession.shared.data(for: i)) != nil
    }

    /// gizli/github anahtarı (bir kez okunur). Boş: otomatik yayın ayarlanmamış.
    private var yayinAnahtari: String?

    /// İçerik kaydedilince sitenin yayın işini hemen başlatır (panel: siteyiGuncelle).
    /// - Returns: nil: anahtar yok (en geç 6 saatte yayına çıkar); true: başladı; false: başlatılamadı
    func siteyiGuncelle() async -> Bool? {
        if yayinAnahtari == nil {
            let b: [String: FSDeger]? = (try? await istemci().belge("gizli/github")) ?? nil
            yayinAnahtari = b?["token"]?.metinDegeri ?? ""
        }
        guard let t = yayinAnahtari, !t.isEmpty else { return nil }
        guard let (_, cevap) = try? await URLSession.shared.data(for: SiteYayini.istek(anahtar: t)) else { return false }
        return (cevap as? HTTPURLResponse)?.statusCode == 204
    }

    // MARK: - Görüşme rehberi

    /// settings/rehber (Ayarlar'dan kaydedilen); ilk açılışta bir kez okunur.
    private(set) var rehberBelgesi: [String: FSDeger]?
    private var rehberOkundu = false

    func rehberYukle() async {
        guard !rehberOkundu else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { rehberOkundu = true; return }
        #endif
        guard let f = try? await istemci() else { return }
        rehberBelgesi = (try? await f.belge("settings/rehber")) ?? nil
        rehberOkundu = true
    }

    // MARK: - WhatsApp teyidi ve hazır mesajlar

    /// Cevabı beklenen WhatsApp açılışı (panel: wa-teyit.js). Uygulama WhatsApp'ın
    /// gönderilip gönderilmediğini bilemez; danışmana sorar. Soru kapatılamaz ve
    /// Anahtar Zinciri'nde tutulur: uygulama kapansa da sonraki açılışta yeniden sorulur.
    private(set) var bekleyenWa: WaTeyidi?
    /// Her teyit kaydında artar; mesaj geçmişini gösteren ekran yeniden okur.
    private(set) var waTeyitSayaci = 0
    /// settings/wa; ilk gerektiğinde bir kez okunur.
    private(set) var waSablonlari: [WaSablonu]?

    /// wa.me'yi açar ve teyit sorusunu bekletir. Numara geçersizse false.
    func waAc(_ t: WaTeyidi) -> Bool {
        guard let u = MusteriMesaji.waBaglantisi(telefon: t.telefon, metin: t.metin) else { return false }
        bekleyenWa = t
        AnahtarZinciri.yaz(t, servis: Self.servis, hesap: "waTeyidi")
        UIApplication.shared.open(u)
        return true
    }

    /// "Gönderdim" / "Göndermedim": mesajKaydi'na yazılır. Hata metni döner (nil: tamam);
    /// yazılamazsa soru açık kalır, tekrar denenir.
    func waTeyitKaydet(gonderildi: Bool) async -> String? {
        guard let t = bekleyenWa, let c = calisan else { return "Oturum bulunamadı." }
        if let y = MusteriMesaji.waTeyidi(t, gonderildi: gonderildi, calisan: c) {
            #if DEBUG
            let ornek = ProcessInfo.processInfo.arguments.contains("-ornek-ekip")
            #else
            let ornek = false
            #endif
            if !ornek {
                do { try await istemci().isle(y) } catch {
                    return HataAciklamasi.metin(error, "Kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.")
                }
            }
        }
        bekleyenWa = nil
        AnahtarZinciri.sil(servis: Self.servis, hesap: "waTeyidi")
        waTeyitSayaci += 1
        return nil
    }

    func waSablonlariYukle() async {
        guard waSablonlari == nil else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { waSablonlari = WaSablonu.liste(belge: nil); return }
        #endif
        let b: [String: FSDeger]? = (try? await istemci().belge("settings/wa")) ?? nil
        waSablonlari = WaSablonu.liste(belge: b)
    }

    /// Hazır WhatsApp/SMS mesajlarını kaydeder (yönetici ve lead.manage). Hata metni ya da nil.
    func waSablonlariKaydet(_ l: [WaSablonu]) async -> String? {
        guard let c = calisan else { return "Oturum bulunamadı." }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { waSablonlari = l; return nil }
        #endif
        do {
            let f = try await istemci()
            try await f.isle(WaSablonu.kaydet(l, calisan: c))
            let b: [String: FSDeger]? = (try? await f.belge("settings/wa")) ?? nil
            waSablonlari = WaSablonu.liste(belge: b)
            return nil
        } catch {
            return HataAciklamasi.metin(error, "Kaydedilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.")
        }
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
