import Foundation

// Randevu kağıdı girişi ve müşteriye giden otomatik bildirimlerin planı.
// Panelin karşılıkları:
//   panel/js/basvuru-akisi.js   randevuHatalari, randevuKaydi, randevuMs
//   panel/js/konumlar.js        harita bağlantıları (Ayarlar → Randevu konumları)
//   panel/js/bildirim.js        planla (randevu alındı, evrak hatırlatması)
//   panel/js/bildirim-ayar.js   mergeAyar, ulkeAyari, kanallar, buildBildirim
//   panel/js/bildirim-zaman.js  planTime, gönderim penceresi, evrak son tarihi
//   panel/js/bekletme.js        olayla tetiklenen mesaj en erken 30 dk sonra
// Seçenek listeleri (merkezler, iller, saatler, temsilcilikler) sitenin
// uygulama dosyasından gelir (uygulama.json → randevu).

// MARK: - Seçenekler

public struct Temsilcilik: Decodable, Equatable, Identifiable, Hashable {
    public var ulke: String
    public var tur: String
    public var ad: String
    public var sehir: String
    public var harita: String
    public var id: String { ad }

    public init(ulke: String, tur: String, ad: String, sehir: String, harita: String) {
        self.ulke = ulke; self.tur = tur; self.ad = ad; self.sehir = sehir; self.harita = harita
    }
}

public struct RandevuSecenekleri: Decodable, Equatable {
    public var merkezler: [String]
    public var temsilcilikTurleri: [String]
    public var sehirler: [String]
    public var sikSehirSayisi: Int
    public var saatler: [String]
    public var temsilcilikler: [Temsilcilik]
    public var merkezHaritalari: [String: String]

    enum Anahtar: String, CodingKey { case merkezler, temsilcilikTurleri, sehirler, sikSehirSayisi, saatler, temsilcilikler, merkezHaritalari }

    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        merkezler = c.dizi(.merkezler)
        temsilcilikTurleri = c.dizi(.temsilcilikTurleri)
        sehirler = c.dizi(.sehirler)
        sikSehirSayisi = Int(c.sayi(.sikSehirSayisi))
        saatler = c.dizi(.saatler)
        temsilcilikler = c.dizi(.temsilcilikler)
        merkezHaritalari = c.nesne(.merkezHaritalari) ?? [:]
    }

    public init(merkezler: [String], temsilcilikTurleri: [String], sehirler: [String], sikSehirSayisi: Int,
                saatler: [String], temsilcilikler: [Temsilcilik], merkezHaritalari: [String: String]) {
        self.merkezler = merkezler; self.temsilcilikTurleri = temsilcilikTurleri; self.sehirler = sehirler
        self.sikSehirSayisi = sikSehirSayisi; self.saatler = saatler; self.temsilcilikler = temsilcilikler
        self.merkezHaritalari = merkezHaritalari
    }

    public func temsilcilikMi(_ merkez: String) -> Bool { temsilcilikTurleri.contains(merkez) }
    public func temsilcilik(_ ad: String) -> Temsilcilik? { temsilcilikler.first { $0.ad == ad } }
    /// Başvurunun ülkesindeki temsilcilikler (tür verilirse yalnız o tür).
    public func temsilcilikler(ulke: String, tur: String? = nil) -> [Temsilcilik] {
        temsilcilikler.filter { $0.ulke == ulke && (tur == nil || $0.tur == tur) }
    }
}

/// Ayarlar → Randevu konumları (settings/konumlar): kesin harita bağlantıları.
public struct KonumAyari: Equatable {
    public var temsilcilik: [String: String]
    public var merkez: [String: String]
    static let haritaDeseni = "^https://(www\\.google\\.com/maps/|maps\\.app\\.goo\\.gl/)\\S{1,480}$"

