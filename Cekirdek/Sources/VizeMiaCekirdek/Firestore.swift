import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Firestore'daki bir değer (REST biçimi).
public indirect enum FSDeger: Equatable {
    case bos
    case mantik(Bool)
    case tam(Int)
    case ondalik(Double)
    case metin(String)
    case zaman(Date)
    case dizi([FSDeger])
    case harita([String: FSDeger])

    public var metinDegeri: String? { if case .metin(let v) = self { return v }; return nil }
    public var mantikDegeri: Bool? { if case .mantik(let v) = self { return v }; return nil }
    public var zamanDegeri: Date? { if case .zaman(let v) = self { return v }; return nil }
    public var diziDegeri: [FSDeger]? { if case .dizi(let v) = self { return v }; return nil }
    public var haritaDegeri: [String: FSDeger]? { if case .harita(let v) = self { return v }; return nil }
    public var tamDegeri: Int? {
        switch self {
        case .tam(let v): return v
        // Panel sayıyı ondalık yazmış olabilir (3.0); yalnız tam sayıysa kabul.
        case .ondalik(let v): return v == v.rounded() ? Int(v) : nil
        default: return nil
        }
    }

    /// REST yanıtındaki `{ "stringValue": "…" }` biçiminden.
    init(json: Any) {
        guard let o = json as? [String: Any] else { self = .bos; return }
        if let v = o["stringValue"] as? String { self = .metin(v) }
        else if let v = o["booleanValue"] as? Bool { self = .mantik(v) }
        else if let v = o["integerValue"] {
            if let s = v as? String, let n = Int(s) { self = .tam(n) }
            else if let n = v as? Int { self = .tam(n) }
            else { self = .bos }
        }
        else if let v = o["doubleValue"] as? Double { self = .ondalik(v) }
        else if let v = o["doubleValue"] as? Int { self = .ondalik(Double(v)) }
        else if let v = o["timestampValue"] as? String, let d = FSDeger.zamanOku(v) { self = .zaman(d) }
        else if let v = o["arrayValue"] as? [String: Any] {
            self = .dizi(((v["values"] as? [Any]) ?? []).map { FSDeger(json: $0) })
        }
        else if let v = o["mapValue"] as? [String: Any] {
            self = .harita(FSDeger.alanlar(v["fields"]))
        }
        else { self = .bos }
    }

    static func alanlar(_ json: Any?) -> [String: FSDeger] {
        var out: [String: FSDeger] = [:]
        for (k, v) in (json as? [String: Any]) ?? [:] { out[k] = FSDeger(json: v) }
        return out
    }

    /// REST isteğine yazılacak biçim.
    var json: [String: Any] {
        switch self {
        case .bos: return ["nullValue": NSNull()]
        case .mantik(let v): return ["booleanValue": v]
        case .tam(let v): return ["integerValue": String(v)]
        case .ondalik(let v): return ["doubleValue": v]
        case .metin(let v): return ["stringValue": v]
        case .zaman(let v): return ["timestampValue": FSDeger.zamanYaz(v)]
        case .dizi(let v): return ["arrayValue": ["values": v.map { $0.json }]]
        case .harita(let v): return ["mapValue": ["fields": v.mapValues { $0.json }]]
        }
    }

    /// "2026-11-05T09:41:16.458Z" ya da kesirsiz "2026-11-05T09:41:16Z".
    static func zamanOku(_ s: String) -> Date? {
        let kesirli = ISO8601DateFormatter()
        kesirli.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = kesirli.date(from: s) { return d }
        let duz = ISO8601DateFormatter()
        duz.formatOptions = [.withInternetDateTime]
        if let d = duz.date(from: s) { return d }
        // Nanosaniyeli (9 hane) zamanlar: kesri at.
        return duz.date(from: s.degistir("\\.[0-9]+", ""))
    }

    static func zamanYaz(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }
}

public enum FirestoreHatasi: Error, Equatable {
    /// Güvenlik kuralı isteği reddetti (403).
    case izinYok
    /// Sunucu başka bir hata döndü.
    case sunucu(Int)
    /// Bağlantı kurulamadı.
    case baglanti
}

/// Firestore'un REST arayüzü. Firebase SDK'sı yerine bu kullanılıyor: uygulama
/// yalnız üç şey yapıyor (kimlikle tek belge okumak, iki koleksiyona kayıt
/// eklemek); bunun için 20 MB'lık bir kütüphane taşımaya gerek yok. İstekler
/// giriş yapmadan gider ve siteyle aynı güvenlik kurallarından geçer.
public struct FirestoreIstemci {
    public var taban: URL
    public var proje: String
    public var oturum: URLSession
    /// Çalışan girişi yapıldıysa Firebase kimlik belirteci: istekler o çalışan
    /// adına gider, güvenlik kuralları panelle aynı izinleri uygular.
    public var belirtec: String?

