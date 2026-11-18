import Foundation

// Sosyal medya (panel: pages/sosyal.js, sosyal-ortak.js, sosyal-liste.js).
// Postları günlük görev (sosyal bot) ekler: posts/<YYYY-AA-GG-sıra>; görseller
// posts/<id>/gorseller, Reels videosu posts/<id>/video parçalarında. Çalışan
// her kanal için "paylaştım" işaretler (yalnız o kanalın alanları), Instagram'da
// otomatik paylaşım ister, beğenmediği postu siler, post isteği yazar.

public struct SosyalPost: Equatable, Identifiable {
    public struct Kanal: Equatable {
        public var metin: String
        public var gorseller: [String]
        public var durum: String
        public var paylasildiTarih: Date?
        public var paylasan: String
        public var istekTarih: Date?
        public var isteyen: String
        public var medyaId: String
        public var permalink: String
        public var hata: String
        /// Reels: video dosyası ve parça sayısı.
        public var videoDosya: String
        public var videoParca: Int

        init(_ a: [String: FSDeger]) {
            func m(_ k: String) -> String { a[k]?.metinDegeri ?? "" }
            metin = m("metin")
            gorseller = (a["gorseller"]?.diziDegeri ?? []).compactMap { $0.haritaDegeri?["dosya"]?.metinDegeri }
            durum = m("durum").isEmpty ? "bekliyor" : m("durum")
            paylasildiTarih = a["paylasildi_tarih"]?.zamanDegeri; paylasan = m("paylasan")
            istekTarih = a["istek_tarih"]?.zamanDegeri; isteyen = m("isteyen")
            medyaId = m("medya_id")
            let p = m("permalink")
            permalink = p.eslesir("^https://(www\\.)?instagram\\.com/") ? p : ""
            hata = m("hata")
            let v = a["video"]?.haritaDegeri
            videoDosya = v?["dosya"]?.metinDegeri ?? ""
            videoParca = v?["parca"]?.tamDegeri ?? 0
        }
    }

    public static let kanallar: [(id: String, ad: String, paylastim: String)] = [
        ("instagram", "Instagram", "Instagram'da paylaştım"), ("x", "X", "X'te paylaştım"),
        ("whatsapp", "WhatsApp", "WhatsApp'ta paylaştım"), ("reels", "Reels", "Reels'i paylaştım"),
    ]
    public static let turler = ["haber": "Güncel haber", "bilgi": "Bilgi kartı", "ipucu": "İpucu", "sss": "Sık sorulan",
                                "eglence": "Eğlenceli", "tavsiye": "Tavsiye", "etkinlik": "Yaklaşan etkinlik", "ozelgun": "Özel gün"]
    public static let anaKanal = "instagram"
    public static let otomatikKanal = "instagram"
    public static let videoKanali = "reels"
    /// "Bekleyenler" sekmesindeki (henüz paylaşılmamış) durumlar.
    public static let bekleyenDurumlar = ["bekliyor", "paylasim-bekliyor", "paylasiliyor", "hata"]
    public static let gorselSaklamaGun = 60
    public static let videoSaklamaGun = 30

