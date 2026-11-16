import Foundation

/// Sitenin basit Markdown'ı (scripts/sayfa-sablonu.mjs → markdown, inline):
/// ##–#### başlık, "- " madde, "1. " sıralı madde, paragraf; satır içinde
/// **kalın** ve [bağlantı](https://… ya da /yol). Başka hiçbir şey yok —
/// site ne çiziyorsa uygulama da onu çizsin diye bilerek aynı küçük küme.
public enum MdParca: Equatable {
    case duz(String)
    case kalin(String)
    case bag(metin: String, adres: String)
}

public enum MdBlok: Equatable {
    case baslik(seviye: Int, [MdParca])
    case paragraf([MdParca])
    case liste(sirali: Bool, [[MdParca]])
}

public enum Markdown {
    private static let satirIciDesen = try! NSRegularExpression(
        pattern: "(\\*\\*[^*]+\\*\\*)|\\[([^\\]]+)\\]\\((https?://[^)\\s]+|/[^)\\s]*)\\)")
    private static let madde = try! NSRegularExpression(pattern: "^\\s*[-*]\\s+(.*)$")
    private static let sira = try! NSRegularExpression(pattern: "^\\s*\\d+\\.\\s+(.*)$")
    private static let baslik = try! NSRegularExpression(pattern: "^(#{2,4})\\s+(.*)$")

    private static func grup(_ desen: NSRegularExpression, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = desen.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    public static func satirIci(_ metin: String) -> [MdParca] {
        let ns = metin as NSString
        var out: [MdParca] = []
        var son = 0
        for m in satirIciDesen.matches(in: metin, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > son { out.append(.duz(ns.substring(with: NSRange(location: son, length: m.range.location - son)))) }
            if m.range(at: 1).location != NSNotFound {
                let k = ns.substring(with: m.range(at: 1))
                out.append(.kalin(String(k.dropFirst(2).dropLast(2))))
            } else {
                out.append(.bag(metin: ns.substring(with: m.range(at: 2)), adres: ns.substring(with: m.range(at: 3))))
            }
            son = m.range.location + m.range.length
        }
        if son < ns.length { out.append(.duz(ns.substring(from: son))) }
        return out
    }

    public static func coz(_ kaynak: String) -> [MdBlok] {
        var out: [MdBlok] = []
        var liste: [[MdParca]] = []
        var sirali = false
        func kapat() {
            if !liste.isEmpty { out.append(.liste(sirali: sirali, liste)); liste = [] }
        }
        for ham in kaynak.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            var satir = String(ham)
            while let s = satir.last, s == " " || s == "\t" { satir.removeLast() }
            let m = grup(madde, satir)
            let s = m == nil ? grup(sira, satir) : nil
            if let g = m ?? s {
                let yeniSirali = m == nil
                if !liste.isEmpty && sirali != yeniSirali { kapat() }
                sirali = yeniSirali
                liste.append(satirIci(g[1]))
                continue
            }
            kapat()
            if satir.kirpik.isEmpty { continue }
            if let h = grup(baslik, satir) {
                out.append(.baslik(seviye: h[1].count, satirIci(h[2])))
            } else {
                out.append(.paragraf(satirIci(satir)))
            }
        }
        kapat()
        return out
    }

    /// Biçim işaretleri atılmış düz metin (arama, özet, erişilebilirlik).
    public static func duzMetin(_ s: String) -> String {
        satirIci(s).map { p -> String in
            switch p {
            case .duz(let t), .kalin(let t): return t
            case .bag(let t, _): return t
            }
        }.joined()
    }
}
