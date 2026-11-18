import Foundation

// Bildirimler ekranı (panel: pages/bildirimler.js, bildirim.js, bekletme.js).
// WhatsApp sunucudan gitmiyor: mesaj hazır bir wa.me bağlantısıyla açılıyor,
// danışman kendi WhatsApp'ından gönderip "Gönderdim" diyor. E-posta ve SMS'i
// zamanlanmış iş (scripts/send-bildirim.mjs) gönderiyor. Kayıtta metin yok:
// şablon (settings/bildirim) gösterim anında kayıtla doldurulur.

/// bildirimler/{id}
public struct BildirimGorevi: Equatable, Identifiable {
    public static let turAdlari = ["randevu-alindi": "Randevu alındı (müjde)", "evrak-hatirlatma": "Evrak hatırlatması",
                                   "form-linki": "Başvuru formu bağlantısı"]
    public static let kanalAdlari = ["wa": "WhatsApp", "sms": "SMS", "email": "E-posta"]
    public static let durumAdlari = ["planned": "Planlandı", "sent": "Gönderildi", "cancelled": "İptal", "failed": "Gönderilemedi"]
    /// Olayla tetiklenen tür: 30 dk bekleme bitmeden WhatsApp görevi açılmaz (panel: BEKLETILEN_TURLER).
    static let bekletilen: Set<String> = ["randevu-alindi"]
    /// wa.me bağlantısındaki metin sınırı (panel: WA_MAX).
    public static let waEnCok = 900

    public var id: String
    public var appId: String
    public var takipKodu: String
    public var tur: String
    public var gonderim: Date?
    public var durum: String
    public var kanallar: [String: Bool]
    public var ad: String
    public var ulke: String
    public var ulkeAdi: String
    public var randevu: String
    public var evrakSon: String
    public var hatirlatmaGun: Int?
    public var randevuSaati: String
    public var randevuMerkezi: String
    public var randevuSehri: String
    public var randevuYeri: String
    public var randevuHarita: String
    public var telefon: String
    public var eposta: String
    public var atanan: String
    public var atananAd: String
    public var waDurum: String
    public var waZaman: Date?
    public var zorla: Bool
    public var iptalSebebi: String
    public var hata: String

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        func m(_ k: String) -> String { a[k]?.metinDegeri ?? "" }
        id = kimlik
        appId = m("appId"); takipKodu = m("trackingCode"); tur = m("kind")
        gonderim = a["sendAt"]?.zamanDegeri; durum = m("status")
        var k: [String: Bool] = [:]
        for (ad, v) in a["channels"]?.haritaDegeri ?? [:] { k[ad] = v.mantikDegeri ?? false }
        kanallar = k
        ad = m("name"); ulke = m("country"); ulkeAdi = m("countryName")
        randevu = m("appointmentDate"); evrakSon = m("docDeadline"); hatirlatmaGun = a["reminderDays"]?.tamDegeri
        randevuSaati = m("randevuSaati"); randevuMerkezi = m("randevuMerkezi"); randevuSehri = m("randevuSehri")
        randevuYeri = m("randevuYeri"); randevuHarita = m("randevuHarita")
        telefon = m("phone"); eposta = m("email")
        atanan = m("assignedTo"); atananAd = m("assignedName")
        waDurum = m("waStatus"); waZaman = a["waAt"]?.zamanDegeri
        zorla = a["force"]?.mantikDegeri ?? false
        iptalSebebi = m("cancelReason"); hata = m("error")
    }

    public var turAdi: String { Self.turAdlari[tur] ?? tur }
    public var durumAdi: String { Self.durumAdlari[durum] ?? durum }
    /// "WhatsApp, SMS"
    public var kanalMetni: String {
        let l = ["wa", "sms", "email"].filter { kanallar[$0] == true }.compactMap { Self.kanalAdlari[$0] }
        return l.isEmpty ? "—" : l.joined(separator: ", ")
    }

    /// WhatsApp görevi açık mı (panel: waGoreviHazir). İptal edilenin görevi de düşer;
    /// e-posta / SMS gitmiş ("sent") kayıtta WhatsApp'ı hâlâ danışman gönderir.
    public var waGorevi: Bool {
        waDurum == "pending" && durum != "cancelled" && !(Self.bekletilen.contains(tur) && durum == "planned" && !zorla)
    }

    /// Planlı ama zamanı geçmiş (gönderim turunu bekliyor).
    public func gecikmis(_ simdi: Date = Date()) -> Bool { durum == "planned" && (gonderim.map { $0 < simdi } ?? false) }

    /// Görev bu danışmana mı düşüyor? Atanmamışlar herkeste görünür (sahipsiz mesaj ortada kalmasın).
    public func bana(_ uid: String) -> Bool { atanan.isEmpty || atanan == uid }
}

