import Foundation

// Müşteri arşivi (musteriArsivi/{id}): KVKK ile silinen başvurulardan kalan
// kayıtlar — ad soyad, telefon, e-posta, son vize, işlemler, fiyat, ödemeler.
// TCKN, pasaport, adres, form cevapları ve belgeler saklanmaz.
// Panelin karşılığı: panel/js/musteri-arsivi.js, pages/arsiv.js.

public struct ArsivKaydi: Equatable, Identifiable {
    public struct Odeme: Equatable {
        public var tarih: String
        public var tutar: Double?
        public var paraBirimi: String
        public var yontem: String
        public var onayKodu: String
        public var aciklama: String
        public var kim: String
        public var dekontVardi: Bool
    }
    public struct Gider: Equatable {
        public var tarih: String
        public var tutar: Double?
        public var paraBirimi: String
        public var kategori: String
        public var aciklama: String
        public var kim: String
    }
    public struct Islem: Equatable {
        public var metin: String
        public var kim: String
        public var zaman: Date?
    }

    public var id: String
    public var ad: String
    public var soyad: String
    public var telefon: String
    public var eposta: String
    public var ulke: String
    public var ulkeAdi: String
    public var takipKodu: String
    public var sonStatu: String
    public var acilis: Date?
    public var sonuclanma: Date?
    public var randevu: Date?
    public var seyahat: Date?
    public var konsTakipKodu: String
    public var fiyat: (tutar: Double, paraBirimi: String, aciklama: String)?
    public var odemeler: [Odeme]
    public var giderler: [Gider]
    public var islemler: [Islem]
    public var silmeTuru: String
    public var silenAd: String
    public var silinme: Date?
    public var silmeSebebi: String
    public var kaynak: String

    public static func == (a: ArsivKaydi, b: ArsivKaydi) -> Bool { a.id == b.id && a.silinme == b.silinme }

    static func sayi(_ d: FSDeger?) -> Double? {
        switch d {
        case .tam(let n)?: return Double(n)
        case .ondalik(let x)?: return x
        default: return nil
        }
    }

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        id = kimlik
        let m = { (k: String) in a[k]?.metinDegeri ?? "" }
        ad = m("ad"); soyad = m("soyad"); telefon = m("telefon"); eposta = m("eposta")
        ulke = m("ulke"); ulkeAdi = m("ulkeAdi"); takipKodu = m("takipKodu"); sonStatu = m("sonStatu")
        acilis = a["acilis"]?.zamanDegeri; sonuclanma = a["sonuclanma"]?.zamanDegeri
        randevu = a["randevu"]?.zamanDegeri; seyahat = a["seyahat"]?.zamanDegeri
        konsTakipKodu = m("konsTakipKodu")
        if let f = a["fiyat"]?.haritaDegeri, let t = ArsivKaydi.sayi(f["tutar"]) {
            fiyat = (t, f["paraBirimi"]?.metinDegeri ?? "TRY", f["aciklama"]?.metinDegeri ?? "")
        } else { fiyat = nil }
        odemeler = (a["odemeler"]?.diziDegeri ?? []).compactMap { $0.haritaDegeri }.map { o in
            Odeme(tarih: o["tarih"]?.metinDegeri ?? "", tutar: ArsivKaydi.sayi(o["tutar"]), paraBirimi: o["paraBirimi"]?.metinDegeri ?? "",
                  yontem: o["yontem"]?.metinDegeri ?? "", onayKodu: o["onayKodu"]?.metinDegeri ?? "",
                  aciklama: o["aciklama"]?.metinDegeri ?? "", kim: o["kim"]?.metinDegeri ?? "",
                  dekontVardi: o["dekontVardi"]?.mantikDegeri ?? false)
        }
        giderler = (a["giderler"]?.diziDegeri ?? []).compactMap { $0.haritaDegeri }.map { g in
            Gider(tarih: g["tarih"]?.metinDegeri ?? "", tutar: ArsivKaydi.sayi(g["tutar"]), paraBirimi: g["paraBirimi"]?.metinDegeri ?? "",
                  kategori: g["kategori"]?.metinDegeri ?? "", aciklama: g["aciklama"]?.metinDegeri ?? "", kim: g["kim"]?.metinDegeri ?? "")
        }
        islemler = (a["islemler"]?.diziDegeri ?? []).compactMap { $0.haritaDegeri }.map { l in
            let metin = [l["metin"], l["statu"], l["tur"]].compactMap { $0?.metinDegeri }.first { !$0.isEmpty } ?? ""
            return Islem(metin: metin, kim: l["kim"]?.metinDegeri ?? "", zaman: l["at"]?.zamanDegeri)
        }
        silmeTuru = m("silmeTuru"); silenAd = m("silenAd"); silinme = a["silinme"]?.zamanDegeri
        silmeSebebi = m("silmeSebebi"); kaynak = m("kaynak")
    }

    public var adSoyad: String { "\(ad) \(soyad)".kirpik }
    /// Gruplama ve sıralama için zaman: sonuçlanma, silinme ya da açılış.
    var siraZamani: Date { sonuclanma ?? silinme ?? acilis ?? .distantPast }
}

