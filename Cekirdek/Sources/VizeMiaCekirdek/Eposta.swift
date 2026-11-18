import Foundation

// Müşteriye e-posta (panel: pages/eposta.js, eposta.js, eposta-ortak.js).
// Uygulama yalnız kuyruğa yazar ve sıradakini iptal eder; gönderimi Apps
// Script servisi (hemen) ya da scripts/send-eposta.mjs (15 dakikada bir) yapar.
// Metin kuyruğa yazılırken kurulur: danışman son hâlini görür.

/// eposta/{id}
public struct EpostaKaydi: Equatable, Identifiable {
    public static let turAdlari = ["statu": "Statü bilgisi (otomatik)", "tekli": "Tek müşteri", "toplu": "Toplu bilgilendirme",
                                   "kampanya": "Kampanya", "otomatik": "Otomatik bildirim (randevu, evrak)"]
    public static let durumAdlari: [(id: String, ad: String)] = [
        ("queued", "Sırada"), ("hazir", "Gönderiliyor"), ("gonderiliyor", "Gönderiliyor"), ("sent", "Gönderildi"),
        ("cancelled", "İptal"), ("failed", "Gönderilemedi"),
    ]
    public static let konuEnCok = 200
    public static let metinEnCok = 20_000

    public var id: String
    public var alici: String
    public var ad: String
    public var konu: String
    public var metin: String
    public var tur: String
    public var appId: String
    public var kaynak: String
    public var durum: String
    public var olusma: Date?
    public var gonderilme: Date?
    public var yazan: String
    public var iptalSebebi: String
    public var hata: String

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        func m(_ k: String) -> String { a[k]?.metinDegeri ?? "" }
        id = kimlik
        alici = m("to"); ad = m("ad"); konu = m("subject"); metin = m("text"); tur = m("tur"); appId = m("appId")
        kaynak = m("kaynak"); durum = m("status"); olusma = a["createdAt"]?.zamanDegeri; gonderilme = a["sentAt"]?.zamanDegeri
        yazan = m("byName"); iptalSebebi = m("iptalSebebi"); hata = m("lastError")
    }

    public var turAdi: String { kaynak == "serbest" ? "Serbest e-posta" : (Self.turAdlari[tur] ?? tur) }
    public var zaman: Date? { gonderilme ?? olusma }

    /// Panel: durumYazisi.
    public var durumYazisi: String {
        let d = Self.durumAdlari.first { $0.id == durum }?.ad ?? durum
        if durum == "cancelled" && !iptalSebebi.isEmpty { return "\(d) (\(iptalSebebi))" }
        if durum == "failed" && !hata.isEmpty { return "\(d): \(hata)" }
        if durum == "queued" && tur == "statu" { return "\(d) (30 dk bekler)" }
        return d
    }

    public var iptalEdilebilir: Bool { durum == "queued" }
}

public enum EpostaIslemi {
    typealias Y = FirestoreIstemci.Yazim

