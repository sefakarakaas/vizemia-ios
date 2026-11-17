import Foundation

/// Başvuru (applications/{id}) — panelde Müşteriler → Başvurular.
/// Hassas bilgiler (TCKN, pasaport, iletişim) alt belgede (private/data);
/// burada yalnız listede ve takvimde görünenler var.
public struct Basvuru: Equatable, Identifiable {
    public var kimlik: String
    public var takipKodu: String
    public var ad: String
    public var soyad: String
    public var ulke: String
    public var ulkeAdi: String
    public var statuId: String
    public var statuAdi: String
    public var statuZamani: Date?
    public var olusturma: Date?
    public var acilis: Date?
    public var sonArama: Date?
    public var guncelleme: Date?
    public var randevu: Date?
    public var randevuSaati: String
    public var randevuYeri: String
    public var randevuSehri: String
    public var pasaportSon3: String
    public var sorumlu: String
    /// Müşteriyi izleyen danışmanın kimliği (bekleyen WhatsApp görevi ona düşer).
    public var sorumluUid: String
    public var silinecek: Date?
    public var sonAdimZamani: Date?
    /// Silme bekletiliyor (itiraz, dava): yönetici açar.
    public var bekletiliyor: Bool
    /// Evrak kontrol listesi: evrak kimliği → geldi mi.
    public var evraklar: [String: Bool]
    public var odemeSayisi: Int
    public var konsTakipKodu: String
    public var konsTakipZamani: Date?
    public var randevuMerkezi: String
    /// Konsolosluk / büyükelçiliğin adı (başvuru merkezinde boş) ve harita bağlantısı.
    public var randevuYeriAdi: String
    public var randevuHarita: String
    public var grupId: String
    public var grupAdi: String
    /// Telefonda hızlı açılan başvurunun eksik alanları ("Bilgileri kontrol edin").
    public var kontrolNotu: String

    public var id: String { kimlik }

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        self.kimlik = kimlik
        let m = { (k: String) in a[k]?.metinDegeri ?? "" }
        takipKodu = m("trackingCode"); ad = m("firstName"); soyad = m("lastName")
        ulke = m("country"); ulkeAdi = m("countryName").isEmpty ? m("country") : m("countryName")
        statuId = m("statusId"); statuAdi = m("statusName")
        statuZamani = a["statusAt"]?.zamanDegeri
        olusturma = a["createdAt"]?.zamanDegeri
        acilis = a["openedAt"]?.zamanDegeri
        sonArama = a["sonArama"]?.zamanDegeri
        guncelleme = a["updatedAt"]?.zamanDegeri
        randevu = a["appointmentAt"]?.zamanDegeri
        randevuSaati = m("randevuSaati")
        randevuYeri = m("randevuYeri").isEmpty ? m("randevuMerkezi") : m("randevuYeri")
        randevuSehri = m("randevuSehri")
        pasaportSon3 = m("passportLast3")
        sorumlu = m("assignedName")
        sorumluUid = m("assignedTo")
        silinecek = a["deleteAfter"]?.zamanDegeri
        sonAdimZamani = a["finalAt"]?.zamanDegeri
        bekletiliyor = a["legalHold"]?.mantikDegeri ?? false
        evraklar = (a["checklist"]?.haritaDegeri ?? [:]).compactMapValues { $0.mantikDegeri }
        odemeSayisi = a["odemeSayisi"]?.tamDegeri ?? 0
        konsTakipKodu = m("konsTakipKodu")
        konsTakipZamani = a["konsTakipTarih"]?.zamanDegeri
        randevuMerkezi = m("randevuMerkezi")
        randevuYeriAdi = m("randevuYeri")
        randevuHarita = m("randevuHarita")
        grupId = m("grupId"); grupAdi = m("grupAdi")
        kontrolNotu = m("reviewNote")
    }

    public var adSoyad: String {
        let s = "\(ad) \(soyad)".kirpik
        return s.isEmpty ? "—" : s
    }

    public struct AramaDurumu: Equatable {
        public enum Hal { case bekle, ara, gecikti }
        public var enErken: Date
        public var enGec: Date
        public var durum: Hal
        public var gun: Int
    }

    /// Statünün tekrar arama aralığına göre (panel: basvuru-akisi.js → aramaDurumu).
    public func aramaDurumu(_ s: Statu, simdi: Date = Date()) -> AramaDurumu? {
        guard let min = s.aramaMin, let max = s.aramaMax else { return nil }
        let ilk = statuZamani ?? olusturma ?? acilis
        let adaylar = [ilk, sonArama].compactMap { $0 }
        guard let bas = adaylar.max() else { return nil }
        let gun = TakvimIsi.gunSn
        let erken = bas.addingTimeInterval(Double(min) * gun)
        let gec = bas.addingTimeInterval(Double(max) * gun)
        let fark = { (a: Date, b: Date) in Int(ceil(a.timeIntervalSince(b) / gun)) }
        if simdi < erken { return AramaDurumu(enErken: erken, enGec: gec, durum: .bekle, gun: fark(erken, simdi)) }
        if simdi <= gec { return AramaDurumu(enErken: erken, enGec: gec, durum: .ara, gun: Swift.max(0, fark(gec, simdi))) }
        let gecen = Int(floor(simdi.timeIntervalSince(gec) / gun))
        return AramaDurumu(enErken: erken, enGec: gec, durum: .gecikti, gun: gecen == 0 ? 1 : gecen)
    }

    /// "5 gün sonra aranacak", "Bugün aranmalı (son gün)" …
    public static func aramaEtiketi(_ d: AramaDurumu?) -> String {
        guard let d else { return "" }
        switch d.durum {
        case .bekle: return "\(d.gun) gün sonra aranacak"
        case .ara: return d.gun == 0 ? "Bugün aranmalı (son gün)" : "Aranmalı (\(d.gun) gün içinde)"
        case .gecikti: return "Arama gecikti (\(d.gun) gün)"
        }
    }
}

