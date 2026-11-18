import Foundation

// Başvuru ayrıntısındaki işlemler: statü değiştirme, not, üst not, evrak,
// tekrar arama. Panelin karşılıkları:
//   panel/js/basvuru-akisi.js   statuGecisi, gerekenler, gecisEngelleri, aramaDurumu
//   panel/js/takip-asama.js     takipAsamasi (müşterinin ilerleme çubuğu)
//   panel/js/pages/applications.js  buildTakip, statü / not / evrak / üst not yazımları
//   panel/js/eposta-ortak.js, eposta.js  statü maili
//   panel/js/sms.js             SMS kuyruğu
// Yazımların alan listeleri firestore.rules'taki hasOnly listeleriyle aynı;
// emülatör testleri (BasvuruEmulatorTests) gerçek kurallara karşı dener.

// MARK: - Geçiş şartları

/// Statüye geçmeden önce tamamlanması gerekenler (Ayarlar → Statüler).
public enum GecisSarti: String, CaseIterable {
    case odeme, evrak, randevu, takipKodu, fis

    public var ad: String {
        switch self {
        case .odeme: return "Ödeme bilgisi girilmiş"
        case .evrak: return "Evrak kontrol listesi tamam"
        case .randevu: return "Randevu kağıdı yüklenmiş"
        case .takipKodu: return "Konsolosluk takip kodu girilmiş"
        case .fis: return "Pasaport teslim fişi yüklenmiş"
        }
    }

    /// Engel metnindeki adı ("ödeme bilgisi" …).
    var eksikAdi: String {
        switch self {
        case .odeme: return "ödeme bilgisi"
        case .evrak: return "evrak kontrol listesi"
        case .randevu: return "randevu kağıdı"
        case .takipKodu: return "konsolosluk takip kodu"
        case .fis: return "pasaport teslim fişi"
        }
    }
}

extension Basvuru {
    static let gunSn: Double = 86_400

    /// Statü değişince başvuruya yazılacak alanlar ve sunucu saatiyle yazılacaklar.
    ///  - son adım: finalAt + deleteAfter (saklama süresi; zaten son adımdaysa dokunulmaz)
    ///  - silmeGun'lü statü (ör. potansiyel): deleteAfter = şimdi + silmeGun
    ///  - öteki: deleteAfter kalkar (süresiz)
    public func statuGecisi(_ hedef: Statu, saklamaGun: Int, simdi: Date = Date()) -> (alanlar: [String: FSDeger], zaman: [String]) {
        var alanlar: [String: FSDeger] = ["statusId": .metin(hedef.id), "statusName": .metin(hedef.ad)]
        var zaman = ["statusAt"]
        if hedef.son {
            if sonAdimZamani == nil {
                zaman.append("finalAt")
                let gun = saklamaGun > 0 ? saklamaGun : 60
                alanlar["deleteAfter"] = .zaman(simdi.addingTimeInterval(Double(gun) * Basvuru.gunSn))
            }
            return (alanlar, zaman)
        }
        if sonAdimZamani != nil { alanlar["finalAt"] = .bos }
        alanlar["deleteAfter"] = hedef.silmeGun.map { .zaman(simdi.addingTimeInterval(Double($0) * Basvuru.gunSn)) } ?? .bos
        return (alanlar, zaman)
    }

    /// Statüye geçmeden önce eksik kalanlar (boş: geçilebilir). Evrak, randevu
    /// kağıdı ve fiş ekranda bilinir; bilinmiyorsa (nil) denetlenmez.
    public func gecisEngelleri(_ hedef: Statu, evrakTamam: Bool? = nil, randevuVar: Bool? = nil, fisVar: Bool? = nil) -> [String] {
        hedef.gerekenler.compactMap(GecisSarti.init(rawValue:)).compactMap { s -> String? in
            switch s {
            case .odeme: return odemeSayisi > 0 ? nil : s.eksikAdi
            case .evrak: return evrakTamam == false ? s.eksikAdi : nil
            case .randevu: return randevuVar == false ? s.eksikAdi : nil
            case .takipKodu: return konsTakipKodu.isEmpty ? s.eksikAdi : nil
            case .fis: return fisVar == false ? s.eksikAdi : nil
            }
        }
    }

    public static func gecisMesaji(_ hedef: Statu, _ eksik: [String]) -> String {
        eksik.isEmpty ? "" : "\"\(hedef.ad)\" statüsüne geçmeden önce tamamlayın: \(eksik.joined(separator: ", "))."
    }