    /// Metinde doldurulamamış {yer tutucu} kaldı mı? Gönderimden önce danışmana gösterilir.
    public static func bosYerTutucular(_ metin: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "\\{([^}]+)\\}") else { return [] }
        let ns = metin as NSString
        var l: [String] = []
        for m in re.matches(in: metin, range: NSRange(location: 0, length: ns.length)) {
            let k = ns.substring(with: m.range(at: 1)).kirpik
            if !l.contains(k) { l.append(k) }
        }
        return l
    }

    /// Serbest e-postada alıcının adından değerler ("Ayşe Nur Kaya" → ad "Ayşe Nur", soyad "Kaya").
    public static func serbestDegerler(ad: String) -> [String: String] {
        let p = ad.split(whereSeparator: \.isWhitespace).map(String.init)
        let a = p.count > 1 ? p.dropLast().joined(separator: " ") : (p.first ?? "")
        let s = p.count > 1 ? p[p.count - 1] : ""
        let aa = MusteriBildirimi.adDuzelt(a), ss = MusteriBildirimi.adDuzelt(s)
        let adSoyad = "\(aa) \(ss)".kirpik
        return ["ad": aa.isEmpty ? "Müşterimiz" : aa, "isim": aa.isEmpty ? "Müşterimiz" : aa, "soyad": ss,
                "adSoyad": adSoyad.isEmpty ? "Müşterimiz" : adSoyad, "ulke": "", "ülke": "", "statu": "", "statü": "",
                "takipKodu": "", "kod": "", "takipLinki": "", "link": ""]
    }

    /// Kuyruk belgesi (panel: kuyrugaEkle). Adres, konu ya da metin geçersizse nil.
    static func kuyruk(alici: String, ad: String, konu: String, metin: String, tur: String, appId: String = "", kaynak: String = "",
                       kampanyaId: String = "", calisan c: Calisan) -> Y? {
        let e = alici.kirpik.lowercased()
        let k = konu.kirpik, m = metin.kirpik
        guard MusteriBildirimi.epostaGecerli(e), !k.isEmpty, !m.isEmpty else { return nil }
        var a: [String: FSDeger] = [:]
        a["to"] = .metin(e)
        a["ad"] = .metin(String(ad.prefix(120)))
        a["subject"] = .metin(String(k.prefix(EpostaKaydi.konuEnCok)))
        a["text"] = .metin(String(m.prefix(EpostaKaydi.metinEnCok)))
        a["tur"] = .metin(tur)
        if !appId.isEmpty { a["appId"] = .metin(appId) }
        if !kaynak.isEmpty { a["kaynak"] = .metin(kaynak) }
        if !kampanyaId.isEmpty { a["kampanyaId"] = .metin(String(kampanyaId.prefix(60))) }
        a["status"] = .metin("queued")
        a["attempts"] = .tam(0)
        a["createdBy"] = .metin(c.uid)
        a["byName"] = .metin(String(c.gorunenAd.prefix(80)))
        return .olustur(yol: "eposta/\(FirestoreIstemci.yeniKimlik())", alanlar: a, zaman: ["createdAt"])
    }

    static func kayit(_ eylem: String, _ hedef: String, _ ayrinti: String, _ c: Calisan) -> Y {
        .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                 alanlar: IslemKaydi.alanlar(eylem: eylem, hedef: hedef, ayrinti: String(ayrinti.prefix(500)), calisan: c), zaman: ["at"])
    }

    /// Başvurudan tek müşteriye mail (metin yer tutucularla doldurulmuş olarak gelir).
    public static func tekli(_ b: Basvuru, eposta: String, konu: String, metin: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim]? {
        guard let k = kuyruk(alici: eposta, ad: "\(b.ad) \(b.soyad)".kirpik, konu: konu, metin: metin, tur: "tekli", appId: b.kimlik, calisan: c)
        else { return nil }
        return [k, kayit("eposta.tekli", b.kimlik, String(konu.kirpik.prefix(120)), c)]
    }

    /// Sistemde kayıtlı olmayan bir adrese mail ("müşteri değil": hiçbir listeye kaydedilmez).
    public static func serbest(alici: String, konu: String, metin: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim]? {
        guard let k = kuyruk(alici: alici, ad: "", konu: konu, metin: metin, tur: "toplu", kaynak: "serbest", calisan: c) else { return nil }
        return [k, kayit("eposta.serbest", "", "müşteri değil: \(konu.kirpik.prefix(100))", c)]
    }

    /// Sıradaki maili iptal eder.
    public static func iptal(_ m: EpostaKaydi, sebep: String = "panelden iptal", calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.guncelle(yol: "eposta/\(m.id)", alanlar: [
            "status": .metin("cancelled"), "iptalSebebi": .metin(String(sebep.prefix(200))), "iptalEden": .metin(c.uid),
        ], zaman: ["iptalAt"])]
    }
}
