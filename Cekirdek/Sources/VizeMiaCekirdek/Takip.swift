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
public struct TakipKaydi: Equatable {
    public struct Not: Equatable, Identifiable {
        public var id: Int
        public var metin: String
        public var tarih: Date?
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
