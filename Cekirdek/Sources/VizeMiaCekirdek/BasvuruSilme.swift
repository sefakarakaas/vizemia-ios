import Foundation

// Saklama süresi ve elle silme (yalnız yönetici).
// Panel karşılıkları: applications.js → "Saklama süresi" kutusu ve deleteApplication,
// musteri-arsivi.js → arsivKaydi. Silinen başvurudan müşteri arşivinde yalnız ad
// soyad, telefon, e-posta, ülke/sonuç, işlem geçmişi, verilen fiyat, ödemeler ve
// harcamalar kalır; TCKN, pasaport, adres, form cevapları ve belgeler silinir.
// Kural: musteriArsivi yalnız başvuru AYNI yazımda silinirken kabul edilir.

public enum BasvuruSilme {
    static let islemEnCok = 300
    static let odemeEnCok = 100
    static let anahtarEnCok = 20

    /// Silmeden önce okunan her şey (alt koleksiyonlar panelle aynı sınırlarla).
    public struct Okunan {
        public var basvuru: [String: FSDeger]
        public var form: [String: FSDeger]
        public var anahtar: (takipId: String, pasaportOzeti: String)?
        public var loglar: [FirestoreIstemci.Belge]
        public var notlar: [String]
        public var ustNotlar: [String]
        /// Dosya kimliği ve parça sayısı (baytlar okunmadan silinir).
        public var dosyalar: [(id: String, parca: Int)]
        public var odemeler: [FirestoreIstemci.Belge]
        public var fiyat: [String: FSDeger]?
        public var giderler: [[String: FSDeger]]
        public var bildirimler: [String]

        public init(basvuru: [String: FSDeger], form: [String: FSDeger], anahtar: (takipId: String, pasaportOzeti: String)?,
                    loglar: [FirestoreIstemci.Belge], notlar: [String], ustNotlar: [String], dosyalar: [(id: String, parca: Int)],
                    odemeler: [FirestoreIstemci.Belge], fiyat: [String: FSDeger]?, giderler: [[String: FSDeger]], bildirimler: [String]) {
            self.basvuru = basvuru; self.form = form; self.anahtar = anahtar; self.loglar = loglar; self.notlar = notlar
            self.ustNotlar = ustNotlar; self.dosyalar = dosyalar; self.odemeler = odemeler; self.fiyat = fiyat
            self.giderler = giderler; self.bildirimler = bildirimler
        }
    }

    static func kisalt(_ d: FSDeger?, _ n: Int) -> String {
        switch d {
        case .metin(let s)?: return String(s.kirpik.prefix(n))
        case .tam(let t)?: return String(String(t).prefix(n))
        default: return ""
        }
    }

    /// Sayıysa iki haneye yuvarlanır, değilse nil (panel: sayi).
    static func sayi(_ d: FSDeger?) -> Double? {
        switch d {
        case .tam(let t)?: return Double(t)
        case .ondalik(let v)? where v.isFinite: return (v * 100).rounded() / 100
        default: return nil
        }
    }

    static func sayiDegeri(_ v: Double?) -> FSDeger {
        guard let v else { return .bos }
        return v == v.rounded() && abs(v) < 1e15 ? .tam(Int(v)) : .ondalik(v)
    }

    static func zaman(_ d: FSDeger?) -> Date { d?.zamanDegeri ?? .distantPast }

    /// Para birimine göre toplam (panel: odemeToplami).
    static func toplam(_ l: [(Double?, String)]) -> [String: FSDeger] {
        var t: [String: Double] = [:]
        for (v, p) in l { guard let v, !p.isEmpty else { continue }; t[p] = (((t[p] ?? 0) + v) * 100).rounded() / 100 }
        return t.mapValues { sayiDegeri($0) }
    }

    /// Arama anahtarları: ad, soyad (kelime kelime), ad soyad, telefon, e-posta (panel: arsivAnahtarlari).
    public static func anahtarlar(ad: String, soyad: String, telefon: String, eposta: String) -> [String] {
        let a = MusteriArsivi.kucuk(ad), s = MusteriArsivi.kucuk(soyad)
        var l: [String] = []
        for x in a.components(separatedBy: " ") + s.components(separatedBy: " ") + ["\(a) \(s)".kirpik, telefon, eposta]
        where !x.isEmpty && !l.contains(x) { l.append(x) }
        return Array(l.prefix(anahtarEnCok))
    }

    static func eposta(_ s: String) -> String {
        let e = s.kirpik.lowercased()
        return e.eslesir("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$") ? String(e.prefix(120)) : ""
    }

