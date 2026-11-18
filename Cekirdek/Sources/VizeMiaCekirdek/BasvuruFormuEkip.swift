import Foundation

// Ekibin başvuru formu (yeni başvuru / düzenle). Panelin karşılıkları:
//   panel/js/config.js           FORM_FIELDS, FORM_GROUPS (şema: uygulama.json → form)
//   panel/js/form-alanlar.js     panelFieldsOf (ülkeye göre alan listesi; kapalılar kutucuk arkasında)
//   panel/js/data/formlar/ulke-sorulari.js  ulkeFormlariniBirlestir (hazır sorular + ayar)
//   panel/js/pages/applications.js  collect (denetim), createApplication, updateApplication
//   panel/js/util.js             asciiUpper, normalizePassport, genTrackingCode, takip anahtarları

// MARK: - Şema

public struct FormSecenegi: Decodable, Equatable, Hashable {
    public var value: String
    public var label: String
    public init(value: String, label: String) { self.value = value; self.label = label }
}

/// Formun bir alanı.
public struct FormAlani: Decodable, Equatable, Identifiable {
    public var key: String
    public var label: String
    public var group: String
    public var required: Bool
    public var upper: Bool
    /// date, province, district, country, textarea, email, tel, multi … (yoksa metin)
    public var type: String
    public var options: [FormSecenegi]
    public var pattern: String
    public var sensitive: Bool
    public var mirror: String
    public var mirrorYears: Int
    public var help: String
    public var varsayilan: String
    /// Ayarlarda bu ülke için kapatılmış: panelde kutucuk arkasında, zorunlu değil.
    public var kapali = false
    public var id: String { key }

    enum Anahtar: String, CodingKey { case key, label, group, required, upper, type, options, pattern, sensitive, mirror, mirrorYears, help, varsayilan }

    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        key = c.metin(.key); label = c.metin(.label); group = c.metin(.group)
        required = c.mantik(.required); upper = c.mantik(.upper); type = c.metin(.type)
        options = c.dizi(.options); pattern = c.metin(.pattern); sensitive = c.mantik(.sensitive)
        mirror = c.metin(.mirror); mirrorYears = Int(c.sayi(.mirrorYears)); help = c.metin(.help)
        varsayilan = c.metin(.varsayilan)
    }

    public init(key: String, label: String, group: String, required: Bool = false, upper: Bool = false, type: String = "",
                options: [FormSecenegi] = [], pattern: String = "") {
        self.key = key; self.label = label; self.group = group; self.required = required; self.upper = upper
        self.type = type; self.options = options; self.pattern = pattern
        sensitive = false; mirror = ""; mirrorYears = 0; help = ""; varsayilan = ""
    }
}

/// Ülkeye özel ek soru (Ayarlar → Ülke formları → ek sorular).
public struct EkSoru: Decodable, Equatable {
    public var key: String
    public var label: String
    public var group: String
    public var required: Bool
    public var type: String
    public var upper: Bool
    public var options: [FormSecenegi]

    enum Anahtar: String, CodingKey { case key, label, group, required, type, upper, options }

    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        key = c.metin(.key); label = c.metin(.label); group = c.metin(.group); required = c.mantik(.required)
        type = c.metin(.type)
        // Panel: tarih değilse ve açıkça kapatılmadıysa büyük harf.
        let u: Bool? = (try? c.c.decodeIfPresent(Bool.self, forKey: .upper)) ?? nil
        upper = type != "date" && u != false
        options = c.dizi(.options)
    }

    init(alanlar a: [String: FSDeger]) {
        key = a["key"]?.metinDegeri ?? ""; label = a["label"]?.metinDegeri ?? ""
        group = a["group"]?.metinDegeri ?? ""; required = a["required"]?.mantikDegeri ?? false
        type = a["type"]?.metinDegeri ?? ""
        upper = type != "date" && a["upper"]?.mantikDegeri != false
        options = (a["options"]?.diziDegeri ?? []).compactMap { o in
            guard let m = o.haritaDegeri else { return nil }
            return FormSecenegi(value: m["value"]?.metinDegeri ?? "", label: m["label"]?.metinDegeri ?? "")
        }
    }

    /// Alan tanımına çevirir (panel: extraToField).
    func alan(onek: String) -> FormAlani {
        var f = FormAlani(key: "\(onek)\(key)", label: label, group: group.isEmpty ? "ekstra" : group, required: required,
                          upper: upper, type: type == "select" ? "" : (type.isEmpty ? "text" : type))
        if type == "select" { f.options = [FormSecenegi(value: "", label: "Seçiniz")] + options }
        return f
    }
}