    public init(belge: [String: FSDeger]?) {
        func temiz(_ d: FSDeger?) -> [String: String] {
            (d?.haritaDegeri ?? [:]).compactMapValues { v -> String? in
                guard let s = v.metinDegeri?.kirpik, s.eslesir(KonumAyari.haritaDeseni) else { return nil }
                return s
            }
        }
        temsilcilik = temiz(belge?["temsilcilik"])
        merkez = temiz(belge?["merkez"])
    }
}

// MARK: - Randevu kağıdı

public struct RandevuGirdisi: Equatable {
    public var tarih: String   // YYYY-AA-GG (Türkiye)
    public var saat: String
    public var merkez: String
    public var sehir: String
    /// Konsolosluk / büyükelçilikte temsilciliğin adı.
    public var yer: String
    public var ulke: String

    public init(tarih: String, saat: String, merkez: String, sehir: String, yer: String, ulke: String) {
        self.tarih = tarih; self.saat = saat; self.merkez = merkez; self.sehir = sehir; self.yer = yer; self.ulke = ulke
    }
}

public enum RandevuKurali {
    /// Hatalar (boş: kaydedilebilir). Hepsi seçmeli ve zorunlu.
    public static func hatalar(_ r: RandevuGirdisi, _ s: RandevuSecenekleri, bugun: String) -> [String] {
        var h: [String] = []
        if !r.tarih.eslesir("^\\d{4}-\\d{2}-\\d{2}$") || Tr.tarih(r.tarih) == nil { h.append("Randevu tarihini takvimden seçin.") }
        else if r.tarih < bugun { h.append("Randevu tarihi geçmiş bir gün olamaz.") }
        if !s.saatler.contains(r.saat) { h.append("Randevu saatini seçin.") }
        if !s.merkezler.contains(r.merkez) { h.append("Randevu merkezini seçin.") }
        if s.temsilcilikMi(r.merkez) {
            let t = s.temsilcilik(r.yer)
            if t == nil || t?.tur != r.merkez || (!r.ulke.isEmpty && t?.ulke != r.ulke) {
                h.append("Hangi \(r.merkez == "Konsolosluk" ? "konsolosluk" : "büyükelçilik") olduğunu seçin.")
            }
        } else if !s.sehirler.contains(r.sehir) {
            h.append("Randevu şehrini seçin.")
        }
        return h
    }

    public struct Kayit: Equatable {
        public var saat: String
        public var merkez: String
        public var sehir: String
        public var yer: String
        public var harita: String

        public init(saat: String, merkez: String, sehir: String, yer: String, harita: String) {
            self.saat = saat; self.merkez = merkez; self.sehir = sehir; self.yer = yer; self.harita = harita
        }
    }

    /// Kaydedilecek alanlar: temsilcilikte şehir listeden; harita ayardan, yoksa listedeki arama bağlantısı.
    public static func kayit(_ r: RandevuGirdisi, _ s: RandevuSecenekleri, konumlar: KonumAyari) -> Kayit {
        if s.temsilcilikMi(r.merkez), let t = s.temsilcilik(r.yer) {
            return Kayit(saat: r.saat, merkez: r.merkez, sehir: t.sehir, yer: t.ad, harita: konumlar.temsilcilik[t.ad] ?? t.harita)
        }
        let k = "\(r.merkez)|\(r.sehir)"
        return Kayit(saat: r.saat, merkez: r.merkez, sehir: r.sehir, yer: "", harita: konumlar.merkez[k] ?? s.merkezHaritalari[k] ?? "")
    }

    /// Türkiye saatiyle (UTC+3, yaz saati yok) tarih + saat.
    public static func an(_ tarih: String, _ saat: String) -> Date? {
        FSDeger.zamanOku("\(tarih)T\(saat):00+03:00") ?? {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: "\(tarih)T\(saat):00+03:00")
        }()
    }
}

