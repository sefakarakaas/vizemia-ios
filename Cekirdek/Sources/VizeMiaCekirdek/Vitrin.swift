import Foundation

/// Ana sayfa vitrinindeki bir slayt (/assets/vitrin.json → slaytlar).
public struct Slayt: Codable, Equatable, Identifiable {
    public var id: String
    public var ust: String
    public var baslik: String
    public var metin: String
    public var dugme: String
    public var link: String
    public var gorsel: String
    public var alt: String
    public var ulke: String
    /// Görselin görünen alanı: "50% 30%".
    public var odak: String
    public var baslangic: String?
    public var bitis: String?
    public var sira: Double

    enum Anahtar: String, CodingKey {
        case id, ust, baslik, metin, dugme, link, gorsel, alt, ulke, odak, baslangic, bitis, sira
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Anahtar.self)
        func m(_ k: Anahtar) -> String { ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "" }
        baslik = m(.baslik)
        id = m(.id).isEmpty ? baslik : m(.id)
        ust = m(.ust); metin = m(.metin); dugme = m(.dugme); link = m(.link)
        gorsel = m(.gorsel); alt = m(.alt); ulke = m(.ulke); odak = m(.odak)
        baslangic = (try? c.decodeIfPresent(String.self, forKey: .baslangic)) ?? nil
        bitis = (try? c.decodeIfPresent(String.self, forKey: .bitis)) ?? nil
        sira = ((try? c.decodeIfPresent(Double.self, forKey: .sira)) ?? nil) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Anahtar.self)
        try c.encode(id, forKey: .id); try c.encode(ust, forKey: .ust); try c.encode(baslik, forKey: .baslik)
        try c.encode(metin, forKey: .metin); try c.encode(dugme, forKey: .dugme); try c.encode(link, forKey: .link)
        try c.encode(gorsel, forKey: .gorsel); try c.encode(alt, forKey: .alt); try c.encode(ulke, forKey: .ulke)
        try c.encode(odak, forKey: .odak); try c.encodeIfPresent(baslangic, forKey: .baslangic)
        try c.encodeIfPresent(bitis, forKey: .bitis); try c.encode(sira, forKey: .sira)
    }

    /// Odak noktası 0…1 (x, y). Yoksa orta.
    public var odakNoktasi: (x: Double, y: Double) {
        let p = odak.split(separator: " ").compactMap { Double($0.replacingOccurrences(of: "%", with: "")) }
        guard p.count == 2 else { return (0.5, 0.5) }
        return (min(max(p[0], 0), 100) / 100, min(max(p[1], 0), 100) / 100)
    }
}

public struct VitrinDosyasi: Codable, Equatable {
    public var slaytlar: [Slayt]
}

/// Hangi slayt, hangi sırayla — site/assets/vitrin-secim.js ile aynı kurallar.
public enum Vitrin {
    /// Bağlantı yalnız üç biçimde kabul edilir: site içi yol, sayfa içi çapa, https adresi.
    public static func guvenliLink(_ link: String) -> String {
        let s = link.kirpik
        if s.eslesir("^/[^\\s]*$") && !s.hasPrefix("//") { return s }
        if s.eslesir("^#[A-Za-z0-9_-]*$") { return s }
        if s.eslesir("^https://[^\\s]+$") { return s }
        return ""
    }

    /// Bugün yayında mı? Başlangıç ve bitiş günleri dâhil.
    public static func tarihteMi(_ s: Slayt, bugun: String) -> Bool {
        let desen = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
        if let b = s.baslangic, b.eslesir(desen), bugun < b { return false }
        if let b = s.bitis, b.eslesir(desen), bugun > b { return false }
        return true
    }

    /// Gösterilecek slaytlar, sırasıyla. `ulke` verilirse o ülkenin slaytları öne gelir.
    public static func gosterilecekler(_ slaytlar: [Slayt], bugun: String = Tr.bugun(), ulke: String = "") -> [Slayt] {
        let u = ulke.kirpik.lowercased()
        return slaytlar
            .filter { !$0.baslik.kirpik.isEmpty && tarihteMi($0, bugun: bugun) }
            .map { s -> Slayt in var y = s; y.link = guvenliLink(s.link); return y }
            .enumerated()
            .sorted { a, b in
                let pa = !u.isEmpty && a.element.ulke == u ? 0 : 1
                let pb = !u.isEmpty && b.element.ulke == u ? 0 : 1
                if pa != pb { return pa < pb }
                if a.element.sira != b.element.sira { return a.element.sira < b.element.sira }
                return a.offset < b.offset
            }
            .map { $0.element }
    }
}
