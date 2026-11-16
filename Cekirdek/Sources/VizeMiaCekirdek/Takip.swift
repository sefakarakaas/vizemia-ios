import Foundation

/// Başvuru takibi: site/assets/takip-giris.js ve takip.js ile aynı kurallar.
///
/// Kayıtlar `takip/{kimlik}` belgesinden okunur; kimlik bilinmeden belge
/// listelenemez (kurallarda `get` var, `list` yok). Kimlik türetmesi siteyle
/// ve panelle (panel/js/util.js → takipIdFor) birebir aynı olmak zorunda;
/// ayrı düşerse müşteri başvurusunu göremez.
public enum Takip {
    /// Pasaport numarası: boşluk ve tire atılır, büyük harfe çevrilir.
    public static func pasaportTemizle(_ v: String) -> String {
        v.degistir("[\\s-]", "").uppercased()
    }

    /// takipId = SHA-256("vizemia-takip|" + KOD + "|" + PASAPORT)
    public static func kimlik(kod: String, pasaport: String) -> String {
        Ozet.sha256Hex("vizemia-takip|\(kod)|\(pasaport)")
    }

    /// Takip kodu: YYYY-AA#### (ör. 2026-091234).
    public static func kodGecerli(_ kod: String) -> Bool {
        kod.eslesir("^[0-9]{4}-(0[1-9]|1[0-2])[0-9]{4}$")
    }

    public static func pasaportGecerli(_ temiz: String) -> Bool {
        temiz.eslesir("^[A-Z0-9]{6,12}$")
    }

    /// Yapıştırılan tam kodu (10 rakam) yıl ve 6 haneye böler.
    public static func kodAyir(_ metin: String) -> (yil: String, kalan: String)? {
        let d = metin.filter { $0.isASCII && $0.isNumber }
        guard d.count == 10 else { return nil }
        return (String(d.prefix(4)), String(d.suffix(6)))
    }

    /// Hata metni ya da nil.
    public static func hata(kod: String, pasaport: String) -> String? {
        if !kodGecerli(kod) { return "Takip kodunu kontrol edin: yıl, ardından 6 rakam (ör. 091234)." }
        if !pasaportGecerli(pasaportTemizle(pasaport)) { return "Pasaport numarasını kontrol edin." }
        return nil
    }
}

/// Müşterinin gördüğü durum (Firestore `takip/{kimlik}`).
/// Codable: "Beni unutma" diyen müşterinin son gördüğü durum cihazda saklanır
/// (açılışta karşılama, çevrimdışı gösterim, değişiklik bildirimi).
public struct TakipKaydi: Equatable, Codable {
    public struct Not: Equatable, Identifiable, Codable {
        public var id: Int
        public var metin: String
        public var tarih: Date?

        public init(id: Int, metin: String, tarih: Date? = nil) {
            self.id = id
            self.metin = metin
            self.tarih = tarih
        }
    }

    public var ulke: String
    public var ad: String
    public var durum: String
    public var aciklama: String
    /// Panelden gelen renk; yalnız geçerli bir renk kodu kabul edilir.
    public var renk: String?
    public var bitti: Bool
    public var notlar: [Not]
    public var asamalar: [String]
    public var asama: Int?
    public var guncelleme: Date?

    public init(ulke: String, ad: String, durum: String, aciklama: String = "", renk: String? = nil, bitti: Bool = false,
                notlar: [Not] = [], asamalar: [String] = [], asama: Int? = nil, guncelleme: Date? = nil) {
        self.ulke = ulke; self.ad = ad; self.durum = durum; self.aciklama = aciklama; self.renk = renk
        self.bitti = bitti; self.notlar = notlar; self.asamalar = asamalar; self.asama = asama
        self.guncelleme = guncelleme
    }

    public init(belge: [String: FSDeger]) {
        ulke = belge["countryName"]?.metinDegeri ?? ""
        ad = belge["firstName"]?.metinDegeri ?? ""
        durum = belge["statusName"]?.metinDegeri ?? ""
        aciklama = belge["statusDescription"]?.metinDegeri ?? ""
        let r = belge["statusColor"]?.metinDegeri ?? ""
        renk = r.eslesir("^#[0-9a-fA-F]{3,8}$") ? r : nil
        bitti = belge["isFinal"]?.mantikDegeri ?? false
        guncelleme = belge["updatedAt"]?.zamanDegeri
        var liste: [Not] = []
        for (i, n) in (belge["notes"]?.diziDegeri ?? []).enumerated() {
            guard let h = n.haritaDegeri, let m = h["text"]?.metinDegeri, !m.isEmpty else { continue }
            liste.append(Not(id: i, metin: m, tarih: h["at"]?.zamanDegeri))
        }
        notlar = liste
        asamalar = Array((belge["asamalar"]?.diziDegeri ?? []).compactMap { $0.metinDegeri }.prefix(10))
        asama = belge["asama"]?.tamDegeri
    }

    /// Üst satır: "Almanya vize başvurusu · Sayın Ayşe"
    public var ustSatir: String {
        "\(ulke) vize başvurusu\(ad.isEmpty ? "" : " · Sayın \(ad)")".kirpik
    }

