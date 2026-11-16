import Foundation
import Observation
import VizeMiaCekirdek

/// "Beni unutma" diyen müşteri: takip bilgisi ve son görülen durum.
///
/// Düğmeye basan müşteri için uygulama her açılışta adıyla karşılar, Takip
/// sekmesi doğrudan süreci gösterir ve aşama değişince bildirim gelir.
/// Basmayan için hiçbir şey saklanmaz.
@MainActor
@Observable
final class TakipHafizasi {
    /// Hatırlanan başvuru; nil ise kimse hatırlanmıyor.
    private(set) var kayit: Kasa.Kayit?
    /// Müşterinin henüz görmediği bir değişiklik var (Takip sekmesindeki rozet).
    private(set) var yeniVar = false
    /// Kayıt sunucuda artık yok (işlem bittikten sonra saklama süresi dolunca silinir).
    private(set) var silinmis = false
    private(set) var yenileniyor = false

    private var sonYenileme: Date?
    /// Ekran testleri için örnek kayıt (yalnız geliştirme derlemesinde): ağa ve
    /// Anahtar Zinciri'ne dokunulmaz.
    private let ornek: Bool

    var hatirlaniyor: Bool { kayit != nil }
    var son: TakipKaydi? { kayit?.son }

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-takip") {
            ornek = true
            kayit = Kasa.Kayit(kod: "2026-110001", pasaport: "U00000000", son: TakipHafizasi.ornekKayit)
            return
        }
        #endif
        ornek = false
        kayit = Kasa.oku()
    }

    /// Sorgulanan başvuruyu bu telefonda hatırlar.
    func hatirla(kod: String, pasaport: String, son: TakipKaydi) {
        let k = Kasa.Kayit(kod: kod, pasaport: pasaport, son: son)
        kayit = k
        silinmis = false
        yeniVar = false
        sonYenileme = Date()
        if !ornek { Kasa.yaz(k) }
    }

    /// Kayıtlı bilgiyi siler; bildirim de gelmez.
    func unut() {
        kayit = nil
        silinmis = false
        yeniVar = false
        if !ornek { Kasa.sil() }
        Bildirimler.planiIptalEt()
        Bildirimler.rozetiSil()
    }

    /// Takip sekmesi açıldı: değişiklik görüldü.
    func goruldu() {
        yeniVar = false
        Bildirimler.rozetiSil()
    }

    /// Arka plandaki denetim kaydı güncellemiş olabilir; uygulama öne gelince diskteki okunur.
    func disktenOku() {
        guard !ornek, let k = kayit, let disk = Kasa.oku(), disk.kod == k.kod, disk.son != k.son else { return }
        if let eski = k.son, let yeni = disk.son, yeni.bildirim(onceki: eski) != nil { yeniVar = true }
        kayit = disk
    }

    /// Durumu sunucudan tazeler. `zorla` değilse dakikada en çok bir kez.
    func yenile(zorla: Bool = false) async {
        guard !ornek, let k = kayit, !yenileniyor else { return }
        if !zorla, let s = sonYenileme, Date().timeIntervalSince(s) < 60 { return }
        sonYenileme = Date()
        yenileniyor = true
        defer { yenileniyor = false }
        switch await TakipHafizasi.sor(k) {
        case .guncel(let yeni):
            // Araya "beni unut" ya da başka bir başvuru girdiyse eski cevap yazılmaz.
            guard kayit?.kod == k.kod, kayit?.pasaport == k.pasaport else { return }
            silinmis = false
            if let eski = k.son, yeni.bildirim(onceki: eski) != nil { yeniVar = true }
            var guncel = k
            guncel.son = yeni
            kayit = guncel
            Kasa.yaz(guncel)
        case .yok:
            if kayit?.kod == k.kod { silinmis = true }
        case .hata:
            break   // bağlantı yok: eldeki durum kalır
        }
    }

    enum Cevap {
        case guncel(TakipKaydi)
        case yok
        case hata
    }

    /// Kaydın güncel hâlini Firestore'dan okur.
    nonisolated static func sor(_ k: Kasa.Kayit) async -> Cevap {
        do {
            let kimlik = Takip.kimlik(kod: k.kod, pasaport: k.pasaport)
            guard let belge = try await FirestoreIstemci().belge("takip/\(kimlik)") else { return .yok }
            return .guncel(TakipKaydi(belge: belge))
        } catch {
            return .hata
        }
    }

    /// Arka plan görevi: uygulama kapalıyken durum denetlenir; son görülenden
    /// farklıysa bildirim gösterilir.
    nonisolated static func arkaPlandaDenetle() async {
        Bildirimler.sonrakiDenetimiPlanla()
        guard var k = Kasa.oku() else { return }
        guard case .guncel(let yeni) = await sor(k) else { return }
        let bildirim = k.son.flatMap { yeni.bildirim(onceki: $0) }
        k.son = yeni
        Kasa.yaz(k)
        if let b = bildirim { await Bildirimler.gonder(b) }
    }

    #if DEBUG
    static let ornekKayit = TakipKaydi(
        ulke: "Almanya", ad: "AHMET", durum: "Randevunuz alındı",
        aciklama: "Randevu bilgileriniz size iletildi.", renk: "#5a4f9c", bitti: false,
        notlar: [TakipKaydi.Not(id: 0, metin: "Randevunuz 3 Aralık 10:30. Evraklarınızın asıllarını yanınızda getirin.", tarih: Date())],
        asamalar: ["Görüşme", "Randevu takibi", "Randevu alındı", "Evraklar", "Parmak izi", "Konsoloslukta", "Sonuç", "Teslim"],
        asama: 2, guncelleme: Date())
    #endif
}