    /// Arşiv belgesi (panel: arsivKaydi, silmeTuru 'manuel'). `silinme` sunucu zamanıyla yazılır.
    public static func arsivKaydi(_ o: Okunan, calisan c: Calisan) -> [String: FSDeger] {
        let b = o.basvuru, f = o.form
        let ad = kisalt(b["firstName"]?.metinDegeri?.isEmpty == false ? b["firstName"] : f["firstName"], 80)
        let soyad = kisalt(b["lastName"]?.metinDegeri?.isEmpty == false ? b["lastName"] : f["lastName"], 80)
        let telefon = MusteriArsivi.telefon(f["phone"]?.metinDegeri ?? "")
        let ep = eposta(f["email"]?.metinDegeri ?? "")
        let islemler: [FSDeger] = o.loglar.map(\.alanlar).sorted { zaman($0["at"]) > zaman($1["at"]) }.prefix(islemEnCok).map { l in
            .harita(["tur": .metin(kisalt(l["type"], 30)), "metin": .metin(kisalt(l["text"], 500)), "statu": .metin(kisalt(l["statusName"], 60)),
                     "kim": .metin(kisalt(l["byName"], 80)), "at": l["at"] ?? .bos])
        }
        let odemeler = o.odemeler.map(\.alanlar).sorted {
            let x = kisalt($0["tarih"], 10), y = kisalt($1["tarih"], 10)
            return x != y ? x > y : zaman($0["at"]) > zaman($1["at"])
        }.prefix(odemeEnCok)
        let odemeListesi: [FSDeger] = odemeler.map { p in
            .harita(["tarih": .metin(kisalt(p["tarih"], 10)), "tutar": sayiDegeri(sayi(p["tutar"])), "paraBirimi": .metin(kisalt(p["paraBirimi"], 3)),
                     "yontem": .metin(kisalt(p["yontem"], 20)), "onayKodu": .metin(kisalt(p["onayKodu"], 80)),
                     "aciklama": .metin(kisalt(p["aciklama"], 300)), "dekontVardi": .mantik(!(p["dosyaId"]?.metinDegeri ?? "").isEmpty),
                     "kim": .metin(kisalt(p["byName"], 80)), "at": p["at"] ?? .bos])
        }
        let giderler = o.giderler.filter { $0["tur"]?.metinDegeri == "gider" && $0["iptal"]?.mantikDegeri != true }
            .sorted { kisalt($0["tarih"], 10) > kisalt($1["tarih"], 10) }.prefix(odemeEnCok)
        let giderListesi: [FSDeger] = giderler.map { g in
            .harita(["tarih": .metin(kisalt(g["tarih"], 10)), "kategori": .metin(kisalt(g["kategori"], 60)), "tutar": sayiDegeri(sayi(g["tutar"])),
                     "paraBirimi": .metin(kisalt(g["paraBirimi"], 3)), "yontem": .metin(kisalt(g["yontem"], 20)),
                     "aciklama": .metin(kisalt(g["aciklama"], 300)), "kim": .metin(kisalt(g["byName"], 80))])
        }
        var fiyat: FSDeger = .bos
        if let p = o.fiyat, let t = sayi(p["tutar"]) {
            fiyat = .harita(["tutar": sayiDegeri(t), "paraBirimi": .metin(kisalt(p["paraBirimi"], 3)), "aciklama": .metin(kisalt(p["aciklama"], 300))])
        }
        return [
            "ad": .metin(ad), "soyad": .metin(soyad), "telefon": .metin(String(telefon.prefix(20))), "eposta": .metin(ep),
            "kampanyaIzni": .mantik(f["kampanyaIzni"]?.mantikDegeri == true),
            "anahtarlar": .dizi(anahtarlar(ad: ad, soyad: soyad, telefon: telefon, eposta: ep).map { .metin($0) }),
            "ulke": .metin(kisalt(b["country"], 40)), "ulkeAdi": .metin(kisalt(b["countryName"], 60)),
            "takipKodu": .metin(kisalt(b["trackingCode"], 20)),
            "sonStatuId": .metin(kisalt(b["statusId"], 60)), "sonStatu": .metin(kisalt(b["statusName"], 60)),
            "acilis": b["openedAt"].flatMap { $0.zamanDegeri == nil ? nil : $0 } ?? b["createdAt"] ?? .bos,
            "sonuclanma": b["finalAt"] ?? .bos, "randevu": b["appointmentAt"] ?? .bos, "seyahat": b["travelAt"] ?? .bos,
            "konsTakipKodu": .metin(kisalt(b["konsTakipKodu"], 60)),
            "fiyat": fiyat,
            "odemeler": .dizi(odemeListesi),
            "odemeToplam": .harita(toplam(odemeler.map { (sayi($0["tutar"]), kisalt($0["paraBirimi"], 3)) })),
            "giderler": .dizi(giderListesi),
            "giderToplam": .harita(toplam(giderler.map { (sayi($0["tutar"]), kisalt($0["paraBirimi"], 3)) })),
            "islemler": .dizi(islemler),
            "silmeTuru": .metin("manuel"), "silen": .metin(String(c.uid.prefix(60))), "silenAd": .metin(String(c.gorunenAd.prefix(80))),
        ]
    }

