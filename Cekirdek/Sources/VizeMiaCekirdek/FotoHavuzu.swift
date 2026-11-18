import Foundation

// Fotoğraf havuzu (panel: pages/havuz.js, data/foto-havuzu.js): görsel
// yüklenmemiş vitrin slaytlarının arka planları. Hazır fotoğraflar sitede
// (assets/img/havuz/<id>.webp), panelden / uygulamadan eklenenler Firestore'da
// (fotoHavuzu; görsel küçültülmüş data: adresi, en çok 700 bin karakter).
// "Görünen alan" (odak): fotoğrafın ekranda ortada tutulacak noktası, "x% y%".

public enum FotoHavuzu {
    public struct Hazir: Equatable, Identifiable {
        public var id: String
        public var ulke: String
        public var odak: String
        /// Otomatik seçime girer mi (hazır slaytların kendi fotoğrafları girmez).
        public var oto = true
        public var url: URL { URL(string: "https://vizemia.com/assets/img/havuz/\(id).webp")! }
    }

    public static let orta = "50% 50%"
    /// Kural: str(gorsel, 700000).
    public static let gorselSiniri = 700_000

    /// Depodaki fotoğraflar, panelle aynı sırada (otomatik seçim sıraya bağlı).
    public static let hazirlar: [Hazir] = {
        let l: [(String, String, String)] = [
            ("almanya-brandenburg", "almanya", orta), ("almanya-rothenburg", "almanya", orta),
            ("fransa-eyfel", "fransa", "60% 50%"), ("fransa-kopru", "fransa", orta), ("fransa-eyfel-park", "fransa", orta),
            ("italya-kolezyum", "italya", orta), ("italya-venedik", "italya", orta),
            ("hollanda-amsterdam", "hollanda", orta), ("hollanda-kanal", "hollanda", orta),
            ("cekya-prag", "cekya", orta),
            ("ispanya-sevilla", "ispanya", orta), ("ispanya-madrid", "ispanya", orta),
            ("yunanistan-akropolis", "yunanistan", orta), ("yunanistan-santorini", "yunanistan", orta),
            ("avusturya-viyana", "avusturya", orta), ("avusturya-hofburg", "avusturya", orta),
            ("isvicre-alpler", "isvicre", orta), ("isvicre-lauterbrunnen", "isvicre", orta),
            ("birlesik-krallik-big-ben", "birlesik-krallik", orta), ("birlesik-krallik-westminster", "birlesik-krallik", orta),
            ("birlesik-krallik-londra", "birlesik-krallik", orta),
            ("abd-ozgurluk-heykeli", "abd", orta), ("abd-golden-gate", "abd", orta), ("abd-new-york", "abd", orta),
            ("kanada-moraine", "kanada", orta), ("kanada-toronto", "kanada", orta),
            ("genel-ucak-kanadi", "", orta), ("genel-ucak-penceresi", "", orta), ("genel-havalimani", "", orta),
            ("genel-yolcu", "", orta), ("genel-terminal", "", orta), ("genel-gol", "", orta), ("genel-bulutlar", "", orta),
            ("genel-ucak", "", orta), ("genel-sirt-cantasi", "", orta), ("genel-harita", "", orta),
        ]
        // Hazır vitrin slaytlarının kendi fotoğrafları: yalnız o slaytlar (havuzFoto ile) kullanır.
        let varsayilan = ["randevu", "gerekenler", "schengen-evrak", "vize-reddi", "biyometrik-fotograf", "seyahat-sigortasi", "basvuru-suresi"]
            .map { Hazir(id: "varsayilan-\($0)", ulke: "", odak: orta, oto: false) }
        return l.map { Hazir(id: $0.0, ulke: $0.1, odak: $0.2) } + varsayilan
    }()

    /// Havuzdaki bir fotoğraf (hazır ya da eklenen) — arka plan seçimi için.
    public struct Foto: Equatable, Identifiable {
        public var id: String
        public var ulke: String
        public var odak: String
        public var oto: Bool
        public var hazir: Bool
        /// Görüntü: hazırda site adresi, eklenende data: adresi.
        public var yol: String
    }

    /// Hazır + eklenen tek listede (panel: havuzKur). Eklenenin kimliği "u-<belge>".
    public static func kur(_ eklenenler: [Eklenen]) -> [Foto] {
        hazirlar.map { Foto(id: $0.id, ulke: $0.ulke, odak: $0.odak, oto: $0.oto, hazir: true, yol: $0.url.absoluteString) }
            + eklenenler.map { Foto(id: "u-\($0.id)", ulke: $0.ulke, odak: odakGecerli($0.odak) ? $0.odak : orta, oto: true, hazir: false, yol: $0.gorsel) }
    }