    public var id: String
    public var tarih: String
    public var sira: Int
    public var tur: String
    public var no: Int?
    public var konu: String
    public var kaynak: String
    public var kanallar: [String: Kanal]

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        id = kimlik
        tarih = a["tarih"]?.metinDegeri ?? ""
        sira = a["sira"]?.tamDegeri ?? 0
        tur = a["tur"]?.metinDegeri ?? ""
        no = a["no"]?.tamDegeri
        konu = a["konu"]?.metinDegeri ?? ""
        kaynak = a["kaynak"]?.metinDegeri ?? ""
        var k: [String: Kanal] = [:]
        for (ad, v) in a["kanallar"]?.haritaDegeri ?? [:] { if let m = v.haritaDegeri { k[ad] = Kanal(m) } }
        kanallar = k
    }

    public var turAdi: String { Self.turler[tur] ?? tur }
    public func durum(_ k: String) -> String { kanallar[k]?.durum ?? "bekliyor" }
    public func paylasilmadi(_ k: String) -> Bool { durum(k) != "paylasildi" }

    /// Kanalın görselleri: kendi görseli yoksa Instagram'ınki.
    public func gorseller(_ k: String) -> [String] {
        if let g = kanallar[k]?.gorseller, !g.isEmpty { return g }
        return kanallar[Self.anaKanal]?.gorseller ?? []
    }

    /// Seçili kanal dışında paylaşıldığı kanallar (kartta "X ✓").
    public func rozetler(_ secili: String) -> [String] {
        Self.kanallar.filter { $0.id != secili && kanallar[$0.id] != nil && durum($0.id) == "paylasildi" }.map(\.ad)
    }

    /// "Instagram'da paylaş" istenebilir mi (kural da aynısını şart koşar).
    public func otomatikIstenebilir(_ k: String) -> Bool {
        guard k == Self.otomatikKanal, let kv = kanallar[k] else { return false }
        return kv.medyaId.isEmpty && ["bekliyor", "hata"].contains(kv.durum)
    }

    /// Otomatik paylaşım sürüyor mu (istendi ya da gönderiliyor): elle işaret kapalı.
    public func otomatikSuruyor(_ k: String) -> Bool { ["paylasim-bekliyor", "paylasiliyor"].contains(durum(k)) }
    public func elleKilitli(_ k: String) -> Bool { otomatikSuruyor(k) || !(kanallar[k]?.medyaId.isEmpty ?? true) }

    /// Görsel saklama süresi geçti mi (görseller silinir, metin kalır).
    public func eski(gun: Int, bugun: String = Tr.bugun()) -> Bool {
        guard let a = Tr.tarih(tarih), let b = Tr.tarih(bugun) else { return false }
        return b.timeIntervalSince(a) / 86_400 > Double(gun)
    }

    /// Seçili kanal ve sekmeye göre: tarih yeniden eskiye, aynı günde sıra küçükten büyüğe.
    public static func suz(_ l: [SosyalPost], kanal: String, paylasilan: Bool) -> [SosyalPost] {
        l.filter { $0.kanallar[kanal] != nil && $0.paylasilmadi(kanal) != paylasilan }
            .sorted { $0.tarih != $1.tarih ? $0.tarih > $1.tarih : $0.sira < $1.sira }
    }

    public static func bekleyenSayilari(_ l: [SosyalPost]) -> [String: Int] {
        var s: [String: Int] = [:]
        for k in kanallar { s[k.id] = l.filter { $0.kanallar[k.id] != nil && $0.paylasilmadi(k.id) }.count }
        return s
    }
}

/// postIstekleri/{id}
public struct PostIstegi: Equatable, Identifiable {
    public var id: String
    public var metin: String
    public var hedefTarih: String
    public var durum: String
    public var isteyen: String
    public var isteyenUid: String
    public var zaman: Date?
    public var yapildiPost: String

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        func m(_ k: String) -> String { a[k]?.metinDegeri ?? "" }
        id = kimlik
        metin = m("metin"); hedefTarih = m("hedefTarih"); durum = m("durum"); isteyen = m("isteyen"); isteyenUid = m("isteyenUid")
        zaman = a["at"]?.zamanDegeri; yapildiPost = m("yapildiPost")
    }

    public static let metinEnCok = 500

    /// Bekleyenler önce (eskiden yeniye: görev de bu sırayla yapar), sonra ötekiler yeniden eskiye.
    public static func sirala(_ l: [PostIstegi]) -> [PostIstegi] {
        let bek = l.filter { $0.durum == "bekliyor" }.sorted { ($0.zaman ?? .distantPast) < ($1.zaman ?? .distantPast) }
        let oteki = l.filter { $0.durum != "bekliyor" }.sorted { ($0.zaman ?? .distantPast) > ($1.zaman ?? .distantPast) }
        return bek + oteki
    }

    /// Yeni isteğin hatası (boş: geçerli).
    public static func hata(metin: String, hedefTarih: String, bugun: String) -> String? {
        let m = metin.kirpik
        if m.isEmpty { return "İstek metni boş olamaz." }
        if m.count > metinEnCok { return "İstek en çok \(metinEnCok) karakter olabilir." }
        if !hedefTarih.isEmpty && Tr.tarih(hedefTarih) == nil { return "Tarih geçersiz." }
        if !hedefTarih.isEmpty && hedefTarih < bugun { return "Geçmiş bir tarih seçilemez." }
        return nil
    }
}

