import Foundation

/// Kur verisi: /assets/kur.json (TCMB, her yayında yenilenir) ya da Apps Script
/// servisi (Google Finance, ~20 dk gecikmeli). 1 birim dövizin TL karşılığı.
public struct KurVerisi: Codable, Equatable {
    public var tarih: String?
    public var zaman: String?
    public var kaynak: String?
    public var kurlar: [String: Double]

    public static let kodlar = ["EUR", "USD", "GBP", "CAD"]
    public static let semboller = ["EUR": "€", "USD": "$", "GBP": "£", "CAD": "C$", "TRY": "₺"]

    public init(tarih: String? = nil, zaman: String? = nil, kaynak: String? = nil, kurlar: [String: Double]) {
        self.tarih = tarih; self.zaman = zaman; self.kaynak = kaynak; self.kurlar = kurlar
    }

    /// Dört kurun hepsi pozitif sayı olmalı.
    public var gecerli: Bool {
        KurVerisi.kodlar.allSatisfy { (kurlar[$0] ?? 0) > 0 }
    }

    /// "TCMB döviz satış kuru, 12 Ekim 2026"
    public var bilgi: String {
        var ne = ""
        if let z = zaman, let d = FSDeger.zamanOku(z) {
            let p = Tr.takvim.dateComponents([.month, .day, .hour, .minute], from: d)
            ne = "\(p.day ?? 0) \(Mesai.ayAdi[(p.month ?? 1) - 1]) \(Tr.iki(p.hour ?? 0)):\(Tr.iki(p.minute ?? 0))"
        } else if let t = tarih {
            ne = Tr.uzunTarih(t)
        }
        let ad = kaynak == "TCMB" ? "TCMB döviz satış kuru" : "Piyasa kuru (Google Finance)"
        return ne.isEmpty ? ad : "\(ad), \(ne)"
    }

    public struct Sonuc: Equatable {
        public var tutar: String
        public var oran: String
    }

    /// `kaynak` para biriminden çeviri. TRY → € ve $; diğerleri → ₺.
    public func cevir(miktar: Double, kaynak para: String) -> Sonuc? {
        guard gecerli, miktar >= 0, miktar.isFinite else { return nil }
        let eur = kurlar["EUR"] ?? 0, usd = kurlar["USD"] ?? 0
        if para == "TRY" {
            return Sonuc(
                tutar: "\(Sayi.para(miktar / eur)) €  /  \(Sayi.para(miktar / usd)) $",
                oran: "1 € = \(Sayi.kur(eur)) ₺ | 1 $ = \(Sayi.kur(usd)) ₺")
        }
        guard let k = kurlar[para], k > 0 else { return nil }
        return Sonuc(
            tutar: "\(Sayi.para(miktar * k)) ₺",
            oran: "1 \(KurVerisi.semboller[para] ?? para) = \(Sayi.kur(k)) ₺")
    }
}

/// Türkçe sayı biçimi: 1.234,56
public enum Sayi {
    static func bicim(_ n: Double, enAz: Int, enCok: Int) -> String {
        let carpan = pow(10.0, Double(enCok))
        let yuvarlak = (abs(n) * carpan).rounded() / carpan
        var kesir = String(format: "%.\(enCok)f", yuvarlak)
        let tam: String
        if let nokta = kesir.firstIndex(of: ".") {
            tam = String(kesir[..<nokta])
            kesir = String(kesir[kesir.index(after: nokta)...])
        } else {
            tam = kesir; kesir = ""
        }
        while kesir.count > enAz, kesir.hasSuffix("0") { kesir.removeLast() }
        var grup = ""
        for (i, c) in tam.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grup.append(".") }
            grup.append(c)
        }
        let govde = String(grup.reversed()) + (kesir.isEmpty ? "" : "," + kesir)
        return n < 0 ? "-" + govde : govde
    }

    public static func para(_ n: Double) -> String { bicim(n, enAz: 2, enCok: 2) }
    public static func kur(_ n: Double) -> String { bicim(n, enAz: 2, enCok: 4) }

    /// Kullanıcının yazdığı tutar: "1.250,50" ya da "1250.5".
    public static func oku(_ s: String) -> Double? {
        var t = s.kirpik
        if t.contains(",") { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        return Double(t)
    }
}