    public static func ulkeFotosuVar(_ ulke: String, _ havuz: [Foto]) -> Bool {
        !ulke.isEmpty && havuz.contains { $0.ulke == ulke && $0.oto }
    }

    /// Aday fotoğraflar: ülke seçiliyse (ve fotoğrafı varsa) o ülkeninkiler, değilse genel.
    public static func adaylar(ulke: String, _ havuz: [Foto]) -> [Foto] {
        let secilebilir = havuz.filter(\.oto)
        return ulkeFotosuVar(ulke, havuz) ? secilebilir.filter { $0.ulke == ulke } : secilebilir.filter { $0.ulke.isEmpty }
    }

    /// Kararlı özet (FNV-1a, 32 bit): aynı slayt her yayında aynı fotoğrafı alır.
    static func ozet(_ s: String) -> UInt32 {
        var x: UInt32 = 2_166_136_261
        for u in s.unicodeScalars { x ^= u.value; x = x &* 16_777_619 }
        return x
    }

    public struct ArkaPlan: Equatable {
        public var gorsel: String
        public var odak: String
        /// yuklenen | secilen | otomatik | yok
        public var kaynak: String
        public var fotoId: String
    }

    /// Slaytın arka plan girdisi.
    public struct SlaytGirdisi: Equatable {
        public var id: String
        public var ulke: String
        public var gorsel: String
        public var havuzFoto: String
        public var odak: String
        public var sira: Int
        public init(id: String, ulke: String = "", gorsel: String = "", havuzFoto: String = "", odak: String = "", sira: Int = 0) {
            self.id = id; self.ulke = ulke; self.gorsel = gorsel; self.havuzFoto = havuzFoto; self.odak = odak; self.sira = sira
        }
    }

    /// Tek slaytın arka planı (panel: slaytFotosu). `onceki`: soldaki slaytın görseli (tekrar olmasın).
    public static func slaytFotosu(_ s: SlaytGirdisi, _ havuz: [Foto], onceki: String = "") -> ArkaPlan {
        func odakOf(_ v: String) -> String { odakGecerli(s.odak) ? s.odak : (v.isEmpty ? orta : v) }
        if !s.gorsel.isEmpty { return ArkaPlan(gorsel: s.gorsel, odak: odakOf(orta), kaynak: "yuklenen", fotoId: "") }
        if !s.havuzFoto.isEmpty, let f = havuz.first(where: { $0.id == s.havuzFoto }) {
            return ArkaPlan(gorsel: f.yol, odak: odakOf(f.odak), kaynak: "secilen", fotoId: f.id)
        }
        let l = adaylar(ulke: s.ulke, havuz)
        guard !l.isEmpty else { return ArkaPlan(gorsel: "", odak: orta, kaynak: "yok", fotoId: "") }
        let bas = Int(ozet(s.id) % UInt32(l.count))
        for k in 0..<l.count {
            let f = l[(bas + k) % l.count]
            if f.yol != onceki || l.count == 1 { return ArkaPlan(gorsel: f.yol, odak: odakOf(f.odak), kaynak: "otomatik", fotoId: f.id) }
        }
        return ArkaPlan(gorsel: "", odak: orta, kaynak: "yok", fotoId: "")
    }

    /// Sıralı slaytların arka planları, yan yana tekrar olmadan (panel: vitrinFotolari).
    public static func vitrinFotolari(_ l: [SlaytGirdisi], _ havuz: [Foto]) -> [ArkaPlan] {
        var onceki = ""
        return l.map { s in
            let f = slaytFotosu(s, havuz, onceki: onceki)
            onceki = f.gorsel
            return f
        }
    }

    /// Slaytın yayındaki sırasına göre arka planı (panel: arkaPlanOf). `komsular`: yayındaki diğer slaytlar.
    public static func arkaPlan(_ taslak: SlaytGirdisi, komsular: [SlaytGirdisi], _ havuz: [Foto]) -> ArkaPlan {
        let liste = (komsular.filter { $0.id != taslak.id } + [taslak]).enumerated()
            .sorted { $0.element.sira != $1.element.sira ? $0.element.sira < $1.element.sira : $0.offset < $1.offset }.map(\.element)
        let i = liste.firstIndex { $0.id == taslak.id } ?? 0
        let s = vitrinFotolari(liste, havuz)[i]
        let fotoId = taslak.gorsel.isEmpty ? (havuz.first { $0.yol == s.gorsel }?.id ?? "") : ""
        let kaynak = !taslak.gorsel.isEmpty ? "yuklenen"
            : (!taslak.havuzFoto.isEmpty && fotoId == taslak.havuzFoto ? "secilen" : (s.gorsel.isEmpty ? "yok" : "otomatik"))
        return ArkaPlan(gorsel: s.gorsel, odak: s.odak, kaynak: kaynak, fotoId: fotoId)
    }

