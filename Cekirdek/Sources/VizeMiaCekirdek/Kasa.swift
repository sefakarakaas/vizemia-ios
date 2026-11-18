import Foundation

// Kasa: gelir/gider defteri, döviz çevrimi, rutin ödemeler ve raporlar.
// Panel: panel/js/kasa.js (testleri tests/kasa.test.mjs; buradaki testler aynı örnekleri kullanır).
// Para birimleri hiçbir yerde birbirine çevrilmez: TL, EUR, USD, GBP ayrı toplanır.

/// Birim → tutar ("TRY": 1500, "EUR": 80).
public typealias ParaToplami = [String: Double]

public enum KasaKurali {
    public static let paraBirimleri = ["TRY", "EUR", "USD", "GBP"]
    public static let yontemler: [(id: String, ad: String)] = [
        ("nakit", "Nakit"), ("kart", "Kredi / banka kartı"), ("havale", "Havale / EFT"), ("diger", "Diğer"),
    ]
    public static func yontemAdi(_ id: String) -> String { yontemler.first { $0.id == id }?.ad ?? id }
    public static let enCokTutar = 10_000_000.0
    public static let kategoriEnCok = 40

    /// Kuruşa yuvarlar.
    public static func yuvarla(_ n: Double) -> Double { (n * 100).rounded() / 100 }
    static func tarihMi(_ s: String) -> Bool { s.eslesir("^\\d{4}-\\d{2}-\\d{2}$") }
    static func tutarGecerli(_ t: Double?) -> Bool { if let t { return t > 0 && t <= enCokTutar && t.isFinite }; return false }

    /// Metin listesi: kırpılmış, boşsuz, tekrarsız (panel: listeTemizle).
    public static func listeTemizle(_ l: [String], enCok: Int = kategoriEnCok, uzunluk: Int = 60) -> [String] {
        var gorulen = Set<String>(), sonuc: [String] = []
        for x in l {
            let s = String(x.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(uzunluk))
            if !s.isEmpty && !gorulen.contains(s) { gorulen.insert(s); sonuc.append(s) }
        }
        return Array(sonuc.prefix(enCok))
    }

    /// Harcama formu hataları (boş: geçerli).
    public static func giderHatalari(_ g: KasaGirdisi, bugun: String, kategoriler: [String] = []) -> [String] {
        var h: [String] = []
        if !["musteri", "genel"].contains(g.kapsam) { h.append("Harcama türünü seçin.") }
        if g.kategori.isEmpty { h.append("Kategori seçin.") }
        else if !kategoriler.isEmpty && !kategoriler.contains(g.kategori) { h.append("Kategori listede yok.") }
        if !tutarGecerli(g.tutar) { h.append("Geçerli bir tutar girin.") }
        if !paraBirimleri.contains(g.paraBirimi) { h.append("Para birimi geçersiz.") }
        if !yontemler.contains(where: { $0.id == g.yontem }) { h.append("Ödeme yöntemini seçin.") }
        if !tarihMi(g.tarih) { h.append("Tarih girin.") } else if g.tarih > bugun { h.append("İleri tarihli harcama girilemez.") }
        if g.kapsam == "musteri" && g.appId.isEmpty { h.append("Müşteriyi (başvuruyu) seçin.") }
        if g.aciklama.count > 300 { h.append("Açıklama en çok 300 karakter.") }
        return h
    }

    /// Döviz çevrimi formu hataları.
    public static func cevrimHatalari(_ c: KasaGirdisi, bugun: String) -> [String] {
        var h: [String] = []
        if !tutarGecerli(c.tutar) { h.append("Verilen tutarı girin.") }
        if !tutarGecerli(c.hedefTutar) { h.append("Çevrim tutarını (alınan tutar) girin.") }
        if !paraBirimleri.contains(c.paraBirimi) || !paraBirimleri.contains(c.hedefParaBirimi) { h.append("Para birimi geçersiz.") }
        else if c.paraBirimi == c.hedefParaBirimi { h.append("Verilen ve alınan para birimi farklı olmalı.") }
        let buro = c.buro.kirpik
        if buro.isEmpty { h.append("Döviz bürosunu girin.") } else if buro.count > 80 { h.append("Büro adı en çok 80 karakter.") }
        if !yontemler.contains(where: { $0.id == c.yontem }) { h.append("Yöntemi seçin.") }
        if !tarihMi(c.tarih) { h.append("Tarih girin.") } else if c.tarih > bugun { h.append("İleri tarihli çevrim girilemez.") }
        if c.aciklama.count > 300 { h.append("Açıklama en çok 300 karakter.") }
        return h
    }