extension BasvuruIslemi {
    /// Randevu kağıdı: dosya + randevu bilgileri (tarih, saat, merkez, şehir, yer, harita) + geçmiş + işlem kaydı.
    public static func randevuBelgesi(_ b: Basvuru, _ r: RandevuGirdisi, kayit k: RandevuKurali.Kayit, dosya: HazirDosya, calisan c: Calisan)
        -> [FirestoreIstemci.Yazim] {
        let an = RandevuKurali.an(r.tarih, r.saat) ?? Date()
        let gun = Tr.tarih(r.tarih).map { Tr.kisaTarih($0) } ?? r.tarih
        return Dosya.ekle(ust: ust(b), tur: "randevu", dosya: dosya, calisan: c).yazimlar + [
            gecmis(b, tur: "dosya", metin: "Belge eklendi: Randevu kağıdı — \(dosya.ad)", c),
            .guncelle(yol: ust(b), alanlar: [
                "appointmentAt": .zaman(an), "randevuSaati": .metin(k.saat), "randevuMerkezi": .metin(k.merkez),
                "randevuSehri": .metin(k.sehir), "randevuYeri": .metin(k.yer), "randevuHarita": .metin(k.harita),
                "updatedBy": .metin(c.uid),
            ], zaman: ["updatedAt"]),
            gecmis(b, tur: "randevu", metin: "Randevu: \(gun) \(k.saat) · \(k.yer.isEmpty ? "\(k.merkez) · \(k.sehir)" : k.yer)", c),
            kayit("app.dosya", b, "randevu: \(dosya.ad)", c),
        ]
    }
}

// MARK: - Bildirim ayarı

/// Otomatik müşteri bildirimlerinin ayarı (settings/bildirim; panel: mergeAyar).
public struct BildirimAyari: Equatable {
    public struct Sablon: Equatable {
        public var acik: Bool
        public var mod: String        // hemen | sonrasi | oncesi
        public var gun: Int
        public var saat: Int?
        /// Mesaj metni ve e-posta konusu (yer tutucularla; gönderim anında doldurulur).
        public var metin = ""
        public var konu = ""
    }
    public var acik: Bool
    public var pencereBas: Int
    public var pencereSon: Int
    public var evrakGun: Int
    public var kanallar: (wa: Bool, sms: Bool, email: Bool)
    public var sablonlar: [String: Sablon]
    /// Ülke grupları: ülke kimlikleri → grubun şablonları.
    public var gruplar: [(ulkeler: [String], sablonlar: [String: Sablon])]

    public static func == (a: BildirimAyari, b: BildirimAyari) -> Bool {
        a.acik == b.acik && a.pencereBas == b.pencereBas && a.pencereSon == b.pencereSon && a.evrakGun == b.evrakGun
            && a.sablonlar == b.sablonlar
    }

    static let varsayilan: [String: Sablon] = [
        "randevu-alindi": Sablon(acik: true, mod: "hemen", gun: 0, saat: nil,
                                 metin: "🎉 Müjde {isim}!\n{ülke} vize randevunuz alındı. ✈️\n{randevu bilgileri}\n"
                                     + "Randevunuza {hatırlatma günü} gün kala evraklarınızla ilgili size tekrar hatırlatma yapacağız.\n"
                                     + "Sorunuz olursa bize yazabilirsiniz. 😊\n— VizeMia",
                                 konu: "{ülke} vize randevunuz alındı 🎉"),
        "evrak-hatirlatma": Sablon(acik: true, mod: "oncesi", gun: 15, saat: 9,
                                   metin: "📂 Merhaba {isim},\n{ülke} vize randevunuza {hatırlatma günü} gün kaldı! ⏳\n"
                                       + "📅 Randevu tarihiniz: {randevu tarihi}\nEvraklarınızı hazırlamaya başlamanız gerekiyor.\n"
                                       + "⚠️ Evraklarınızın en geç {evrak son tarihi} tarihinde bizde olması gerekiyor.\n"
                                       + "Takıldığınız bir şey olursa bize yazabilirsiniz, yardımcı oluruz.\n— VizeMia",
                                   konu: "{ülke} randevunuza {hatırlatma günü} gün kaldı — evraklar"),
        "form-linki": Sablon(acik: true, mod: "kural", gun: 0, saat: 9,
                             metin: "📝 Merhaba {isim},\n{ülke} vize başvurunuz için formunuz hazır.\n"
                                 + "Aşağıdaki bağlantıdan bilgilerinizi tamamlayıp evraklarınızı yükleyebilirsiniz:\n{form bağlantısı}\n"
                                 + "🔒 Bu bağlantı yalnızca size özel; başkasıyla paylaşmayın.\n"
                                 + "Takıldığınız bir yer olursa bize yazabilirsiniz.\n— VizeMia",
                             konu: "{ülke} vize başvurunuz — formunuz hazır"),
    ]

