import Foundation

// Müşteriye mesaj: bir başvurunun müşterisine e-posta, WhatsApp ya da SMS.
// Panel karşılıkları:
//   panel/js/mesaj-ortak.js   kanal kuralları, yer tutucular, geçmiş
//   panel/js/wa-teyit.js      WhatsApp "Gönderdim / Göndermedim" kaydı
//   panel/js/wa-sablon*.js    hazır WhatsApp/SMS mesajları (settings/wa)
//   panel/js/sms.js           SMS kuyruğu (tur 'elle')
// WhatsApp'ın API'si yok: uygulama wa.me bağlantısını açar, danışman gönder'e
// kendi WhatsApp'ında basar; gönderilip gönderilmediğini uygulama bilemez, o
// yüzden danışmana sorar ve cevabı mesajKaydi/ belgesine yazar.

public enum MesajKanali: String, CaseIterable, Identifiable {
    case eposta, whatsapp, sms
    public var id: String { rawValue }
    public var ad: String {
        switch self {
        case .eposta: return "E-posta"
        case .whatsapp: return "WhatsApp"
        case .sms: return "SMS"
        }
    }
    /// En çok metin uzunluğu (e-postada sınır kuyruk kuralında).
    public var sinir: Int {
        switch self {
        case .eposta: return EpostaKaydi.metinEnCok
        case .whatsapp: return MusteriMesaji.waEnCok
        case .sms: return MusteriMesaji.smsEnCok
        }
    }
}

public enum MusteriMesaji {
    public static let waEnCok = 900
    public static let smsEnCok = 480
    public static let smsKurulmadi = "SMS altyapısı kurulmadı"
    typealias Y = FirestoreIstemci.Yazim

    /// Türkiye numarası → E.164 (+905xxxxxxxxx); "+" ile yazılmış yabancı
    /// numara da olur. Tanınmazsa "" (panel: telefonE164).
    public static func telefonE164(_ s: String) -> String {
        let d = s.filter { $0.isASCII && $0.isNumber }
        if d.eslesir("^90[2-5][0-9]{9}$") { return "+\(d)" }
        if d.eslesir("^0[2-5][0-9]{9}$") { return "+9\(d)" }
        if d.eslesir("^[2-5][0-9]{9}$") { return "+90\(d)" }
        if s.kirpik.hasPrefix("+") && d.eslesir("^[1-9][0-9]{7,14}$") { return "+\(d)" }
        return ""
    }

    /// Kanal bu müşteri için kullanılabilir mi? Değilse neden (panel: kanalDurumu).
    public static func kanalDurumu(_ k: MesajKanali, eposta: String, telefon: String, smsHazir: Bool, smsIzni: Bool) -> (olur: Bool, neden: String) {
        switch k {
        case .eposta:
            return MusteriBildirimi.epostaGecerli(eposta) ? (true, "") : (false, "Müşterinin geçerli bir e-posta adresi yok.")
        case .whatsapp:
            return telefonE164(telefon).isEmpty ? (false, "Müşterinin telefon numarası yok ya da hatalı.") : (true, "")
        case .sms:
            if !smsHazir { return (false, smsKurulmadi) }
            if !smsIzni { return (false, "SMS göndermek için \"Statü değiştirme / müşteriye not\" izni gerekir.") }
            return telefonE164(telefon).isEmpty ? (false, "Müşterinin telefon numarası yok ya da hatalı.") : (true, "")
        }
    }

    /// Yer tutucu değerleri: e-posta şablonlarının ({ad} {adSoyad} {takipLinki}…)
    /// ve WhatsApp şablonlarının ({tam_ad} {kod} {form_link} {benim_adim}…)
    /// adları birlikte; hangi şablon seçilirse dolsun (panel: mesajDegerleri).
    public static func degerler(_ b: Basvuru, statu: String, benimAdim: String) -> [String: String] {
        var d = MusteriBildirimi.epostaDegerleri(b, statu: statu)
        d["tam_ad"] = d["adSoyad"] ?? ""
        d["kod"] = d["takipKodu"] ?? ""
        d["takip_link"] = d["takipLinki"] ?? ""
        d["form_link"] = b.takipKodu.isEmpty ? "" : BildirimMetni.formBaglantisi(b.takipKodu)
        d["benim_adim"] = benimAdim
        d["benim_ilk_adim"] = benimAdim.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        d["saat"] = ""
        return d
    }

    /// wa.me bağlantısı: numaraya metin hazır açılır.
    public static func waBaglantisi(telefon: String, metin: String) -> URL? {
        let t = telefonE164(telefon)
        guard !t.isEmpty else { return nil }
        return BildirimMetni.waBaglantisi(telefon: t, metin: metin.kirpik)
    }

