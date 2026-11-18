import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Çalışan girişi ve panel verisi — panelle (panel/js/app.js, state.js,
// pages/talepler.js) aynı hesaplar, aynı kurallar.

/// Firebase'in kimlik doğrulama arayüzü (REST). Panelle aynı hesaplar:
/// kullanıcı adı "sefa" → "sefa@panel.vizemia.local".
public struct KimlikIstemci {
    public static let apiAnahtari = "AIzaSyAt7T8brjEbzmoo5Py28o38IentdXXosi4"
    public static let alanAdi = "panel.vizemia.local"

    public var kimlikTaban: String
    public var belirtecTaban: String
    public var oturum: URLSession

    public init(
        kimlikTaban: String = "https://identitytoolkit.googleapis.com/v1",
        belirtecTaban: String = "https://securetoken.googleapis.com/v1",
        oturum: URLSession = .shared
    ) {
        self.kimlikTaban = kimlikTaban
        self.belirtecTaban = belirtecTaban
        self.oturum = oturum
    }

    public struct Oturum: Equatable, Codable {
        public var uid: String
        public var belirtec: String
        public var yenileme: String
        /// Belirtecin geçerlilik sonu (Firebase bir saat veriyor).
        public var bitis: Date

        public init(uid: String, belirtec: String, yenileme: String, bitis: Date) {
            self.uid = uid; self.belirtec = belirtec; self.yenileme = yenileme; self.bitis = bitis
        }

        /// Son beş dakikaya girdiyse yenilenmeli.
        public func eskidi(_ simdi: Date = Date()) -> Bool { simdi.addingTimeInterval(300) >= bitis }
    }

    public enum Hata: Error, Equatable {
        case kullaniciAdiGecersiz
        case bilgilerYanlis
        case hesapKapali
        case cokDeneme
        case oturumBitti
        case baglanti
        case sunucu(String)

        public var mesaj: String {
            switch self {
            case .kullaniciAdiGecersiz: return "Kullanıcı adı geçersiz."
            case .bilgilerYanlis: return "Kullanıcı adı ya da şifre hatalı."
            case .hesapKapali: return "Bu hesap kapatılmış. Yöneticinizle görüşün."
            case .cokDeneme: return "Çok fazla deneme yapıldı. Birkaç dakika sonra yeniden deneyin."
            case .oturumBitti: return "Oturumunuz sona erdi. Yeniden giriş yapın."
            case .baglanti: return "Bağlantı kurulamadı. İnternetinizi kontrol edin."
            case .sunucu(let k): return "Giriş yapılamadı (\(k))."
            }
        }
    }

    /// Kullanıcı adı panelle aynı kurala uyar: 3–40 karakter, küçük harf, rakam, . _ -
    public static func temizAd(_ ad: String) -> String? {
        let a = ad.kirpik.lowercased()
        return a.eslesir("^[a-z0-9._-]{3,40}$") ? a : nil
    }

    public func giris(kullaniciAdi: String, sifre: String, simdi: Date = Date()) async throws -> Oturum {
        guard let ad = KimlikIstemci.temizAd(kullaniciAdi) else { throw Hata.kullaniciAdiGecersiz }
        let govde: [String: Any] = ["email": "\(ad)@\(KimlikIstemci.alanAdi)", "password": sifre, "returnSecureToken": true]
        let j = try await istek("\(kimlikTaban)/accounts:signInWithPassword?key=\(KimlikIstemci.apiAnahtari)",
                                govde: try JSONSerialization.data(withJSONObject: govde), tur: "application/json")
        guard let uid = j["localId"] as? String, let b = j["idToken"] as? String, let y = j["refreshToken"] as? String else {
            throw Hata.sunucu("eksik cevap")
        }
        return Oturum(uid: uid, belirtec: b, yenileme: y, bitis: simdi.addingTimeInterval(Double(KimlikIstemci.sure(j["expiresIn"]))))
    }

    /// Süresi dolan belirteci yeniler (şifre sorulmaz).
    public func yenile(_ o: Oturum, simdi: Date = Date()) async throws -> Oturum {
        let govde = "grant_type=refresh_token&refresh_token=\(o.yenileme.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
        let j = try await istek("\(belirtecTaban)/token?key=\(KimlikIstemci.apiAnahtari)",
                                govde: Data(govde.utf8), tur: "application/x-www-form-urlencoded")
        guard let b = j["id_token"] as? String else { throw Hata.oturumBitti }
        return Oturum(uid: (j["user_id"] as? String) ?? o.uid, belirtec: b,
                      yenileme: (j["refresh_token"] as? String) ?? o.yenileme,
                      bitis: simdi.addingTimeInterval(Double(KimlikIstemci.sure(j["expires_in"]))))
    }

    /// Yeni şifrenin kuralı (panel: en az 12 karakter; büyük harf, küçük harf, rakam ve özel karakter). Boş: uygun.
    public static func sifreHatasi(_ s: String) -> String? {
        if s.count < 12 { return "Yeni şifre en az 12 karakter olmalı." }
        if !s.contains(where: { $0.isUppercase }) { return "Yeni şifrede büyük harf olmalı." }
        if !s.contains(where: { $0.isLowercase }) { return "Yeni şifrede küçük harf olmalı." }
        if !s.contains(where: { $0.isNumber }) { return "Yeni şifrede rakam olmalı." }
        if !s.contains(where: { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }) { return "Yeni şifrede özel karakter (ör. ! ? * .) olmalı." }
        return nil
    }

    /// Şifre değiştirme: önce mevcut şifreyle yeniden doğrulanır (panel: reauthenticate),
    /// sonra yeni şifre yazılır. Yeni oturum döner (eski belirteçler geçersiz olur).
    public func sifreDegistir(kullaniciAdi: String, mevcut: String, yeni: String, simdi: Date = Date()) async throws -> Oturum {
        let o = try await giris(kullaniciAdi: kullaniciAdi, sifre: mevcut, simdi: simdi)
        let govde: [String: Any] = ["idToken": o.belirtec, "password": yeni, "returnSecureToken": true]
        let j = try await istek("\(kimlikTaban)/accounts:update?key=\(KimlikIstemci.apiAnahtari)",
                                govde: try JSONSerialization.data(withJSONObject: govde), tur: "application/json")
        guard let b = j["idToken"] as? String, let y = j["refreshToken"] as? String else { throw Hata.sunucu("eksik cevap") }
        return Oturum(uid: (j["localId"] as? String) ?? o.uid, belirtec: b, yenileme: y,
                      bitis: simdi.addingTimeInterval(Double(KimlikIstemci.sure(j["expiresIn"]))))
    }

    static func sure(_ v: Any?) -> Int {
        if let s = v as? String, let n = Int(s) { return n }
        if let n = v as? Int { return n }
        return 3600
    }

    private func istek(_ adres: String, govde: Data, tur: String) async throws -> [String: Any] {
        guard let u = URL(string: adres) else { throw Hata.baglanti }
        var i = URLRequest(url: u)
        i.httpMethod = "POST"
        i.timeoutInterval = 20
        i.setValue(tur, forHTTPHeaderField: "Content-Type")
        i.httpBody = govde
        let veri: Data, kod: Int
        do { (veri, kod) = try await Ag.gonder(i, oturum: oturum) } catch { throw Hata.baglanti }
        let j = (try? JSONSerialization.jsonObject(with: veri)) as? [String: Any] ?? [:]
        guard kod == 200 else { throw KimlikIstemci.hata(kod: kod, j) }
        return j
    }

    /// Firebase hata kodunu Türkçe karşılığına çevirir.
    static func hata(kod: Int, _ j: [String: Any]) -> Hata {
        let m = ((j["error"] as? [String: Any])?["message"] as? String) ?? ""
        if m.hasPrefix("INVALID_LOGIN_CREDENTIALS") || m.hasPrefix("INVALID_PASSWORD") || m.hasPrefix("EMAIL_NOT_FOUND")
            || m.hasPrefix("INVALID_EMAIL") { return .bilgilerYanlis }
        if m.hasPrefix("USER_DISABLED") { return .hesapKapali }
        if m.hasPrefix("TOO_MANY_ATTEMPTS") { return .cokDeneme }
        if m.hasPrefix("WEAK_PASSWORD") || m.hasPrefix("PASSWORD_DOES_NOT_MEET_REQUIREMENTS") {
            return .sunucu("yeni şifre güvenlik kurallarına uymuyor")
        }
        if m.hasPrefix("TOKEN_EXPIRED") || m.hasPrefix("INVALID_REFRESH_TOKEN") || m.hasPrefix("USER_NOT_FOUND") { return .oturumBitti }
        return .sunucu(m.isEmpty ? "\(kod)" : m)
    }
}

/// Panel çalışanı (employees/{uid}) ve rolünün izinleri (settings/permissions).
public struct Calisan: Equatable, Codable {
    public var uid: String
    public var kullaniciAdi: String
    public var adSoyad: String
    public var rol: String
    public var aktif: Bool
    public var izinler: Set<String>

    public static let rolAdlari = ["admin": "Yönetici", "writer": "Operasyon", "reader": "İzleyici", "intern": "Stajyer"]

    public init(uid: String, belge: [String: FSDeger], izinBelgesi: [String: FSDeger]?) {
        self.uid = uid
        kullaniciAdi = belge["username"]?.metinDegeri ?? ""
        adSoyad = belge["displayName"]?.metinDegeri ?? ""
        rol = belge["role"]?.metinDegeri ?? ""
        aktif = belge["active"]?.mantikDegeri ?? false
        // Ayar belgesi yoksa panelin varsayılanları (panel/js/config.js → DEFAULT_ROLE_PERMS).
        if let roller = izinBelgesi?["roles"]?.haritaDegeri {
            izinler = Set((roller[rol]?.diziDegeri ?? []).compactMap { $0.metinDegeri })
        } else {
            izinler = Set(Calisan.varsayilanIzinler[rol] ?? [])
        }
    }

    public static let varsayilanIzinler: [String: [String]] = [
        "writer": ["app.view", "app.create", "app.edit", "app.status", "app.sensitive", "app.checklist",
                   "note.add", "lead.view", "lead.manage", "armut.view", "armut.manage", "support.view", "support.manage",
                   "content.draft", "content.publish", "vitrin.edit", "vitrin.publish", "havuz.manage",
                   "surec.edit", "social.view", "social.share"],
        "reader": ["app.view", "lead.view", "support.view", "social.view"],
        "intern": ["app.view", "app.create", "app.checklist", "note.add", "content.draft", "vitrin.edit",
                   "social.view", "social.share"],
    ]

    public var yonetici: Bool { rol == "admin" }

    /// Panelle aynı kural: yönetici her şeye yetkili; diğerleri rol izinleri.
    public func yapabilir(_ izin: String) -> Bool { aktif && (yonetici || izinler.contains(izin)) }

    /// Karşılamada kullanılan ad: "Sefa Karakaş" → "Sefa".
    public var ilkAd: String {
        let a = adSoyad.kirpik.split(separator: " ").first.map(String.init) ?? ""
        return a.isEmpty ? kullaniciAdi : a
    }

    public var rolAdi: String { Calisan.rolAdlari[rol] ?? rol }
}

/// Geri arama ya da başvuru talebi (callback / applicationRequests).
public struct Talep: Equatable, Identifiable {
    public enum Tur: String { case geriArama = "callback", basvuru = "applicationRequests" }

    public var tur: Tur
    public var kimlik: String
    public var ad: String
    public var telefon: String
    public var eposta: String
    public var ulkeAdi: String
    public var vizeTuru: String
    public var mod: String
    public var tarih: String
    public var saatler: [String]
    public var mesaj: String
    public var durum: String
    public var icNot: String
    public var kaynak: String
    public var silindi: Bool
    public var olusturma: Date?
    /// Kaydın bütün alanları (başvuruya çevirirken taslak, ülke, izin …).
    public var ham: [String: FSDeger] = [:]

    public var id: String { "\(tur.rawValue)/\(kimlik)" }
    public var yol: String { "\(tur.rawValue)/\(kimlik)" }

    /// Hâlâ iş bekleyen durumlar (panel: OPEN_LEAD_STATUS).
    public static let acikDurumlar = ["new", "called", "reached"]
    public static let iptalSebepleri = [
        "İlgilenmiyor / vazgeçti", "Ulaşılamadı (defalarca denendi)", "Başka firmayla ilerledi",
        "Şartları uygun değil", "Yanlış / geçersiz numara", "Mükerrer talep", "Diğer",
    ]

    public init(tur: Tur, kimlik: String, alanlar a: [String: FSDeger]) {
        self.tur = tur
        self.kimlik = kimlik
        self.ham = a
        let m = { (k: String) in a[k]?.metinDegeri ?? "" }
        if tur == .geriArama {
            ad = m("name")
            mod = m("mode"); tarih = m("date")
            saatler = (a["times"]?.diziDegeri ?? []).compactMap { $0.metinDegeri }
        } else {
            ad = "\(m("firstName")) \(m("lastName"))".kirpik
            mod = m("callbackMode"); tarih = m("callbackDate")
            saatler = (a["callbackTimes"]?.diziDegeri ?? []).compactMap { $0.metinDegeri }
        }
        telefon = m("phone"); eposta = m("email"); ulkeAdi = m("countryName"); vizeTuru = m("visaType")
        mesaj = m("message"); durum = m("status"); icNot = m("internalNote"); kaynak = m("kaynak")
        silindi = a["silindi"]?.mantikDegeri ?? false
        olusturma = a["createdAt"]?.zamanDegeri
    }

    /// Kayıttaki durumun görünen adı (panel: CALLBACK_STATUS / REQUEST_STATUS).
    public var durumAdi: String { Talep.durumAdi(durum, tur: tur) }

    public static func durumAdi(_ d: String, tur: Tur) -> String {
        switch d {
        case "new": return tur == .geriArama ? "Aranacak" : "Yeni"
        case "called": return "Arandı, ulaşılamadı"
        case "reached": return "Görüşüldü"
        case "approved": return "Onaylandı — başvuru açıldı"
        case "cancelled": return "İptal"
        case "converted": return "Başvuruya dönüştü"
        case "closed": return "Kapatıldı"
        default: return d
        }
    }

    /// Müşteri "hemen arayın" dedi ve hâlâ aranmadı.
    public var acil: Bool { durum == "new" && mod == "hemen" }
    /// Arama günü geçti, hâlâ aranmadı.
    public func gecikti(bugun: String) -> Bool { durum == "new" && !tarih.isEmpty && tarih < bugun }
    public func bugun(_ b: String) -> Bool { tarih == b }
    public var acik: Bool { Talep.acikDurumlar.contains(durum) && !silindi }
    public var turAdi: String { tur == .geriArama ? "Geri arama" : "Başvuru talebi" }

    /// "Bugün 10:00–11:00", "Yarın 14:00–14:30", "21 Eyl Pzt 09:00–09:30", "Hemen".
    public func aramaMetni(bugun: String) -> String {
        if mod == "hemen" && durum == "new" { return "Hemen aranmak istiyor" }
        let dilimler = saatler.compactMap { s -> Int? in
            let p = s.split(separator: ":").compactMap { Int($0) }
            return p.count == 2 ? p[0] * 60 + p[1] : nil
        }
        let saat = dilimler.isEmpty ? "" : " " + Mesai.aralikOzeti(dilimler)
        if tarih.isEmpty { return saat.kirpik }
        let gun: String
        if tarih == bugun { gun = "Bugün" }
        else if tarih == Tr.gunEkle(bugun, 1) { gun = "Yarın" }
        else if tarih == Tr.gunEkle(bugun, -1) { gun = "Dün" }
        else { gun = Mesai.gunMetni(tarih) }
        return gun + saat
    }

    /// WhatsApp için numara: "+905321234567" → "905321234567".
    public var whatsappNumarasi: String {
        var d = telefon.filter { $0.isASCII && $0.isNumber }
        if d.hasPrefix("0") { d = "90" + d.dropFirst() }
        if d.count == 10 { d = "90" + d }
        return d
    }

    /// Panelle aynı sıra: hemen aranmak isteyen en üstte, sonra arama gününe göre.
    public static func sirala(_ t: [Talep]) -> [Talep] {
        t.sorted { a, b in
            if a.acil != b.acil { return a.acil }
            if a.tarih != b.tarih { return a.tarih < b.tarih }
            return (a.saatler.first ?? "") < (b.saatler.first ?? "")
        }
    }

    /// Durum değiştirme yazısı (kural: yalnız status, internalNote, cancelReason, handledAt, handledBy).
    public static func durumAlanlari(durum: String, icNot: String, iptalSebebi: String? = nil, uid: String) -> [String: FSDeger] {
        var a: [String: FSDeger] = [
            "status": .metin(durum),
            "internalNote": .metin(String(icNot.kirpik.prefix(2000))),
            "handledBy": .metin(uid),
        ]
        if let s = iptalSebebi { a["cancelReason"] = .metin(String(s.prefix(200))) }
        return a
    }

    /// Başvuru açılınca talep kapanır: onaylandı + başvurunun kimliği (handledAt sunucu saatiyle).
    public static func onayAlanlari(basvuruId: String, uid: String) -> [String: FSDeger] {
        ["status": .metin("approved"), "applicationId": .metin(String(basvuruId.prefix(40))), "handledBy": .metin(uid)]
    }
}

/// Ekip ana sayfasının özeti.
public struct TalepOzeti: Equatable {
    public var acil = 0
    public var bugun = 0
    public var geciken = 0
    public var acik = 0

    public init(_ talepler: [Talep], bugun gun: String) {
        let a = talepler.filter { $0.acik }
        acik = a.count
        acil = a.filter { $0.acil }.count
        bugun = a.filter { $0.durum == "new" && $0.bugun(gun) && !$0.acil }.count
        geciken = a.filter { $0.gecikti(bugun: gun) }.count
    }
}

/// İşlem kaydı (audit): panelle aynı alanlar.
public enum IslemKaydi {
    public static func alanlar(eylem: String, hedef: String, ayrinti: String, calisan: Calisan) -> [String: FSDeger] {
        [
            "action": .metin(String(eylem.prefix(60))),
            "target": .metin(String(hedef.prefix(120))),
            "detail": .metin(String(ayrinti.prefix(500))),
            "by": .metin(calisan.uid),
            "byName": .metin(String((calisan.adSoyad.isEmpty ? calisan.kullaniciAdi : calisan.adSoyad).prefix(80))),
        ]
    }
}