// MARK: - Liste

/// Başvurular listesinin kuralları (panel: pages/applications.js → ApplicationsPage, grup.js).
public enum BasvuruListesi {
    /// "2026 029825", "2026029825" → "2026-029825"; geçersizse nil.
    public static func takipKodu(_ s: String) -> String? {
        let d = s.filter(\.isNumber)
        guard d.count == 10 else { return nil }
        let k = "\(d.prefix(4))-\(d.dropFirst(4))"
        return k.eslesir("^[0-9]{4}-(0[1-9]|1[0-2])[0-9]{4}$") ? k : nil
    }

    /// Pasaportla arama dizininin anahtarı (lookup/{hash}).
    public static func pasaportOzeti(_ s: String) -> String {
        Ozet.sha256Hex("vizemia-pasaport|\(s.filter { $0 != " " && $0 != "-" }.uppercased())")
    }

    /// Tam aramada pasaport numarası gibi görünüyor mu (7–12 harf/rakam).
    public static func pasaportGibi(_ s: String) -> Bool {
        s.filter { $0 != " " && $0 != "-" }.eslesir("^[A-Za-z0-9]{7,12}$")
    }

    /// Yazarken süzme: ad soyad, takip kodu ya da pasaportun son 3 hanesi.
    public static func suz(_ l: [Basvuru], _ terim: String) -> [Basvuru] {
        let t = terim.kirpik.lowercased(with: Tr.yerel)
        guard !t.isEmpty else { return l }
        return l.filter { a in
            "\(a.ad) \(a.soyad)".lowercased(with: Tr.yerel).contains(t)
                || a.takipKodu.contains(t)
                || (t.count == 3 && a.pasaportSon3.lowercased() == t)
        }
    }

    public enum Satir: Identifiable, Equatable {
        case tek(Basvuru)
        case grup(id: String, ad: String, uyeler: [Basvuru])
        public var id: String {
            switch self {
            case .tek(let a): return a.kimlik
            case .grup(let id, _, _): return "grup:\(id)"
            }
        }
    }

    /// Aynı grubun en az iki üyesi listedeyse tek başlık altında, ilk üyenin yerinde.
    public static func grupla(_ l: [Basvuru]) -> [Satir] {
        var gruplar: [String: [Basvuru]] = [:]
        for a in l where !a.grupId.isEmpty { gruplar[a.grupId, default: []].append(a) }
        var cikti: [Satir] = []
        var eklenen = Set<String>()
        for a in l {
            guard let u = gruplar[a.grupId], !a.grupId.isEmpty, u.count >= 2 else { cikti.append(.tek(a)); continue }
            if eklenen.contains(a.grupId) { continue }
            eklenen.insert(a.grupId)
            cikti.append(.grup(id: a.grupId, ad: u.first { !$0.grupAdi.isEmpty }?.grupAdi ?? "Grup", uyeler: u))
        }
        return cikti
    }

    /// Grubun ortak ülkesi ya da "Karışık ülke".
    public static func grupUlkesi(_ u: [Basvuru]) -> String {
        var adlar: [String] = []
        for a in u where !a.ulkeAdi.isEmpty && !adlar.contains(a.ulkeAdi) { adlar.append(a.ulkeAdi) }
        return adlar.count == 1 ? adlar[0] : adlar.isEmpty ? "—" : "Karışık ülke"
    }

    /// Silinmeye kalan gün (bugün dâhil; geçmişse 0 ya da eksi).
    public static func kalanGun(_ d: Date?, simdi: Date = Date()) -> Int? {
        guard let d else { return nil }
        return Int(ceil(d.timeIntervalSince(simdi) / 86_400))
    }
}