public enum BildirimMetni {
    /// encodeURIComponent'in bıraktığı karakterler (geri kalanı yüzde kodlanır).
    static let uriBilesen: CharacterSet = {
        var c = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        c.insert(charactersIn: "-_.!~*'()")
        return c
    }()

    /// "23 Kasım 2026 Pazartesi" (panel: trTarih).
    public static func trTarih(_ iso: String, gun: Bool = true) -> String {
        guard Tr.tarih(iso) != nil else { return "" }
        let p = iso.split(separator: "-").compactMap { Int($0) }
        let temel = "\(p[2]) \(Mesai.ayAdi[p[1] - 1]) \(p[0])"
        return gun ? "\(temel) \(Mesai.gunAdi[Tr.gunNo(iso)])" : temel
    }

    /// Randevu bilgileri bloğu: yalnız dolu satırlar.
    static func randevuBilgileri(_ b: BildirimGorevi) -> String {
        [
            trTarih(b.randevu).isEmpty ? "" : "📅 Tarih: \(trTarih(b.randevu))",
            b.randevuSaati.isEmpty ? "" : "🕘 Saat: \(b.randevuSaati)",
            !b.randevuYeri.isEmpty ? "🏛️ Yer: \(b.randevuYeri)" : (b.randevuMerkezi.isEmpty ? "" : "🏢 Randevu merkezi: \(b.randevuMerkezi)"),
            b.randevuSehri.isEmpty ? "" : "📍 Şehir: \(b.randevuSehri)",
            b.randevuHarita.isEmpty ? "" : "🗺️ Konum: \(b.randevuHarita)",
        ].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Müşteri formu bağlantısı (panel: musteri-formu-link.js).
    public static func formBaglantisi(_ kod: String) -> String {
        "https://vizemia.com/form?kod=\(kod.addingPercentEncoding(withAllowedCharacters: uriBilesen) ?? kod)"
    }

    /// Yer tutucular (panel: templateVars). Aynı şey için birkaç yazım kabul edilir.
    static func degiskenler(_ b: BildirimGorevi, sablonlar: [String: BildirimAyari.Sablon]) -> [String: String] {
        let gun = String(abs(b.hatirlatmaGun ?? sablonlar["evrak-hatirlatma"]?.gun ?? 0))
        let bilgi = randevuBilgileri(b)
        let form = b.takipKodu.isEmpty ? "" : formBaglantisi(b.takipKodu)
        var d: [String: String] = [:]
        d["randevu yeri"] = b.randevuYeri.isEmpty ? b.randevuMerkezi : b.randevuYeri
        d["randevu konumu"] = b.randevuHarita
        d["randevu saati"] = b.randevuSaati
        d["randevu merkezi"] = b.randevuMerkezi
        d["randevu şehri"] = b.randevuSehri
        d["randevu sehri"] = b.randevuSehri
        d["randevu bilgileri"] = bilgi
        d["randevu bilgisi"] = bilgi
        d["form bağlantısı"] = form
        d["form baglantisi"] = form
        d["form"] = form
        d["isim"] = b.ad
        d["ad"] = b.ad
        d["ülke"] = b.ulkeAdi
        d["ulke"] = b.ulkeAdi
        d["randevu tarihi"] = trTarih(b.randevu)
        d["randevu"] = trTarih(b.randevu)
        d["evrak son tarihi"] = trTarih(b.evrakSon)
        d["randevudan 3 gün önceki tarih"] = trTarih(b.evrakSon)
        d["hatırlatma günü"] = gun
        d["hatirlatma gunu"] = gun
        return d
    }

    /// Tanınmayan yer tutucu olduğu gibi kalır (panel: renderTemplate).
    static func doldur(_ sablon: String, _ d: [String: String]) -> String {
        var sonuc = ""
        var kalan = Substring(sablon)
        while let ac = kalan.firstIndex(of: "{") {
            sonuc += kalan[..<ac]
            let sonra = kalan[kalan.index(after: ac)...]
            guard let kapa = sonra.firstIndex(of: "}"), kapa > sonra.startIndex else {
                sonuc += "{"
                kalan = sonra
                continue
            }
            let anahtar = sonra[..<kapa].trimmingCharacters(in: .whitespaces)
            if let v = d[anahtar] { sonuc += v } else { sonuc += "{" + sonra[..<kapa] + "}" }
            kalan = sonra[sonra.index(after: kapa)...]
        }
        return sonuc + kalan
    }

    /// Kaydın mesajı ve e-posta konusu (ülkenin grubu varsa onun şablonuyla).
    public static func kur(_ b: BildirimGorevi, ayar: BildirimAyari) -> (metin: String, konu: String) {
        let s = ayar.sablonlar(ulke: b.ulke)
        let t = s[b.tur]
        let d = degiskenler(b, sablonlar: s)
        return (doldur(t?.metin ?? "", d), doldur(t?.konu ?? "", d))
    }

    /// wa.me bağlantısı: yalnız rakamlar, metin 900 karakterle (panel: waLink).
    public static func waBaglantisi(telefon: String, metin: String) -> URL? {
        let rakam = telefon.filter { $0.isASCII && $0.isNumber }
        guard !rakam.isEmpty else { return nil }
        let m = String(metin.prefix(BildirimGorevi.waEnCok))
        let k = m.addingPercentEncoding(withAllowedCharacters: uriBilesen) ?? ""
        return URL(string: "https://wa.me/\(rakam)?text=\(k)")
    }
}

extension BasvuruIslemi {
    static func bildirimDamgasi(_ c: Calisan) -> [String: FSDeger] { ["updatedBy": .metin(c.uid)] }