    static func kayit(_ eylem: String, _ hedef: String, _ ayrinti: String, _ c: Calisan) -> Y {
        .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                 alanlar: IslemKaydi.alanlar(eylem: eylem, hedef: hedef, ayrinti: String(ayrinti.prefix(500)), calisan: c), zaman: ["at"])
    }

    /// WhatsApp teyidi: mesajKaydi/ + işlem kaydı (panel: wa-teyit.js cevap()).
    /// Telefon ya da metin geçersizse nil.
    public static func waTeyidi(_ t: WaTeyidi, gonderildi: Bool, calisan c: Calisan) -> [FirestoreIstemci.Yazim]? {
        let to = telefonE164(t.telefon)
        let metin = String(t.metin.kirpik.prefix(waEnCok))
        guard !to.isEmpty, !metin.isEmpty, !t.appId.isEmpty || (!t.talepId.isEmpty && !t.talepKol.isEmpty) else { return nil }
        let teyit = gonderildi ? "gonderildi" : "gonderilmedi"
        var a: [String: FSDeger] = [
            "kanal": .metin("whatsapp"), "to": .metin(to), "ad": .metin(String(t.ad.prefix(120))), "text": .metin(metin),
            "teyit": .metin(teyit),
            "createdBy": .metin(c.uid), "byName": .metin(String(c.gorunenAd.prefix(80))),
        ]
        // Kayıt ya başvuruya ya da talebe bağlıdır, ikisine birden değil (kural).
        if !t.appId.isEmpty { a["appId"] = .metin(t.appId) } else {
            a["talepId"] = .metin(t.talepId); a["talepKol"] = .metin(t.talepKol)
        }
        if !t.sablon.isEmpty { a["sablon"] = .metin(String(t.sablon.prefix(40))) }
        return [
            .olustur(yol: "mesajKaydi/\(FirestoreIstemci.yeniKimlik())", alanlar: a, zaman: ["createdAt"]),
            kayit("mesaj.whatsapp.\(teyit)", t.appId.isEmpty ? t.talepId : t.appId, String(metin.prefix(120)), c),
        ]
    }

    /// Elle yazılan SMS (tur 'elle': 30 dk bekletmeye girmez). SMS kapalıysa,
    /// telefon ya da metin geçersizse nil (panel: queueSms(..., 'elle')).
    public static func sms(_ b: Basvuru, telefon: String, metin: String, ayar: SmsAyari, calisan c: Calisan) -> [FirestoreIstemci.Yazim]? {
        let to = telefonE164(telefon)
        let govde = String(MusteriBildirimi.ascii(metin).kirpik.prefix(smsEnCok))
        guard ayar.acik, !to.isEmpty, !govde.isEmpty else { return nil }
        let a: [String: FSDeger] = [
            "to": .metin(to), "text": .metin(govde), "appId": .metin(b.kimlik), "trackingCode": .metin(b.takipKodu),
            "status": .metin("queued"), "attempts": .tam(0), "tur": .metin("elle"),
            "createdBy": .metin(c.uid), "byName": .metin(String(c.gorunenAd.prefix(80))),
        ]
        return [
            .olustur(yol: "sms/\(FirestoreIstemci.yeniKimlik())", alanlar: a, zaman: ["createdAt"]),
            kayit("mesaj.sms", b.kimlik, String(govde.prefix(120)), c),
        ]
    }
}

/// Cevabı beklenen WhatsApp açılışı. Uygulama kapanıp açılsa da soru kaybolmasın
/// diye cihazda saklanır (panel: localStorage'daki bekleyen teyit).
public struct WaTeyidi: Codable, Equatable {
    public var appId: String
    /// Talepten açıldıysa: talebin kimliği ve koleksiyonu (callback,
    /// applicationRequests, armutTalepleri).
    public var talepId: String
    public var talepKol: String
    public var telefon: String
    public var ad: String
    public var metin: String
    public var sablon: String
    public init(appId: String = "", talepId: String = "", talepKol: String = "", telefon: String, ad: String, metin: String, sablon: String = "") {
        self.appId = appId; self.talepId = talepId; self.talepKol = talepKol
        self.telefon = telefon; self.ad = ad; self.metin = metin; self.sablon = sablon
    }
}

/// Mesaj geçmişinin bir satırı: eposta/, sms/ ve mesajKaydi/ tek listede.
public struct MesajSatiri: Equatable, Identifiable {
    public static let smsDurumlari = ["queued": "Sırada", "sent": "Gönderildi", "failed": "Gönderilemedi", "cancelled": "İptal"]

    public var id: String
    public var kanal: MesajKanali
    public var zaman: Date?
    public var metin: String
    public var durum: String
    public var kim: String

    public init(id: String, kanal: MesajKanali, zaman: Date?, metin: String, durum: String, kim: String) {
        self.id = id; self.kanal = kanal; self.zaman = zaman; self.metin = metin; self.durum = durum; self.kim = kim
    }

