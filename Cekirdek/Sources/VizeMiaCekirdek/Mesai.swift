import Foundation

/// Panelden gelen mesai ayarı (site/assets/mesai.json):
/// `{ "gunler": { "0": null, "1": [540, 1080], … }, "tatiller": ["2026-10-29"] }`
public struct MesaiAyari: Codable, Equatable {
    public var gunler: [String: [Int]?]?
    public var tatiller: [String]?

    public init(gunler: [String: [Int]?]? = nil, tatiller: [String]? = nil) {
        self.gunler = gunler
        self.tatiller = tatiller
    }
}

/// Mesai saatleri — site/assets/mesai.js ile aynı kurallar.
///
/// "Şu an açık mıyız" sorusu birkaç yerde soruluyor (hemen arayın seçeneği,
/// Ara düğmesi, saat seçici); hepsi buradan cevap alır ki müşteri "hemen
/// arayın" deyip kimseyi bulamasın diye bir durum olmasın.
public struct Mesai: Equatable {
    /// Gün (0 = Pazar … 6 = Cumartesi) → [açılış, kapanış] dakika. Listede olmayan gün kapalı.
    public var calisma: [Int: [Int]]
    /// Kapalı olunan tarihler (YYYY-AA-GG, Türkiye takvimi).
    public var tatiller: Set<String>

    public static let varsayilan = Mesai(
        calisma: [1: [540, 1080], 2: [540, 1080], 3: [540, 1080], 4: [540, 1080], 5: [540, 1080], 6: [600, 840]],
        tatiller: []
    )

