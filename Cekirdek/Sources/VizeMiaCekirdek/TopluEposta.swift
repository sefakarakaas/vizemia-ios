import Foundation

// Toplu e-posta: bilgilendirme (toplu) ya da kampanya (panel: pages/eposta.js →
// TopluGonder, eposta-ortak.js → aliciSec). Kaynaklar: başvurular, talepler,
// müşteri arşivi. Kampanya yalnız kampanya izni veren ve abonelikten çıkmamış
// kişilere gider; İYS kaydı tamamlanmadan gönderilemez. Gönderimi kuyruktan
// Apps Script / GitHub görevi yapar (günlük sınır orada uygulanır).

public struct TopluAday: Equatable, Identifiable {
    public var eposta: String
    public var ad: String
    public var soyad: String
    public var ulke: String
    public var kampanyaIzni: Bool
    /// basvuru | talep | arsiv
    public var kaynak: String
    public var basvuru: Basvuru?
    public var sec = true
    public var id: String { eposta }

    public init(eposta: String, ad: String, soyad: String, ulke: String, kampanyaIzni: Bool, kaynak: String, basvuru: Basvuru? = nil) {
        self.eposta = eposta; self.ad = ad; self.soyad = soyad; self.ulke = ulke
        self.kampanyaIzni = kampanyaIzni; self.kaynak = kaynak; self.basvuru = basvuru
    }

    public static let kaynakAdlari = ["basvuru": "Başvuru", "talep": "Talep", "arsiv": "Arşiv"]
}

public enum TopluEposta {
    public static let enCok = 1000

    public struct Atlanan: Equatable { public var epostaYok = 0, izinYok = 0, ayrildi = 0, tekrar = 0 }

    /// Geçersiz adres, izinsiz (kampanya), abonelikten çıkmış (kampanya) ve tekrar eden atılır.
    public static func aliciSec(_ l: [TopluAday], kampanya: Bool, ayrilanlar: Set<String>) -> (alicilar: [TopluAday], atlanan: Atlanan) {
        var a = Atlanan()
        var gorulen = Set<String>()
        var o: [TopluAday] = []
        for k in l {
            let e = k.eposta.kirpik.lowercased()
            if !MusteriBildirimi.epostaGecerli(e) { a.epostaYok += 1; continue }
            if kampanya && !k.kampanyaIzni { a.izinYok += 1; continue }
            if kampanya && ayrilanlar.contains(e) { a.ayrildi += 1; continue }
            if gorulen.contains(e) { a.tekrar += 1; continue }
            gorulen.insert(e)
            var y = k
            y.eposta = e
            o.append(y)
        }
        return (Array(o.prefix(enCok)), a)
    }

    public static func ozet(_ n: Int, _ a: Atlanan) -> String {
        var p = ["\(n) alıcı"]
        if a.epostaYok > 0 { p.append("\(a.epostaYok) kişinin e-postası yok") }
        if a.izinYok > 0 { p.append("\(a.izinYok) kişi kampanya izni vermemiş") }
        if a.ayrildi > 0 { p.append("\(a.ayrildi) kişi abonelikten çıkmış") }
        if a.tekrar > 0 { p.append("\(a.tekrar) tekrar eden adres birleştirildi") }
        return p.joined(separator: " · ")
    }

    /// Kişinin yer tutucu değerleri: başvurudansa takip bağlantısıyla (panel: basvuruDegerleri / epostaDegerleri).
    public static func degerler(_ k: TopluAday) -> [String: String] {
        if let b = k.basvuru { return MusteriBildirimi.epostaDegerleri(b, statu: b.statuAdi) }
        let a = MusteriBildirimi.adDuzelt(k.ad), s = MusteriBildirimi.adDuzelt(k.soyad)
        let adSoyad = "\(a) \(s)".kirpik
        return ["ad": a.isEmpty ? "Müşterimiz" : a, "isim": a.isEmpty ? "Müşterimiz" : a, "soyad": s,
                "adSoyad": adSoyad.isEmpty ? "Müşterimiz" : adSoyad, "ulke": k.ulke, "ülke": k.ulke, "statu": "", "statü": "",
                "takipKodu": "", "kod": "", "takipLinki": "", "link": ""]
    }

    /// "Mehmet Ali Yılmaz" → ("Mehmet Ali", "Yılmaz") (geri arama talebinde ad tek alan).
    public static func adBol(_ s: String) -> (ad: String, soyad: String) {
        let p = s.split(whereSeparator: \.isWhitespace).map(String.init)
        return (p.count > 1 ? p.dropLast().joined(separator: " ") : (p.first ?? ""), p.count > 1 ? p[p.count - 1] : "")
    }

    /// Kampanya kimliği (panel: "k" + zaman damgası, 36'lık).
    public static func kampanyaId(_ simdi: Date = Date()) -> String { "k" + String(Int(simdi.timeIntervalSince1970 * 1000), radix: 36) }

    /// Kuyruk yazımları 400'erli toplu yazımlar hâlinde (Firestore tek yazımda en çok 500);
    /// sonuncusuna işlem kaydı eklenir. Konu ya da metin boşsa nil.
    public static func kuyruk(_ l: [TopluAday], konu: String, metin: String, kampanya: Bool, kampanyaId: String, calisan c: Calisan)
        -> (gruplar: [[FirestoreIstemci.Yazim]], adet: Int)? {
        guard !konu.kirpik.isEmpty, !metin.kirpik.isEmpty else { return nil }
        let yazimlar = l.compactMap { k -> FirestoreIstemci.Yazim? in
            let d = degerler(k)
            return EpostaIslemi.kuyruk(alici: k.eposta, ad: "\(k.ad) \(k.soyad)".kirpik, konu: MusteriBildirimi.doldur(konu, d),
                                       metin: MusteriBildirimi.doldur(metin, d), tur: kampanya ? "kampanya" : "toplu",
                                       appId: k.basvuru?.kimlik ?? "", kaynak: k.kaynak, kampanyaId: kampanyaId, calisan: c)
        }
        guard !yazimlar.isEmpty else { return nil }
        var gruplar = stride(from: 0, to: yazimlar.count, by: 400).map { Array(yazimlar[$0..<min($0 + 400, yazimlar.count)]) }
        gruplar[gruplar.count - 1].append(EpostaIslemi.kayit("eposta.toplu", kampanyaId,
            "\(yazimlar.count) alıcı, \(kampanya ? "kampanya" : "bilgilendirme"): \(konu.kirpik.prefix(80))", c))
        return (gruplar, yazimlar.count)
    }
}