    var takipBaglantisi: String {
        "https://vizemia.com/takip?kod=\(takipKodu.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-"))) ?? takipKodu)"
    }
}

// MARK: - Notlar ve geçmiş

/// Başvuru notu (applications/{id}/notes): müşteriye görünür olanlar takip sayfasına da gider.
public struct BasvuruNotu: Equatable, Identifiable {
    public var id: String
    public var metin: String
    public var musteriyeGorunur: Bool
    public var yazan: String
    public var zaman: Date?

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        id = kimlik
        metin = a["text"]?.metinDegeri ?? ""
        musteriyeGorunur = a["public"]?.mantikDegeri ?? false
        yazan = a["byName"]?.metinDegeri ?? ""
        zaman = a["at"]?.zamanDegeri
    }

    public init(id: String, metin: String, musteriyeGorunur: Bool, yazan: String, zaman: Date?) {
        self.id = id; self.metin = metin; self.musteriyeGorunur = musteriyeGorunur; self.yazan = yazan; self.zaman = zaman
    }
}

/// Üst not (applications/{id}/ustNotlar): ekip içi, sayfanın en üstünde, mesaj gibi.
public struct UstNot: Equatable, Identifiable {
    public var id: String
    public var metin: String
    public var yazanUid: String
    public var yazan: String
    public var zaman: Date?

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        id = kimlik
        metin = a["metin"]?.metinDegeri ?? ""
        yazanUid = a["by"]?.metinDegeri ?? ""
        yazan = a["byName"]?.metinDegeri ?? ""
        zaman = a["at"]?.zamanDegeri
    }
}

/// Geçmiş satırı (applications/{id}/log).
public struct GecmisSatiri: Equatable, Identifiable {
    public var id: String
    public var tur: String
    public var metin: String
    public var yazan: String
    public var zaman: Date?

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        id = kimlik
        tur = a["type"]?.metinDegeri ?? ""
        let m = a["text"]?.metinDegeri ?? ""
        metin = m.isEmpty ? tur : m
        yazan = a["byName"]?.metinDegeri ?? ""
        zaman = a["at"]?.zamanDegeri
    }

    /// Geçmişe yazılacak satır (`at` sunucu saatiyle).
    public static func alanlar(tur: String, metin: String, statu: Statu? = nil, calisan: Calisan) -> [String: FSDeger] {
        [
            "type": .metin(tur),
            "text": .metin(String(metin.prefix(500))),
            "statusId": .metin(statu?.id ?? ""),
            "statusName": .metin(statu?.ad ?? ""),
            "by": .metin(calisan.uid),
            "byName": .metin(String(calisan.gorunenAd.prefix(80))),
        ]
    }
}

extension Calisan {
    /// Kayıtlarda görünen ad (panel: myName → displayName, yoksa kullanıcı adı).
    public var gorunenAd: String { adSoyad.isEmpty ? kullaniciAdi : adSoyad }
}

// MARK: - Müşterinin takip sayfası

/// Müşteri takip belgesi (takip/{takipId}): statünün müşteriye görünen adı,
/// açıklaması, görünür notlar ve ilerleme çubuğu.
public enum TakipBelgesi {
    /// Panelde 12 statü var; müşteriye sade aşamalar gösterilir (panel/js/takip-asama.js).
    static let asamalar: [(ad: String, statuler: [String])] = [
        ("Görüşme", ["potansiyel"]),
        ("Randevu takibi", ["randevu-takip"]),
        ("Randevu alındı", ["randevu"]),
        ("Evraklar", ["evrak-bekleniyor", "eksik-evrak", "evrak-tamam", "form-dolduruldu"]),
        ("Parmak izi", ["biyometri"]),
        ("Konsoloslukta", ["konsoloslukta"]),
        ("Sonuç", ["sonuc-onay", "sonuc-ret"]),
        ("Teslim", ["teslim"]),
    ]
    static let asamaEnCok = 10

    static func asamaNo(_ id: String) -> Int? { asamalar.firstIndex { $0.statuler.contains(id) } }