    /// Bilgi amaçlı kur: "1 EUR = 48,5 TRY" (hesaplarda kullanılmaz).
    public static func cevrimKuru(tutar: Double?, paraBirimi: String, hedefTutar: Double?, hedefParaBirimi: String) -> String {
        guard let t = tutar, let ht = hedefTutar, t > 0, ht > 0 else { return "" }
        let (az, cok, oran) = ht >= t ? (paraBirimi, hedefParaBirimi, ht / t) : (hedefParaBirimi, paraBirimi, t / ht)
        return "1 \(az) = \(Sayi.bicim(oran, enAz: 0, enCok: 4)) \(cok)"
    }

    // MARK: Tarih aralıkları (hafta pazartesi başlar)

    public static let araliklar: [(id: String, ad: String)] = [
        ("bugun", "Bugün"), ("dun", "Dün"), ("hafta", "Bu hafta"), ("gecenHafta", "Geçen hafta"),
        ("ay", "Bu ay"), ("gecenAy", "Geçen ay"), ("ozel", "Tarih aralığı"),
    ]

    /// İki uç dahil.
    public static func aralik(_ tur: String, bugun: String, ozelBas: String = "", ozelBit: String = "") -> (bas: String, bit: String) {
        let haftaBasi = { (iso: String) in Tr.gunEkle(iso, -((Tr.gunNo(iso) + 6) % 7)) }
        let ayBasi = { (iso: String) in String(iso.prefix(7)) + "-01" }
        switch tur {
        case "dun": let d = Tr.gunEkle(bugun, -1); return (d, d)
        case "hafta": return (haftaBasi(bugun), bugun)
        case "gecenHafta": let b = Tr.gunEkle(haftaBasi(bugun), -7); return (b, Tr.gunEkle(b, 6))
        case "ay": return (ayBasi(bugun), bugun)
        case "gecenAy": let bit = Tr.gunEkle(ayBasi(bugun), -1); return (ayBasi(bit), bit)
        case "ozel":
            let bas = tarihMi(ozelBas) ? ozelBas : bugun
            let bit = tarihMi(ozelBit) ? ozelBit : bas
            return bas <= bit ? (bas, bit) : (bit, bas)
        default: return (bugun, bugun)
        }
    }

    /// Aralıktaki günler (en çok 366).
    public static func gunler(bas: String, bit: String) -> [String] {
        var l: [String] = []
        var d = bas
        while d <= bit && l.count < 366 { l.append(d); d = Tr.gunEkle(d, 1) }
        return l
    }

    // MARK: Yazı

    /// "1.500 TRY + 80 EUR"; boşsa `bos`.
    public static func paraYazi(_ t: ParaToplami, bos: String = "0") -> String {
        let l = t.filter { $0.value != 0 }
            .sorted { (paraBirimleri.firstIndex(of: $0.key) ?? 99) < (paraBirimleri.firstIndex(of: $1.key) ?? 99) }
            .map { "\(Sayi.bicim($0.value, enAz: 0, enCok: 2)) \($0.key)" }
        return l.isEmpty ? bos : l.joined(separator: " + ")
    }

    /// "+4.850 TRY, −100 EUR"
    public static func isaretli(_ t: ParaToplami) -> String {
        let l = t.filter { $0.value != 0 }
            .sorted { (paraBirimleri.firstIndex(of: $0.key) ?? 99) < (paraBirimleri.firstIndex(of: $1.key) ?? 99) }
            .map { "\($0.value > 0 ? "+" : "−")\(paraYazi([$0.key: abs($0.value)]))" }
        return l.isEmpty ? "—" : l.joined(separator: ", ")
    }

