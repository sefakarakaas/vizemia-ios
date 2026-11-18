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

// MARK: - Elle post yükleme (panel: sosyal-liste.js → ellePost; social.upload)

/// Çalışanın kendi görseli ve kanal metinleriyle eklediği post. Günlük görev 1–6.
/// sıraları kullanır; elle postlar 10'dan başlar (kural da şart koşar). Post ve
/// görselleri tek yazımda.
public enum ElleSosyalPost {
    public static let siraEnAz = 10, siraEnCok = 99
    public static let gorselEnCok = 10
    public static let gorselBaytEnCok = 900_000
    public static let toplamBaytEnCok = 7_000_000
    public static let kanalMetinEnCok = 5000, igMetinEnCok = 2200, konuEnCok = 200, kaynakEnCok = 500
    public static let gorselUzantilari = ["image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"]

    public struct Gorsel: Equatable {
        public var tur: String
        public var bayt: Data
        public init(tur: String, bayt: Data) { self.tur = tur; self.bayt = bayt }
    }

    /// Baytlara bakarak görsel türü (gönderici de böyle denetler); tanınmazsa nil.
    public static func gorselTuru(_ d: Data) -> String? {
        let u = [UInt8](d.prefix(12))
        if u.count >= 3 && u[0] == 0xff && u[1] == 0xd8 && u[2] == 0xff { return "image/jpeg" }
        if u.count >= 8 && u.prefix(8) == [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] { return "image/png" }
        if u.count >= 12 && String(bytes: u[0..<4], encoding: .ascii) == "RIFF" && String(bytes: u[8..<12], encoding: .ascii) == "WEBP" { return "image/webp" }
        return nil
    }

    /// O günün dolu sıralarına göre ilk boş sıra (10–99); yer yoksa nil.
    public static func bosSira(_ dolu: [Int]) -> Int? {
        let d = Set(dolu)
        return (siraEnAz...siraEnCok).first { !d.contains($0) }
    }

    /// "VizeMia-Post-NNN-TARİH-tür" (görevle aynı biçim).
    public static func dosyaAdi(no: Int, tarih: String, tur: String) -> String {
        "VizeMia-Post-\(String(format: "%03d", no))-\(tarih)-\(tur)"
    }

    static func kanal(_ metin: String, _ gorseller: [String] = []) -> FSDeger {
        .harita(["metin": .metin(metin), "gorseller": .dizi(gorseller.map { .harita(["dosya": .metin($0)]) }),
                 "durum": .metin("bekliyor"), "paylasildi_tarih": .bos, "paylasan": .bos])
    }

    /// Denetler ve yazımları kurar; hata metni ya da (kimlik, yazımlar).
    public static func olustur(tarih: String, sira: Int?, no: Int, tur: String, konu: String, kaynak: String,
                               instagram: String, x: String, whatsapp: String, gorseller: [Gorsel], calisan c: Calisan)
        -> Result<(id: String, yazimlar: [FirestoreIstemci.Yazim]), PostHatasi> {
        func hata(_ s: String) -> Result<(id: String, yazimlar: [FirestoreIstemci.Yazim]), PostHatasi> { .failure(PostHatasi(mesaj: s)) }
        guard Tr.tarih(tarih) != nil else { return hata("Gün seçin.") }
        guard SosyalPost.turler[tur] != nil else { return hata("Tür seçin.") }
        guard let s = sira, (siraEnAz...siraEnCok).contains(s) else { return hata("Bu güne eklenecek yer kalmadı.") }
        guard (0...999_999).contains(no) else { return hata("Post numarası hesaplanamadı.") }
        let k = konu.kirpik, kay = kaynak.kirpik, ig = instagram.kirpik
        guard !k.isEmpty else { return hata("Konu boş olamaz (panelde kartın başlığı olur).") }
        guard k.count <= konuEnCok else { return hata("Konu en çok \(konuEnCok) karakter olabilir.") }
        guard kay.count <= kaynakEnCok else { return hata("Kaynak en çok \(kaynakEnCok) karakter olabilir.") }
        guard !ig.isEmpty else { return hata("Instagram açıklaması boş olamaz.") }
        guard ig.count <= igMetinEnCok else { return hata("Instagram açıklaması en çok \(igMetinEnCok) karakter olabilir.") }
        guard !gorseller.isEmpty else { return hata("En az bir görsel seçin.") }
        guard gorseller.count <= gorselEnCok else { return hata("En çok \(gorselEnCok) görsel seçilebilir.") }
        var toplam = 0
        for (i, g) in gorseller.enumerated() {
            guard gorselUzantilari[g.tur] != nil else { return hata("\(i + 1). görsel jpg, png ya da webp olmalı.") }
            guard !g.bayt.isEmpty, g.bayt.count <= gorselBaytEnCok else { return hata("\(i + 1). görsel en çok \(gorselBaytEnCok / 1000) KB olmalı.") }
            toplam += g.bayt.count
        }
        guard toplam <= toplamBaytEnCok else { return hata("Görsellerin toplamı en çok \(toplamBaytEnCok / 1_000_000) MB olabilir.") }
        let dosya = dosyaAdi(no: no, tarih: tarih, tur: tur)
        let adlar = gorseller.enumerated().map { "\(dosya)-\($0.offset + 1).\(gorselUzantilari[$0.element.tur] ?? "jpg")" }
        var kanallar: [String: FSDeger] = ["instagram": kanal(ig, adlar)]
        for (ad, id, m) in [("X", "x", x), ("WhatsApp", "whatsapp", whatsapp)] {
            let t = m.kirpik
            if t.isEmpty { continue }
            guard t.count <= kanalMetinEnCok else { return hata("\(ad) metni en çok \(kanalMetinEnCok) karakter olabilir.") }
            kanallar[id] = kanal(t)
        }
        let id = "\(tarih)-\(s)"
        var y: [FirestoreIstemci.Yazim] = [
            .olustur(yol: "posts/\(id)", alanlar: [
                "tarih": .metin(tarih), "sira": .tam(s), "tur": .metin(tur), "no": .tam(no), "dosya": .metin(dosya),
                "konu": .metin(k), "kaynak": .metin(kay), "kanallar": .harita(kanallar),
            ], zaman: ["olusturma"]),
        ]
        for (i, g) in gorseller.enumerated() {
            y.append(.olustur(yol: "posts/\(id)/gorseller/\(adlar[i])", alanlar: ["dosya": .metin(adlar[i]), "tur": .metin(g.tur), "veri": .bayt(g.bayt)]))
        }
        y.append(.olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                          alanlar: IslemKaydi.alanlar(eylem: "social.upload", hedef: id, ayrinti: String(k.prefix(120)), calisan: c), zaman: ["at"]))
        return .success((id, y))
    }
}

public struct PostHatasi: Error, Equatable { public var mesaj: String }