    /// Aşama çubuğu gösterilecek mi? (en az 2 aşama ve geçerli sıra)
    public var ilerleme: Ilerleme? {
        guard let s = asama, asamalar.count >= 2, s >= 0, s < asamalar.count else { return nil }
        return Ilerleme(adlar: asamalar, simdi: s, bitti: bitti)
    }

    public struct Ilerleme: Equatable {
        public var adlar: [String]
        public var simdi: Int
        public var bitti: Bool

        /// 0…1: pasaportun çubuktaki yeri.
        public var oran: Double { adlar.count > 1 ? Double(simdi) / Double(adlar.count - 1) : 0 }

        public var ozet: String {
            if bitti { return "İşleminiz tamamlandı." }
            var s = "\(simdi + 1). aşama: \(adlar[simdi])"
            if simdi < adlar.count - 1 { s += " · Sıradaki: \(adlar[simdi + 1])" }
            return s
        }

        public func gecti(_ i: Int) -> Bool { i < simdi || bitti }
    }
}

/// Aşama değişince müşteriye gösterilecek bildirim.
public struct TakipBildirimi: Equatable {
    public var baslik: String
    public var govde: String

    public init(baslik: String, govde: String) {
        self.baslik = baslik
        self.govde = govde
    }
}

extension TakipKaydi {
    /// Önceki görülen durumla karşılaştırır; müşteriye haber verilecek bir
    /// değişiklik varsa bildirim metnini döner.
    ///
    /// Durum ya da aşama değiştiyse panelde müşteri için yazılan metin gider
    /// ("Randevunuz alındı. Randevu bilgileriniz size iletildi."). Yalnız yeni
    /// not geldiyse notun içeriği yazılmaz: bildirim kilit ekranında görünür.
    public func bildirim(onceki: TakipKaydi) -> TakipBildirimi? {
        let baslik = ulke.isEmpty ? "Vize başvurunuz" : "\(ulke) vize başvurunuz"
        if durum != onceki.durum || asama != onceki.asama || bitti != onceki.bitti {
            var govde = durum.isEmpty ? "Başvurunuzun durumu güncellendi." : durum
            if !govde.hasSuffix(".") { govde += "." }
            if !aciklama.isEmpty { govde += " " + aciklama }
            return TakipBildirimi(baslik: baslik, govde: govde)
        }
        if notlar.count > onceki.notlar.count {
            return TakipBildirimi(baslik: baslik, govde: "Size yeni bir not iletildi. Görmek için dokunun.")
        }
        return nil
    }
}

/// Açılıştaki karşılama: "Günaydın, Ahmet".
public enum Selamlama {
    /// Günün saatine göre (cihazın saati): 05–11 Günaydın, 12–17 İyi günler,
    /// 18–21 İyi akşamlar, 22–04 İyi geceler.
    public static func metin(saat: Int) -> String {
        switch saat {
        case 5..<12: return "Günaydın"
        case 12..<18: return "İyi günler"
        case 18..<22: return "İyi akşamlar"
        default: return "İyi geceler"
        }
    }

    /// Takip kaydındaki ad büyük harfle ve çoğunlukla Latin harfleriyle durur
    /// ("AHMET", "AYSE NUR"); karşılamada "Ahmet", "Ayse Nur" yazılır.
    ///
    /// I harfi: Latin harfli adda "i" olur (ALI → Ali). Adda Türkçe büyük harf
    /// varsa (İBRAHİM, IŞIK) Türkçe kuralı geçerlidir: I → ı, İ → i.
    public static func ad(_ ham: String) -> String {
        let s = ham.kirpik
        if s.isEmpty || s.contains(where: { $0.isLowercase }) { return s }
        let turkce = s.contains(where: { "ÇĞİÖŞÜ".contains($0) })
        var out = ""
        var basta = true
        for c in s {
            if c == " " || c == "-" || c == "'" {
                out.append(c)
                basta = true
            } else if basta {
                out.append(c)
                basta = false
            } else if c == "I" {
                out += turkce ? "ı" : "i"
            } else if c == "İ" {
                out += "i"
            } else {
                out += String(c).lowercased()
            }
        }
        return out
    }

    /// "Günaydın, Ahmet" — ad yoksa yalnız "Günaydın".
    public static func cumle(saat: Int, ad ham: String) -> String {
        let a = ad(ham)
        return a.isEmpty ? metin(saat: saat) : "\(metin(saat: saat)), \(a)"
    }
}

/// Kısa aralıkta çok deneme yapılmasını engeller (kaba kuvvet): 10 dakikada 8.
/// Sunucu tarafı sınır değil — kurallar zaten kimliği bilmeyene belge vermiyor —
/// ama yanlış yazan müşteriyi de, taramayı da yavaşlatıyor.
public struct DenemeSiniri: Equatable {
    public var zamanlar: [Date] = []
    public var enCok: Int
    public var pencere: TimeInterval

    public init(enCok: Int = 8, pencere: TimeInterval = 600) {
        self.enCok = enCok
        self.pencere = pencere
    }

    /// Denemeyi kaydeder; sınır aşıldıysa true.
    public mutating func asildi(simdi: Date = Date()) -> Bool {
        zamanlar = zamanlar.filter { simdi.timeIntervalSince($0) < pencere }
        zamanlar.append(simdi)
        return zamanlar.count > enCok
    }
}
