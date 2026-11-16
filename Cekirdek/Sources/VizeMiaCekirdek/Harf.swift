import Foundation

/// Harf ve biçim kuralları — site/assets/form-kosul.js (latinBuyuk) ve
/// basvuru.js (FILTERS) ile aynı. Sunucu kuralı da aynısını bekliyor;
/// uygulama temizlemezse müşteri gönderirken anlamsız bir hata alır.
public enum Harf {
    private static let tr: [Character: String] = [
        "ç": "c", "Ç": "C", "ğ": "g", "Ğ": "G", "ı": "i", "İ": "I",
        "ö": "o", "Ö": "O", "ş": "s", "Ş": "S", "ü": "u", "Ü": "U",
    ]

    /// Bu ülkede Ö/Ü korunuyor mu? Almanya kabul ediyor (Almancada da var).
    public static func ouKorunur(_ ulke: String) -> Bool {
        ulke.kirpik.lowercased() == "almanya"
    }

    private static func aksansiz(_ c: Character) -> String {
        String(String.UnicodeScalarView(String(c).decomposedStringWithCanonicalMapping.unicodeScalars.filter {
            !(0x0300...0x036f).contains($0.value)
        }))
    }

    /// Türkçe harfleri Latin karşılığına çevirip büyütür: "Karakaş" → "KARAKAS".
    /// Almanya'da Ö/Ü kalır: "Öztürk" → "ÖZTÜRK"; başka ülkede "OZTURK".
    public static func latinBuyuk(_ s: String, ulke: String = "") -> String {
        let koru = ouKorunur(ulke)
        var out = ""
        for c in s.precomposedStringWithCanonicalMapping {
            if koru, "öÖüÜ".contains(c) { out.append(c); continue }
            out += tr[c] ?? aksansiz(c)
        }
        return out.uppercased()
    }

    /// Ad / soyad: yalnız A–Z, boşluk, tire (Almanya'da Ö ve Ü de).
    public static func adSoyad(_ s: String, ulke: String) -> String {
        latinBuyuk(s, ulke: ulke).degistir(ouKorunur(ulke) ? "[^A-ZÖÜ -]" : "[^A-Z -]", "")
    }

    /// Pasaport numarası: yalnız A–Z ve rakam.
    public static func harfRakam(_ s: String) -> String {
        latinBuyuk(s).degistir("[^A-Z0-9]", "")
    }

    public static func rakam(_ s: String) -> String {
        s.degistir("[^0-9]", "")
    }

    /// E-posta: Türkçe harfler ASCII'ye, hepsi küçük harfe.
    public static func eposta(_ s: String) -> String {
        var out = ""
        for c in s.kirpik { out += tr[c] ?? String(c) }
        return out.lowercased()
    }

    public static func epostaGecerli(_ temiz: String) -> Bool {
        temiz.eslesir("^[^@\\s]+@[^@\\s]+\\.[^@\\s]{2,}$")
    }

    /// Telefonun 10 hanesi (başındaki 90 ve 0 atılır); geçersizse nil.
    public static func telefonHaneleri(_ s: String) -> String? {
        var d = rakam(s)
        if d.hasPrefix("90") { d.removeFirst(2) }
        if d.hasPrefix("0") { d.removeFirst() }
        return d.eslesir("^[2-5][0-9]{9}$") ? d : nil
    }

    /// T.C. kimlik numarası doğrulaması (panel/js/mrz.js → isValidTckn).
    public static func tcknGecerli(_ v: String) -> Bool {
        guard v.eslesir("^[1-9][0-9]{10}$") else { return false }
        let d = v.compactMap { $0.wholeNumberValue }
        let tek = d[0] + d[2] + d[4] + d[6] + d[8]
        let cift = d[1] + d[3] + d[5] + d[7]
        if ((tek * 7 - cift) % 10 + 10) % 10 != d[9] { return false }
        return d[0..<10].reduce(0, +) % 10 == d[10]
    }
}
