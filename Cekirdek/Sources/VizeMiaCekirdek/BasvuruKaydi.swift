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
    public var silinecek: Date?

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
        silinecek = a["deleteAfter"]?.zamanDegeri
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
