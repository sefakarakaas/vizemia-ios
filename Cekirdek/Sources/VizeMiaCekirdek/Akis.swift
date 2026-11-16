import Foundation

// Sitenin uygulama için yazdığı veri dosyası: https://vizemia.com/assets/uygulama.json
// (VizeMia deposu → scripts/uygulama-akisi.mjs).
//
// SÖZLEŞME: alan adları o dosyayla birebir aynı. Site yalnız YENİ alan
// ekler; var olanı kaldırmaz. Burada da her alan eksik gelebilir diye
// varsayılanla okunuyor — sitedeki bir ekleme ya da eksik, telefondaki
// uygulamayı boş ekrana düşürmesin.

struct Coz<Anahtar: CodingKey> {
    let c: KeyedDecodingContainer<Anahtar>
    func metin(_ k: Anahtar) -> String { ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "" }
    func sayi(_ k: Anahtar) -> Double { ((try? c.decodeIfPresent(Double.self, forKey: k)) ?? nil) ?? 0 }
    func mantik(_ k: Anahtar) -> Bool { ((try? c.decodeIfPresent(Bool.self, forKey: k)) ?? nil) ?? false }
    func dizi<T: Decodable>(_ k: Anahtar, _ tur: T.Type = T.self) -> [T] { ((try? c.decodeIfPresent([T].self, forKey: k)) ?? nil) ?? [] }
    func nesne<T: Decodable>(_ k: Anahtar, _ tur: T.Type = T.self) -> T? { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil }
}

public struct Akis: Decodable, Equatable {
    public var surum: Int
    public var uretim: String
    public var iletisim: Iletisim
    public var servisUrl: String
    public var mesai: MesaiAyari?
    public var surec: Surec?
    public var kitalar: [Kita]
    public var sss: [Soru]
    public var harclar: [HarcGrubu]
    public var sayfalar: [Sayfa]

    enum Anahtar: String, CodingKey { case surum, uretim, iletisim, servisUrl, mesai, surec, kitalar, sss, harclar, sayfalar }

    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        surum = Int(c.sayi(.surum))
        uretim = c.metin(.uretim)
        iletisim = c.nesne(.iletisim) ?? Iletisim.varsayilan
        servisUrl = c.metin(.servisUrl)
        mesai = c.nesne(.mesai)
        surec = c.nesne(.surec)
        kitalar = c.dizi(.kitalar)
        sss = c.dizi(.sss)
        harclar = c.dizi(.harclar)
        sayfalar = c.dizi(.sayfalar)
    }

    public var ulkeRehberleri: [Sayfa] { sayfalar.filter { $0.tur == "ulke" } }
    public var yazilar: [Sayfa] { sayfalar.filter { $0.tur == "yazi" } }
    public func sayfa(_ yol: String) -> Sayfa? { sayfalar.first { $0.yol == yol } }
    public var tumUlkeler: [Ulke] { kitalar.flatMap { $0.ulkeler } }
    public func ulke(_ slug: String) -> Ulke? { tumUlkeler.first { $0.slug == slug } }
}

public struct Iletisim: Decodable, Equatable {
    public var telefonGorunen: String
    public var telefon: String
    public var whatsapp: String
    public var eposta: String
    public var adres: String
    public var enlem: Double
    public var boylam: Double
    public var haritaSorgu: String
    public var googleProfil: String
    public var instagram: String
    public var unvan: String