    /// "Gönderdim": WhatsApp görevi kapanır (kayıt gönderilmiş olsa bile serbest).
    public static func waGonderildi(_ b: BildirimGorevi, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [
            .guncelle(yol: "bildirimler/\(b.id)", alanlar: bildirimDamgasi(c).merging(["waStatus": .metin("sent"), "waBy": .metin(c.uid)]) { $1 },
                      zaman: ["waAt", "updatedAt"]),
            .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                     alanlar: IslemKaydi.alanlar(eylem: "bildirim.wa", hedef: b.id, ayrinti: b.tur, calisan: c), zaman: ["at"]),
        ]
    }

    /// "Şimdi gönder": bekleme ve gönderim penceresi atlanır; ilk turda gider.
    public static func bildirimSimdi(_ b: BildirimGorevi, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [
            .guncelle(yol: "bildirimler/\(b.id)", alanlar: bildirimDamgasi(c).merging(["force": .mantik(true)]) { $1 },
                      zaman: ["sendAt", "updatedAt"]),
            .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                     alanlar: IslemKaydi.alanlar(eylem: "bildirim.now", hedef: b.id, ayrinti: b.tur, calisan: c), zaman: ["at"]),
        ]
    }

    public static func bildirimIptal(_ b: BildirimGorevi, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [
            .guncelle(yol: "bildirimler/\(b.id)", alanlar: bildirimDamgasi(c).merging([
                "status": .metin("cancelled"), "cancelReason": .metin(String("\(c.gorunenAd) iptal etti".prefix(200))),
            ]) { $1 }, zaman: ["updatedAt"]),
            .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                     alanlar: IslemKaydi.alanlar(eylem: "bildirim.cancel", hedef: b.id, ayrinti: b.tur, calisan: c), zaman: ["at"]),
        ]
    }
}
