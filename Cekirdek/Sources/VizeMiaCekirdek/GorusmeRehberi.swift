import Foundation

// Görüşme rehberi: müşteriyle telefonda konuşurken yanda duran bilgi kutusu.
// Varsayılan uygulama.json → rehber (panel: data/gorusme-rehberi.js), Ayarlar'dan
// kaydedilen hâli settings/rehber; ikisi rehberAyari kuralıyla birleşir.
// Metin biçimi: satır başında "- " madde, **iki yıldız** arası kalın.

public struct GorusmeRehberi: Decodable, Equatable {
    public struct Kart: Decodable, Equatable, Identifiable {
        public var baslik: String
        public var etiket: String
        public var metin: String
        public var id: String { baslik }
        enum Anahtar: String, CodingKey { case baslik, etiket, metin }
        public init(from decoder: Decoder) throws {
            let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
            baslik = c.metin(.baslik); etiket = c.metin(.etiket); metin = c.metin(.metin)
        }
        public init(baslik: String, etiket: String, metin: String) { self.baslik = baslik; self.etiket = etiket; self.metin = metin }
    }

    public struct KritikSoru: Decodable, Equatable {
        public var soru: String
        public var aciklama: String
        public var evet: String
        public var hayir: String
        enum Anahtar: String, CodingKey { case soru, aciklama, evet, hayir }
        public init(from decoder: Decoder) throws {
            let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
            soru = c.metin(.soru); aciklama = c.metin(.aciklama); evet = c.metin(.evet); hayir = c.metin(.hayir)
        }
        public init(soru: String, aciklama: String, evet: String, hayir: String) {
            self.soru = soru; self.aciklama = aciklama; self.evet = evet; self.hayir = hayir
        }
    }

    public struct UlkeAlani: Decodable, Equatable { public var key: String; public var ad: String }

    public var kaynak: String
    public var ilkSorular: [String]
    public var kritikSoru: KritikSoru
    public var ornekKonusma: String
    public var kategoriler: [Kart]
    public var bolumler: [Kart]
    /// Ülke kimliği → alan (merkez, randevu, otelUcak, ikametgah, ilkBasvuru, notlar) → metin.
    public var ulkeler: [String: [String: String]]
    public var ulkeAlanlari: [UlkeAlani]