    /// "Başka fotoğraf": adaylar arasında bir sonraki.
    public static func sonrakiFoto(ulke: String, _ havuz: [Foto], simdiki: String) -> String {
        let l = adaylar(ulke: ulke, havuz)
        guard !l.isEmpty else { return "" }
        let i = l.firstIndex { $0.id == simdiki } ?? -1
        return l[(i + 1) % l.count].id
    }

    /// Panelden / uygulamadan eklenen (fotoHavuzu/{id}).
    public struct Eklenen: Equatable, Identifiable {
        public var id: String
        public var gorsel: String
        public var ulke: String
        public var odak: String
        public var ad: String

        public init(kimlik: String, alanlar a: [String: FSDeger]) {
            id = kimlik
            gorsel = a["gorsel"]?.metinDegeri ?? ""
            ulke = a["ulke"]?.metinDegeri ?? ""
            odak = a["odak"]?.metinDegeri ?? FotoHavuzu.orta
            ad = a["ad"]?.metinDegeri ?? ""
        }

        /// data: adresindeki baytlar (görüntülemek için).
        public var bayt: Data? {
            guard let v = gorsel.range(of: ";base64,") else { return nil }
            return Data(base64Encoded: String(gorsel[v.upperBound...]))
        }
    }

    /// "x% y%" ve 0–100 arası mı?
    public static func odakGecerli(_ v: String) -> Bool {
        let p = v.components(separatedBy: " ")
        guard p.count == 2 else { return false }
        return p.allSatisfy { s in
            guard s.hasSuffix("%"), let n = Int(s.dropLast()), s.count <= 4 else { return false }
            return (0...100).contains(n)
        }
    }

    /// Dokunulan nokta (yüzde) → "x% y%" (panel: odakYaz).
    public static func odakYaz(_ x: Double, _ y: Double) -> String {
        "\(Int(min(100, max(0, x)).rounded()))% \(Int(min(100, max(0, y)).rounded()))%"
    }

    /// "x% y%" → (0…1, 0…1); geçersizse orta.
    public static func odakOku(_ v: String) -> (x: Double, y: Double) {
        guard odakGecerli(v) else { return (0.5, 0.5) }
        let p = v.split(separator: " ").compactMap { Int($0.dropLast()) }
        return (Double(p[0]) / 100, Double(p[1]) / 100)
    }

    /// JPEG baytlarından kurala uyan data: adresi.
    public static func veriAdresi(jpeg: Data) -> String { "data:image/jpeg;base64,\(jpeg.base64EncodedString())" }

    static func kayit(_ eylem: String, _ hedef: String, _ ayrinti: String, _ c: Calisan) -> FirestoreIstemci.Yazim {
        .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                 alanlar: IslemKaydi.alanlar(eylem: eylem, hedef: hedef, ayrinti: String(ayrinti.prefix(500)), calisan: c), zaman: ["at"])
    }

    public static func ekle(gorsel: String, ulke: String, odak: String, ad: String, kimlik: String = FirestoreIstemci.yeniKimlik(),
                            calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let a: [String: FSDeger] = [
            "gorsel": .metin(gorsel), "ulke": .metin(ulke), "odak": .metin(odakGecerli(odak) ? odak : orta),
            "ad": .metin(String(ad.kirpik.prefix(80))), "createdBy": .metin(c.uid), "updatedBy": .metin(c.uid),
        ]
        return [.olustur(yol: "fotoHavuzu/\(kimlik)", alanlar: a, zaman: ["createdAt", "updatedAt"]), kayit("havuz.create", kimlik, ad, c)]
    }

    /// Yalnız görünen alan değişir (görsel ve oluşturma alanları olduğu gibi).
    public static func odakGuncelle(_ e: Eklenen, odak: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.guncelle(yol: "fotoHavuzu/\(e.id)", alanlar: ["odak": .metin(odak), "updatedBy": .metin(c.uid)], zaman: ["updatedAt"]),
         kayit("havuz.update", e.id, odak, c)]
    }

    public static func sil(_ e: Eklenen, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.sil(yol: "fotoHavuzu/\(e.id)"), kayit("havuz.delete", e.id, e.ad, c)]
    }
}