    /// Aşama adları ve şimdiki sıra. Sıra Ayarlar → Statüler'deki sıradan;
    /// listede olmayan statü kendinden önceki bilinen statünün aşamasında sayılır.
    public static func asamasi(statuler: [Statu], statuId: String) -> (asamalar: [String], asama: Int)? {
        let sirali = statuler.enumerated().sorted { a, b in
            a.element.sira != b.element.sira ? a.element.sira < b.element.sira : a.offset < b.offset
        }.map(\.element)
        var yer: [Int: Int] = [:]
        for (i, s) in sirali.enumerated() { if let a = asamaNo(s.id), yer[a] == nil { yer[a] = i } }
        let dizi = yer.sorted { $0.value < $1.value }.map(\.key)
        guard dizi.count >= 2, let i = sirali.firstIndex(where: { $0.id == statuId }) else { return nil }
        var a = asamaNo(statuId)
        var j = i - 1
        while a == nil && j >= 0 { a = asamaNo(sirali[j].id); j -= 1 }
        var asama = dizi.firstIndex(of: a ?? dizi[0]) ?? 0
        if sirali[i].son { asama = dizi.count - 1 }
        return (Array(dizi.prefix(asamaEnCok)).map { asamalar[$0].ad }, min(asama, asamaEnCok - 1))
    }

    /// Belgenin alanları (`updatedAt` sunucu saatiyle ayrıca). `notlar`: müşteriye
    /// görünür notlar, en yenisi başta.
    public static func alanlar(basvuru: Basvuru, statu: Statu?, statuler: [Statu], notlar: [BasvuruNotu], simdi: Date = Date()) -> [String: FSDeger] {
        let ad = [statu?.musteriAdi, statu?.ad, basvuru.statuAdi].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        var a: [String: FSDeger] = [
            "countryName": .metin(String(basvuru.ulkeAdi.prefix(60))),
            "firstName": .metin(String(basvuru.ad.prefix(80))),
            "statusName": .metin(String(ad.prefix(60))),
            "statusDescription": .metin(String((statu?.musteriAciklamasi ?? "").prefix(400))),
            "statusColor": .metin(String(((statu?.renk).flatMap { $0.isEmpty ? nil : $0 } ?? "#1e2c4d").prefix(20))),
            "isFinal": .mantik(statu?.son ?? false),
            "notes": .dizi(notlar.prefix(30).map {
                .harita(["text": .metin(String($0.metin.prefix(2000))), "at": .zaman($0.zaman ?? simdi)])
            }),
        ]
        if let r = asamasi(statuler: statuler, statuId: statu?.id ?? basvuru.statuId) {
            a["asamalar"] = .dizi(r.asamalar.map { .metin($0) })
            a["asama"] = .tam(r.asama)
        }
        return a
    }
}

// MARK: - Evrak kontrol listesi

/// Sitenin uygulama dosyasındaki katalog (uygulama.json → evrak).
public struct EvrakKatalogu: Decodable, Equatable {
    public var etiketler: [String: String]
    public var genel: [String]
    public var kosullu: [String]
    public var ulkeler: [String: [String]]

    enum Anahtar: String, CodingKey { case etiketler, genel, kosullu, ulkeler }

    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        etiketler = c.nesne(.etiketler) ?? [:]
        genel = c.dizi(.genel)
        kosullu = c.dizi(.kosullu)
        ulkeler = c.nesne(.ulkeler) ?? [:]
    }

    public init(etiketler: [String: String], genel: [String], kosullu: [String], ulkeler: [String: [String]]) {
        self.etiketler = etiketler; self.genel = genel; self.kosullu = kosullu; self.ulkeler = ulkeler
    }
}

public struct Evrak: Equatable, Identifiable {
    public var id: String
    public var ad: String
    /// Herkesten değil, müşterinin durumuna göre isteniyor (emekli, 18 yaş altı…): sayaca girmez.
    public var kosullu: Bool

    public init(id: String, ad: String, kosullu: Bool = false) { self.id = id; self.ad = ad; self.kosullu = kosullu }
}

/// Ayarlardaki listeler (settings/checklist: items, byCountry).
public struct EvrakAyari: Equatable {
    public var genel: [Evrak]?
    public var ulkeler: [String: [Evrak]]

    public init(belge: [String: FSDeger]?) {
        func liste(_ d: FSDeger?) -> [Evrak]? {
            d?.diziDegeri?.compactMap { x -> Evrak? in
                guard let m = x.haritaDegeri, let id = m["id"]?.metinDegeri, !id.isEmpty else { return nil }
                return Evrak(id: id, ad: m["label"]?.metinDegeri ?? id, kosullu: false)
            }
        }
        genel = liste(belge?["items"])
        ulkeler = (belge?["byCountry"]?.haritaDegeri ?? [:]).compactMapValues { liste($0) }
    }

