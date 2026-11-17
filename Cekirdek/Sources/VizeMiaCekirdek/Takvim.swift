import Foundation

/// Başvuru statüsü (statuses): panelde Ayarlar → Statüler.
public struct Statu: Equatable, Identifiable, Codable {
    public var id: String
    public var ad: String
    public var musteriAdi: String
    public var musteriAciklamasi: String
    public var renk: String
    public var son: Bool
    public var sira: Double
    /// Tekrar arama aralığı (gün): ör. potansiyel müşteri 7–14 gün sonra aranır.
    public var aramaMin: Int?
    public var aramaMax: Int?

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        id = kimlik
        ad = a["name"]?.metinDegeri ?? kimlik
        musteriAdi = a["publicName"]?.metinDegeri ?? ""
        musteriAciklamasi = a["publicDescription"]?.metinDegeri ?? ""
        renk = a["color"]?.metinDegeri ?? ""
        son = a["isFinal"]?.mantikDegeri ?? false
        sira = a["order"].flatMap { d -> Double? in
            if let n = d.tamDegeri { return Double(n) }
            if case .ondalik(let v) = d { return v }
            return nil
        } ?? 0
        aramaMin = Statu.gun(a["aramaMin"])
        aramaMax = Statu.gun(a["aramaMax"])
    }

    /// 1–365 gün arası tam sayı; değilse yok (panel: gunSayisi).
    static func gun(_ d: FSDeger?) -> Int? {
        var n: Int?
        if let t = d?.tamDegeri { n = t }
        if case .ondalik(let v)? = d { n = Int(v.rounded()) }
        guard let x = n, x >= 1, x <= 365 else { return nil }
        return x
    }

    public var tekrarAranir: Bool { aramaMin != nil && aramaMax != nil }
}

/// Takvimdeki iş: aranacak talep, randevu ya da tekrar arama (panel/js/takvim.js).
public struct TakvimIsi: Equatable, Identifiable {
    public enum Tur: String, CaseIterable {
        case arama, randevu, tekrar
        public var ad: String {
            switch self {
            case .arama: return "Aranacak"
            case .randevu: return "Randevu"
            case .tekrar: return "Tekrar arama"
            }
        }
    }

    public var id: String
    public var tur: Tur
    public var gun: String
    public var saat: String
    public var baslik: String
    public var alt: String
    /// Dokununca açılacak kayıt: "talep:callback/abc" ya da "basvuru:xyz".
    public var bag: String
    public var gecikti: Bool
    public var onemli: Bool

    static let gunSn: Double = 86_400

    /// Panelle aynı kurallar: aranacak talepler (yeni / ulaşılamadı), randevular,
    /// statüsünün tekrar arama aralığı açılan başvurular.
    public static func olustur(
        talepler: [Talep], randevular: [Basvuru], tekrarlar: [Basvuru], statuler: [String: Statu],
        bugun: String, simdi: Date = Date()
    ) -> [TakvimIsi] {
        var out: [TakvimIsi] = []
        for t in talepler where ["new", "called"].contains(t.durum) && !t.silindi {
            let gun = t.tarih.eslesir("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") ? t.tarih : (t.olusturma.map { Tr.bugun($0) } ?? "")
            if gun.isEmpty { continue }
            let alt = [t.kaynak == "armut" ? "Armut" : "", t.ulkeAdi, t.durum == "called" ? "arandı, ulaşılamadı" : ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            out.append(TakvimIsi(id: "talep:\(t.yol)", tur: .arama, gun: gun, saat: t.saatler.first ?? "",
                                 baslik: t.ad.isEmpty ? "—" : t.ad, alt: alt, bag: "talep:\(t.yol)",
                                 gecikti: gun < bugun, onemli: true))
        }
        for a in randevular {
            guard let r = a.randevu else { continue }
            let saat = a.randevuSaati.eslesir("^[0-9]{2}:[0-9]{2}$") ? a.randevuSaati : ""
            let alt = [a.ulkeAdi, a.randevuYeri, a.randevuSehri].filter { !$0.isEmpty }.joined(separator: " · ")
            out.append(TakvimIsi(id: "randevu:\(a.kimlik)", tur: .randevu, gun: Tr.bugun(r), saat: saat,
                                 baslik: a.adSoyad, alt: alt, bag: "basvuru:\(a.kimlik)", gecikti: false, onemli: true))
        }
        for a in tekrarlar {
            guard let s = statuler[a.statuId], let d = a.aramaDurumu(s, simdi: simdi) else { continue }
            let erken = Tr.bugun(d.enErken), gec = Tr.bugun(d.enGec)
            let gun = erken > bugun ? erken : bugun
            let kisa = { (g: String) -> String in
                let p = g.split(separator: "-"); return p.count == 3 ? "\(p[2]).\(p[1])" : g
            }
            let aralik = d.durum == .gecikti ? "gecikti (son gün \(kisa(gec)))" : "\(kisa(erken))–\(kisa(gec)) arası"
            out.append(TakvimIsi(id: "tekrar:\(a.kimlik)", tur: .tekrar, gun: gun, saat: "", baslik: a.adSoyad,
                                 alt: [s.ad, aralik].filter { !$0.isEmpty }.joined(separator: " · "),
                                 bag: "basvuru:\(a.kimlik)", gecikti: d.durum == .gecikti, onemli: false))
        }
        return out
    }

    /// Gün içinde: önemliler önce, saatliler önce (saate göre), sonra ada göre.
    public static func sirala(_ l: [TakvimIsi]) -> [TakvimIsi] {
        l.sorted { a, b in
            if a.onemli != b.onemli { return a.onemli }
            if a.saat.isEmpty != b.saat.isEmpty { return !a.saat.isEmpty }
            if a.saat != b.saat { return a.saat < b.saat }
            return a.baslik.compare(b.baslik, locale: Tr.yerel) == .orderedAscending
        }
    }

    /// Ayın takvim ızgarası: Pazartesi başlar; 6 hafta × 7 gün.
    public static func ayIzgarasi(yil: Int, ay: Int) -> [String] {
        let ilk = Tr.iso(yil: yil, ay: ay, gun: 1)
        let geri = (Tr.gunNo(ilk) + 6) % 7
        let bas = Tr.gunEkle(ilk, -geri)
        return (0..<42).map { Tr.gunEkle(bas, $0) }
    }
}