    /// "Döviz çevrimi · Kızılay Döviz" ya da kategori.
    public static func tutarYazi(_ x: KasaHareketi) -> String {
        if x.tur == "cevrim" {
            return "−\(paraYazi([x.paraBirimi: x.tutar ?? 0])) → +\(paraYazi([x.hedefParaBirimi: x.hedefTutar ?? 0]))"
        }
        guard let t = x.tutar else { return "—" }
        return "\(x.tur == "gelir" ? "+" : "−")\(paraYazi([x.paraBirimi: t]))"
    }
}

/// Formdan gelen kayıt (gider ya da çevrim).
public struct KasaGirdisi: Equatable {
    public var tur = "gider"
    public var kapsam = "genel"
    public var kategori = ""
    public var tutar: Double?
    public var paraBirimi = "TRY"
    public var yontem = "nakit"
    public var tarih = ""
    public var aciklama = ""
    public var appId = ""
    public var takipKodu = ""
    public var musteriAd = ""
    public var rutinId = ""
    public var rutinVade = ""
    public var hedefTutar: Double?
    public var hedefParaBirimi = "TRY"
    public var buro = ""

    public init() {}

    /// Kurallardaki alan listesiyle aynı (ortak(d)): rutin ve çevrim alanları yalnız gerekiyorsa.
    func alanlar(calisan c: Calisan, fisId: String?) -> [String: FSDeger] {
        var a: [String: FSDeger] = [:]
        a["tur"] = .metin(tur)
        a["kapsam"] = .metin(kapsam)
        a["kategori"] = .metin(String(kategori.prefix(60)))
        a["tutar"] = OdemeKurali.tutarDegeri(tutar)
        a["paraBirimi"] = .metin(paraBirimi)
        a["yontem"] = .metin(yontem)
        a["tarih"] = .metin(tarih)
        a["aciklama"] = .metin(String(aciklama.kirpik.prefix(300)))
        a["appId"] = .metin(appId)
        a["takipKodu"] = .metin(takipKodu)
        a["musteriAd"] = .metin(String(musteriAd.prefix(160)))
        if !rutinId.isEmpty { a["rutinId"] = .metin(rutinId); a["rutinVade"] = .metin(rutinVade) }
        if tur == "cevrim" {
            a["hedefTutar"] = OdemeKurali.tutarDegeri(hedefTutar)
            a["hedefParaBirimi"] = .metin(hedefParaBirimi)
            a["buro"] = .metin(String(buro.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(80)))
        }
        if let fisId { a["fisId"] = .metin(fisId) }
        a["by"] = .metin(c.uid)
        a["byName"] = .metin(String(c.gorunenAd.prefix(80)))
        a["iptal"] = .mantik(false)
        return a
    }
}

/// Defterdeki bir hareket (kasa/{id}).
public struct KasaHareketi: Equatable, Identifiable {
    public var id: String
    public var tur: String
    public var kapsam: String
    public var kategori: String
    public var tutar: Double?
    public var paraBirimi: String
    public var yontem: String
    public var tarih: String
    public var aciklama: String
    public var appId: String
    public var takipKodu: String
    public var musteriAd: String
    public var rutinId: String
    public var rutinVade: String
    public var hedefTutar: Double?
    public var hedefParaBirimi: String
    public var buro: String
    public var fisId: String
    public var yazan: String
    public var zaman: Date?
    public var iptal: Bool
    public var iptalNot: String
    public var iptalAd: String

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        func sayi(_ k: String) -> Double? {
            switch a[k] {
            case .tam(let v): return Double(v)
            case .ondalik(let v): return v
            default: return nil
            }
        }
        func m(_ k: String) -> String { a[k]?.metinDegeri ?? "" }
        id = kimlik
        tur = m("tur"); kapsam = m("kapsam"); kategori = m("kategori")
        tutar = sayi("tutar"); paraBirimi = m("paraBirimi"); yontem = m("yontem"); tarih = m("tarih")
        aciklama = m("aciklama"); appId = m("appId"); takipKodu = m("takipKodu"); musteriAd = m("musteriAd")
        rutinId = m("rutinId"); rutinVade = m("rutinVade")
        hedefTutar = sayi("hedefTutar"); hedefParaBirimi = m("hedefParaBirimi"); buro = m("buro")
        fisId = m("fisId"); yazan = m("byName"); zaman = a["at"]?.zamanDegeri
        iptal = a["iptal"]?.mantikDegeri ?? false
        iptalNot = m("iptalNot"); iptalAd = m("iptalAd")
    }
}