    /// Ülkenin listesi (panel: checklistShownFor). Sıra: ayardaki ülke listesi →
    /// katalogdaki ülke listesi → ayardaki genel liste (yoksa katalogdaki genel).
    /// Listede artık olmayan ama işaretlenmiş evraklar sona eklenir.
    public func liste(ulke: String, katalog: EvrakKatalogu, isaretli: [String: Bool]) -> [Evrak] {
        let kosullu = Set(katalog.kosullu)
        let ad = { (id: String) in katalog.etiketler[id] ?? id }
        var l: [Evrak]
        if let u = ulkeler[ulke], !u.isEmpty { l = u }
        else if let u = katalog.ulkeler[ulke] { l = u.map { Evrak(id: $0, ad: ad($0), kosullu: false) } }
        else { l = genel ?? katalog.genel.map { Evrak(id: $0, ad: ad($0), kosullu: false) } }
        let varOlan = Set(l.map(\.id))
        let tum = (genel ?? []) + ulkeler.values.flatMap { $0 }
        let eski = isaretli.filter { $0.value && !varOlan.contains($0.key) }.keys.sorted().map { id in
            Evrak(id: id, ad: tum.first { $0.id == id }?.ad ?? ad(id), kosullu: false)
        }
        return (l + eski).map { Evrak(id: $0.id, ad: $0.ad, kosullu: kosullu.contains($0.id)) }
    }
}

// MARK: - Müşteriye otomatik bildirim (statü maili, SMS)

/// Müşterinin iletişim bilgisi ve tercihleri (private/data → form).
public struct MusteriIletisimi: Equatable {
    public var telefon: String
    public var eposta: String
    public var whatsapp: Bool
    public var sms: Bool
    public var epostaIzni: Bool

    public init(form: [String: FSDeger]?) {
        let f = form ?? [:]
        telefon = f["phone"]?.metinDegeri ?? ""
        eposta = f["email"]?.metinDegeri ?? ""
        // Hiç seçim yoksa (eski kayıt) üçü de açık (panel: bildirim-tercih.js → tercihOku).
        if let c = f["channels"]?.haritaDegeri {
            whatsapp = c["wa"]?.mantikDegeri == true
            sms = c["sms"]?.mantikDegeri == true
            epostaIzni = c["email"]?.mantikDegeri == true
        } else {
            whatsapp = true; sms = true; epostaIzni = true
        }
    }

    public var epostaAcik: Bool { epostaIzni && MusteriBildirimi.epostaGecerli(eposta) }
    public var smsAcik: Bool { sms && !telefon.kirpik.isEmpty }
}

/// Statü maili şablonları (settings/eposta → statuSablonlari).
public struct EpostaAyari: Equatable {
    public struct Sablon: Equatable { public var aktif: Bool; public var konu: String; public var metin: String }
    /// Tekli ve toplu gönderimde seçilen hazır metin (tur: bilgi | kampanya).
    public struct HazirMetin: Equatable, Identifiable {
        public var id: String
        public var ad: String
        public var tur: String
        public var konu: String
        public var metin: String
    }
    public var statuSablonlari: [String: Sablon]
    public var sablonlar: [HazirMetin] = EpostaAyari.varsayilanSablonlar
    public var gunlukSinir = 280
    /// Ticari ileti (kampanya) için İYS kaydı şart; kayıt bitene kadar kampanya gönderilemez.
    public var iysTamam = false

    static let varsayilanSablonlar: [HazirMetin] = [
        HazirMetin(id: "evrak-hatirlatma", ad: "Evrak hatırlatması", tur: "bilgi", konu: "{ulke} vize başvurunuz için evraklarınız",
                   metin: "Sayın {adSoyad},\n\n{ulke} vize başvurunuz için evraklarınızı bekliyoruz. Eksik evrak listesini size ayrıca ilettik.\n\nBaşvuru takibi: {takipLinki}"),
        HazirMetin(id: "genel-bilgi", ad: "Genel bilgilendirme", tur: "bilgi", konu: "VizeMia — bilgilendirme", metin: "Sayın {adSoyad},\n\n"),
        HazirMetin(id: "kampanya-ornek", ad: "Kampanya (örnek)", tur: "kampanya", konu: "VizeMia'dan size özel",
                   metin: "Merhaba {ad},\n\nYeni seyahatiniz için vize başvurunuzda yanınızdayız. "),
    ]