/// Bir ülkenin form ayarı: kapalı alanlar, zorunlular, ek sorular.
public struct UlkeFormu: Decodable, Equatable {
    public var hidden: [String]?
    public var required: [String]?
    public var extra: [EkSoru]?
    public var formTuru: String
    /// Ülkenin form gönderim kuralı (settings/forms → countries.<ülke>.formGonderim).
    public var formGonderim: FormGonderimKurali?

    enum Anahtar: String, CodingKey { case hidden, required, extra, formTuru }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Anahtar.self)
        hidden = (try? c.decodeIfPresent([String].self, forKey: .hidden)) ?? nil
        required = (try? c.decodeIfPresent([String].self, forKey: .required)) ?? nil
        extra = (try? c.decodeIfPresent([EkSoru].self, forKey: .extra)) ?? nil
        formTuru = ((try? c.decodeIfPresent(String.self, forKey: .formTuru)) ?? nil) ?? ""
    }

    /// settings/forms → countries.<ülke> belgesinden.
    public init(alanlar a: [String: FSDeger]) {
        hidden = a["hidden"]?.diziDegeri?.compactMap { $0.metinDegeri }
        required = a["required"]?.diziDegeri?.compactMap { $0.metinDegeri }
        extra = a["extra"]?.diziDegeri?.compactMap { $0.haritaDegeri.map { EkSoru(alanlar: $0) } }
        formTuru = a["formTuru"]?.metinDegeri ?? ""
        formGonderim = a["formGonderim"]?.haritaDegeri.flatMap { FormGonderimKurali(alanlar: $0) }
    }

    public init() { hidden = nil; required = nil; extra = nil; formTuru = "" }
}

public struct FormGrubu: Decodable, Equatable, Identifiable {
    public var id: String
    public var label: String
}

public struct Il: Decodable, Equatable, Hashable {
    public var ad: String
    public var ilceler: [String]
}

/// Başvuru formunun şeması (uygulama.json → form).
public struct FormSemasi: Decodable, Equatable {
    public var gruplar: [FormGrubu]
    public var alanlar: [FormAlani]
    public var ekOnek: String
    public var pdfUlkeler: [String]
    public var ulkeSorulari: [String: UlkeFormu]
    public var sablonlar: [String: [FormAlani]]
    public var iller: [Il]