    enum Anahtar: String, CodingKey {
        case telefonGorunen, telefon, whatsapp, eposta, adres, enlem, boylam, haritaSorgu, googleProfil, instagram, unvan
    }

    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        let v = Iletisim.varsayilan
        func dolu(_ s: String, _ yedek: String) -> String { s.isEmpty ? yedek : s }
        telefonGorunen = dolu(c.metin(.telefonGorunen), v.telefonGorunen)
        telefon = dolu(c.metin(.telefon), v.telefon)
        whatsapp = dolu(c.metin(.whatsapp), v.whatsapp)
        eposta = dolu(c.metin(.eposta), v.eposta)
        adres = dolu(c.metin(.adres), v.adres)
        enlem = c.sayi(.enlem) == 0 ? v.enlem : c.sayi(.enlem)
        boylam = c.sayi(.boylam) == 0 ? v.boylam : c.sayi(.boylam)
        haritaSorgu = dolu(c.metin(.haritaSorgu), v.haritaSorgu)
        googleProfil = dolu(c.metin(.googleProfil), v.googleProfil)
        instagram = dolu(c.metin(.instagram), v.instagram)
        unvan = dolu(c.metin(.unvan), v.unvan)
    }

    init(telefonGorunen: String, telefon: String, whatsapp: String, eposta: String, adres: String, enlem: Double,
         boylam: Double, haritaSorgu: String, googleProfil: String, instagram: String, unvan: String) {
        self.telefonGorunen = telefonGorunen; self.telefon = telefon; self.whatsapp = whatsapp; self.eposta = eposta
        self.adres = adres; self.enlem = enlem; self.boylam = boylam; self.haritaSorgu = haritaSorgu
        self.googleProfil = googleProfil; self.instagram = instagram; self.unvan = unvan
    }

    public static let varsayilan = Iletisim(
        telefonGorunen: "0549 907 25 23", telefon: "+905499072523", whatsapp: "905499072523",
        eposta: "iletisim@vizemia.com",
        adres: "Çamlıca Mah. Bağdat Cad. No:83 İç Kapı No:157 Faras Ofis, Yenimahalle/Ankara",
        enlem: 39.959742148429214, boylam: 32.77444405239361,
        haritaSorgu: "Faras Ofis, Bağdat Cd. No:83, Çamlıca, Yenimahalle, Ankara",
        googleProfil: "https://www.google.com/maps?cid=1208255632900604146",
        instagram: "https://www.instagram.com/vizemiacom/",
        unvan: "VizeMia Seyahat Turizm Acentası Yazılım ve Mühendislik Ltd. Şti.")
}

public struct Surec: Decodable, Equatable {
    public struct Adim: Decodable, Equatable {
        public var baslik: String
        public var metin: String
        enum Anahtar: String, CodingKey { case baslik, metin }
        public init(from decoder: Decoder) throws {
            let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
            baslik = c.metin(.baslik); metin = c.metin(.metin)
        }
    }

    public var baslik: String
    public var aciklama: String
    public var adimlar: [Adim]

    enum Anahtar: String, CodingKey { case baslik, aciklama, adimlar }
    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        baslik = c.metin(.baslik); aciklama = c.metin(.aciklama); adimlar = c.dizi(.adimlar)
    }
}

public struct Ulke: Decodable, Equatable, Identifiable, Hashable {
    public var ad: String
    public var bayrak: String
    /// Formların Firestore'a yazdığı ülke kimliği (ör. "birlesik-krallik").
    public var slug: String
    public var schengen: Bool
    public var id: String { slug }

    enum Anahtar: String, CodingKey { case ad, bayrak, slug, schengen }
    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        ad = c.metin(.ad); bayrak = c.metin(.bayrak); slug = c.metin(.slug); schengen = c.mantik(.schengen)
    }
}

public struct Kita: Decodable, Equatable, Identifiable {
    public var id: String
    public var ad: String
    public var not: String
    public var ulkeler: [Ulke]

    enum Anahtar: String, CodingKey { case id, ad, not, ulkeler }
    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        id = c.metin(.id); ad = c.metin(.ad); not = c.metin(.not); ulkeler = c.dizi(.ulkeler)
    }
}

public struct Soru: Decodable, Equatable, Identifiable {
    public var soru: String
    public var cevap: String
    public var id: String { soru }

    enum Anahtar: String, CodingKey { case soru, cevap }
    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        soru = c.metin(.soru); cevap = c.metin(.cevap)
    }
}

public struct HarcGrubu: Decodable, Equatable, Identifiable {
    public var id: String
    public var ad: String
    /// Her satır [ad, tutar].
    public var satirlar: [[String]]
    /// [ad, adres]
    public var kaynak: [String]
    public var guncelleme: String