public enum MusteriArsivi {
    static func kucuk(_ s: String) -> String {
        s.kirpik.lowercased(with: Tr.yerel).degistir("\\s+", " ")
    }

    /// Telefon: +90XXXXXXXXXX; tanınmazsa yalnız rakamlar.
    public static func telefon(_ s: String) -> String {
        let ham = s.filter { $0.isNumber || $0 == "+" }
        let n = s.filter(\.isNumber)
        if n.isEmpty { return "" }
        if ham.hasPrefix("+") { return "+\(n)" }
        if n.count == 10 && n.hasPrefix("5") { return "+90\(n)" }
        if n.count == 11 && n.hasPrefix("0") { return "+90\(n.dropFirst())" }
        if n.count == 12 && n.hasPrefix("90") { return "+\(n)" }
        return n
    }

    /// Arama kutusuna yazılanı sorgu anahtarına çevirir (array-contains): e-posta küçük harf,
    /// telefon +90…, ad küçük harf tek boşluk.
    public static func aramaAnahtari(_ girdi: String) -> String {
        let s = girdi.kirpik
        if s.isEmpty { return "" }
        if s.contains("@") { return s.lowercased() }
        if s.eslesir("^[\\d\\s()+-]+$") { return telefon(s) }
        return kucuk(s)
    }

    /// Türkçe harf ve büyük/küçük farkı olmadan ("YARGIN" = "yargın" = "yargin").
    public static func sade(_ s: String) -> String {
        let t = s.lowercased(with: Tr.yerel)
            .replacingOccurrences(of: "ç", with: "c").replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ş", with: "s").replacingOccurrences(of: "ü", with: "u")
        let d = t.decomposedStringWithCanonicalMapping.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }
        return String(String.UnicodeScalarView(d)).degistir("\\s+", " ").kirpik
    }

    /// Kayıt aramaya uyuyor mu: her kelime ad soyad, e-posta, takip kodu ya da ülkede; telefonda rakamlar.
    public static func eslesir(_ k: ArsivKaydi, _ terim: String) -> Bool {
        let t = sade(terim)
        if t.isEmpty { return true }
        let rakam = t.filter(\.isNumber)
        if rakam.count >= 4 && t.eslesir("^[\\d\\s()+-]+$") {
            let tel = k.telefon.filter(\.isNumber), kod = k.takipKodu.filter(\.isNumber)
            let r = rakam.hasPrefix("0") ? String(rakam.dropFirst()) : rakam
            return tel.contains(r) || kod.contains(rakam)
        }
        let metin = sade("\(k.ad) \(k.soyad) \(k.eposta) \(k.takipKodu) \(k.ulkeAdi)")
        return t.split(separator: " ").allSatisfy { metin.contains($0) }
    }

    /// Aynı müşterinin kayıtları bir arada (telefon → e-posta → ad soyad); en yeni başta.
    public static func gruplar(_ l: [ArsivKaydi]) -> [[ArsivKaydi]] {
        var sira: [String] = []
        var g: [String: [ArsivKaydi]] = [:]
        for k in l {
            let a = !k.telefon.isEmpty ? k.telefon : (!k.eposta.isEmpty ? k.eposta : kucuk(k.adSoyad))
            if g[a] == nil { sira.append(a) }
            g[a, default: []].append(k)
        }
        return sira.compactMap { g[$0]?.sorted { $0.siraZamani > $1.siraZamani } }
            .sorted { ($0.first?.siraZamani ?? .distantPast) > ($1.first?.siraZamani ?? .distantPast) }
    }

    /// Para birimine göre toplam ("4.500 TRY + 100 EUR").
    public static func toplam(_ kalemler: [(Double?, String)]) -> [(String, Double)] {
        var t: [String: Double] = [:]
        var sira: [String] = []
        for (tutar, birim) in kalemler {
            guard let tutar, !birim.isEmpty else { continue }
            if t[birim] == nil { sira.append(birim) }
            t[birim] = (((t[birim] ?? 0) + tutar) * 100).rounded() / 100
        }
        return sira.map { ($0, t[$0] ?? 0) }
    }

    /// Yeniden başvuru açmak için form tohumu: ad, soyad, telefon, e-posta, ülke.
    public static func tohum(_ k: ArsivKaydi, ulkeler: Set<String>) -> (ulke: String, degerler: [String: String]) {
        let ulke = ulkeler.contains(k.ulke) ? k.ulke : ""
        var d: [String: String] = [:]
        let alanlar = ["firstName": EkipFormu.latinBuyuk(k.ad, ulke: ulke), "lastName": EkipFormu.latinBuyuk(k.soyad, ulke: ulke),
                       "phone": k.telefon, "email": k.eposta]
        for (a, v) in alanlar where !v.isEmpty { d[a] = v }
        return (ulke, d)
    }
}