    enum Anahtar: String, CodingKey { case gruplar, alanlar, ekOnek, pdfUlkeler, ulkeSorulari, sablonlar, iller }

    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        gruplar = c.dizi(.gruplar); alanlar = c.dizi(.alanlar)
        let o = c.metin(.ekOnek); ekOnek = o.isEmpty ? "x_" : o
        pdfUlkeler = c.dizi(.pdfUlkeler)
        ulkeSorulari = c.nesne(.ulkeSorulari) ?? [:]
        sablonlar = c.nesne(.sablonlar) ?? [:]
        iller = c.dizi(.iller)
    }

    /// Ülkenin ayarı: kayıtlı ayar (settings/forms) + hazır sorular; kayıtta olmayan liste hazırdan gelir.
    public func ulkeAyari(_ ulke: String, kayitli: [String: UlkeFormu]) -> UlkeFormu {
        var u = kayitli[ulke] ?? UlkeFormu()
        if let hazir = ulkeSorulari[ulke] {
            if u.hidden == nil { u.hidden = hazir.hidden }
            if u.required == nil { u.required = hazir.required }
            if u.extra == nil { u.extra = hazir.extra }
        }
        return u
    }

    /// Panelin alan listesi (panelFieldsOf): kapatılanlar dahil, `kapali` işaretli ve zorunlu değil.
    public func panelAlanlari(_ ulke: String, kayitli: [String: UlkeFormu]) -> [FormAlani] {
        let ayar = ulkeAyari(ulke, kayitli: kayitli)
        let gizli = Set(ayar.hidden ?? []), zorunlu = Set(ayar.required ?? [])
        let temel = sablonlar[ulke] ?? alanlar
        let std = temel.map { f -> FormAlani in
            var a = f
            if zorunlu.contains(f.key) { a.required = true }
            return a
        }
        let ek = (ayar.extra ?? []).map { $0.alan(onek: ekOnek) }
        return (std + ek).map { f in
            guard gizli.contains(f.key) else { return f }
            var a = f; a.kapali = true; a.required = false
            return a
        }
    }

    /// Başvuru formu kâğıt mı (AB ortak PDF) yoksa konsolosluğun portalı mı?
    public func formTuru(_ ulke: String, kayitli: [String: UlkeFormu]) -> String {
        let s = kayitli[ulke]?.formTuru ?? ""
        if s == "pdf" || s == "online" { return s }
        return pdfUlkeler.contains(ulke) ? "pdf" : "online"
    }

    public func ilceler(_ il: String) -> [String] { iller.first { $0.ad == il }?.ilceler ?? [] }
    /// İlçe adından il(ler) (ilçe yazılınca il bulunur).
    public func iller(ilce: String) -> [String] {
        let q = ilce.lowercased(with: Tr.yerel)
        return iller.filter { $0.ilceler.contains { $0.lowercased(with: Tr.yerel) == q } }.map(\.ad)
    }
}

// MARK: - Kurallar

public enum EkipFormu {
    /// Panelin asciiUpper'ı: önce ß, Æ, Ø … karşılığına, sonra Latin büyük harf (Almanya'da Ö/Ü kalır).
    public static func latinBuyuk(_ s: String, ulke: String) -> String {
        let ek: [Character: String] = ["ß": "SS", "Æ": "AE", "æ": "AE", "Ø": "O", "ø": "O", "Đ": "D", "đ": "D",
                                       "Ł": "L", "ł": "L", "Þ": "TH", "þ": "TH", "Ð": "D", "ð": "D"]
        return Harf.latinBuyuk(s.map { ek[$0] ?? String($0) }.joined(), ulke: ulke)
    }

    public static func pasaport(_ s: String) -> String { s.filter { $0 != " " && $0 != "-" && !$0.isWhitespace }.uppercased() }