    static func sinirla(_ d: FSDeger?, _ alt: Int, _ ust: Int, _ yedek: Int) -> Int {
        var n: Int?
        if let t = d?.tamDegeri { n = t }
        if case .ondalik(let v)? = d { n = Int(v.rounded()) }
        if case .metin(let s)? = d { n = Int(s) }
        guard let x = n else { return yedek }
        return min(ust, max(alt, x))
    }

    static func sablon(_ m: [String: FSDeger]?, ustune s: Sablon) -> Sablon {
        guard let m else { return s }
        var t = s
        if let a = m["enabled"]?.mantikDegeri { t.acik = a }
        if let mod = m["sendMode"]?.metinDegeri { t.mod = mod }
        if m["offsetDays"] != nil { t.gun = sinirla(m["offsetDays"], 0, 365, 0) }
        if let h = m["hour"] {
            if case .bos = h { t.saat = nil } else { t.saat = sinirla(h, 0, 23, 9) }
        }
        if let x = m["text"]?.metinDegeri { t.metin = x }
        if let x = m["emailSubject"]?.metinDegeri { t.konu = x }
        return t
    }

    public init(belge d: [String: FSDeger]?) {
        acik = d?["enabled"]?.mantikDegeri ?? true
        pencereBas = BildirimAyari.sinirla(d?["windowStart"], 0, 23, 9)
        pencereSon = BildirimAyari.sinirla(d?["windowEnd"], 1, 24, 21)
        evrakGun = BildirimAyari.sinirla(d?["evrakGun"], 0, 60, 3)
        let k = d?["channels"]?.haritaDegeri
        kanallar = (k?["wa"]?.mantikDegeri ?? true, k?["sms"]?.mantikDegeri ?? true, k?["email"]?.mantikDegeri ?? true)
        let kayitli = d?["templates"]?.haritaDegeri
        var s: [String: Sablon] = [:]
        for (tur, v) in BildirimAyari.varsayilan { s[tur] = BildirimAyari.sablon(kayitli?[tur]?.haritaDegeri, ustune: v) }
        sablonlar = s
        gruplar = (d?["gruplar"]?.diziDegeri ?? []).prefix(60).compactMap { g in
            guard let m = g.haritaDegeri, !(m["id"]?.metinDegeri ?? "").isEmpty else { return nil }
            let ulkeler = (m["ulkeler"]?.diziDegeri ?? []).compactMap { $0.metinDegeri }
            if ulkeler.isEmpty { return nil }
            let gt = m["templates"]?.haritaDegeri
            var t: [String: Sablon] = [:]
            for (tur, v) in s { t[tur] = BildirimAyari.sablon(gt?[tur]?.haritaDegeri, ustune: v) }
            return (ulkeler, t)
        }
    }

    /// Ülkenin şablonları: grubu varsa onunkiler, yoksa genel (panel: ulkeAyari).
    public func sablonlar(ulke: String) -> [String: Sablon] {
        gruplar.first { $0.ulkeler.contains(ulke) }?.sablonlar ?? sablonlar
    }
}

// MARK: - Zaman (Türkiye saati)

public enum BildirimZamani {
    static var takvim: Calendar { Tr.takvim }

    /// Türkiye saatiyle gün ve saat.
    static func parca(_ d: Date) -> (iso: String, saat: Int) {
        let p = takvim.dateComponents([.year, .month, .day, .hour], from: d)
        return (Tr.iso(yil: p.year ?? 2000, ay: p.month ?? 1, gun: p.day ?? 1), p.hour ?? 0)
    }