/// Raporun toplamları (panel: kasaOzeti). İptal edilenler sayılmaz.
public struct KasaOzeti: Equatable {
    public struct Gun: Equatable {
        public var gelir: ParaToplami = [:]
        public var gider: ParaToplami = [:]
        public var cevrim: ParaToplami = [:]
        public init(gelir: ParaToplami = [:], gider: ParaToplami = [:], cevrim: ParaToplami = [:]) {
            self.gelir = gelir; self.gider = gider; self.cevrim = cevrim
        }
    }
    public struct Sayilar: Equatable {
        public var gelir = 0, gider = 0, cevrim = 0, iptal = 0, tutarsizGelir = 0
        public init(gelir: Int = 0, gider: Int = 0, cevrim: Int = 0, iptal: Int = 0, tutarsizGelir: Int = 0) {
            self.gelir = gelir; self.gider = gider; self.cevrim = cevrim; self.iptal = iptal; self.tutarsizGelir = tutarsizGelir
        }
    }
    public var gelir: ParaToplami = [:]
    public var gider: ParaToplami = [:]
    public var net: ParaToplami = [:]
    public var nakit: ParaToplami = [:]
    public var giderKategori: [String: ParaToplami] = [:]
    public var giderKapsam: [String: ParaToplami] = [:]
    public var gelirYontem: [String: ParaToplami] = [:]
    public var giderYontem: [String: ParaToplami] = [:]
    public var cevrimCikan: ParaToplami = [:]
    public var cevrimGiren: ParaToplami = [:]
    public var cevrimNet: ParaToplami = [:]
    public var kasa: ParaToplami = [:]
    public var gunluk: [String: Gun] = [:]
    public var sayi = Sayilar()

    static func art(_ t: inout ParaToplami, _ b: String, _ n: Double) { t[b] = KasaKurali.yuvarla((t[b] ?? 0) + n) }
    static func ekle(_ o: inout [String: ParaToplami], _ k: String, _ b: String, _ n: Double) {
        var t = o[k] ?? [:]
        art(&t, b, n)
        o[k] = t
    }

    public init(_ hareketler: [KasaHareketi]) {
        for x in hareketler {
            if x.iptal { sayi.iptal += 1; continue }
            if x.tur == "cevrim" {
                sayi.cevrim += 1
                guard let t = x.tutar, let ht = x.hedefTutar, t > 0, ht > 0, !x.paraBirimi.isEmpty, !x.hedefParaBirimi.isEmpty else { continue }
                Self.art(&cevrimCikan, x.paraBirimi, t)
                Self.art(&cevrimGiren, x.hedefParaBirimi, ht)
                Self.art(&cevrimNet, x.paraBirimi, -t)
                Self.art(&cevrimNet, x.hedefParaBirimi, ht)
                Self.art(&kasa, x.paraBirimi, -t)
                Self.art(&kasa, x.hedefParaBirimi, ht)
                if x.yontem == "nakit" { Self.art(&nakit, x.paraBirimi, -t); Self.art(&nakit, x.hedefParaBirimi, ht) }
                var g = gunluk[x.tarih] ?? Gun()
                Self.art(&g.cevrim, x.paraBirimi, -t)
                Self.art(&g.cevrim, x.hedefParaBirimi, ht)
                gunluk[x.tarih] = g
                continue
            }
            let gelirMi = x.tur == "gelir"
            if gelirMi { sayi.gelir += 1 } else { sayi.gider += 1 }
            guard let t = x.tutar, t > 0, !x.paraBirimi.isEmpty else {
                if gelirMi { sayi.tutarsizGelir += 1 }
                continue
            }
            let b = x.paraBirimi
            let isaret: Double = gelirMi ? 1 : -1
            if gelirMi { Self.art(&gelir, b, t) } else { Self.art(&gider, b, t) }
            Self.art(&net, b, isaret * t)
            Self.art(&kasa, b, isaret * t)
            if x.yontem == "nakit" { Self.art(&nakit, b, isaret * t) }
            if gelirMi {
                Self.ekle(&gelirYontem, x.yontem.isEmpty ? "diger" : x.yontem, b, t)
            } else {
                Self.ekle(&giderKategori, x.kategori.isEmpty ? "Diğer" : x.kategori, b, t)
                Self.ekle(&giderKapsam, x.kapsam == "musteri" ? "musteri" : "genel", b, t)
                Self.ekle(&giderYontem, x.yontem.isEmpty ? "diger" : x.yontem, b, t)
            }
            var g = gunluk[x.tarih] ?? Gun()
            if gelirMi { Self.art(&g.gelir, b, t) } else { Self.art(&g.gider, b, t) }
            gunluk[x.tarih] = g
        }
    }