    /// Pasaport tarihleri: biri girilince öteki aynı gün ve ayla ±10 yıl (29 Şubat artık yıl değilse 28).
    public static func yilKaydir(_ iso: String, _ yil: Int) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]) else { return "" }
        let n = y + yil
        guard n >= 1900, n <= 2200 else { return "" }
        var gun = String(p[2])
        if p[1] == "02" && gun == "29" && !((n % 4 == 0 && n % 100 != 0) || n % 400 == 0) { gun = "28" }
        return "\(n)-\(p[1])-\(gun)"
    }

    /// Form denetimi ve kaydedilecek veri (panel: collect). `acikKapalilar`: kutucuğu
    /// işaretlenip açılan kapalı alanlar. `korunan`: alan tanımı dışında korunan veri
    /// (bildirim kanalları, kampanya izni).
    public static func topla(_ degerler: [String: String], alanlar: [FormAlani], acikKapalilar: Set<String>,
                             ulke: String, acilis: String, bugun: String, korunan: [String: FSDeger] = [:])
        -> (veri: [String: FSDeger], sorunlar: [String]) {
        var veri = korunan
        var s: [String: String] = [:]
        var sorunlar: [String] = []
        for f in alanlar {
            if f.kapali && !acikKapalilar.contains(f.key) { continue }
            var v = (degerler[f.key] ?? "").kirpik
            if f.upper && f.type != "email" && f.type != "tel" { v = latinBuyuk(v, ulke: ulke) }
            if f.key == "passportNo" { v = pasaport(v) }
            if f.required && v.isEmpty && f.key != "passportNo" { sorunlar.append("\(f.label) zorunlu.") }
            if !v.isEmpty && !f.pattern.isEmpty && !v.eslesir(f.pattern) { sorunlar.append("\(f.label) biçimi hatalı.") }
            if !v.isEmpty { s[f.key] = String(v.prefix(500)) }
        }
        if s["birthProvince"] != nil || s["birthDistrict"] != nil {
            s["birthPlace"] = s["birthDistrict"] ?? s["birthProvince"]
        }
        if let t = s["nationalId"], !Harf.tcknGecerli(t) { sorunlar.append("T.C. kimlik numarası geçersiz.") }
        if let p = s["passportNo"], !p.eslesir("^[A-Z0-9]{6,12}$") { sorunlar.append("Pasaport numarası 6–12 harf/rakam olmalı.") }
        if let e = s["email"] {
            let k = e.kirpik.lowercased()
            s["email"] = k
            if !k.eslesir("^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}$") {
                sorunlar.append("E-posta geçersiz. Yalnızca İngilizce harf, rakam ve . _ % + - kullanın.")
            }
        }
        if let a = s["passportIssued"], let b = s["passportExpires"], b <= a {
            sorunlar.append("Pasaport geçerlilik tarihi, veriliş tarihinden sonra olmalı.")
        }
        if s["passportNo"] == nil && s["phone"] == nil { sorunlar.append("Pasaport numarası ya da telefon gerekli (pasaportu sonradan girebilirsiniz).") }
        if ulke.isEmpty { sorunlar.append("Ülke seçin.") }
        if !acilis.isEmpty && acilis > bugun { sorunlar.append("Oluşturma tarihi ileri bir tarih olamaz.") }
        for (k, v) in s { veri[k] = .metin(v) }
        return (veri, sorunlar)
    }

    /// Talepten forma: taslak + kayıttaki bilgiler (panel: talepler.js → draftFrom, talepIzni).
    /// Döner: ülke kimliği (listede varsa), alan değerleri, korunan veri (bildirim kanalları, kampanya izni).
    public static func tohum(_ t: Talep, ulkeler: Set<String>) -> (ulke: String, degerler: [String: String], korunan: [String: FSDeger]) {
        let a = t.ham
        let m = { (k: String) in a[k]?.metinDegeri ?? "" }
        let ulke = ulkeler.contains(m("country")) ? m("country") : ""
        let parcalar = m("name").kirpik.split(whereSeparator: \.isWhitespace).map(String.init)
        let ad = m("firstName").isEmpty ? parcalar.dropLast().joined(separator: " ") : m("firstName")
        let soyad = m("lastName").isEmpty ? (parcalar.count > 1 ? parcalar.last ?? "" : "") : m("lastName")
        let amac = ["turistik": "Turistik", "ticari": "Ticari", "ziyaret": "Aile_Arkadasi", "ogrenci": "Diger", "transit": "Diger"]
        var d: [String: String] = [:]
        for (k, v) in a["draft"]?.haritaDegeri ?? [:] { if let s = v.metinDegeri, !s.isEmpty, k != "country" { d[k] = s } }
        let tohum: [String: String] = [
            "firstName": latinBuyuk(ad, ulke: ulke), "lastName": latinBuyuk(soyad, ulke: ulke),
            "passportNo": m("passportNo"), "nationalId": m("nationalId"), "birthDate": m("birthDate"),
            "passportExpires": m("expiryDate"), "phone": m("phone"), "email": m("email"), "entryDate": m("travelDate"),
            "travelPurpose": amac[m("visaType")] ?? "",
        ]
        for (k, v) in tohum where d[k] == nil && !v.isEmpty { d[k] = v }
        var korunan: [String: FSDeger] = [:]
        if let c = a["channels"], case .harita = c { korunan["channels"] = c }
        if a["kampanyaIzni"]?.mantikDegeri == true {
            korunan["kampanyaIzni"] = .mantik(true)
            korunan["kampanyaIzniKaynak"] = .metin("site")
            korunan["kampanyaIzniSurum"] = .metin(String(m("kampanyaIzniSurum").prefix(10)))
            korunan["kampanyaIzniTarih"] = .metin(t.olusturma.map { FSDeger.zamanYaz($0) } ?? "")
        }
        let taslakUlke = a["draft"]?.haritaDegeri?["country"]?.metinDegeri ?? ""
        return (ulkeler.contains(taslakUlke) ? taslakUlke : ulke, d, korunan)
    }

    /// Yeni takip kodu: YYYY-AA + 4 rastgele rakam.
    public static func takipKodu(_ d: Date = Date()) -> String {
        let p = Tr.takvim.dateComponents([.year, .month], from: d)
        let r = Int.random(in: 0..<10_000)
        return "\(p.year ?? 2026)-\(p.month ?? 1 < 10 ? "0" : "")\(p.month ?? 1)\(String(format: "%04d", r))"
    }

    /// Takip anahtarları: pasaport varsa müşterinin sorgusuyla aynı; yoksa başvuruya özgü, tahmin edilemez yer tutucu.
    public static func anahtarlar(kod: String, pasaport p: String, appId: String) -> (takipId: String, pasaportOzeti: String) {
        if !p.isEmpty {
            return (Ozet.sha256Hex("vizemia-takip|\(kod)|\(pasaport(p))"), BasvuruListesi.pasaportOzeti(p))
        }
        return (Ozet.sha256Hex("vizemia-takip|\(kod)|pasaportsuz|\(appId)|\(UUID().uuidString.lowercased())"),
                Ozet.sha256Hex("vizemia-pasaportsuz|\(appId)"))
    }
}