    enum Anahtar: String, CodingKey { case id, ad, satirlar, kaynak, guncelleme }
    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        id = c.metin(.id); ad = c.metin(.ad); satirlar = c.dizi(.satirlar); kaynak = c.dizi(.kaynak)
        guncelleme = c.metin(.guncelleme)
    }
}

/// Ülke rehberi, blog yazısı ya da kurumsal sayfa.
public struct Sayfa: Decodable, Equatable, Identifiable, Hashable {
    /// "ulke", "yazi" ya da "kurumsal".
    public var tur: String
    /// Sitedeki adresi: "/almanya-vizesi", "/blog/vize-reddi-sonrasi".
    public var yol: String
    public var baslik: String
    public var ad: String
    public var ozet: String
    public var gorsel: String
    public var alt: String
    /// Sayfadaki "Başvur" düğmesinin seçeceği ülke kimliği.
    public var ulke: String
    public var tarih: String
    public var guncelleme: String
    public var bloklar: [Blok]
    public var id: String { yol }

    public static func == (a: Sayfa, b: Sayfa) -> Bool { a.yol == b.yol && a.guncelleme == b.guncelleme && a.bloklar == b.bloklar }
    public func hash(into h: inout Hasher) { h.combine(yol) }

    enum Anahtar: String, CodingKey { case tur, yol, baslik, ad, ozet, gorsel, alt, ulke, tarih, guncelleme, bloklar }
    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        tur = c.metin(.tur); yol = c.metin(.yol); baslik = c.metin(.baslik); ad = c.metin(.ad)
        ozet = c.metin(.ozet); gorsel = c.metin(.gorsel); alt = c.metin(.alt); ulke = c.metin(.ulke)
        tarih = c.metin(.tarih); guncelleme = c.metin(.guncelleme); bloklar = c.dizi(.bloklar)
    }
}

/// Sayfanın bir parçası. Bilinmeyen tür (sitenin sonradan eklediği) atlanır.
public enum Blok: Decodable, Equatable {
    public struct Oge: Decodable, Equatable {
        public var baslik: String
        public var md: String
        enum Anahtar: String, CodingKey { case baslik, md }
        public init(from decoder: Decoder) throws {
            let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
            baslik = c.metin(.baslik); md = c.metin(.md)
        }
    }

    /// Basit Markdown metni.
    case metin(String)
    /// "Kısaca" kutusu.
    case ozet(String)
    /// Başvur çağrısı.
    case cta(baslik: String, metin: String, ulke: String)
    /// İki sütunlu tablo (harç).
    case tablo(baslik: String, satirlar: [[String]], not: String)
    /// Çok sütunlu karşılaştırma tablosu.
    case karsilastirma(baslik: String, sutunlar: [String], satirlar: [[String]], not: String)
    /// Açılır kutular (SSS, mesleğe göre evrak).
    case acilir(baslik: String, ogeler: [Oge])
    /// Resmî kaynaklar: [ad, adres].
    case kaynaklar([[String]])
    case bilinmeyen

    enum Anahtar: String, CodingKey { case tur, md, baslik, metin, ulke, satirlar, sutunlar, not, ogeler }

    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        switch c.metin(.tur) {
        case "metin": self = .metin(c.metin(.md))
        case "ozet": self = .ozet(c.metin(.md))
        case "cta": self = .cta(baslik: c.metin(.baslik), metin: c.metin(.metin), ulke: c.metin(.ulke))
        case "tablo": self = .tablo(baslik: c.metin(.baslik), satirlar: c.dizi(.satirlar), not: c.metin(.not))
        case "karsilastirma":
            self = .karsilastirma(baslik: c.metin(.baslik), sutunlar: c.dizi(.sutunlar), satirlar: c.dizi(.satirlar), not: c.metin(.not))
        case "acilir": self = .acilir(baslik: c.metin(.baslik), ogeler: c.dizi(.ogeler, Oge.self))
        case "kaynaklar": self = .kaynaklar(c.dizi(.ogeler, [String].self))
        default: self = .bilinmeyen
        }
    }
}