    /// Kırılım satırları, TL tutarı büyükten küçüğe (panel: kirilim).
    public static func kirilim(_ o: [String: ParaToplami]) -> [(ad: String, toplam: ParaToplami)] {
        o.map { ($0.key, $0.value) }.sorted { ($0.1["TRY"] ?? 0) > ($1.1["TRY"] ?? 0) }
    }

    /// Bu dönemde hareketi olan para birimleri.
    public var birimler: [String] {
        KasaKurali.paraBirimleri.filter { b in [gelir, gider, cevrimCikan, cevrimGiren, nakit].contains { ($0[b] ?? 0) != 0 } }
    }
}

/// Excel'de açılan CSV (noktalı virgül, UTF-8 BOM). Panel: kasaCsv.
public enum KasaCsv {
    public static func metin(_ hareketler: [KasaHareketi]) -> String {
        func hucre(_ s: String) -> String {
            s.contains(where: { $0 == "\"" || $0 == ";" || $0 == "\n" || $0 == "\r" }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
        }
        func sayi(_ n: Double?) -> String {
            guard let n else { return "" }
            return OdemeKurali.sayiYazi(n).replacingOccurrences(of: ".", with: ",")
        }
        let turAdi = ["gelir": "Gelir", "gider": "Gider", "cevrim": "Döviz çevrimi"]
        var satirlar: [[String]] = [["Tarih", "Tür", "Kapsam", "Kategori", "Müşteri", "Takip kodu", "Açıklama", "Yöntem", "Tutar", "Para birimi",
                                     "Çevrim tutarı (alınan)", "Alınan para birimi", "Döviz bürosu", "Fiş", "Giren", "Durum"]]
        for x in hareketler {
            let eksi = x.tur == "gider" || x.tur == "cevrim"
            satirlar.append([
                x.tarih, turAdi[x.tur] ?? x.tur, x.kapsam == "musteri" ? "Müşteri" : "Genel", x.kategori,
                x.musteriAd, x.takipKodu, x.aciklama, KasaKurali.yontemAdi(x.yontem),
                sayi(x.tutar.map { eksi ? -$0 : $0 }), x.paraBirimi,
                sayi(x.hedefTutar), x.hedefParaBirimi, x.buro, x.fisId.isEmpty ? "" : "Var", x.yazan,
                x.iptal ? "İptal: \(x.iptalNot)" : "",
            ])
        }
        return "\u{FEFF}" + satirlar.map { $0.map(hucre).joined(separator: ";") }.joined(separator: "\r\n") + "\r\n"
    }
}

// MARK: - Ayarlar

/// settings/kasa (panel: kasaAyari). Yalnız uygulamanın kullandığı alanlar.
public struct KasaAyari: Equatable {
    public static let varsayilanMusteriGiderleri = [
        "Fotokopi", "Fotoğraf çekimi", "Çıktı / tarama", "Kargo / kurye", "Noter onayı", "Tercüme",
        "Konsolosluk harcı", "Aracı kurum (VFS, iDATA…) ücreti", "Seyahat sağlık sigortası",
        "Otel / uçak rezervasyonu", "Ulaşım", "Diğer",
    ]
    public static let varsayilanGenelGiderler = [
        "Market alışverişi", "Kırtasiye", "Yemek / ikram", "Temizlik", "Ulaşım", "Fatura (elektrik, su, internet, telefon)",
        "Kira", "Reklam", "Bakım / onarım", "Diğer",
    ]
    public var musteriGiderleri = varsayilanMusteriGiderleri
    public var genelGiderler = varsayilanGenelGiderler
    public var raporSaati = "20:00"
    public var dovizBurolari: [String] = []

    public init() {}