    public static let gunAdi = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"]
    public static let gunKisa = ["Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"]
    public static let ayKisa = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]
    public static let ayAdi = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]

    /// Kaç gün ileriye arama saati verilebilir.
    public static let gunIleri = 14
    /// Bugün için en erken kaç dakika sonrası seçilebilir.
    public static let onSure = 60

    public init(calisma: [Int: [Int]], tatiller: Set<String>) {
        self.calisma = calisma
        self.tatiller = tatiller
    }

    /// Panel ayarını varsayılanın üstüne uygular. Bozuk gün atlanır, varsayılan kalır.
    public init(ayar: MesaiAyari?) {
        var c = Mesai.varsayilan.calisma
        if let g = ayar?.gunler {
            for i in 0..<7 {
                guard let kayit = g[String(i)] else { continue }
                guard let v = kayit else { c[i] = nil; continue }
                if v.count == 2, v.allSatisfy({ $0 % 30 == 0 && $0 >= 7 * 60 && $0 <= 23 * 60 }), v[0] < v[1] {
                    c[i] = v
                }
            }
        }
        calisma = c
        tatiller = Set((ayar?.tatiller ?? []).filter { $0.eslesir("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") })
    }

    /// Arama saati seçeneklerinin tümü: her açık günün yarım saatleri, birleşik (panel: aramaDilimleri).
    public var aramaDilimleri: [String] {
        var k = Set<Int>()
        for a in calisma.values where a.count == 2 { for dk in stride(from: a[0], to: a[1], by: 30) { k.insert(dk) } }
        return k.sorted().map { Mesai.hhmm($0) }
    }

    /// Türkiye saatiyle şimdiki yarım saat; mesai dışındaysa en yakın uç (panel: simdikiSaat).
    public func simdikiSaat(_ simdi: Date = Date()) -> String {
        let a = Mesai.trSimdi(simdi)
        let s = Mesai.hhmm(a.dakika / 30 * 30)
        let l = aramaDilimleri
        guard let ilk = l.first, let son = l.last, !l.contains(s) else { return s }
        return s < ilk ? ilk : son
    }

    public static func hhmm(_ dakika: Int) -> String {
        "\(Tr.iki(dakika / 60)):\(Tr.iki(dakika % 60))"
    }

    public struct An: Equatable {
        public var iso: String
        public var gun: Int
        public var dakika: Int
    }

    /// Türkiye saatiyle "şimdi".
    public static func trSimdi(_ simdi: Date = Date()) -> An {
        let p = Tr.takvim.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: simdi)
        return An(
            iso: Tr.iso(yil: p.year ?? 0, ay: p.month ?? 0, gun: p.day ?? 0),
            gun: ((p.weekday ?? 1) + 6) % 7,
            dakika: (p.hour ?? 0) * 60 + (p.minute ?? 0)
        )
    }

    public func tatilMi(_ iso: String) -> Bool { tatiller.contains(iso) }

    /// Şu anda açık mıyız? Tatil günü saat ne olursa olsun kapalı.
    public func acikMi(_ simdi: Date = Date()) -> Bool {
        let t = Mesai.trSimdi(simdi)
        if tatilMi(t.iso) { return false }
        guard let a = calisma[t.gun] else { return false }
        return t.dakika >= a[0] && t.dakika < a[1]
    }

    public struct Acilis: Equatable {
        public var gun: Int
        public var dakika: Int
        public var metin: String
    }

    /// Kapalıyken "ne zaman açılıyoruz": "bugün 09:00", "yarın 09:00", "Pazartesi 09:00".
    public func sonrakiAcilis(_ simdi: Date = Date()) -> Acilis {
        let t = Mesai.trSimdi(simdi)
        // Bayram tatili haftayı aşabiliyor; panel en çok 60 tatil günü kabul ediyor.
        for i in 0..<62 {
            let g = (t.gun + i) % 7
            guard let a = calisma[g], !tatilMi(Tr.gunEkle(t.iso, i)) else { continue }
            // Bugünse ve açılışı geçmişsek (gün bitmiş) sonraki güne bak.
            if i == 0 && t.dakika >= a[0] { continue }
            let saat = Mesai.hhmm(a[0])
            let metin = i == 0 ? "bugün \(saat)" : i == 1 ? "yarın \(saat)" : "\(Mesai.gunAdi[g]) \(saat)"
            return Acilis(gun: g, dakika: a[0], metin: metin)
        }
        return Acilis(gun: 1, dakika: 540, metin: "Pazartesi 09:00")
    }

    /// "Hafta içi 09:00–18:00, Cumartesi 10:00–14:00"
    public func metin() -> String {
        func aralik(_ g: Int) -> String {
            guard let a = calisma[g] else { return "" }
            return "\(Mesai.hhmm(a[0]))–\(Mesai.hhmm(a[1]))"
        }
        let hi = (1...5).map(aralik)
        var parca: [String] = []
        if hi.allSatisfy({ $0 == hi[0] }) {
            if !hi[0].isEmpty { parca.append("Hafta içi \(hi[0])") }
        } else {
            for (i, g) in (1...5).enumerated() where !hi[i].isEmpty { parca.append("\(Mesai.gunAdi[g]) \(hi[i])") }
        }
        if !aralik(6).isEmpty { parca.append("Cumartesi \(aralik(6))") }
        if !aralik(0).isEmpty { parca.append("Pazar \(aralik(0))") }
        return parca.joined(separator: ", ")
    }

    public struct DisiMesaji: Equatable {
        public var baslik: String
        public var metin: String
        public var sonraki: String
    }

    /// "Ara" düğmesi için: mesai içindeyse nil (düğme olduğu gibi arar),
    /// dışındaysa müşteriye gösterilecek metin. Aramayı engellemiyoruz ama
    /// uyarıyoruz: gece arayan müşteri açılmayan telefonla karşılaşınca çoğu
    /// zaman bir daha denemiyor; talebini bırakırsa ertesi sabah biz arıyoruz.
    public func disiMesaji(_ simdi: Date = Date()) -> DisiMesaji? {
        if acikMi(simdi) { return nil }
        let sonraki = sonrakiAcilis(simdi).metin
        return DisiMesaji(
            baslik: "Şu an mesai saatleri dışındayız",
            metin: "Çalışma saatlerimiz: \(metin()). Talebinizi şimdi bırakın, \(sonraki) açıldığımızda ilk sizi arayalım. İsterseniz WhatsApp'tan da yazabilirsiniz.",
            sonraki: sonraki
        )
    }

    // MARK: - Arama saati seçici (site/assets/slot-picker.js)

    /// O gün seçilebilecek yarım saatlik aralıkların başlangıçları (dakika).
    public func dilimler(_ iso: String, simdi: Date = Date()) -> [Int] {
        guard let a = calisma[Tr.gunNo(iso)], !tatilMi(iso) else { return [] }
        let t = Mesai.trSimdi(simdi)
        // Bugünse geçmiş saatleri ve "az sonrası"nı gösterme.
        let enErken = iso == t.iso ? t.dakika + Mesai.onSure : -1
        return stride(from: a[0], to: a[1], by: 30).filter { $0 > enErken }
    }

    /// Arama saati seçilebilecek günler (en çok 14).
    public func uygunGunler(simdi: Date = Date()) -> [String] {
        let bugun = Mesai.trSimdi(simdi).iso
        var gunler: [String] = []
        var i = 0
        while gunler.count < Mesai.gunIleri && i < Mesai.gunIleri + 7 {
            let g = Tr.gunEkle(bugun, i)
            if !dilimler(g, simdi: simdi).isEmpty { gunler.append(g) }
            i += 1
        }
        return gunler
    }

    public struct DilimGrubu: Equatable, Identifiable {
        public var id: String
        public var ad: String
        public var dilimler: [Int]
        /// "09:00–12:00"
        public var aralik: String {
            guard let ilk = dilimler.first, let son = dilimler.last else { return "" }
            return "\(Mesai.hhmm(ilk))–\(Mesai.hhmm(son + 30))"
        }
    }

    /// Dilimler üç grupta: öğleden önce, öğle, öğleden sonra. Gruplar günün
    /// tamamını kapsıyor; mesai 08:00'e ya da 20:00'ye çekilirse uçtaki
    /// dilimler kaybolmuyor.
    public static func gruplar(_ dilimler: [Int]) -> [DilimGrubu] {
        let tanim: [(String, String, Int, Int)] = [
            ("sabah", "Öğleden önce", 0, 12), ("ogle", "Öğle", 12, 14), ("ogleden-sonra", "Öğleden sonra", 14, 24),
        ]
        return tanim.compactMap { g in
            let ic = dilimler.filter { $0 >= g.2 * 60 && $0 < g.3 * 60 }
            return ic.isEmpty ? nil : DilimGrubu(id: g.0, ad: g.1, dilimler: ic)
        }
    }

    /// Ardışık aralıkları birleştirir: 09:00, 09:30, 10:00 → "09:00–10:30".
    public static func aralikOzeti(_ secili: [Int]) -> String {
        let liste = secili.sorted()
        guard var bas = liste.first else { return "henüz seçim yok" }
        var onceki = bas
        var araliklar: [(Int, Int)] = []
        for m in liste.dropFirst() {
            if m == onceki + 30 { onceki = m; continue }
            araliklar.append((bas, onceki + 30))
            bas = m; onceki = m
        }
        araliklar.append((bas, onceki + 30))
        return araliklar.map { "\(hhmm($0.0))–\(hhmm($0.1))" }.joined(separator: ", ")
    }

    /// "21 Eyl Pzt"
    public static func gunMetni(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return iso }
        return "\(p[2]) \(ayKisa[p[1] - 1]) \(gunKisa[Tr.gunNo(iso)])"
    }
}