    /// Türkiye saatiyle "gün saat:dakika" anı.
    static func an(_ iso: String, saat: Int, dakika: Int = 0) -> Date {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return Date() }
        var c = DateComponents()
        c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = saat; c.minute = dakika
        return takvim.date(from: c) ?? Date()
    }

    /// Gönderim penceresinin dışına düşen an ileri kaydırılır (gece mesaj yok).
    static func pencereye(_ d: Date, bas: Int, son: Int) -> Date {
        let p = parca(d)
        if p.saat < bas { return an(p.iso, saat: bas) }
        if p.saat >= son { return an(Tr.gunEkle(p.iso, 1), saat: bas) }
        return d
    }

    /// Mesajın gideceği an (panel: planTime).
    public static func plan(_ t: BildirimAyari.Sablon, randevu: String, simdi: Date, bas: Int, son: Int) -> Date {
        if t.mod == "oncesi" {
            let gun = Tr.gunEkle(randevu, -abs(t.gun))
            let at = an(gun, saat: t.saat ?? bas)
            return at <= simdi ? pencereye(simdi, bas: bas, son: son) : at
        }
        if t.mod == "sonrasi" {
            if t.gun == 0 && t.saat == nil { return pencereye(simdi, bas: bas, son: son) }
            let at = an(Tr.gunEkle(parca(simdi).iso, abs(t.gun)), saat: t.saat ?? bas)
            return at <= simdi ? pencereye(simdi, bas: bas, son: son) : at
        }
        return pencereye(simdi, bas: bas, son: son)
    }
}

// MARK: - Plan

/// Bir başvurunun var olan bildirim kaydı (bildirimler/{id}).
public struct BildirimKaydi: Equatable {
    public var id: String
    public var tur: String
    public var durum: String

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        id = kimlik
        tur = a["kind"]?.metinDegeri ?? ""
        durum = a["status"]?.metinDegeri ?? ""
    }
}

public enum BildirimPlani {
    /// Randevuyla planlanan türler (form bağlantısının kendi kuralı var; dokunulmaz).
    static let turler = ["randevu-alindi", "evrak-hatirlatma"]
    /// Olayla tetiklenen mesaj en erken 30 dakika sonra (hata payı).
    static let bekletilen: Set<String> = ["randevu-alindi"]
    static let beklemeSn: TimeInterval = 30 * 60

    public struct Sonuc {
        public var yazimlar: [FirestoreIstemci.Yazim]
        public var yazilan: [String]
        public var iptal: Int
        public var atlanan: [String]
    }

