import Foundation

// Blog ve SSS (panel: pages/content.js). content/{id}; kaydedilince site yayını başlar.
// İçeriğin ana sayfa slaytı (vitrin/icerik-<id>) varsa metni de güncellenir;
// görseli (yüklenen ya da havuzdan) olduğu gibi kalır. Slaytı açıp kapatmak ve
// görselini seçmek Vitrin'den / panelden.

public struct Icerik: Equatable, Identifiable {
    public static let turler: [(id: String, ad: String)] = [("blog", "Blog yazısı"), ("faq", "SSS")]

    public var id: String
    public var tur = "blog"
    public var baslik = ""
    public var slug = ""
    public var ozet = ""
    public var metin = ""
    public var ulke = ""
    public var durum = "draft"
    public var yayinTarihi: Date?
    public var olusma: Date?
    public var olusturan = ""
    public var guncelleme: Date?

    public init(id: String = FirestoreIstemci.yeniKimlik()) { self.id = id }

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        func m(_ k: String) -> String { a[k]?.metinDegeri ?? "" }
        id = kimlik
        tur = m("type"); baslik = m("title"); slug = m("slug"); ozet = m("excerpt"); metin = m("body"); ulke = m("country")
        durum = m("status"); yayinTarihi = a["publishedAt"]?.zamanDegeri; olusma = a["createdAt"]?.zamanDegeri
        olusturan = m("createdBy"); guncelleme = a["updatedAt"]?.zamanDegeri
    }

    public var yayinda: Bool { durum == "published" }
    public var turAdi: String { Self.turler.first { $0.id == tur }?.ad ?? tur }

    /// Sayfa adresi parçası (panel: slugify): Türkçe harfler sadeleşir, geri kalanı "-".
    public static func slug(_ s: String) -> String {
        let tablo: [Character: Character] = ["ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u"]
        let kucuk = String(s.lowercased(with: Tr.yerel).map { tablo[$0] ?? $0 })
        let sade = kucuk.decomposedStringWithCanonicalMapping.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }
        var o = ""
        var tire = false
        for u in sade {
            let c = Character(u)
            if (c >= "a" && c <= "z") || (c >= "0" && c <= "9") { o.append(c); tire = false } else if !tire { o.append("-"); tire = true }
        }
        while o.hasPrefix("-") { o.removeFirst() }
        while o.hasSuffix("-") { o.removeLast() }
        return String(o.prefix(120))
    }

    public var hatalar: [String] {
        var h: [String] = []
        if baslik.kirpik.count < 3 { h.append("Başlık en az 3 karakter olmalı.") }
        if Icerik.slug(slug).isEmpty && Icerik.slug(baslik).isEmpty { h.append("Geçerli bir adres (slug) girin.") }
        if metin.kirpik.isEmpty { h.append("Metin boş olamaz.") }
        return h
    }
}

public enum IcerikIslemi {
    typealias Y = FirestoreIstemci.Yazim

    static func kayit(_ eylem: String, _ hedef: String, _ ayrinti: String, _ c: Calisan) -> Y {
        .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                 alanlar: IslemKaydi.alanlar(eylem: eylem, hedef: hedef, ayrinti: String(ayrinti.prefix(500)), calisan: c), zaman: ["at"])
    }

    /// İçeriği yazar. `yeni`: ilk kayıt (oluşturma alanları şimdi). `slayt`: içeriğin
    /// mevcut ana sayfa slaytı (varsa ve yazılabiliyorsa metni güncellenir).
    /// Yayınlama yetkisi yoksa taslak olarak kaydedilir.
    public static func kaydet(_ i: Icerik, yeni: Bool, yayinlayabilir: Bool, slayt: [String: FSDeger]?, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let durum = yayinlayabilir ? i.durum : "draft"
        let slug = Icerik.slug(i.slug).isEmpty ? Icerik.slug(i.baslik) : Icerik.slug(i.slug)
        var a: [String: FSDeger] = [:]
        a["type"] = .metin(i.tur)
        a["title"] = .metin(String(i.baslik.kirpik.prefix(200)))
        a["slug"] = .metin(slug)
        a["excerpt"] = .metin(String(i.ozet.kirpik.prefix(400)))
        a["body"] = .metin(String(i.metin.prefix(100_000)))
        a["country"] = .metin(i.ulke)
        a["status"] = .metin(durum)
        a["updatedBy"] = .metin(c.uid)
        var zaman = ["updatedAt"]
        if yeni { a["createdBy"] = .metin(c.uid); zaman.append("createdAt") }
        // Yayın tarihi ilk yayında konur, sonra korunur; taslağa dönünce boşalır.
        if durum == "published" {
            if i.yayinTarihi == nil { zaman.append("publishedAt") }
        } else {
            a["publishedAt"] = .bos
        }
        // Düzenlemede yalnız değişen alanlar yazılır: oluşturma alanları (kural
        // "değişmedi" diye bakıyor) okunup geri yazılırsa zaman hassasiyeti kaybolur.
        let icerik: Y = yeni ? .yaz(yol: "content/\(i.id)", alanlar: a, zaman: zaman) : .guncelle(yol: "content/\(i.id)", alanlar: a, zaman: zaman)
        var y: [Y] = [icerik,
                      kayit(yeni ? "content.create" : "content.update", i.id, "\(i.baslik.kirpik) (\(durum))", c)]
        if let s = slayt {
            let blog = i.tur == "blog"
            var d: [String: FSDeger] = [:]
            d["ust"] = .metin(blog ? "Blog" : "Sıkça sorulan sorular")
            d["baslik"] = .metin(String(i.baslik.kirpik.prefix(80)))
            if (s["metin"]?.metinDegeri ?? "").isEmpty { d["metin"] = .metin(String(i.ozet.kirpik.prefix(200))) }
            d["dugme"] = .metin(blog ? "Yazıyı oku" : "Cevabı oku")
            d["link"] = .metin(blog ? "/blog/\(slug)" : "/sss")
            d["ulke"] = .metin(i.ulke)
            d["durum"] = .metin(durum == "published" ? "yayinda" : "taslak")
            d["updatedBy"] = .metin(c.uid)
            y.append(.guncelle(yol: "vitrin/icerik-\(i.id)", alanlar: d, zaman: ["updatedAt"]))
            y.append(kayit("vitrin.update", "icerik-\(i.id)", i.baslik.kirpik, c))
        }
        return y
    }

    /// Kalıcı silme (yayınlama yetkisi); slaytı da silinir.
    public static func sil(_ i: Icerik, slaytVar: Bool, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        var y: [Y] = []
        if slaytVar { y.append(.sil(yol: "vitrin/icerik-\(i.id)")) }
        y.append(.sil(yol: "content/\(i.id)"))
        y.append(kayit("content.delete", i.id, i.baslik, c))
        return y
    }
}
