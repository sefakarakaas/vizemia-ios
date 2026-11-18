import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Sitenin panelden değişen içerikleri (süreç adımları, blog, SSS, vitrin,
// fotoğraf havuzu). Site statik: içerik Firestore'a yazılır, GitHub'daki
// "Test ve yayın" işi siteyi üretir. Kayıttan sonra iş hemen tetiklenir
// (panel: yayin.js); anahtar yoksa içerik en geç 6 saatte yayına çıkar.

public enum SiteYayini {
    static let api = "https://api.github.com/repos/sefakarakaas/VizeMia/actions/workflows/deploy.yml/dispatches"

    /// Yayın işini başlatan istek (gizli/github anahtarıyla; yalnız Actions yetkili, ince ayarlı anahtar).
    public static func istek(anahtar: String) -> URLRequest {
        var i = URLRequest(url: URL(string: api)!)
        i.httpMethod = "POST"
        i.timeoutInterval = 20
        i.setValue("Bearer \(anahtar)", forHTTPHeaderField: "Authorization")
        i.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        i.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        i.setValue("application/json", forHTTPHeaderField: "Content-Type")
        i.httpBody = try? JSONSerialization.data(withJSONObject: ["ref": "main", "inputs": ["kaynak": "panel"]])
        return i
    }

    public static func mesaj(basladi: Bool?) -> String {
        switch basladi {
        case .some(true): return "Kaydedildi. Sitede 2–3 dakika içinde görünecek."
        case .some(false): return "Kaydedildi ama yayın başlatılamadı; sitede en geç 6 saat içinde görünür."
        case .none: return "Kaydedildi. Otomatik yayın ayarlanmadığı için sitede en geç 6 saat içinde görünür."
        }
    }
}

/// Ana sayfadaki "5 adımda başvuru" bölümü (siteMetin/surec; panel: pages/surec.js).
public struct SurecAdimlari: Equatable {
    public struct Adim: Equatable, Identifiable {
        public var id = UUID()
        public var baslik: String
        public var metin: String
        public init(baslik: String, metin: String) { self.baslik = baslik; self.metin = metin }
        public static func == (a: Adim, b: Adim) -> Bool { a.baslik == b.baslik && a.metin == b.metin }
    }
    public static let enAz = 3
    public static let enFazla = 6

    public var baslik: String
    public var aciklama: String
    public var adimlar: [Adim]

    /// Belge hiç kaydedilmediyse sitede depodaki metin durur; bu onun aynısı.
    public static let varsayilan = SurecAdimlari(baslik: "5 adımda başvuru", aciklama: "", adimlar: [
        Adim(baslik: "Ön görüşme", metin: "Seyahat amacınızı, önceki vizelerinizi ve tarihlerinizi konuşur, size uygun vize türünü belirleriz."),
        Adim(baslik: "Belge listesi ve kontrol", metin: "Durumunuza özel belge listesini iletir, hazırladığınız evrakı tek tek kontrol ederiz."),
        Adim(baslik: "Form ve randevu", metin: "Başvuru formunu sizinle birlikte doldurur, randevu sürecini takip ederiz."),
        Adim(baslik: "Parmak izi / biyometri", metin: "Randevu günü başvuru merkezinde biyometrik verilerinizi verir, dosyanızı teslim edersiniz."),
        Adim(baslik: "Pasaport teslimi ve takip", metin: "Sonuçlanana kadar durumu takip eder, pasaportunuz geldiğinde size haber veririz."),
    ])

    public init(baslik: String, aciklama: String, adimlar: [Adim]) {
        self.baslik = baslik; self.aciklama = aciklama; self.adimlar = adimlar
    }

    public init(belge a: [String: FSDeger]?) {
        guard let a else { self = .varsayilan; return }
        baslik = a["baslik"]?.metinDegeri ?? ""
        aciklama = a["aciklama"]?.metinDegeri ?? ""
        adimlar = (a["adimlar"]?.diziDegeri ?? []).compactMap { d in
            d.haritaDegeri.map { Adim(baslik: $0["baslik"]?.metinDegeri ?? "", metin: $0["metin"]?.metinDegeri ?? "") }
        }
    }

    /// Kaydetmeden önce (boş: kaydedilebilir).
    public var hatalar: [String] {
        var h: [String] = []
        if adimlar.contains(where: { $0.baslik.kirpik.isEmpty }) { h.append("Her adımın bir başlığı olmalı.") }
        if adimlar.count < Self.enAz || adimlar.count > Self.enFazla { h.append("Adım sayısı \(Self.enAz) ile \(Self.enFazla) arasında olmalı.") }
        if baslik.kirpik.count < 2 { h.append("Bölüm başlığı boş olamaz.") }
        return h
    }

    public func yazimlar(calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let temiz = adimlar.map { FSDeger.harita(["baslik": .metin(String($0.baslik.kirpik.prefix(60))), "metin": .metin(String($0.metin.kirpik.prefix(300)))]) }
        return [
            .yaz(yol: "siteMetin/surec", alanlar: [
                "baslik": .metin(String(baslik.kirpik.prefix(80))), "aciklama": .metin(String(aciklama.kirpik.prefix(300))),
                "adimlar": .dizi(temiz), "updatedBy": .metin(c.uid),
            ], zaman: ["updatedAt"]),
            .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                     alanlar: IslemKaydi.alanlar(eylem: "siteMetin.surec", hedef: "surec", ayrinti: "\(adimlar.count) adım", calisan: c), zaman: ["at"]),
        ]
    }
}
