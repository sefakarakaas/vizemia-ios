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

/// Ana sayfadaki kayan slayt (vitrin/{id}; panel: pages/vitrin.js).
public struct VitrinSlayti: Equatable, Identifiable {
    /// "Düğme nereye gitsin?" hazır seçenekleri.
    public static let baglantilar: [(yol: String, ad: String)] = [
        ("/basvuru", "Başvuru sayfası (Sizi Arayalım)"), ("#randevu", "Arama formu (ana sayfa)"), ("#ulkeler", "Ülke seçimi (ana sayfa)"),
        ("#rehber", "Randevu günü rehberi (ana sayfa)"), ("#sss", "Sıkça sorulan sorular (ana sayfa)"), ("/blog", "Blog"), ("/takip", "Başvuru takibi"),
    ]

    public var id: String
    public var ust = ""
    public var baslik = ""
    public var metin = ""
    public var dugme = "Başvur"
    public var link = "/basvuru"
    public var gorsel = ""
    public var havuzFoto = ""
    public var odak = ""
    public var ulke = ""
    public var baslangic = ""
    public var bitis = ""
    public var sira = 10
    public var durum = "taslak"
    public var guncelleme: Date?
    public var kayitli = false

    public init(id: String = FirestoreIstemci.yeniKimlik()) { self.id = id }

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        func m(_ k: String) -> String { a[k]?.metinDegeri ?? "" }
        id = kimlik
        ust = m("ust"); baslik = m("baslik"); metin = m("metin"); dugme = m("dugme"); link = m("link")
        gorsel = m("gorsel"); havuzFoto = m("havuzFoto"); odak = m("odak"); ulke = m("ulke")
        baslangic = m("baslangic"); bitis = m("bitis"); sira = a["sira"]?.tamDegeri ?? 0; durum = m("durum")
        guncelleme = a["updatedAt"]?.zamanDegeri
        kayitli = true
    }

    public var icerikten: Bool { id.hasPrefix("icerik-") }
    public var girdi: FotoHavuzu.SlaytGirdisi {
        FotoHavuzu.SlaytGirdisi(id: id, ulke: ulke, gorsel: gorsel, havuzFoto: havuzFoto, odak: odak, sira: sira)
    }

    /// Listede gösterilen durum: taslak / süresi doldu / başlayacak / yayında.
    public func durumYazisi(bugun: String = Tr.bugun()) -> (metin: String, tur: String) {
        if durum != "yayinda" { return ("Taslak", "taslak") }
        if !bitis.isEmpty && bugun > bitis { return ("Süresi doldu", "bitti") }
        if !baslangic.isEmpty && bugun < baslangic { return ("\(BildirimMetni.trTarih(baslangic, gun: false)) tarihinde başlayacak", "bekliyor") }
        return ("Yayında", "yayinda")
    }

    /// Sitede şu an yayında mı (komşu slaytlar için; panel: komsulariGetir).
    public func sitede(bugun: String = Tr.bugun()) -> Bool { durum == "yayinda" && !(!bitis.isEmpty && bitis < bugun) }

    public var hatalar: [String] {
        var h: [String] = []
        if baslik.kirpik.count < 2 { h.append("Başlık boş olamaz.") }
        let l = link.kirpik
        if !l.isEmpty && !l.eslesir("^(/[^\\s]*|#[A-Za-z0-9_-]*|https://[^\\s]+)$") { h.append("Adres / ile ya da https:// ile başlamalı.") }
        if !baslangic.isEmpty && !bitis.isEmpty && bitis < baslangic { h.append("Bitiş tarihi başlangıçtan önce olamaz.") }
        if gorsel.count > FotoHavuzu.gorselSiniri { h.append("Görsel çok büyük; daha küçük bir görsel seçin.") }
        return h
    }
}

public enum VitrinIslemi {
    static func kayit(_ eylem: String, _ hedef: String, _ ayrinti: String, _ c: Calisan) -> FirestoreIstemci.Yazim {
        .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                 alanlar: IslemKaydi.alanlar(eylem: eylem, hedef: hedef, ayrinti: String(ayrinti.prefix(500)), calisan: c), zaman: ["at"])
    }

    /// Slaytı yazar (yayınlama yetkisi yoksa taslak). Yeni slaytta oluşturma alanları şimdi;
    /// düzenlemede yalnız içerik alanları (oluşturma alanları olduğu gibi kalır).
    public static func kaydet(_ s: VitrinSlayti, yayinlayabilir: Bool, havuzaEkle: Bool = false, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let durum = yayinlayabilir ? s.durum : "taslak"
        var a: [String: FSDeger] = [:]
        a["ust"] = .metin(String(s.ust.kirpik.prefix(40)))
        a["baslik"] = .metin(String(s.baslik.kirpik.prefix(80)))
        a["metin"] = .metin(String(s.metin.kirpik.prefix(200)))
        a["dugme"] = .metin(String(s.dugme.kirpik.prefix(30)))
        a["link"] = .metin(s.link.kirpik)
        a["gorsel"] = .metin(s.gorsel)
        a["havuzFoto"] = .metin(s.gorsel.isEmpty ? s.havuzFoto : "")
        a["odak"] = .metin(FotoHavuzu.odakGecerli(s.odak) ? s.odak : "")
        a["ulke"] = .metin(s.ulke)
        a["baslangic"] = s.baslangic.isEmpty ? .bos : .metin(s.baslangic)
        a["bitis"] = s.bitis.isEmpty ? .bos : .metin(s.bitis)
        a["sira"] = .tam(min(999, max(0, s.sira)))
        a["durum"] = .metin(durum)
        a["updatedBy"] = .metin(c.uid)
        var y: [FirestoreIstemci.Yazim]
        if s.kayitli {
            y = [.guncelle(yol: "vitrin/\(s.id)", alanlar: a, zaman: ["updatedAt"])]
        } else {
            a["createdBy"] = .metin(c.uid)
            y = [.yaz(yol: "vitrin/\(s.id)", alanlar: a, zaman: ["createdAt", "updatedAt"])]
        }
        y.append(kayit(s.kayitli ? "vitrin.update" : "vitrin.create", s.id, "\(s.baslik.kirpik) (\(durum))", c))
        if havuzaEkle && !s.gorsel.isEmpty {
            y += FotoHavuzu.ekle(gorsel: s.gorsel, ulke: s.ulke, odak: FotoHavuzu.odakGecerli(s.odak) ? s.odak : FotoHavuzu.orta,
                                 ad: s.baslik, calisan: c)
        }
        return y
    }

    public static func sil(_ s: VitrinSlayti, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.sil(yol: "vitrin/\(s.id)"), kayit("vitrin.delete", s.id, s.baslik, c)]
    }
}