    public init(belge: [String: FSDeger]?) {
        if let l = belge?["sablonlar"]?.diziDegeri {
            sablonlar = l.prefix(50).compactMap { d in
                guard let m = d.haritaDegeri, let id = m["id"]?.metinDegeri?.kirpik, !id.isEmpty else { return nil }
                let ad = String((m["ad"]?.metinDegeri ?? "").kirpik.prefix(80))
                return HazirMetin(id: String(id.prefix(40)), ad: ad.isEmpty ? "Şablon" : ad,
                                  tur: m["tur"]?.metinDegeri == "kampanya" ? "kampanya" : "bilgi",
                                  konu: String((m["konu"]?.metinDegeri ?? "").kirpik.prefix(200)),
                                  metin: String((m["metin"]?.metinDegeri ?? "").prefix(20_000)))
            }
        }
        if let n = belge?["gunlukSinir"]?.tamDegeri, n >= 1 { gunlukSinir = min(n, 5000) }
        iysTamam = belge?["iysTamam"]?.mantikDegeri == true
        // Varsayılanlar kapalı (panel: DEFAULT_EPOSTA); kayıtlı olan üzerine yazar.
        var s: [String: Sablon] = [
            "sonuc-onay": Sablon(aktif: false, konu: "", metin: ""),
            "sonuc-ret": Sablon(aktif: false, konu: "", metin: ""),
        ]
        for (id, d) in belge?["statuSablonlari"]?.haritaDegeri ?? [:] {
            guard let m = d.haritaDegeri else { continue }
            s[id] = Sablon(aktif: m["aktif"]?.mantikDegeri == true,
                           konu: String((m["konu"]?.metinDegeri ?? "").kirpik.prefix(200)),
                           metin: String((m["metin"]?.metinDegeri ?? "").prefix(20_000)))
        }
        statuSablonlari = s
    }
}

/// SMS ayarı (settings/sms).
public struct SmsAyari: Equatable {
    public var acik: Bool
    public var statuSablonu: String
    public var notSablonu: String

    public init(belge: [String: FSDeger]?) {
        acik = belge?["enabled"]?.mantikDegeri ?? false
        let st = belge?["statusTemplate"]?.metinDegeri ?? ""
        let nt = belge?["noteTemplate"]?.metinDegeri ?? ""
        statuSablonu = st.isEmpty ? "Sayin {ad}, {ulke} vize basvurunuzun durumu: {statu}. Takip: {link}" : st
        notSablonu = nt.isEmpty ? "Sayin {ad}, VizeMia: {not} Takip: {link}" : nt
    }
}

public enum MusteriBildirimi {
    public static func epostaGecerli(_ s: String) -> Bool {
        s.kirpik.lowercased().eslesir("^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}$")
    }

    /// "AYŞE NUR" → "Ayşe Nur" (mailde büyük harf bağırıyor gibi durmasın).
    public static func adDuzelt(_ s: String) -> String {
        var out = ""
        var basta = true
        for ch in s.kirpik.lowercased(with: Tr.yerel) {
            out += basta && ch.isLetter ? String(ch).uppercased(with: Tr.yerel) : String(ch)
            basta = ch == " " || ch == "-"
            if ch.isLetter { basta = false }
        }
        return out
    }

