import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Siteden okunan içerik: uygulama.json (rehberler, blog, SSS, harçlar…),
/// vitrin.json (ana sayfa slaytları), kur.json (TCMB kuru).
///
/// Üç katman var; hangisi varsa o gösterilir, sonraki gelince yerini alır:
///   1. Uygulamayla gelen kopya — internet olmasa da, ilk açılışta da ekran dolu.
///   2. Cihazdaki son indirilen kopya.
///   3. Siteden taze indirilen.
public struct IcerikKaynagi {
    public var site: URL
    public var onbellek: URL?
    public var oturum: URLSession

    public init(site: URL = Hedef.site, onbellek: URL? = nil, oturum: URLSession = .shared) {
        self.site = site
        self.onbellek = onbellek
        self.oturum = oturum
    }

    public enum Dosya: String, CaseIterable {
        case uygulama, vitrin, kur
        var yol: String { "/assets/\(rawValue).json" }
    }

    /// Uygulamayla gelen kopya.
    public static func gomulu<T: Decodable>(_ dosya: Dosya, _ tur: T.Type = T.self) -> T? {
        guard let u = Bundle.module.url(forResource: dosya.rawValue, withExtension: "json"),
              let veri = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(T.self, from: veri)
    }

    /// Cihazdaki son indirilen kopya.
    public func kayitli<T: Decodable>(_ dosya: Dosya, _ tur: T.Type = T.self) -> T? {
        guard let u = onbellek?.appendingPathComponent("\(dosya.rawValue).json"),
              let veri = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(T.self, from: veri)
    }

    /// Siteden indirir; okunabiliyorsa cihaza da kaydeder. Olmazsa nil.
    public func indir<T: Decodable>(_ dosya: Dosya, _ tur: T.Type = T.self) async -> T? {
        guard let u = URL(string: site.absoluteString + dosya.yol) else { return nil }
        return await indir(u, kayit: dosya.rawValue)
    }

    /// Verilen adresten JSON indirir (anlık kur servisi için de kullanılır).
    public func indir<T: Decodable>(_ adres: URL, kayit: String? = nil, _ tur: T.Type = T.self) async -> T? {
        var istek = URLRequest(url: adres)
        istek.cachePolicy = .reloadIgnoringLocalCacheData
        istek.timeoutInterval = 15
        guard let (veri, kod) = try? await Ag.gonder(istek, oturum: oturum), kod == 200,
              let deger = try? JSONDecoder().decode(T.self, from: veri) else { return nil }
        if let ad = kayit, let klasor = onbellek {
            try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
            try? veri.write(to: klasor.appendingPathComponent("\(ad).json"), options: .atomic)
        }
        return deger
    }
}

/// Yeni talep bildirimi: form gönderilince Apps Script servisine yalnız talebin
/// türü ve kimliği gider. Servis talebi Firestore'dan kendisi okur, ekibe
/// Telegram ve e-posta ile haber verir (site/assets/bildirim-servisi.js).
public enum Bildirim {
    public static func gonder(servis: String, tur: String, kimlik: String, oturum: URLSession = .shared) async {
        guard !kimlik.isEmpty, servis.hasPrefix("https://"), let u = URL(string: servis),
              let govde = try? JSONSerialization.data(withJSONObject: ["tur": tur, "id": kimlik]) else { return }
        var istek = URLRequest(url: u)
        istek.httpMethod = "POST"
        istek.timeoutInterval = 20
        istek.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        istek.httpBody = govde
        // Bildirim gitmese de talep kaydedildi; yanıt okunmuyor.
        _ = try? await Ag.gonder(istek, oturum: oturum)
    }
}