    /// Başvuruyu ve bütün kişisel verisini siler, arşiv kaydını aynı yazımda yazar
    /// (panel: deleteApplication). İşlem kaydı da aynı yazımda.
    public static func sil(_ kimlik: String, _ o: Okunan, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let yol = "applications/\(kimlik)"
        var y: [FirestoreIstemci.Yazim] = [
            .olustur(yol: "musteriArsivi/\(kimlik)", alanlar: arsivKaydi(o, calisan: c), zaman: ["silinme"]),
        ]
        y += o.loglar.prefix(150).map { .sil(yol: "\(yol)/log/\($0.kimlik)") }
        y += o.notlar.prefix(150).map { .sil(yol: "\(yol)/notes/\($0)") }
        y += o.ustNotlar.prefix(50).map { .sil(yol: "\(yol)/ustNotlar/\($0)") }
        for d in o.dosyalar.prefix(40) {
            for i in 0..<max(1, d.parca) { y.append(.sil(yol: "\(yol)/dosyaIcerik/\(d.id)_\(i)")) }
            y.append(.sil(yol: "\(yol)/dosyalar/\(d.id)"))
        }
        y += o.odemeler.prefix(50).map { .sil(yol: "\(yol)/odemeler/\($0.kimlik)") }
        for p in ["data", "keys", "passport", "mektup", "fiyat"] { y.append(.sil(yol: "\(yol)/private/\(p)")) }
        y += o.bildirimler.map { .sil(yol: "bildirimler/\($0)") }
        if let a = o.anahtar {
            y.append(.sil(yol: "takip/\(a.takipId)"))
            // Müşteri formu aynı anahtarla duruyor (ad, iş yeri, adres gibi cevaplar).
            y.append(.sil(yol: "formlar/\(a.takipId)"))
            y.append(.diziden(yol: "lookup/\(a.pasaportOzeti)", alan: "apps", degerler: [.metin(kimlik)]))
        }
        y.append(.sil(yol: yol))
        let b = o.basvuru
        let ozet = "\(kisalt(b["firstName"], 80)) \(kisalt(b["lastName"], 80)) · \(kisalt(b["countryName"], 60)) · \(kisalt(b["trackingCode"], 20))"
        y.append(.olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                          alanlar: IslemKaydi.alanlar(eylem: "app.delete", hedef: kimlik,
                                                      ayrinti: String("\(ozet) — elle silindi, müşteri arşivine alındı".prefix(500)), calisan: c),
                          zaman: ["at"]))
        return y
    }

    /// Saklama süresi: silinme günü (Türkiye 03.00), bekletme, gerekçe (panel: "Saklama süresi").
    /// Gün boşsa mevcut tarih korunur. Gerekçe zorunlu.
    public static func saklama(_ b: Basvuru, gun: String, bekletme: Bool, gerekce: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim]? {
        let g = gerekce.kirpik
        guard !g.isEmpty else { return nil }
        let tarih: Date? = Tr.tarih(gun) != nil ? BildirimZamani.an(gun, saat: 3) : b.silinecek
        let metin = "Saklama: \(tarih.map { Tr.kisaTarih($0) } ?? "—")\(bekletme ? " (bekletme açık)" : "") — \(g)"
        return [
            .guncelle(yol: "applications/\(b.kimlik)", alanlar: [
                "deleteAfter": tarih.map { .zaman($0) } ?? .bos, "legalHold": .mantik(bekletme),
                "retentionNote": .metin(String(g.prefix(500))), "updatedBy": .metin(c.uid),
            ], zaman: ["updatedAt"]),
            BasvuruIslemi.gecmis(b, tur: "retention", metin: String(metin.prefix(500)), c),
            BasvuruIslemi.kayit("app.retention", b, String(g.prefix(500)), c),
        ]
    }
}
