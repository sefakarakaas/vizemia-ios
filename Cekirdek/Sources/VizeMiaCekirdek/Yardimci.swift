import Foundation

extension String {
    /// Düzenli ifadenin tamamıyla eşleşiyor mu? (desen ^…$ ile yazılır)
    func eslesir(_ desen: String) -> Bool {
        range(of: desen, options: .regularExpression) != nil
    }

    /// Düzenli ifadeye uyan her parçayı değiştirir.
    func degistir(_ desen: String, _ yeni: String) -> String {
        replacingOccurrences(of: desen, with: yeni, options: .regularExpression)
    }

    var kirpik: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// JavaScript'teki `slice(0, n)` gibi: en çok n karakter.
    func ilk(_ n: Int) -> String { String(prefix(n)) }
}

/// Türkiye saati. Cihazın saat dilimi bizi ilgilendirmiyor: Almanya'daki
/// müşterinin telefonu 16:00 gösterirken Ankara'da 17:00; mesai Ankara'ya göre.
public enum Tr {
    public static let dilim = TimeZone(identifier: "Europe/Istanbul")!
    public static let yerel = Locale(identifier: "tr_TR")

    public static let takvim: Calendar = {
        var t = Calendar(identifier: .gregorian)
        t.timeZone = dilim
        t.locale = yerel
        return t
    }()

    /// Saat dilimi kaymasın diye gün hesapları UTC takvimiyle yapılır.
    static let utc: Calendar = {
        var t = Calendar(identifier: .gregorian)
        t.timeZone = TimeZone(identifier: "UTC")!
        return t
    }()

    /// Türkiye'de bugünün tarihi: "2026-11-20".
    public static func bugun(_ simdi: Date = Date()) -> String {
        let p = takvim.dateComponents([.year, .month, .day], from: simdi)
        return iso(yil: p.year ?? 0, ay: p.month ?? 0, gun: p.day ?? 0)
    }

    /// Takvimden seçilen günü "2026-11-20" yapar. Tarih seçici cihazın
    /// takvimiyle çalışır; kullanıcının ekranda gördüğü gün yazılır.
    public static func isoGun(_ d: Date, takvim: Calendar = .current) -> String {
        let p = takvim.dateComponents([.year, .month, .day], from: d)
        return iso(yil: p.year ?? 0, ay: p.month ?? 0, gun: p.day ?? 0)
    }

    static func iso(yil: Int, ay: Int, gun: Int) -> String {
        "\(dort(yil))-\(iki(ay))-\(iki(gun))"
    }

    static func iki(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    static func dort(_ n: Int) -> String { String(repeating: "0", count: max(0, 4 - "\(n)".count)) + "\(n)" }

    /// "2026-11-20" → o günün öğlesi (UTC). Geçersizse nil.
    public static func tarih(_ iso: String) -> Date? {
        guard iso.eslesir("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") else { return nil }
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var c = DateComponents()
        c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = 12
        guard let d = utc.date(from: c) else { return nil }
        // 31 Şubat gibi tarihler sessizce Mart'a kaymasın.
        let geri = utc.dateComponents([.month, .day], from: d)
        return geri.month == p[1] && geri.day == p[2] ? d : nil
    }

    /// ISO tarihe gün ekler.
    public static func gunEkle(_ iso: String, _ n: Int) -> String {
        guard let d = tarih(iso), let y = utc.date(byAdding: .day, value: n, to: d) else { return iso }
        let p = utc.dateComponents([.year, .month, .day], from: y)
        return Tr.iso(yil: p.year ?? 0, ay: p.month ?? 0, gun: p.day ?? 0)
    }

    /// Haftanın günü: 0 = Pazar … 6 = Cumartesi.
    public static func gunNo(_ iso: String) -> Int {
        guard let d = tarih(iso) else { return 0 }
        return (utc.component(.weekday, from: d) + 6) % 7
    }

    /// "12 Kasım 2026"
    public static func uzunTarih(_ iso: String) -> String {
        guard let d = tarih(iso) else { return "" }
        let p = utc.dateComponents([.year, .month, .day], from: d)
        return "\(p.day ?? 0) \(Mesai.ayAdi[(p.month ?? 1) - 1]) \(p.year ?? 0)"
    }

    /// "12 Kasım 2026 14:05" (Türkiye saati)
    public static func tarihSaat(_ d: Date) -> String {
        let p = takvim.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return "\(p.day ?? 0) \(Mesai.ayAdi[(p.month ?? 1) - 1]) \(p.year ?? 0) \(iki(p.hour ?? 0)):\(iki(p.minute ?? 0))"
    }

    /// "12.11.2026"
    public static func kisaTarih(_ d: Date) -> String {
        let p = takvim.dateComponents([.year, .month, .day], from: d)
        return "\(iki(p.day ?? 0)).\(iki(p.month ?? 0)).\(p.year ?? 0)"
    }
}
