import Foundation

// Talepler'e elle talep (panel: talep-elle.js) ve Armut menüsü (pages/armut.js,
// armut-ortak.js). Armut işlerini Chrome eklentisi Apps Script'e gönderir;
// servis armutTalepleri/armut_<işId> belgesine yazar. Danışman burada
// inceler, iç not yazar, müşteriyle görüşülecekse Talepler'e aktarır.

/// Telefonla (ya da Armut'tan, e-postadan) gelen müşteriyi Talepler'e ekleme.
public struct ElleTalep: Equatable {
    public var ad = ""
    public var telefon = ""
    public var eposta = ""
    public var ulke = ""
    public var ulkeAdi = ""
    public var not = ""
    /// false: şimdi görüşüldü ("Görüşüldü"); true: gün ve saat seçildi ("Aranacak").
    public var sonra = false
    public var tarih = ""
    public var saat = ""
    public var wa = true
    public var sms = false
    public var email = false
    public var onay = false
    /// telefon | eposta | armut | arsiv
    public var kaynak = "telefon"
    /// Armut'tan, telefonu açılmamış müşteri: iletişim Armut mesajlarından.
    public var armutIletisim = false

    public init() {}

    /// Hatalar varsa (hatalar, nil); yoksa ([], alanlar). Kural: firestore.rules → callback (panelden elle).
    public func kayit(bugun: String, mesai: Mesai, simdi: Date = Date()) -> (hatalar: [String], alanlar: [String: FSDeger]?) {
        var h: [String] = []
        let a = ad.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let tel = MusteriBildirimi.e164(telefon)
        let armutla = kaynak == "armut" && armutIletisim && telefon.kirpik.isEmpty
        let e = eposta.kirpik.lowercased()
        if a.count < 2 { h.append("Ad soyad girin.") }
        if !armutla && !tel.eslesir("^\\+90\\d{10}$") { h.append("Telefon numarası geçersiz (ör. 0532 123 45 67).") }
        if !e.isEmpty && !e.eslesir("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$") { h.append("E-posta geçersiz.") }
        if sonra && !tarih.eslesir("^\\d{4}-\\d{2}-\\d{2}$") { h.append("Arama tarihini seçin.") }
        if sonra && tarih < bugun { h.append("Arama tarihi geçmişte olamaz.") }
        if sonra && !mesai.aramaDilimleri.contains(saat) { h.append("Arama saatini mesai saatleri içinden seçin.") }
        if !armutla && !wa && !sms && !email { h.append("Müşteriye haber verme yolu seçin (WhatsApp, SMS ya da e-posta).") }
        if email && e.isEmpty { h.append("E-postayla haber için e-posta adresi girin.") }
        if !onay { h.append("Müşteriye kişisel verilerin işlenmesi anlatılıp onayı alınmalı (KVKK kutusu).") }
        if not.count > 1500 { h.append("Not en çok 1500 karakter.") }
        if !h.isEmpty { return (h, nil) }
        var d: [String: FSDeger] = [:]
        d["name"] = .metin(String(a.prefix(80)))
        d["phone"] = .metin(armutla ? "" : tel)
        d["email"] = .metin(String(e.prefix(120)))
        d["country"] = .metin(String(ulke.prefix(60)))
        d["countryName"] = .metin(String(ulkeAdi.prefix(60)))
        d["mode"] = .metin(sonra ? "saat" : "hemen")
        d["date"] = .metin(sonra ? tarih : bugun)
        d["times"] = .dizi([.metin(sonra ? saat : mesai.simdikiSaat(simdi))])
        d["message"] = .metin(String(not.kirpik.prefix(1500)))
        d["channels"] = .harita(["wa": .mantik(armutla ? false : wa), "sms": .mantik(armutla ? false : sms), "email": .mantik(armutla ? false : email)])
        d["consent"] = .mantik(true)
        d["status"] = .metin(sonra ? "new" : "reached")
        d["kaynak"] = .metin(["eposta", "armut", "arsiv"].contains(kaynak) ? kaynak : "telefon")
        return ([], d)
    }