    /// Şablondaki {ad} {ulke} gibi yer tutucuları doldurur; bilinmeyen olduğu gibi kalır.
    public static func doldur(_ metin: String, _ d: [String: String]) -> String {
        guard let re = try? NSRegularExpression(pattern: "\\{([^}]+)\\}") else { return metin }
        let ns = metin as NSString
        var out = ""
        var son = 0
        for m in re.matches(in: metin, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: son, length: m.range.location - son))
            let k = ns.substring(with: m.range(at: 1)).kirpik
            out += d[k] ?? ns.substring(with: m.range)
            son = m.range.location + m.range.length
        }
        return out + ns.substring(from: son)
    }

    /// Mail yer tutucuları (panel: epostaDegerleri).
    public static func epostaDegerleri(_ b: Basvuru, statu: String) -> [String: String] {
        let a = adDuzelt(b.ad), s = adDuzelt(b.soyad)
        let adSoyad = "\(a) \(s)".kirpik
        let link = b.takipKodu.isEmpty ? "" : b.takipBaglantisi
        return [
            "ad": a.isEmpty ? "Müşterimiz" : a, "isim": a.isEmpty ? "Müşterimiz" : a, "soyad": s,
            "adSoyad": adSoyad.isEmpty ? "Müşterimiz" : adSoyad,
            "ulke": b.ulkeAdi, "ülke": b.ulkeAdi, "statu": statu, "statü": statu,
            "takipKodu": b.takipKodu, "kod": b.takipKodu, "takipLinki": link, "link": link,
        ]
    }

    /// Statü maili kuyruk belgesi (eposta/{id}); şablon kapalıysa ya da adres yoksa nil.
    public static func statuEpostasi(_ b: Basvuru, hedef: Statu, ayar: EpostaAyari, iletisim: MusteriIletisimi, calisan: Calisan) -> [String: FSDeger]? {
        guard let s = ayar.statuSablonlari[hedef.id], s.aktif, iletisim.epostaAcik else { return nil }
        let d = epostaDegerleri(b, statu: hedef.musteriAdi.isEmpty ? hedef.ad : hedef.musteriAdi)
        let konu = doldur(s.konu, d).kirpik, metin = doldur(s.metin, d).kirpik
        guard !konu.isEmpty, !metin.isEmpty else { return nil }
        return [
            "to": .metin(iletisim.eposta.kirpik.lowercased()),
            "ad": .metin(String("\(b.ad) \(b.soyad)".kirpik.prefix(120))),
            "subject": .metin(String(konu.prefix(200))),
            "text": .metin(String(metin.prefix(20_000))),
            "tur": .metin("statu"), "appId": .metin(b.kimlik), "statusId": .metin(hedef.id),
            "status": .metin("queued"), "attempts": .tam(0),
            "createdBy": .metin(calisan.uid), "byName": .metin(String(calisan.gorunenAd.prefix(80))),
        ]
    }

    /// Türkçe harfleri ASCII'ye çevirir (SMS tek parça ücretli kalsın; panel: asciiText).
    public static func ascii(_ s: String) -> String {
        let tablo: [Character: String] = ["ı": "i", "İ": "I", "ğ": "g", "Ğ": "G", "ş": "s", "Ş": "S",
                                          "ö": "o", "Ö": "O", "ü": "u", "Ü": "U", "ç": "c", "Ç": "C"]
        let cevrilmis = s.map { tablo[$0] ?? String($0) }.joined()
        return cevrilmis.decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { !(0x300...0x36F).contains($0.value) }
            .map(String.init).joined()
    }

    /// Telefonu E.164'e çevirir: "0532 123 45 67" → "+905321234567" (panel: normalizePhone).
    public static func e164(_ s: String) -> String {
        let d = s.filter { $0.isNumber || $0 == "+" }
        if d.hasPrefix("+") { return d }
        let n = d.filter(\.isNumber)
        if n.count == 10 && n.hasPrefix("5") { return "+90\(n)" }
        if n.count == 11 && n.hasPrefix("0") { return "+90\(n.dropFirst())" }
        if n.count == 12 && n.hasPrefix("90") { return "+\(n)" }
        return ""
    }

    /// SMS kuyruk belgesi (sms/{id}); SMS kapalıysa, telefon ya da metin yoksa nil.
    public static func sms(_ b: Basvuru, sablon: String, statu: String, not: String, ayar: SmsAyari, telefon: String, calisan: Calisan) -> [String: FSDeger]? {
        let degerler = ["ad": b.ad, "soyad": b.soyad, "ulke": b.ulkeAdi, "statu": statu, "not": not,
                        "kod": b.takipKodu, "link": b.takipBaglantisi]
        // Panelde bilinmeyen yer tutucu boşalır (renderTemplate).
        let dolu = doldur(sablon, degerler).degistir("\\{[A-Za-z0-9_]+\\}", "")
        let metin = String(ascii(dolu).prefix(480)).kirpik
        let to = e164(telefon)
        guard ayar.acik, !to.isEmpty, !metin.isEmpty else { return nil }
        return [
            "to": .metin(to), "text": .metin(metin), "appId": .metin(b.kimlik), "trackingCode": .metin(b.takipKodu),
            "status": .metin("queued"), "attempts": .tam(0),
            "createdBy": .metin(calisan.uid), "byName": .metin(String(calisan.gorunenAd.prefix(80))),
        ]
    }
}

