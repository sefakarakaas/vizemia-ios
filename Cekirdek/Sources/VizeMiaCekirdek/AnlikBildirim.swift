import Foundation

// Anlık bildirim (telefonlara; gönderen site deposundaki apps-script/Bildirim.gs,
// Firebase Cloud Messaging ile). Bu dosya yalnız Firestore'a yazılanları kurar:
//   cihazlar/{kimlik}          telefonun kaydı (müşteri: takip kimliği; danışman: uid + konular)
//   bildirimIstekleri/{id}     elle bildirim (danışman → müşteri / danışman)
// Kural: firestore.rules → cihazlar, bildirimIstekleri.

/// Danışmanın seçebildiği bildirim konuları ve gerektirdiği izin.
public struct BildirimKonusu: Equatable, Identifiable {
    public var id: String
    public var ad: String
    public var aciklama: String
    /// Boş: izin gerekmez (kendisine atanan işler, elle gönderilen).
    public var izin: String

    public static let hepsi: [BildirimKonusu] = [
        BildirimKonusu(id: "talep", ad: "Yeni talepler", aciklama: "Geri arama ve başvuru talebi gelince", izin: "lead.view"),
        BildirimKonusu(id: "destek", ad: "Destek talepleri", aciklama: "Siteden yeni destek talebi", izin: "support.view"),
        BildirimKonusu(id: "gorev", ad: "WhatsApp görevlerim", aciklama: "Bana atanan mesajın zamanı gelince", izin: ""),
        BildirimKonusu(id: "form", ad: "Müşteri formu", aciklama: "Müşterim formu tamamlayınca ya da soru sorunca", izin: ""),
        BildirimKonusu(id: "kasa", ad: "Kasa", aciklama: "Ödeme, harcama ve döviz çevrimi girilince", izin: "kasa.view"),
        BildirimKonusu(id: "armut", ad: "Armut", aciklama: "Yeni Armut işi gelince", izin: "armut.view"),
        BildirimKonusu(id: "elle", ad: "Bana gönderilenler", aciklama: "Bir çalışan bana bildirim gönderince", izin: ""),
    ]

    /// Çalışanın görebildiği konular (izni olmayanınki gösterilmez, kaydedilmez).
    public static func uygun(_ c: Calisan) -> [BildirimKonusu] {
        hepsi.filter { $0.izin.isEmpty || c.yapabilir($0.izin) }
    }
}

public enum AnlikBildirim {
    /// Belge kimliği: jetonun SHA-256'sı. Aynı telefon hem müşteri hem danışman
    /// olabilir; iki kayıt karışmasın diye türü de katılır.
    public static func cihazKimligi(jeton: String, tur: String) -> String {
        Ozet.sha256Hex("vizemia-cihaz|\(tur)|\(jeton)")
    }

    /// Müşterinin telefonu: hatırlanan başvurunun takip kimliğiyle (girişsiz).
    public static func musteriKaydi(jeton: String, takipId: String) -> FirestoreIstemci.Yazim {
        .yaz(yol: "cihazlar/\(cihazKimligi(jeton: jeton, tur: "musteri"))", alanlar: [
            "token": .metin(jeton), "tur": .metin("musteri"), "takipId": .metin(takipId), "platform": .metin("ios"),
        ], zaman: ["updatedAt"])
    }

    /// Danışmanın telefonu: uid ve istediği konular (izni olmayanlar atılır).
    public static func ekipKaydi(jeton: String, calisan c: Calisan, konular: [String]) -> FirestoreIstemci.Yazim {
        let gecerli = Set(BildirimKonusu.uygun(c).map(\.id))
        let k = BildirimKonusu.hepsi.map(\.id).filter { konular.contains($0) && gecerli.contains($0) }
        return .yaz(yol: "cihazlar/\(cihazKimligi(jeton: jeton, tur: "ekip"))", alanlar: [
            "token": .metin(jeton), "tur": .metin("ekip"), "uid": .metin(c.uid), "konular": .dizi(k.map { .metin($0) }),
            "platform": .metin("ios"),
        ], zaman: ["updatedAt"])
    }

    public static func kaydiSil(jeton: String, tur: String) -> FirestoreIstemci.Yazim {
        .sil(yol: "cihazlar/\(cihazKimligi(jeton: jeton, tur: tur))")
    }

    public enum HedefTur: String { case musteri, ekip }

    /// Elle bildirim isteği. Başlık ya da metin boşsa nil.
    public static func istek(hedefTur: HedefTur, hedef: String, hedefAd: String, baslik: String, metin: String,
                             calisan c: Calisan) -> [FirestoreIstemci.Yazim]? {
        let b = baslik.kirpik, m = metin.kirpik
        guard !b.isEmpty, !m.isEmpty, !hedef.isEmpty else { return nil }
        return [
            .olustur(yol: "bildirimIstekleri/\(FirestoreIstemci.yeniKimlik())", alanlar: [
                "hedefTur": .metin(hedefTur.rawValue), "hedef": .metin(String(hedef.prefix(60))),
                "hedefAd": .metin(String(hedefAd.kirpik.prefix(120))),
                "baslik": .metin(String(b.prefix(80))), "metin": .metin(String(m.prefix(500))), "durum": .metin("bekliyor"),
                "createdBy": .metin(c.uid), "byName": .metin(String(c.gorunenAd.prefix(80))),
            ], zaman: ["createdAt"]),
            .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                     alanlar: IslemKaydi.alanlar(eylem: "bildirim.elle", hedef: hedef,
                                                 ayrinti: String("\(hedefTur == .musteri ? "müşteri" : "çalışan"): \(hedefAd) — \(b)".prefix(500)),
                                                 calisan: c), zaman: ["at"]),
        ]
    }

    /// Bildirime dokununca açılacak yer (Bildirim.gs → data.hedef).
    public enum Hedef: Equatable {
        case takip
        case basvuru(String)
        case talep(String)       // "callback/abc"
        case destek(String)
        case kasa
        case bildirimler
        case armut
        case yok

        public init(_ s: String?) {
            let d = s ?? ""
            let (tur, deger) = d.firstIndex(of: ":").map { (String(d[..<$0]), String(d[d.index(after: $0)...])) } ?? (d, "")
            switch tur {
            case "takip": self = .takip
            case "basvuru" where !deger.isEmpty: self = .basvuru(deger)
            case "talep" where deger.hasPrefix("callback/") || deger.hasPrefix("applicationRequests/"): self = .talep(deger)
            case "destek" where !deger.isEmpty: self = .destek(deger)
            case "kasa": self = .kasa
            case "bildirimler": self = .bildirimler
            case "armut": self = .armut
            default: self = .yok
            }
        }
    }
}