public enum SosyalIslemi {
    typealias Y = FirestoreIstemci.Yazim

    static func kayit(_ eylem: String, _ hedef: String, _ ayrinti: String, _ c: Calisan) -> Y {
        .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                 alanlar: IslemKaydi.alanlar(eylem: eylem, hedef: hedef, ayrinti: String(ayrinti.prefix(500)), calisan: c), zaman: ["at"])
    }

    /// "Paylaştım" / "Geri al": YALNIZ o kanalın durum, paylasildi_tarih, paylasan alanları.
    public static func isaret(_ p: SosyalPost, kanal k: String, paylasildi: Bool, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let y: Y
        if paylasildi {
            y = .derin(yol: "posts/\(p.id)", alanlar: [["kanallar", k, "durum"]: .metin("paylasildi"),
                                                     ["kanallar", k, "paylasan"]: .metin(c.gorunenAd)],
                       zaman: [["kanallar", k, "paylasildi_tarih"]])
        } else {
            y = .derin(yol: "posts/\(p.id)", alanlar: [["kanallar", k, "durum"]: .metin("bekliyor"),
                                                     ["kanallar", k, "paylasildi_tarih"]: .bos, ["kanallar", k, "paylasan"]: .bos])
        }
        return [y, kayit(paylasildi ? "social.share" : "social.undo", p.id, k, c)]
    }

    /// "Instagram'da paylaş": durum, istek_tarih, isteyen.
    public static func instagramIstegi(_ p: SosyalPost, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let k = SosyalPost.otomatikKanal
        return [
            .derin(yol: "posts/\(p.id)", alanlar: [["kanallar", k, "durum"]: .metin("paylasim-bekliyor"),
                                                 ["kanallar", k, "isteyen"]: .metin(c.gorunenAd)],
                   zaman: [["kanallar", k, "istek_tarih"]]),
            kayit("social.instagram", p.id, k, c),
        ]
    }

    /// Post, görselleri ve video parçalarıyla aynı yazmada silinir.
    public static func sil(_ p: SosyalPost, gorseller: [String], videoParcalari: [String], calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        gorseller.map { Y.sil(yol: "posts/\(p.id)/gorseller/\($0)") }
            + videoParcalari.map { Y.sil(yol: "posts/\(p.id)/video/\($0)") }
            + [.sil(yol: "posts/\(p.id)"), kayit("social.delete", p.id, p.konu, c)]
    }

    public static func istek(metin: String, hedefTarih: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.olustur(yol: "postIstekleri/\(FirestoreIstemci.yeniKimlik())", alanlar: [
            "metin": .metin(metin.kirpik), "hedefTarih": .metin(hedefTarih), "durum": .metin("bekliyor"),
            "isteyen": .metin(c.gorunenAd), "isteyenUid": .metin(c.uid),
        ], zaman: ["at"])]
    }

    public static func istekIptal(_ i: PostIstegi, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.guncelle(yol: "postIstekleri/\(i.id)", alanlar: ["durum": .metin("iptal"), "iptalEden": .metin(c.gorunenAd)], zaman: ["iptalAt"])]
    }
}