// MARK: - Yazımlar

extension BasvuruIslemi {
    /// Formun başvuru belgesine giden çekirdek alanları (panel: appCore).
    static func cekirdek(_ veri: [String: FSDeger], ulke: Ulke?, ulkeId: String) -> [String: FSDeger] {
        let m = { (k: String) in veri[k]?.metinDegeri ?? "" }
        return [
            "country": .metin(ulkeId), "countryName": .metin(ulke?.ad ?? ulkeId),
            "firstName": .metin(String(m("firstName").prefix(80))), "lastName": .metin(String(m("lastName").prefix(80))),
            "passportLast3": .metin(String(m("passportNo").suffix(3))),
        ]
    }

    /// Takvim gününün öğle saati (Türkiye) — panelin dateTs'i; bugünse sunucu saati kullanılır
    /// (kural "açılış tarihi gelecekte olamaz": öğleden önce bugünün 12.00'si gelecektir).
    static func gunAni(_ iso: String) -> Date? { iso.isEmpty ? nil : RandevuKurali.an(iso, "12:00") }

    /// Takip kodu çakıştı mı (aynı kod alınmış): yeni kodla yeniden denenir.
    public static func kodCakismasi(_ hata: Error) -> Bool {
        guard let h = hata as? FirestoreHatasi else { return false }
        return h == .sunucu(409) || h == .izinYok
    }

    public struct YeniBasvuru {
        public var yazimlar: [FirestoreIstemci.Yazim]
        public var kimlik: String
        public var takipKodu: String
        public var statu: Statu
        public var cekirdek: [String: FSDeger]
    }