    public init(alanlar a: [String: FSDeger]?) {
        guard let a else { return }
        func liste(_ k: String) -> [String]? { a[k]?.diziDegeri.map { $0.compactMap { $0.metinDegeri } } }
        if let l = liste("musteriGiderleri").map({ KasaKurali.listeTemizle($0) }), !l.isEmpty { musteriGiderleri = l }
        if let l = liste("genelGiderler").map({ KasaKurali.listeTemizle($0) }), !l.isEmpty { genelGiderler = l }
        if let s = a["raporSaati"]?.metinDegeri, s.eslesir("^([01]\\d|2[0-3]):[0-5]\\d$") { raporSaati = s }
        dovizBurolari = KasaKurali.listeTemizle(liste("dovizBurolari") ?? [], uzunluk: 80)
    }
}

// MARK: - Rutin ödemeler (kasaRutin)

public struct RutinOdeme: Equatable, Identifiable {
    public static let sikliklar: [(id: String, ad: String)] = [("haftalik", "Haftalık"), ("aylik", "Aylık"), ("yillik", "Yıllık")]
    public static let haftaGunleri = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
    /// Bu kadar günden eski ödenmemiş vadeler artık gösterilmez.
    public static let geriyeGun = 62

    public var id: String
    public var ad = ""
    public var kategori = ""
    public var tutar: Double?
    public var paraBirimi = "TRY"
    public var yontem = "havale"
    public var siklik = "aylik"
    /// Haftalık: 1 = pazartesi … 7 = pazar; aylık: ayın günü; yıllık: başlangıcın günü.
    public var gun = 1
    public var baslangic = ""
    public var bitis = ""
    public var aktif = true
    public var not = ""
    public var otomatik = false
    public var otomatikBas = ""

    public init(id: String = "") { self.id = id }

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        id = kimlik
        ad = a["ad"]?.metinDegeri ?? ""
        kategori = a["kategori"]?.metinDegeri ?? ""
        switch a["tutar"] {
        case .tam(let v): tutar = Double(v)
        case .ondalik(let v): tutar = v
        default: tutar = nil
        }
        paraBirimi = a["paraBirimi"]?.metinDegeri ?? "TRY"
        yontem = a["yontem"]?.metinDegeri ?? "havale"
        siklik = a["siklik"]?.metinDegeri ?? "aylik"
        gun = a["gun"]?.tamDegeri ?? 1
        baslangic = a["baslangic"]?.metinDegeri ?? ""
        bitis = a["bitis"]?.metinDegeri ?? ""
        aktif = a["aktif"]?.mantikDegeri ?? true
        not = a["not"]?.metinDegeri ?? ""
        otomatik = a["otomatik"]?.mantikDegeri ?? false
        otomatikBas = a["otomatikBas"]?.metinDegeri ?? ""
    }

    /// Kural: validRutin (updatedAt / updatedBy yazımda eklenir).
    func alanlar() -> [String: FSDeger] {
        var a: [String: FSDeger] = [:]
        a["ad"] = .metin(String(ad.kirpik.prefix(80)))
        a["kategori"] = .metin(kategori)
        a["tutar"] = OdemeKurali.tutarDegeri(tutar)
        a["paraBirimi"] = .metin(paraBirimi)
        a["yontem"] = .metin(yontem)
        a["siklik"] = .metin(siklik)
        a["gun"] = .tam(gun)
        a["baslangic"] = .metin(baslangic)
        a["bitis"] = .metin(bitis)
        a["aktif"] = .mantik(aktif)
        a["not"] = .metin(String(not.kirpik.prefix(300)))
        a["otomatik"] = .mantik(otomatik)
        a["otomatikBas"] = .metin(otomatikBas)
        return a
    }

    public var hatalar: [String] {
        var h: [String] = []
        if ad.kirpik.isEmpty { h.append("Ad girin (ör. Elektrik faturası).") }
        if kategori.isEmpty { h.append("Kategori seçin.") }
        if tutar != nil && !KasaKurali.tutarGecerli(tutar) { h.append("Tutar geçersiz.") }
        if !Self.sikliklar.contains(where: { $0.id == siklik }) { h.append("Sıklık seçin.") }
        if siklik == "haftalik" && !(1...7).contains(gun) { h.append("Haftanın gününü seçin.") }
        if siklik == "aylik" && !(1...31).contains(gun) { h.append("Ayın gününü girin (1–31).") }
        if !KasaKurali.tarihMi(baslangic) { h.append("Başlangıç tarihi girin.") }
        if !bitis.isEmpty && (!KasaKurali.tarihMi(bitis) || bitis < baslangic) { h.append("Bitiş tarihi başlangıçtan önce olamaz.") }
        if otomatik && tutar == nil { h.append("Otomatik kayıt için tutar girin (tutar her ay değişiyorsa otomatiği kapatın).") }
        return h
    }