    public init(eposta m: EpostaKaydi) {
        self.init(id: "e-\(m.id)", kanal: .eposta, zaman: m.zaman, metin: m.konu, durum: m.durumYazisi, kim: m.yazan)
    }

    public init(sms kimlik: String, alanlar a: [String: FSDeger]) {
        let d = a["status"]?.metinDegeri ?? ""
        self.init(id: "s-\(kimlik)", kanal: .sms, zaman: a["sentAt"]?.zamanDegeri ?? a["createdAt"]?.zamanDegeri,
                  metin: a["text"]?.metinDegeri ?? "", durum: Self.smsDurumlari[d] ?? d, kim: a["byName"]?.metinDegeri ?? "")
    }

    /// Eski kayıtlarda teyit yok: "açıldı" (panel: teyitYazisi).
    public init(whatsapp kimlik: String, alanlar a: [String: FSDeger]) {
        let t = a["teyit"]?.metinDegeri ?? ""
        let d = t == "gonderildi" ? "Gönderildi" : t == "gonderilmedi" ? "Gönderilmedi" : "WhatsApp’ta açıldı (teyit yok)"
        self.init(id: "w-\(kimlik)", kanal: .whatsapp, zaman: a["createdAt"]?.zamanDegeri,
                  metin: a["text"]?.metinDegeri ?? "", durum: d, kim: a["byName"]?.metinDegeri ?? "")
    }

    /// Yeniden eskiye (panel: gecmisBirlestir).
    public static func birlestir(_ l: [MesajSatiri]) -> [MesajSatiri] {
        l.sorted { ($0.zaman ?? .distantPast) > ($1.zaman ?? .distantPast) }
    }
}

/// Hazır WhatsApp/SMS mesajı (settings/wa → templates).
public struct WaSablonu: Equatable, Identifiable {
    public static let enCok = 30

    public var id: String
    public var baslik: String
    public var metin: String
    public init(id: String, baslik: String, metin: String) { self.id = id; self.baslik = baslik; self.metin = metin }

    /// Yeni kurulumda hazır gelenler (panel: DEFAULT_WA_TEMPLATES).
    public static let varsayilanlar: [WaSablonu] = [
        WaSablonu(id: "ulasilamadi", baslik: "Ulaşamadık",
                  metin: "Merhaba {ad}, VizeMia'dan {benim_adim}. Sizi aradık ama ulaşamadık. Müsait olduğunuzda buradan yazabilir ya da bizi arayabilirsiniz."),
        WaSablonu(id: "randevu-hatirlatma", baslik: "Arama saati onayı",
                  metin: "Merhaba {ad}, {ulke} vize başvurunuz için {saat} aralığında sizi arayacağız. Uygun değilse buradan yazmanız yeterli."),
        WaSablonu(id: "form-linki", baslik: "Form bağlantısı",
                  metin: "Merhaba {ad}, başvuru formunuz hazır: {form_link} Açmak için pasaport numaranızı yazmanız yeterli. Takip kodunuz: {kod}"),
    ]

    /// Sonradan eklenenler: kayıtlı listede yoksa ve silinmemişse eklenir (panel: SONRADAN_EKLENEN).
    public static let sonradanEklenen: [WaSablonu] = [
        WaSablonu(id: "armut-bilgi", baslik: "Armut.com — detaylı bilgi",
                  metin: "Merhaba, Vizemia Danışmanlık'tan {benim_ilk_adim} ben. Armut.com üzerinden sizlerle iletişime geçmiştik. Detaylı bilgi için bu numara üzerinden iletişime geçebilirsiniz."),
        WaSablonu(id: "armut-evrak", baslik: "Armut.com — evrak gönderimi",
                  metin: "Merhaba, Vizemia Danışmanlık'tan {benim_ilk_adim} ben. Armut.com üzerinden sizlerle iletişime geçmiştik. Evraklarınızı bu konuşma üzerinden gönderebilirsiniz."),
    ]

    /// settings/wa belgesinden liste (panel: loadTemplates → sablonlariBirlestir).
    public static func liste(belge a: [String: FSDeger]?) -> [WaSablonu] {
        let kayitli: [WaSablonu] = (a?["templates"]?.diziDegeri ?? []).compactMap { d in
            guard let h = d.haritaDegeri, let id = h["id"]?.metinDegeri, !id.isEmpty else { return nil }
            return WaSablonu(id: id, baslik: h["title"]?.metinDegeri ?? "", metin: h["text"]?.metinDegeri ?? "")
        }
        let silinen = Set((a?["kaldirilan"]?.diziDegeri ?? []).compactMap { $0.metinDegeri })
        let temel = kayitli.isEmpty ? varsayilanlar : kayitli
        let olan = Set(temel.map(\.id))
        return Array((temel + sonradanEklenen.filter { !olan.contains($0.id) && !silinen.contains($0.id) }).prefix(enCok))
    }