    /// Talebi yazar (+ işlem kaydı). `ek`: Armut alanları.
    public static func yazimlar(_ alanlar: [String: FSDeger], ek: [String: FSDeger] = [:], kimlik: String = FirestoreIstemci.yeniKimlik(),
                                calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        var a = alanlar.merging(ek) { $1 }
        a["createdBy"] = .metin(c.uid)
        a["createdByName"] = .metin(String(c.gorunenAd.prefix(80)))
        return [.olustur(yol: "callback/\(kimlik)", alanlar: a, zaman: ["createdAt"]),
                IslemKaydiYazimi.yaz("callback.create", kimlik, "\(alanlar["name"]?.metinDegeri ?? "") (\(a["kaynak"]?.metinDegeri ?? ""))", c)]
    }
}

/// Armut işi (armutTalepleri/{id}).
public struct ArmutIsi: Equatable, Identifiable {
    public static let armutDurumlari = [
        "quoted": "Teklif verildi", "chatting": "Mesajlaşılıyor", "won": "İş kazanıldı", "lost": "Başkasına verildi",
        "cancelled": "Müşteri iptal etti", "expired": "Süresi doldu", "ReceivingQuotes": "Teklif topluyor", "Hired": "İş verildi",
        "Completed": "Tamamlandı", "Cancelled": "İptal edildi", "Expired": "Süresi doldu", "Closed": "Kapandı",
    ]
    public static let incelemeDurumlari: [(id: String, ad: String)] = [
        ("yeni", "Yeni"), ("incelendi", "İncelendi"), ("aktarildi", "Talepler'e aktarıldı"), ("ilgisiz", "İlgisiz"),
    ]

    public struct SoruCevap: Equatable { public var soru: String; public var cevap: String }
    public struct Mesaj: Equatable { public var bizden: Bool; public var saat: String; public var metin: String }