/// "Sizi ne zaman arayalım?" seçimi (site/assets/arama-secimi.js).
///
/// Mesai içindeysek iki seçenek var: hemen arayın / saat seçeyim. Mesai
/// dışındaysak yalnız saat seçilir — kimseye tutamayacağımız söz verilmez.
/// "Hemen"de de bir tarih/saat kaydedilir (o anki yarım saatlik dilim);
/// panel tek bir alan yapısıyla çalışır, aciliyeti `mod` alanından anlar.
public struct AramaSecimi: Equatable {
    public enum Mod: String { case hemen, saat }

    public var mod: Mod
    public var gun: String
    public var dilimler: Set<Int>

    public init(mod: Mod, gun: String = "", dilimler: Set<Int> = []) {
        self.mod = mod
        self.gun = gun
        self.dilimler = dilimler
    }

    public struct Yuk: Equatable {
        public var mod: String
        public var tarih: String
        public var saatler: [String]
    }

    public func yuk(simdi: Date = Date()) -> Yuk {
        if mod == .hemen {
            let t = Mesai.trSimdi(simdi)
            return Yuk(mod: "hemen", tarih: t.iso, saatler: [Mesai.hhmm(t.dakika / 30 * 30)])
        }
        return Yuk(mod: "saat", tarih: gun, saatler: dilimler.sorted().map(Mesai.hhmm))
    }

    /// Eksikse hata metni, tamamsa nil.
    public var hata: String? {
        if mod == .hemen { return nil }
        return dilimler.isEmpty || gun.isEmpty
            ? "Sizi ne zaman arayabileceğimizi seçin — en az bir saat aralığı işaretleyin."
            : nil
    }

    /// Onay ekranında gösterilecek cümle.
    public var metin: String {
        mod == .hemen
            ? "En kısa sürede sizi arıyoruz"
            : "\(Mesai.gunMetni(gun)), \(Mesai.aralikOzeti(Array(dilimler))) aralığında sizi arayacağız"
    }
}