    /// Henüz kaydedilmemiş satırın geçici kimliği; kayıtta başlıktan kimlik türetilir.
    public static func geciciKimlik() -> String { "yeni-\(UUID().uuidString)" }

    /// Başlıktan kimlik; çakışırsa sonuna sayı (panel: templateId).
    public static func kimlik(baslik: String, olanlar: [String]) -> String {
        let cevir: [Character: String] = ["ı": "i", "İ": "i", "ğ": "g", "Ğ": "g", "ş": "s", "Ş": "s", "ö": "o", "Ö": "o",
                                          "ü": "u", "Ü": "u", "ç": "c", "Ç": "c"]
        let k = baslik.map { cevir[$0] ?? String($0) }.joined().lowercased()
        var temel = ""
        var tire = false
        for ch in k {
            if ch.isASCII && (ch.isLetter || ch.isNumber) { if tire && !temel.isEmpty { temel += "-" }; temel.append(ch); tire = false }
            else { tire = true }
        }
        temel = String(temel.prefix(40))
        while temel.hasSuffix("-") { temel.removeLast() }
        if temel.isEmpty { temel = "sablon" }
        var id = temel, n = 2
        while olanlar.contains(id) { id = "\(temel)-\(n)"; n += 1 }
        return id
    }

    /// Talepler ve Armut'ta doldurma: bilinmeyen yer tutucu boşalır, metin
    /// kırpılır, 900 karakterle sınırlanır (panel: renderWa).
    public static func doldur(_ metin: String, _ d: [String: String]) -> String {
        guard let re = try? NSRegularExpression(pattern: "\\{([A-Za-z0-9_]+)\\}") else { return metin }
        let ns = metin as NSString
        var out = "", son = 0
        for m in re.matches(in: metin, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: son, length: m.range.location - son))
            out += d[ns.substring(with: m.range(at: 1))] ?? ""
            son = m.range.location + m.range.length
        }
        out += ns.substring(from: son)
        return String(out.kirpik.prefix(MusteriMesaji.waEnCok))
    }

    /// Talep kaydından değerler (panel: waVars).
    public static func degerler(talep t: Talep, benimAdim: String) -> [String: String] {
        let dilimler = t.saatler.compactMap { s -> Int? in
            let p = s.split(separator: ":").compactMap { Int($0) }
            return p.count == 2 ? p[0] * 60 + p[1] : nil
        }
        return degerler(adSoyad: t.ad, ulke: t.ulkeAdi, saat: dilimler.isEmpty ? "" : Mesai.aralikOzeti(dilimler),
                        kod: t.ham["trackingCode"]?.metinDegeri ?? "", benimAdim: benimAdim)
    }

    public static func degerler(adSoyad: String, ulke: String = "", saat: String = "", kod: String = "", benimAdim: String) -> [String: String] {
        let ilk = { (s: String) in s.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "" }
        return ["ad": ilk(adSoyad), "tam_ad": adSoyad.kirpik, "ulke": ulke, "saat": saat, "kod": kod, "form_link": "",
                "benim_adim": benimAdim, "benim_ilk_adim": ilk(benimAdim)]
    }

    /// Listeyi kaydeder (panel: saveTemplates). Silinen sonradan-eklenenler
    /// `kaldirilan`a yazılır ki bir daha kendiliğinden gelmesin.
    public static func kaydet(_ l: [WaSablonu], calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        var olanlar = l.map(\.id).filter { !$0.hasPrefix("yeni-") }
        let kimlikli = l.map { s -> WaSablonu in
            guard s.id.hasPrefix("yeni-") else { return s }
            var y = s
            y.id = kimlik(baslik: s.baslik, olanlar: olanlar + sonradanEklenen.map(\.id))
            olanlar.append(y.id)
            return y
        }
        let temiz = kimlikli.prefix(enCok).map {
            WaSablonu(id: String($0.id.prefix(40)), baslik: String($0.baslik.kirpik.prefix(60)), metin: String($0.metin.kirpik.prefix(MusteriMesaji.waEnCok)))
        }.filter { !$0.id.isEmpty && !$0.baslik.isEmpty && !$0.metin.isEmpty }
        let olan = Set(temiz.map(\.id))
        return [
            .yaz(yol: "settings/wa", alanlar: [
                "templates": .dizi(temiz.map { .harita(["id": .metin($0.id), "title": .metin($0.baslik), "text": .metin($0.metin)]) }),
                "kaldirilan": .dizi(sonradanEklenen.map(\.id).filter { !olan.contains($0) }.map { FSDeger.metin($0) }),
                "updatedBy": .metin(c.uid),
            ], zaman: ["updatedAt"]),
            MusteriMesaji.kayit("wa.templates", "", String(temiz.count), c),
        ]
    }
}