    public var id: String
    public var isId: String
    public var ad: String
    public var telefon: String
    public var eposta: String
    public var baslik: String
    public var kategori: String
    public var konum: String
    public var isTarihi: String
    public var ilanTarihi: String
    public var aciklama: String
    public var url: String
    public var teklifTutari: Double?
    public var paraBirimi: String
    public var armutDurum: String
    public var armutSira: Int?
    public var digerTeklifSayisi: Int?
    public var armutTeklifTarihi: Date?
    public var ilkSenkron: Date?
    public var olusma: Date?
    public var sonSenkron: Date?
    public var incelemeDurum: String
    public var icNot: String
    public var talepId: String
    public var aktaranKisi: String
    public var aktarilmaTarihi: Date?
    public var sonMesaj: String
    public var sonMesajSaat: String
    public var soruCevap: [SoruCevap]
    public var mesajlar: [Mesaj]

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        func m(_ k: String) -> String { a[k]?.metinDegeri ?? "" }
        func zaman(_ k: String) -> Date? {
            if let z = a[k]?.zamanDegeri { return z }
            return a[k]?.metinDegeri.flatMap { FSDeger.zamanOku($0) }
        }
        id = kimlik
        isId = m("isId"); ad = m("ad"); telefon = m("telefon"); eposta = m("eposta"); baslik = m("baslik"); kategori = m("kategori")
        konum = m("konum"); isTarihi = m("isTarihi"); ilanTarihi = m("ilanTarihi"); aciklama = m("aciklama"); url = m("url")
        switch a["teklifTutari"] {
        case .tam(let v): teklifTutari = Double(v)
        case .ondalik(let v): teklifTutari = v
        default: teklifTutari = nil
        }
        paraBirimi = m("paraBirimi").isEmpty ? "TRY" : m("paraBirimi")
        armutDurum = m("armutDurum"); armutSira = a["armutSira"]?.tamDegeri; digerTeklifSayisi = a["digerTeklifSayisi"]?.tamDegeri
        armutTeklifTarihi = zaman("armutTeklifTarihi"); ilkSenkron = zaman("ilkSenkron"); olusma = zaman("createdAt"); sonSenkron = zaman("sonSenkron")
        incelemeDurum = m("incelemeDurum").isEmpty ? "yeni" : m("incelemeDurum")
        icNot = m("icNot"); talepId = m("talepId"); aktaranKisi = m("aktaranKisi"); aktarilmaTarihi = zaman("aktarilmaTarihi")
        sonMesaj = m("sonMesaj"); sonMesajSaat = m("sonMesajSaat")
        soruCevap = (a["soruCevap"]?.diziDegeri ?? []).compactMap { $0.haritaDegeri }.map {
            SoruCevap(soru: $0["soru"]?.metinDegeri ?? "", cevap: $0["cevap"]?.metinDegeri ?? "")
        }
        mesajlar = (a["mesajlar"]?.diziDegeri ?? []).compactMap { $0.haritaDegeri }.map {
            Mesaj(bizden: $0["gonderen"]?.metinDegeri == "biz", saat: $0["saat"]?.metinDegeri ?? "", metin: $0["metin"]?.metinDegeri ?? "")
        }
    }

    public var armutDurumAdi: String { Self.armutDurumlari[armutDurum] ?? (armutDurum.isEmpty ? "—" : armutDurum) }
    public var incelemeAdi: String { Self.incelemeDurumlari.first { $0.id == incelemeDurum }?.ad ?? incelemeDurum }
    public var paneleGelis: Date? { ilkSenkron ?? olusma }
    /// Kart başlığı: ad, yoksa iş başlığı / kategori.
    public var gorunenAd: String { !ad.isEmpty ? ad : (!baslik.isEmpty ? baslik : (kategori.isEmpty ? "Armut işi \(isId)" : kategori)) }

    /// "1.500 ₺"
    public static func tutarYaz(_ n: Double?, _ birim: String) -> String {
        guard let n, n.isFinite else { return "—" }
        let s = Sayi.bicim(n, enAz: 0, enCok: 2)
        let sembol = ["TRY": "₺", "EUR": "€", "USD": "$", "GBP": "£"][birim]
        return "\(s) \(sembol ?? birim)"
    }

    /// Talebin notu (en çok 1500 karakter; panel: armutTalepNotu).
    public var talepNotu: String {
        var l: [String] = []
        if !aciklama.isEmpty { l.append("Müşterinin notu: \(aciklama)") }
        l.append("Armut.com: \(baslik.isEmpty ? (kategori.isEmpty ? "iş" : kategori) : baslik) (iş no \(isId))")
        l.append("Teklifimiz: \(Self.tutarYaz(teklifTutari, paraBirimi)) · Armut durumu: \(armutDurumAdi)")
        if !konum.isEmpty { l.append("Konum: \(konum)") }
        if !isTarihi.isEmpty { l.append("İş tarihi: \(isTarihi)") }
        l += soruCevap.map { "\($0.soru): \($0.cevap)" }
        return String(l.joined(separator: "\n").prefix(1500))
    }

    /// Talep kaydına ayrı alanlar (panel: armutTalepAlanlari).
    public var talepAlanlari: [String: FSDeger] {
        [
            "armutIsId": .metin(String(isId.prefix(40))),
            "armutTeklif": teklifTutari.map { OdemeKurali.tutarDegeri($0) } ?? .bos,
            "armutParaBirimi": .metin(paraBirimi.eslesir("^[A-Z]{3}$") ? paraBirimi : "TRY"),
            "armutNot": .metin(String(aciklama.prefix(1500))),
            "iletisimArmut": .mantik(telefon.isEmpty),
            "armutUrl": .metin(url.eslesir("^https://([a-z0-9-]+\\.)*armut\\.com/") ? String(url.prefix(500)) : ""),
        ]
    }

    /// Sıralama: armut (Armut'taki sıra), teklif (yeni → eski), gelis (panele geliş, yeni → eski).
    public static func sirala(_ l: [ArmutIsi], _ tur: String) -> [ArmutIsi] {
        func ms(_ d: Date?) -> Double? { d?.timeIntervalSince1970 }
        func anahtar(_ k: ArmutIsi) -> Double? {
            switch tur {
            case "teklif": return ms(k.armutTeklifTarihi).map { -$0 }
            case "gelis": return ms(k.paneleGelis).map { -$0 }
            default: return k.armutSira.map(Double.init)
            }
        }
        return l.enumerated().sorted { x, y in
            let ax = anahtar(x.element), ay = anahtar(y.element)
            if ax == nil && ay != nil { return false }
            if ay == nil && ax != nil { return true }
            if let ax, let ay, ax != ay { return ax < ay }
            let gx = ms(x.element.paneleGelis) ?? -.infinity, gy = ms(y.element.paneleGelis) ?? -.infinity
            return gx != gy ? gx > gy : x.offset < y.offset
        }.map(\.element)
    }

    /// "Aleyna Yılmaz (aleyna)"; ad ile kullanıcı adı aynıysa tek.
    public static func aktaranYazisi(ad: String, kullanici: String) -> String {
        let a = ad.kirpik, k = kullanici.kirpik
        return String((!a.isEmpty && !k.isEmpty && a != k ? "\(a) (\(k))" : (a.isEmpty ? (k.isEmpty ? "Bilinmeyen kullanıcı" : k) : a)).prefix(120))
    }

    /// Panelin kendi alanları (inceleme durumu, iç not; aktarılırken talep ve aktaran).
    public static func guncelle(_ k: ArmutIsi, durum: String? = nil, icNot: String? = nil, talepId: String? = nil,
                                calisan c: Calisan) -> FirestoreIstemci.Yazim {
        var a: [String: FSDeger] = ["incelemeDurum": .metin(durum ?? k.incelemeDurum),
                                    "islemBy": .metin(c.uid), "islemByName": .metin(String(c.gorunenAd.prefix(80)))]
        var zaman = ["islemAt"]
        if let n = icNot { a["icNot"] = .metin(String(n.kirpik.prefix(2000))) }
        if let t = talepId {
            a["talepId"] = .metin(t)
            a["aktaranKisi"] = .metin(aktaranYazisi(ad: c.gorunenAd, kullanici: c.kullaniciAdi))
            a["aktaranUid"] = .metin(c.uid)
            zaman.append("aktarilmaTarihi")
        }
        return .guncelle(yol: "armutTalepleri/\(k.id)", alanlar: a, zaman: zaman)
    }

    public static func durumYazimlari(_ k: ArmutIsi, _ yeni: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [guncelle(k, durum: yeni, calisan: c), IslemKaydiYazimi.yaz("armut.\(yeni)", k.id, k.ad, c)]
    }

    /// "Talepler'e aktar": talep + Armut kaydı "aktarıldı" tek yazımda.
    public static func aktar(_ k: ArmutIsi, talep: ElleTalep, bugun: String, mesai: Mesai, calisan c: Calisan)
        -> (hatalar: [String], yazimlar: [FirestoreIstemci.Yazim]) {
        var t = talep
        t.ad = k.ad.isEmpty ? "Armut müşterisi (iş no \(k.isId))" : k.ad
        t.telefon = k.telefon
        t.eposta = k.eposta
        t.kaynak = "armut"
        t.not = k.talepNotu
        t.armutIletisim = k.telefon.isEmpty
        t.wa = true; t.sms = false; t.email = false
        let r = t.kayit(bugun: bugun, mesai: mesai)
        guard let alanlar = r.alanlar else { return (r.hatalar, []) }
        let id = FirestoreIstemci.yeniKimlik()
        var y = ElleTalep.yazimlar(alanlar, ek: k.talepAlanlari, kimlik: id, calisan: c)
        y.removeLast()  // callback.create yerine armut.aktar yazılır
        y.append(guncelle(k, durum: "aktarildi", talepId: id, calisan: c))
        y.append(IslemKaydiYazimi.yaz("armut.aktar", k.id, id, c))
        return ([], y)
    }
}