    public init(
        taban: URL = URL(string: "https://firestore.googleapis.com/v1")!,
        proje: String = "vieze-941cf",
        oturum: URLSession = .shared,
        belirtec: String? = nil
    ) {
        self.taban = taban
        self.proje = proje
        self.oturum = oturum
        self.belirtec = belirtec
    }

    public struct Belge: Equatable {
        /// Belgenin kimliği (yolun son parçası).
        public var kimlik: String
        public var alanlar: [String: FSDeger]
    }

    public enum Yon: String { case artan = "ASCENDING", azalan = "DESCENDING" }

    /// Sorgu koşulu: alan, işlem ("EQUAL", "IN", "GREATER_THAN_OR_EQUAL", "LESS_THAN" …), değer.
    public struct Kosul {
        public var alan: String
        public var islem: String
        public var deger: FSDeger

        public init(_ alan: String, _ islem: String, _ deger: FSDeger) {
            self.alan = alan; self.islem = islem; self.deger = deger
        }

        public static func esit(_ a: String, _ d: FSDeger) -> Kosul { Kosul(a, "EQUAL", d) }
        public static func icinde(_ a: String, _ d: [FSDeger]) -> Kosul { Kosul(a, "IN", .dizi(d)) }
        public static func enAz(_ a: String, _ d: FSDeger) -> Kosul { Kosul(a, "GREATER_THAN_OR_EQUAL", d) }
        public static func kucuk(_ a: String, _ d: FSDeger) -> Kosul { Kosul(a, "LESS_THAN", d) }

        var json: [String: Any] {
            ["fieldFilter": ["field": ["fieldPath": alan], "op": islem, "value": deger.json]]
        }
    }

    /// Tek koleksiyonda sorgu (koşulların hepsi), `sirala` alanına göre, en çok `sinir` kayıt.
    public func sorgu(
        koleksiyon: String,
        kosullar: [Kosul] = [],
        sirala: (String, Yon)? = nil,
        sinir: Int = 200,
        ust: String? = nil
    ) async throws -> [Belge] {
        var istek = URLRequest(url: adres(ust.map { "\(kok)/\($0):runQuery" } ?? "\(kok):runQuery"))
        istek.httpMethod = "POST"
        istek.timeoutInterval = 20
        istek.setValue("application/json", forHTTPHeaderField: "Content-Type")
        istek.httpBody = try JSONSerialization.data(withJSONObject: ["structuredQuery": FirestoreIstemci.sorguYapisi(
            koleksiyon: koleksiyon, kosullar: kosullar, sirala: sirala, sinir: sinir)])
        let (veri, kod) = try await gonder(istek)
        guard kod == 200 else { throw kod == 403 ? FirestoreHatasi.izinYok : FirestoreHatasi.sunucu(kod) }
        return FirestoreIstemci.sorguCevabi(veri)
    }

    static func sorguYapisi(koleksiyon: String, kosullar: [Kosul], sirala: (String, Yon)?, sinir: Int) -> [String: Any] {
        var yapi: [String: Any] = ["from": [["collectionId": koleksiyon]], "limit": sinir]
        if kosullar.count == 1 {
            yapi["where"] = kosullar[0].json
        } else if kosullar.count > 1 {
            yapi["where"] = ["compositeFilter": ["op": "AND", "filters": kosullar.map { $0.json }]]
        }
        if let (a, y) = sirala {
            yapi["orderBy"] = [["field": ["fieldPath": a], "direction": y.rawValue]]
        }
        return yapi
    }

    static func sorguCevabi(_ veri: Data) -> [Belge] {
        let dizi = (try? JSONSerialization.jsonObject(with: veri)) as? [[String: Any]] ?? []
        return dizi.compactMap { satir in
            guard let b = satir["document"] as? [String: Any], let ad = b["name"] as? String else { return nil }
            return Belge(kimlik: String(ad.split(separator: "/").last ?? ""), alanlar: FSDeger.alanlar(b["fields"]))
        }
    }

    /// Var olan belgede yalnız verilen alanları değiştirir; `zamanAlanlari`
    /// sunucu saatiyle yazılır (kurallar `handledAt == request.time` istiyor).
    public func guncelle(_ yol: String, alanlar: [String: FSDeger], zamanAlanlari: [String] = []) async throws {
        var istek = URLRequest(url: adres("\(kok):commit"))
        istek.httpMethod = "POST"
        istek.timeoutInterval = 20
        istek.setValue("application/json", forHTTPHeaderField: "Content-Type")
        istek.httpBody = try JSONSerialization.data(withJSONObject: FirestoreIstemci.guncellemeGovdesi(
            ad: "\(kok)/\(yol)", alanlar: alanlar, zamanAlanlari: zamanAlanlari))
        let (_, kod) = try await gonder(istek)
        guard kod == 200 else { throw kod == 403 ? FirestoreHatasi.izinYok : FirestoreHatasi.sunucu(kod) }
    }

