import Foundation

/// İçerikteki bir bağlantının uygulamada nereye gittiği. Sitedeki yollar
/// ("/takip", "/blog/…", "/basvuru?ulke=almanya") uygulamanın kendi
/// ekranlarına çevrilir; karşılığı olmayan yol sitede açılır.
public enum Hedef: Equatable {
    case anaSayfa
    case basvuru(ulke: String)
    /// `kod`: bağlantıyla gelen takip kodu ("/takip?kod=2026-091234"); yoksa boş.
    case takip(kod: String)
    case destek(kod: String)
    case harclar
    case sss
    case blog
    case sayfa(yol: String)
    case dis(URL)

    public static let site = URL(string: "https://vizemia.com")!

    /// - Parameter sayfaYollari: uygulamanın kendi çizebildiği sayfalar (Akis.sayfalar → yol).
    public static func coz(_ link: String, sayfaYollari: Set<String>) -> Hedef? {
        let s = link.kirpik
        if s.isEmpty || s.hasPrefix("#") { return nil }
        if s.hasPrefix("/") && !s.hasPrefix("//") {
            let parca = s.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            var yol = String(parca[0]).split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "/"
            if yol.count > 1 && yol.hasSuffix("/") { yol.removeLast() }
            let sorgu = parca.count > 1 ? String(parca[1]) : ""
            func deger(_ ad: String) -> String {
                for cift in sorgu.split(separator: "&") {
                    let kv = cift.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    if kv.count == 2 && kv[0] == ad { return String(kv[1]).removingPercentEncoding ?? "" }
                }
                return ""
            }
            switch yol {
            case "/", "": return .anaSayfa
            case "/basvuru", "/pasaport": return .basvuru(ulke: deger("ulke"))
            case "/takip": return .takip(kod: deger("kod"))
            case "/destek": return .destek(kod: deger("kod"))
            case "/harclar": return .harclar
            case "/sss": return .sss
            case "/blog": return .blog
            default:
                if sayfaYollari.contains(yol) { return .sayfa(yol: yol) }
                return URL(string: site.absoluteString + s).map { .dis($0) }
            }
        }
        if s.hasPrefix("https://") || s.hasPrefix("http://") || s.hasPrefix("tel:") || s.hasPrefix("mailto:") {
            guard let u = URL(string: s) else { return nil }
            // vizemia.com adresi tam yazılmışsa da uygulama içinde açılsın.
            if let h = u.host, h == "vizemia.com" || h == "www.vizemia.com" {
                let ic = u.path.isEmpty ? "/" : u.path
                return coz(ic + (u.query.map { "?\($0)" } ?? ""), sayfaYollari: sayfaYollari)
            }
            return .dis(u)
        }
        return nil
    }

    /// Site içi görselin tam adresi ("/assets/img/…" → https://vizemia.com/assets/img/…).
    public static func gorsel(_ yol: String) -> URL? {
        if yol.hasPrefix("https://") { return URL(string: yol) }
        guard yol.hasPrefix("/"), !yol.hasPrefix("//") else { return nil }
        return URL(string: site.absoluteString + yol)
    }
}