    /// Yeni başvuru (panel: createApplication). Kod çakışırsa kural reddeder; çağıran yeni kodla dener.
    public static func olustur(
        veri: [String: FSDeger], ulkeId: String, ulke: Ulke?, randevu: String, acilis: String, bugun: String,
        statuler: [Statu], calisan c: Calisan, kontrolNotu: String = "", simdi: Date = Date(),
        kimlik: String = FirestoreIstemci.yeniKimlik(), kod: String? = nil
    ) -> YeniBasvuru? {
        // İlk statü: şartı olmayan ve son adım olmayan ilk statü (ör. potansiyel müşteri).
        guard let ilk = statuler.first(where: { $0.gerekenler.isEmpty && !$0.son }) ?? statuler.first else { return nil }
        let kod = kod ?? EkipFormu.takipKodu(simdi)
        let pasaport = veri["passportNo"]?.metinDegeri ?? ""
        let a = EkipFormu.anahtarlar(kod: kod, pasaport: pasaport, appId: kimlik)
        let cek = cekirdek(veri, ulke: ulke, ulkeId: ulkeId)
        let yol = "applications/\(kimlik)"
        let p = Tr.takvim.dateComponents([.year, .month], from: simdi)
        var b: [String: FSDeger] = cek
        b["trackingCode"] = .metin(kod)
        b["year"] = .tam(p.year ?? 2026)
        b["month"] = .tam(p.month ?? 1)
        var zaman = ["statusAt", "createdAt", "updatedAt"]
        if acilis.isEmpty || acilis >= bugun { zaman.append("openedAt") } else { b["openedAt"] = gunAni(acilis).map { .zaman($0) } ?? .bos }
        b["appointmentAt"] = gunAni(randevu).map { .zaman($0) } ?? .bos
        b["travelAt"] = gunAni(veri["entryDate"]?.metinDegeri ?? "").map { .zaman($0) } ?? .bos
        b["statusId"] = .metin(ilk.id)
        b["statusName"] = .metin(ilk.ad)
        b["deleteAfter"] = ilk.silmeGun.map { .zaman(simdi.addingTimeInterval(Double($0) * 86_400)) } ?? .bos
        b["checklist"] = .harita([:])
        b["finalAt"] = .bos
        b["legalHold"] = .mantik(false)
        b["retentionNote"] = .metin("")
        b["reviewNote"] = .metin(String(kontrolNotu.prefix(300)))
        b["assignedTo"] = .metin(c.uid)
        b["assignedName"] = .metin(String(c.gorunenAd.prefix(80)))
        b["createdBy"] = .metin(c.uid)
        b["updatedBy"] = .metin(c.uid)
        var y: [FirestoreIstemci.Yazim] = [
            .olustur(yol: "trackingCodes/\(kod)", alanlar: ["appId": .metin(kimlik)], zaman: ["createdAt"]),
            .olustur(yol: yol, alanlar: b, zaman: zaman),
            .olustur(yol: "\(yol)/private/data", alanlar: ["form": .harita(veri), "updatedBy": .metin(c.uid)], zaman: ["updatedAt"]),
            .olustur(yol: "\(yol)/private/keys", alanlar: ["takipId": .metin(a.takipId), "passportHash": .metin(a.pasaportOzeti),
                                                           "updatedBy": .metin(c.uid)], zaman: ["updatedAt"]),
        ]
        var taslak = Basvuru(kimlik: kimlik, alanlar: cek)
        taslak.statuId = ilk.id
        y.append(.yaz(yol: "takip/\(a.takipId)", alanlar: TakipBelgesi.alanlar(basvuru: taslak, statu: ilk, statuler: statuler, notlar: []),
                      zaman: ["updatedAt"]))
        if !pasaport.isEmpty { y.append(.diziyeEkle(yol: "lookup/\(a.pasaportOzeti)", alan: "apps", degerler: [.metin(kimlik)])) }
        y.append(.olustur(yol: "\(yol)/log/\(FirestoreIstemci.yeniKimlik())",
                          alanlar: GecmisSatiri.alanlar(tur: "created", metin: "Başvuru oluşturuldu (\(ilk.ad))", statu: ilk, calisan: c),
                          zaman: ["at"]))
        y.append(.olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                          alanlar: IslemKaydi.alanlar(eylem: "app.create", hedef: kimlik, ayrinti: kod, calisan: c), zaman: ["at"]))
        return YeniBasvuru(yazimlar: y, kimlik: kimlik, takipKodu: kod, statu: ilk, cekirdek: cek)
    }

    /// Başvuruyu düzenle (panel: updateApplication). Pasaport değiştiyse takip anahtarları
    /// yenilenir (eski takip belgesi silinir, pasaport dizini güncellenir).
    public static func duzenle(
        _ b: Basvuru, eskiForm: [String: FSDeger], yeniVeri: [String: FSDeger], alanlar: [FormAlani], ulkeId: String, ulke: Ulke?,
        randevu: String, acilis: String, eskiAnahtar: (takipId: String, pasaportOzeti: String)?, statuler: [Statu],
        acikNotlar: [BasvuruNotu], calisan c: Calisan, simdi: Date = Date()
    ) -> [FirestoreIstemci.Yazim] {
        let yol = "applications/\(b.kimlik)"
        let cek = cekirdek(yeniVeri, ulke: ulke, ulkeId: ulkeId)
        var degisen = alanlar.filter { (eskiForm[$0.key]?.metinDegeri ?? "") != (yeniVeri[$0.key]?.metinDegeri ?? "") }.map(\.label)
        if b.ulke != ulkeId { degisen.append("Ülke") }
        var u = cek
        u["openedAt"] = gunAni(acilis).map { .zaman($0) } ?? (b.acilis.map { .zaman($0) } ?? .bos)
        // Gün değişmediyse randevu kağıdından gelen saat korunur.
        if let r = b.randevu, Tr.bugun(r) == randevu { u["appointmentAt"] = .zaman(r) } else { u["appointmentAt"] = gunAni(randevu).map { .zaman($0) } ?? .bos }
        u["travelAt"] = gunAni(yeniVeri["entryDate"]?.metinDegeri ?? "").map { .zaman($0) } ?? .bos
        u["updatedBy"] = .metin(c.uid)
        var y: [FirestoreIstemci.Yazim] = [
            .guncelle(yol: yol, alanlar: u, zaman: ["updatedAt"]),
            .yaz(yol: "\(yol)/private/data", alanlar: ["form": .harita(yeniVeri), "updatedBy": .metin(c.uid)], zaman: ["updatedAt"]),
        ]
        var sonra = b
        sonra.ulke = ulkeId; sonra.ulkeAdi = ulke?.ad ?? ulkeId
        sonra.ad = cek["firstName"]?.metinDegeri ?? b.ad; sonra.soyad = cek["lastName"]?.metinDegeri ?? b.soyad
        let statu = statuler.first { $0.id == b.statuId }
        let eskiPasaport = EkipFormu.pasaport(eskiForm["passportNo"]?.metinDegeri ?? "")
        let yeniPasaport = yeniVeri["passportNo"]?.metinDegeri ?? ""
        if eskiPasaport != yeniPasaport || eskiAnahtar == nil {
            let a = EkipFormu.anahtarlar(kod: b.takipKodu, pasaport: yeniPasaport, appId: b.kimlik)
            if let e = eskiAnahtar {
                y.append(.sil(yol: "takip/\(e.takipId)"))
                if !eskiPasaport.isEmpty { y.append(.diziden(yol: "lookup/\(e.pasaportOzeti)", alan: "apps", degerler: [.metin(b.kimlik)])) }
            }
            y.append(.yaz(yol: "\(yol)/private/keys", alanlar: ["takipId": .metin(a.takipId), "passportHash": .metin(a.pasaportOzeti),
                                                              "updatedBy": .metin(c.uid)], zaman: ["updatedAt"]))
            y.append(.yaz(yol: "takip/\(a.takipId)", alanlar: TakipBelgesi.alanlar(basvuru: sonra, statu: statu, statuler: statuler,
                                                                                 notlar: acikNotlar, simdi: simdi), zaman: ["updatedAt"]))
            if !yeniPasaport.isEmpty { y.append(.diziyeEkle(yol: "lookup/\(a.pasaportOzeti)", alan: "apps", degerler: [.metin(b.kimlik)])) }
        } else if let e = eskiAnahtar, b.ulke != ulkeId || b.ad != sonra.ad {
            y.append(.yaz(yol: "takip/\(e.takipId)", alanlar: TakipBelgesi.alanlar(basvuru: sonra, statu: statu, statuler: statuler,
                                                                                 notlar: acikNotlar, simdi: simdi), zaman: ["updatedAt"]))
        }
        let ozet = degisen.isEmpty ? "değişiklik yok" : degisen.joined(separator: ", ")
        y.append(gecmis(b, tur: "edit", metin: "Düzenlendi: \(ozet)", c))
        y.append(kayit("app.edit", b, String(ozet.prefix(500)), c))
        return y
    }
}