    /// Belgeyi verilen alanlarla yazar (varsa üzerine). Yalnız testlerde, emülatöre
    /// yönetici belirteciyle örnek veri koymak için.
    func belgeYaz(_ yol: String, alanlar: [String: FSDeger]) async throws {
        var istek = URLRequest(url: adres("\(kok):commit"))
        istek.httpMethod = "POST"
        istek.setValue("application/json", forHTTPHeaderField: "Content-Type")
        istek.httpBody = try JSONSerialization.data(withJSONObject: [
            "writes": [["update": ["name": "\(kok)/\(yol)", "fields": alanlar.mapValues { $0.json }]]],
        ])
        let (_, kod) = try await gonder(istek)
        guard kod == 200 else { throw FirestoreHatasi.sunucu(kod) }
    }

    static func guncellemeGovdesi(ad: String, alanlar: [String: FSDeger], zamanAlanlari: [String]) -> [String: Any] {
        [
            "writes": [[
                "update": ["name": ad, "fields": alanlar.mapValues { $0.json }],
                "updateMask": ["fieldPaths": alanlar.keys.sorted()],
                "currentDocument": ["exists": true],
                "updateTransforms": zamanAlanlari.map { ["fieldPath": $0, "setToServerValue": "REQUEST_TIME"] },
            ] as [String: Any]],
        ]
    }

    var kok: String { "projects/\(proje)/databases/(default)/documents" }

    /// Tek belgeyi okur. Belge yoksa nil.
    public func belge(_ yol: String) async throws -> [String: FSDeger]? {
        var istek = URLRequest(url: adres("\(kok)/\(yol)"))
        istek.cachePolicy = .reloadIgnoringLocalCacheData
        istek.timeoutInterval = 20
        let (veri, kod) = try await gonder(istek)
        if kod == 404 { return nil }
        guard kod == 200 else { throw kod == 403 ? FirestoreHatasi.izinYok : FirestoreHatasi.sunucu(kod) }
        let o = (try? JSONSerialization.jsonObject(with: veri)) as? [String: Any]
        return FSDeger.alanlar(o?["fields"])
    }

    /// Koleksiyona yeni belge ekler; `zamanAlani` sunucu saatiyle doldurulur
    /// (kurallar `createdAt == request.time` istiyor). Belgenin kimliğini döner.
    @discardableResult
    public func ekle(koleksiyon: String, alanlar: [String: FSDeger], zamanAlani: String = "createdAt") async throws -> String {
        let kimlik = FirestoreIstemci.yeniKimlik()
        var istek = URLRequest(url: adres("\(kok):commit"))
        istek.httpMethod = "POST"
        istek.timeoutInterval = 20
        istek.setValue("application/json", forHTTPHeaderField: "Content-Type")
        istek.httpBody = try JSONSerialization.data(withJSONObject: FirestoreIstemci.eklemeGovdesi(
            ad: "\(kok)/\(koleksiyon)/\(kimlik)", alanlar: alanlar, zamanAlani: zamanAlani))
        let (_, kod) = try await gonder(istek)
        guard kod == 200 else { throw kod == 403 ? FirestoreHatasi.izinYok : FirestoreHatasi.sunucu(kod) }
        return kimlik
    }

    /// `documents:commit` gövdesi: belge yoksa oluştur, zaman alanını sunucu yazsın.
    static func eklemeGovdesi(ad: String, alanlar: [String: FSDeger], zamanAlani: String) -> [String: Any] {
        [
            "writes": [[
                "update": ["name": ad, "fields": alanlar.mapValues { $0.json }],
                "currentDocument": ["exists": false],
                "updateTransforms": [["fieldPath": zamanAlani, "setToServerValue": "REQUEST_TIME"]],
            ] as [String: Any]],
        ]
    }

    /// Firebase SDK'sının ürettiğiyle aynı biçimde 20 karakterlik rastgele kimlik.
    static func yeniKimlik() -> String {
        let harfler = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var uretec = SystemRandomNumberGenerator()
        return String((0..<20).map { _ in harfler[Int.random(in: 0..<harfler.count, using: &uretec)] })
    }

    func adres(_ yol: String) -> URL {
        // "(default)" ve ":commit" yolun parçası; olduğu gibi kalmalı.
        URL(string: taban.absoluteString + "/" + yol)!
    }

    func gonder(_ istek: URLRequest) async throws -> (Data, Int) {
        var i = istek
        if let b = belirtec { i.setValue("Bearer \(b)", forHTTPHeaderField: "Authorization") }
        return try await Ag.gonder(i, oturum: oturum)
    }
}

/// URLSession'ın async sarmalayıcısı (Linux'ta da aynı çalışsın diye elle).
enum Ag {
    static func gonder(_ istek: URLRequest, oturum: URLSession) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { devam in
            let gorev = oturum.dataTask(with: istek) { veri, yanit, hata in
                if hata != nil || veri == nil {
                    devam.resume(throwing: FirestoreHatasi.baglanti)
                    return
                }
                devam.resume(returning: (veri ?? Data(), (yanit as? HTTPURLResponse)?.statusCode ?? 0))
            }
            gorev.resume()
        }
    }
}