    /// Randevu girilince / değişince bildirimleri (yeniden) planlar (panel: bildirim.js → planla).
    /// Planlı olanlar iptal edilir, yenileri yazılır; gönderilmiş türler yeniden
    /// planlanmaz (`yenidenGonder` dışında: randevu kağıdı girilince "randevu alındı"
    /// yeni bilgilerle bir kez daha gider).
    public static func planla(
        _ b: Basvuru, randevu r: RandevuGirdisi, kayit k: RandevuKurali.Kayit, iletisim: MusteriIletisimi,
        ayar: BildirimAyari, mevcut: [BildirimKaydi], yenidenGonder: Set<String> = ["randevu-alindi"],
        calisan c: Calisan, simdi: Date = Date()
    ) -> Sonuc {
        var s = Sonuc(yazimlar: [], yazilan: [], iptal: 0, atlanan: [])
        guard ayar.acik else { s.atlanan.append("bildirimler kapalı"); return s }
        // Kurallar yalnız Türkiye cep telefonunu kabul ediyor (isPhone): öteki numarada WhatsApp/SMS planlanmaz.
        let tel = MusteriBildirimi.e164(iletisim.telefon)
        let telefon = tel.eslesir("^\\+90[0-9]{10}$") ? tel : ""
        let eposta = MusteriBildirimi.epostaGecerli(iletisim.eposta) ? iletisim.eposta.kirpik.lowercased() : ""
        let wa = iletisim.whatsapp && ayar.kanallar.wa && !telefon.isEmpty
        let sms = iletisim.sms && ayar.kanallar.sms && !telefon.isEmpty
        let email = iletisim.epostaIzni && ayar.kanallar.email && !eposta.isEmpty
        guard wa || sms || email else { s.atlanan.append("açık kanal yok"); return s }

        let gonderilmis = Set(mevcut.filter { $0.durum == "sent" && !yenidenGonder.contains($0.tur) }.map(\.tur))
        for m in mevcut where m.durum == "planned" && m.tur != "form-linki" {
            s.yazimlar.append(.guncelle(yol: "bildirimler/\(m.id)", alanlar: [
                "status": .metin("cancelled"), "cancelReason": .metin("Randevu tarihi güncellendi"), "updatedBy": .metin(c.uid),
            ], zaman: ["updatedAt"]))
            s.iptal += 1
        }
        let sablonlar = ayar.sablonlar(ulke: b.ulke)
        let hatirlatma = sablonlar["evrak-hatirlatma"]?.gun ?? 15
        let evrakSon = Tr.gunEkle(r.tarih, -abs(ayar.evrakGun))
        let sorumlu = b.sorumluUid.isEmpty ? c.uid : b.sorumluUid
        let sorumluAd = b.sorumluUid.isEmpty ? c.gorunenAd : b.sorumlu
        for tur in turler {
            guard let t = sablonlar[tur], t.acik else { s.atlanan.append(tur); continue }
            if gonderilmis.contains(tur) { s.atlanan.append(tur); continue }
            var at = BildirimZamani.plan(t, randevu: r.tarih, simdi: simdi, bas: ayar.pencereBas, son: ayar.pencereSon)
            if bekletilen.contains(tur) && at < simdi.addingTimeInterval(beklemeSn) { at = simdi.addingTimeInterval(beklemeSn) }
            var a: [String: FSDeger] = [:]
            a["appId"] = .metin(b.kimlik)
            a["trackingCode"] = .metin(String(b.takipKodu.prefix(20)))
            a["kind"] = .metin(tur)
            a["status"] = .metin("planned")
            a["channels"] = .harita(["wa": .mantik(wa), "sms": .mantik(sms), "email": .mantik(email)])
            a["name"] = .metin(String("\(b.ad) \(b.soyad)".kirpik.prefix(160)))
            a["countryName"] = .metin(String(b.ulkeAdi.prefix(60)))
            a["country"] = .metin(String(b.ulke.prefix(40)))
            a["appointmentDate"] = .metin(r.tarih)
            a["docDeadline"] = .metin(evrakSon)
            a["reminderDays"] = .tam(min(365, max(0, hatirlatma)))
            a["randevuSaati"] = .metin(String(k.saat.prefix(5)))
            a["randevuMerkezi"] = .metin(String(k.merkez.prefix(60)))
            a["randevuSehri"] = .metin(String(k.sehir.prefix(40)))
            a["randevuYeri"] = .metin(String(k.yer.prefix(120)))
            a["randevuHarita"] = .metin(String(k.harita.prefix(500)))
            a["phone"] = wa || sms ? .metin(telefon) : .bos
            a["email"] = email ? .metin(eposta) : .bos
            a["assignedTo"] = .metin(String(sorumlu.prefix(60)))
            a["assignedName"] = .metin(String(sorumluAd.prefix(80)))
            a["waStatus"] = .metin(wa ? "pending" : "skipped")
            a["attempts"] = .tam(0)
            a["sentAt"] = .bos
            a["force"] = .mantik(false)
            a["sendAt"] = .zaman(at)
            a["createdBy"] = .metin(c.uid)
            a["updatedBy"] = .metin(c.uid)
            s.yazimlar.append(.olustur(yol: "bildirimler/\(FirestoreIstemci.yeniKimlik())", alanlar: a, zaman: ["createdAt", "updatedAt"]))
            s.yazilan.append(tur)
        }
        return s
    }
}