    enum Anahtar: String, CodingKey { case kaynak, ilkSorular, kritikSoru, ornekKonusma, kategoriler, bolumler, ulkeler, ulkeAlanlari }

    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        kaynak = c.metin(.kaynak)
        ilkSorular = c.dizi(.ilkSorular)
        kritikSoru = c.nesne(.kritikSoru) ?? KritikSoru(soru: "", aciklama: "", evet: "", hayir: "")
        ornekKonusma = c.metin(.ornekKonusma)
        kategoriler = c.dizi(.kategoriler)
        bolumler = c.dizi(.bolumler)
        ulkeler = c.nesne(.ulkeler) ?? [:]
        ulkeAlanlari = c.dizi(.ulkeAlanlari)
    }

    static let enCokKart = 30
    static let enCokUlke = 120

    static func kisalt(_ d: FSDeger?, _ n: Int) -> String { String((d?.metinDegeri ?? "").replacingOccurrences(of: "\r", with: "").prefix(n)) }

    static func kartlar(_ d: FSDeger?) -> [Kart] {
        (d?.diziDegeri ?? []).compactMap { x -> Kart? in
            let m = x.haritaDegeri ?? [:]
            let k = Kart(baslik: kisalt(m["baslik"], 80).kirpik, etiket: kisalt(m["etiket"], 30).kirpik, metin: kisalt(m["metin"], 4000).kirpik)
            return k.baslik.isEmpty ? nil : k
        }.prefix(enCokKart).map { $0 }
    }

    /// settings/rehber belgesini doğrular; eksik ya da bozuk kısım varsayılandan gelir (panel: rehberAyari).
    public func ayarla(_ belge: [String: FSDeger]?) -> GorusmeRehberi {
        guard let b = belge else { return self }
        var r = self
        let sorular = (b["ilkSorular"]?.diziDegeri ?? []).map { kisaltS($0.metinDegeri, 80) }.filter { !$0.isEmpty }.prefix(20)
        let ks = b["kritikSoru"]?.haritaDegeri ?? [:]
        r.kaynak = b["kaynak"] != nil ? Self.kisalt(b["kaynak"], 120) : kaynak
        r.ilkSorular = sorular.isEmpty ? ilkSorular : Array(sorular)
        r.kritikSoru = KritikSoru(
            soru: Self.kisalt(ks["soru"], 120).kirpik.isEmpty ? kritikSoru.soru : Self.kisalt(ks["soru"], 120).kirpik,
            aciklama: ks["aciklama"] != nil ? Self.kisalt(ks["aciklama"], 300).kirpik : kritikSoru.aciklama,
            evet: Self.kisalt(ks["evet"], 80).kirpik.isEmpty ? kritikSoru.evet : Self.kisalt(ks["evet"], 80).kirpik,
            hayir: Self.kisalt(ks["hayir"], 80).kirpik.isEmpty ? kritikSoru.hayir : Self.kisalt(ks["hayir"], 80).kirpik)
        r.ornekKonusma = b["ornekKonusma"] != nil ? Self.kisalt(b["ornekKonusma"], 4000).kirpik : ornekKonusma
        if b["kategoriler"]?.diziDegeri != nil { r.kategoriler = Self.kartlar(b["kategoriler"]) }
        if b["bolumler"]?.diziDegeri != nil { r.bolumler = Self.kartlar(b["bolumler"]) }
        if let u = b["ulkeler"]?.haritaDegeri {
            var l: [String: [String: String]] = [:]
            for (id, v) in u.sorted(by: { $0.key < $1.key }).prefix(Self.enCokUlke) {
                guard id.eslesir("^[a-z0-9-]{2,40}$"), let m = v.haritaDegeri else { continue }
                var satir = ["notlar": Self.kisalt(m["notlar"], 4000).kirpik]
                for a in ulkeAlanlari { satir[a.key] = Self.kisalt(m[a.key], 60).kirpik }
                l[id] = satir
            }
            r.ulkeler = l
        }
        return r
    }

    private func kisaltS(_ s: String?, _ n: Int) -> String { String((s ?? "").prefix(n)).kirpik }

    /// Kategori kartı (kritik sorunun cevabına göre).
    public func kategori(_ ad: String) -> Kart? {
        kategoriler.first { $0.baslik.lowercased(with: Tr.yerel) == ad.lowercased(with: Tr.yerel) }
    }

    // MARK: Metin biçimi

    public struct Parca: Equatable { public var metin: String; public var kalin: Bool }
    public enum Blok: Equatable { case paragraf([Parca]), liste([[Parca]]) }

    /// "a **b** c" → [a, b(kalın), c] (panel: satirParcalari).
    public static func parcalar(_ s: String) -> [Parca] {
        s.components(separatedBy: "**").enumerated().map { Parca(metin: $0.element, kalin: $0.offset % 2 == 1) }.filter { !$0.metin.isEmpty }
    }

    /// Ardışık "- " satırları bir liste, öteki satırlar paragraf (panel: metinBloklari).
    public static func bloklar(_ metin: String) -> [Blok] {
        var b: [Blok] = []
        for satir in metin.components(separatedBy: "\n").map({ $0.kirpik }) where !satir.isEmpty {
            if satir.hasPrefix("- ") || satir.hasPrefix("• ") || satir.hasPrefix("-\t") {
                let m = parcalar(String(satir.dropFirst(2)).kirpik)
                if case .liste(var l)? = b.last { l.append(m); b[b.count - 1] = .liste(l) } else { b.append(.liste([m])) }
            } else {
                b.append(.paragraf(parcalar(satir)))
            }
        }
        return b
    }

    /// "Temsilci: metin" → (kim, metin) (panel: konusmaSatirlari).
    public static func konusma(_ metin: String) -> [(kim: String, metin: String)] {
        metin.components(separatedBy: "\n").map { $0.kirpik }.filter { !$0.isEmpty }.map { s in
            if let i = s.firstIndex(of: ":"), s.distance(from: s.startIndex, to: i) <= 30, i > s.startIndex {
                return (String(s[..<i]).kirpik, String(s[s.index(after: i)...]).kirpik)
            }
            return ("", s)
        }
    }

    /// Dikkat çekilecek değer ("önerilmez", "şart", "çok önemli").
    public static func dikkat(_ s: String) -> Bool {
        let k = s.lowercased(with: Tr.yerel)
        return k.contains("önerilmez") || k.contains("şart") || k.contains("çok önemli")
    }
}