    /// "Her ayın 15. günü", "Her cuma", "Her yıl 01.03".
    public var yazi: String {
        if siklik == "haftalik" {
            let g = (1...7).contains(gun) ? Self.haftaGunleri[gun - 1] : ""
            return "Her \(g.lowercased(with: Tr.yerel))"
        }
        if siklik == "aylik" { return "Her ayın \(gun). günü" }
        let p = baslangic.split(separator: "-")
        return p.count == 3 ? "Her yıl \(p[2]).\(p[1])" : "Her yıl"
    }

    static func ayinSonGunu(_ y: Int, _ m: Int) -> Int {
        let son = Tr.gunEkle(Tr.iso(yil: m == 12 ? y + 1 : y, ay: m == 12 ? 1 : m + 1, gun: 1), -1)
        return Int(son.suffix(2)) ?? 28
    }

    /// [bas, bit] aralığındaki vade günleri (panel: rutinVadeleri).
    public func vadeler(bas: String, bit: String) -> [String] {
        guard aktif, KasaKurali.tarihMi(baslangic) else { return [] }
        let ilk = baslangic > bas ? baslangic : bas
        let son = !bitis.isEmpty && bitis < bit ? bitis : bit
        var l: [String] = []
        if ilk > son { return l }
        if siklik == "haftalik" {
            var d = ilk
            while d <= son {
                if (Tr.gunNo(d) + 6) % 7 + 1 == gun { l.append(d) }
                d = Tr.gunEkle(d, 1)
            }
            return l
        }
        var y = Int(ilk.prefix(4)) ?? 0
        var m = Int(ilk.dropFirst(5).prefix(2)) ?? 1
        let bm = Int(baslangic.dropFirst(5).prefix(2)) ?? 1
        let bg = Int(baslangic.suffix(2)) ?? 1
        for _ in 0..<400 {
            let d: String
            if siklik == "aylik" {
                d = Tr.iso(yil: y, ay: m, gun: min(gun, Self.ayinSonGunu(y, m)))
                m += 1
                if m > 12 { m = 1; y += 1 }
            } else {
                d = Tr.iso(yil: y, ay: bm, gun: min(bg, Self.ayinSonGunu(y, bm)))
                y += 1
            }
            if d > son { break }
            if d >= ilk { l.append(d) }
        }
        return l
    }

    /// Rutin vadesinin defter kimliği (kural da aynısını ister).
    public static func kasaId(_ rutinId: String, _ vade: String) -> String { "r_\(rutinId)_\(vade)" }

    public struct Vade: Equatable, Identifiable {
        public var rutin: RutinOdeme
        public var vade: String
        public var id: String { "\(rutin.id)|\(vade)" }
    }

    /// Ödenmemiş vadeler (geçmiş 62 gün) ve yaklaşanlar (panel: bekleyenRutinler).
    public static func bekleyenler(_ rutinler: [RutinOdeme], odenenler: [KasaHareketi], bugun: String, ileriGun: Int = 7)
        -> (geciken: [Vade], bugun: [Vade], yaklasan: [Vade]) {
        let odendi = Set(odenenler.filter { !$0.iptal && !$0.rutinId.isEmpty }.map { "\($0.rutinId)|\($0.rutinVade)" })
        var g: [Vade] = [], b: [Vade] = [], y: [Vade] = []
        let bas = Tr.gunEkle(bugun, -geriyeGun), bit = Tr.gunEkle(bugun, ileriGun)
        for r in rutinler {
            for v in r.vadeler(bas: bas, bit: bit) where !odendi.contains("\(r.id)|\(v)") {
                let x = Vade(rutin: r, vade: v)
                if v < bugun { g.append(x) } else if v == bugun { b.append(x) } else { y.append(x) }
            }
        }
        let sirala = { (l: [Vade]) in
            l.sorted { $0.vade != $1.vade ? $0.vade < $1.vade : $0.rutin.ad.compare($1.rutin.ad, locale: Tr.yerel) == .orderedAscending }
        }
        return (sirala(g), sirala(b), sirala(y))
    }
}