// MARK: - Yazımlar

/// Başvuru ayrıntısındaki işlemlerin toplu yazımları. Her biri panelin aynı
/// düğmesinin yazdıklarını, aynı sırayla ve tek seferde yazar.
public enum BasvuruIslemi {
    typealias Y = FirestoreIstemci.Yazim

    static func yol(_ b: Basvuru) -> String { "applications/\(b.kimlik)" }
    static func damga(_ c: Calisan) -> [String: FSDeger] { ["updatedBy": .metin(c.uid)] }
    static func kayit(_ eylem: String, _ b: Basvuru, _ ayrinti: String, _ c: Calisan) -> Y {
        .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                 alanlar: IslemKaydi.alanlar(eylem: eylem, hedef: b.kimlik, ayrinti: ayrinti, calisan: c), zaman: ["at"])
    }
    static func gecmis(_ b: Basvuru, tur: String, metin: String, statu: Statu? = nil, _ c: Calisan) -> Y {
        .olustur(yol: "\(yol(b))/log/\(FirestoreIstemci.yeniKimlik())",
                 alanlar: GecmisSatiri.alanlar(tur: tur, metin: metin, statu: statu, calisan: c), zaman: ["at"])
    }
    static func takip(_ id: String, _ b: Basvuru, _ s: Statu?, _ statuler: [Statu], _ notlar: [BasvuruNotu], _ simdi: Date) -> Y {
        .yaz(yol: "takip/\(id)", alanlar: TakipBelgesi.alanlar(basvuru: b, statu: s, statuler: statuler, notlar: notlar, simdi: simdi),
             zaman: ["updatedAt"])
    }

    public struct StatuSonucu {
        public var yazimlar: [FirestoreIstemci.Yazim]
        public var eposta: Bool
        public var sms: Bool
    }

    /// "Statüyü kaydet": statü (değiştiyse) + geçmiş + müşteri notu + takip sayfası
    /// + (açıksa) statü maili ve SMS + işlem kaydı.
    public static func statu(
        _ b: Basvuru, hedef: Statu, statuler: [Statu], musteriNotu: String,
        acikNotlar: [BasvuruNotu], takipId: String, calisan c: Calisan, saklamaGun: Int,
        eposta: EpostaAyari?, sms: SmsAyari?, smsGonder: Bool, iletisim: MusteriIletisimi?, simdi: Date = Date()
    ) -> StatuSonucu {
        var y: [Y] = []
        let degisti = hedef.id != b.statuId
        let not = musteriNotu.kirpik
        if degisti {
            let g = b.statuGecisi(hedef, saklamaGun: saklamaGun, simdi: simdi)
            y.append(.guncelle(yol: yol(b), alanlar: g.alanlar.merging(damga(c)) { $1 }, zaman: g.zaman + ["updatedAt"]))
            y.append(gecmis(b, tur: "status", metin: "\(b.statuAdi.isEmpty ? "—" : b.statuAdi) → \(hedef.ad)", statu: hedef, c))
        }
        var notlar = acikNotlar
        if !not.isEmpty {
            y.append(.olustur(yol: "\(yol(b))/notes/\(FirestoreIstemci.yeniKimlik())", alanlar: [
                "text": .metin(String(not.prefix(2000))), "public": .mantik(true),
                "by": .metin(c.uid), "byName": .metin(String(c.gorunenAd.prefix(80))),
            ], zaman: ["at"]))
            notlar.insert(BasvuruNotu(id: "", metin: not, musteriyeGorunur: true, yazan: c.gorunenAd, zaman: simdi), at: 0)
        }
        y.append(takip(takipId, b, hedef, statuler, notlar, simdi))
        var mail = false, mesaj = false
        if degisti, let e = eposta, let i = iletisim,
           let m = MusteriBildirimi.statuEpostasi(b, hedef: hedef, ayar: e, iletisim: i, calisan: c) {
            y.append(.olustur(yol: "eposta/\(FirestoreIstemci.yeniKimlik())", alanlar: m, zaman: ["createdAt"]))
            mail = true
        }
        if smsGonder, let s = sms, let i = iletisim, i.smsAcik,
           let m = MusteriBildirimi.sms(b, sablon: not.isEmpty ? s.statuSablonu : s.notSablonu,
                                statu: hedef.musteriAdi.isEmpty ? hedef.ad : hedef.musteriAdi, not: not,
                                ayar: s, telefon: i.telefon, calisan: c) {
            y.append(.olustur(yol: "sms/\(FirestoreIstemci.yeniKimlik())", alanlar: m, zaman: ["createdAt"]))
            mesaj = true
        }
        if degisti { y.append(kayit("app.status", b, "\(b.statuAdi) → \(hedef.ad)", c)) }
        return StatuSonucu(yazimlar: y, eposta: mail, sms: mesaj)
    }

    /// "Not ekle": müşteriye görünürse takip sayfası da yenilenir.
    public static func not(
        _ b: Basvuru, metin: String, musteriyeGorunur: Bool, statu: Statu?, statuler: [Statu],
        acikNotlar: [BasvuruNotu], takipId: String?, calisan c: Calisan, sms: SmsAyari?, smsGonder: Bool,
        iletisim: MusteriIletisimi?, simdi: Date = Date()
    ) -> [FirestoreIstemci.Yazim] {
        let m = String(metin.kirpik.prefix(2000))
        var y: [Y] = [.olustur(yol: "\(yol(b))/notes/\(FirestoreIstemci.yeniKimlik())", alanlar: [
            "text": .metin(m), "public": .mantik(musteriyeGorunur),
            "by": .metin(c.uid), "byName": .metin(String(c.gorunenAd.prefix(80))),
        ], zaman: ["at"])]
        if musteriyeGorunur, let t = takipId {
            let yeni = BasvuruNotu(id: "", metin: m, musteriyeGorunur: true, yazan: c.gorunenAd, zaman: simdi)
            y.append(takip(t, b, statu, statuler, [yeni] + acikNotlar, simdi))
            if smsGonder, let s = sms, let i = iletisim, i.smsAcik,
               let k = MusteriBildirimi.sms(b, sablon: s.notSablonu,
                                    statu: statu.map { $0.musteriAdi.isEmpty ? $0.ad : $0.musteriAdi } ?? "",
                                    not: m, ayar: s, telefon: i.telefon, calisan: c) {
                y.append(.olustur(yol: "sms/\(FirestoreIstemci.yeniKimlik())", alanlar: k, zaman: ["createdAt"]))
            }
        }
        return y
    }

    /// Evrak "geldi" / "kaldırıldı" (yalnız o evrak; aynı anda başkası başka evrakı işaretleyebilir).
    public static func evrak(_ b: Basvuru, _ e: Evrak, geldi: Bool, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [
            .guncelle(yol: yol(b), alanlar: damga(c), ic: ["checklist": [e.id: .mantik(geldi)]], zaman: ["updatedAt"]),
            gecmis(b, tur: "checklist", metin: "\(e.ad): \(geldi ? "geldi" : "kaldırıldı")", c),
        ]
    }

    /// Tekrar arama: "Arandı" (statü değişmez; sonraki arama aralığı buna göre).
    public static func arandi(_ b: Basvuru, not: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let n = not.kirpik
        return [
            .guncelle(yol: yol(b), alanlar: damga(c), zaman: ["sonArama", "updatedAt"]),
            gecmis(b, tur: "arama", metin: "Müşteri arandı\(n.isEmpty ? "" : ": \(n)")", c),
            kayit("app.arama", b, String(n.prefix(200)), c),
        ]
    }

    public static func ustNotEkle(_ b: Basvuru, metin: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let m = String(metin.kirpik.prefix(2000))
        return [
            .olustur(yol: "\(yol(b))/ustNotlar/\(FirestoreIstemci.yeniKimlik())", alanlar: [
                "metin": .metin(m), "by": .metin(c.uid), "byName": .metin(String(c.gorunenAd.prefix(80))),
            ], zaman: ["at"]),
            gecmis(b, tur: "ustNot", metin: "Üst not eklendi: \(m)", c),
            kayit("app.ustNot", b, String(m.prefix(200)), c),
        ]
    }

    public static func ustNotSil(_ b: Basvuru, _ n: UstNot, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.sil(yol: "\(yol(b))/ustNotlar/\(n.id)"), kayit("app.ustNot.sil", b, String(n.metin.prefix(200)), c)]
    }

    /// "Bilgileri kontrol edin" uyarısını kaldırır.
    public static func kontrolEdildi(_ b: Basvuru, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.guncelle(yol: yol(b), alanlar: damga(c).merging(["reviewNote": .metin("")]) { $1 }, zaman: ["updatedAt"])]
    }
}