// MARK: - Yazımlar

public enum KasaIslemi {
    typealias Y = FirestoreIstemci.Yazim

    /// Harcama / çevrim / rutin ödemesi (+ varsa fiş) tek yazımda (panel: kasaYaz).
    /// `basvuru`: müşteri harcaması başvuru ekranından girildiyse geçmişe de yazılır.
    public static func kaydet(_ g: KasaGirdisi, fis: HazirDosya?, kimlik: String = FirestoreIstemci.yeniKimlik(),
                              basvuru: Basvuru? = nil, calisan c: Calisan) -> (id: String, yazimlar: [FirestoreIstemci.Yazim]) {
        let yol = "kasa/\(kimlik)"
        var y: [Y] = []
        var fisId: String?
        if let fis {
            let e = Dosya.ekle(ust: yol, tur: "fis", dosya: fis, calisan: c)
            fisId = e.id
            y += e.yazimlar
        }
        y.insert(.olustur(yol: yol, alanlar: g.alanlar(calisan: c, fisId: fisId), zaman: ["at"]), at: 0)
        if let b = basvuru {
            let tutar = g.tutar.map { OdemeKurali.sayiYazi($0) } ?? ""
            var metin = "Harcama: \(g.kategori) · \(tutar) \(g.paraBirimi)"
            if !g.aciklama.kirpik.isEmpty { metin += " · \(g.aciklama.kirpik)" }
            if fis != nil { metin += " · fiş eklendi" }
            y.append(BasvuruIslemi.gecmis(b, tur: "gider", metin: String(metin.prefix(500)), c))
        }
        return (kimlik, y)
    }

    /// Yönetici: yanlış kaydı gerekçeyle iptal eder (silinmez; raporlarda sayılmaz).
    public static func iptal(_ x: KasaHareketi, neden: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let n = String(neden.kirpik.prefix(300))
        let tutar = x.tutar.map { OdemeKurali.sayiYazi($0) } ?? ""
        return [
            .guncelle(yol: "kasa/\(x.id)", alanlar: [
                "iptal": .mantik(true), "iptalNot": .metin(n), "iptalBy": .metin(c.uid), "iptalAd": .metin(String(c.gorunenAd.prefix(80))),
            ], zaman: ["iptalAt"]),
            islemKaydi("kasa.iptal", x.id, "\(x.tarih) \(x.kategori) \(tutar) \(x.paraBirimi) — \(n)", c),
        ]
    }

    /// Rutin ödeme ekle / düzenle / durdur (belge baştan yazılır; panel: setDoc).
    /// Durdurma / yeniden başlatma işlem kaydına yazılmaz (panelde de öyle).
    public static func rutinKaydet(_ r: RutinOdeme, kaydaYaz: Bool = true, calisan c: Calisan) -> (id: String, yazimlar: [FirestoreIstemci.Yazim]) {
        let yeni = r.id.isEmpty
        let id = yeni ? FirestoreIstemci.yeniKimlik() : r.id
        var a = r.alanlar()
        a["updatedBy"] = .metin(c.uid)
        var y: [Y] = [.yaz(yol: "kasaRutin/\(id)", alanlar: a, zaman: ["updatedAt"])]
        if kaydaYaz { y.append(islemKaydi("kasa.rutin", id, "\(yeni ? "Eklendi" : "Düzenlendi"): \(r.ad.kirpik) (\(r.yazi))", c)) }
        return (id, y)
    }

    public static func rutinSil(_ r: RutinOdeme, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.sil(yol: "kasaRutin/\(r.id)"), islemKaydi("kasa.rutin", r.id, "Silindi: \(r.ad)", c)]
    }

    static func islemKaydi(_ eylem: String, _ hedef: String, _ ayrinti: String, _ c: Calisan) -> Y {
        .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                 alanlar: IslemKaydi.alanlar(eylem: eylem, hedef: hedef, ayrinti: String(ayrinti.prefix(500)), calisan: c), zaman: ["at"])
    }
}
