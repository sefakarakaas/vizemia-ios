import Foundation

// Başvuru ayrıntısının ek kutuları: ödemeler, verilen fiyat, belgeler,
// konsolosluk takip kodu, pasaport teslim fişi. Panelin karşılıkları:
//   panel/js/basvuru-akisi.js   odemeHatalari, ileriStatu, takip kodu, dosya kuralları
//   panel/js/dosya-yukle.js     dosyaEkle / dosyaSil (Storage yok: Firestore'da parçalar)
//   panel/js/pages/basvuru-ekleri.js  OdemePanel, FiyatBolumu, KonsoloslukTakipPanel
//   panel/js/kasa.js            gelirKaydi (ödemeyle aynı yazmada kasa defterine gelir)

// MARK: - Ödeme

public enum OdemeKurali {
    public static let paraBirimleri = ["TRY", "EUR", "USD", "GBP"]
    public static let yontemler: [(id: String, ad: String)] = [
        ("havale", "Havale / EFT"), ("kart", "Kredi kartı / POS"), ("nakit", "Nakit"), ("diger", "Diğer"),
    ]
    public static func yontemAdi(_ id: String) -> String { yontemler.first { $0.id == id }?.ad ?? id }

    /// Kaydetmeden önce denetim (boş: kaydedilebilir). Dekont zorunlu değil.
    public static func hatalar(tarih: String, tutar: Double?, paraBirimi: String, yontem: String,
                               onayKodu: String, aciklama: String, bugun: String) -> [String] {
        var h: [String] = []
        if !tarih.eslesir("^\\d{4}-\\d{2}-\\d{2}$") { h.append("Ödeme tarihi girin.") }
        else if tarih > bugun { h.append("Ödeme tarihi ileri bir tarih olamaz.") }
        let kod = onayKodu.kirpik
        if !kod.isEmpty && !kod.eslesir("^[A-Za-z0-9 ./_#-]{1,80}$") {
            h.append("Onay kodu yalnız harf, rakam ve - / . _ # içerebilir (en çok 80).")
        }
        if let t = tutar, !(t > 0 && t <= 10_000_000 && t.isFinite) { h.append("Tutar geçersiz.") }
        if !paraBirimleri.contains(paraBirimi) { h.append("Para birimi seçin.") }
        if !yontemler.contains(where: { $0.id == yontem }) { h.append("Ödeme yöntemi seçin.") }
        if aciklama.count > 300 { h.append("Açıklama en çok 300 karakter.") }
        return h
    }

    /// Klavyeden girilen tutar: "2.250,50", "2250,5", "2250.5" → 2250.5; boşsa nil.
    public static func tutarOku(_ s: String) -> Double? {
        var t = s.filter { !$0.isWhitespace }
        if t.isEmpty { return nil }
        if t.contains(",") {
            t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if t.filter({ $0 == "." }).count > 1 {
            t = t.replacingOccurrences(of: ".", with: "")
        }
        return Double(t)
    }

    /// Kuruşa yuvarlanmış tutar; tam sayıysa tam sayı yazılır (panelde de öyle).
    static func tutarDegeri(_ t: Double?) -> FSDeger {
        guard let t else { return .bos }
        let y = (t * 100).rounded() / 100
        return y == y.rounded() && abs(y) < 1e15 ? .tam(Int(y)) : .ondalik(y)
    }

    /// Geçmiş satırındaki sayı ("4500", "12.5").
    public static func sayiYazi(_ t: Double) -> String {
        let y = (t * 100).rounded() / 100
        return y == y.rounded() ? String(Int(y)) : String(y)
    }
}

/// Alınan ödeme (applications/{id}/odemeler).
public struct Odeme: Equatable, Identifiable {
    public var id: String
    public var tarih: String
    public var tutar: Double?
    public var paraBirimi: String
    public var yontem: String
    public var onayKodu: String
    public var aciklama: String
    public var dosyaId: String?
    public var yazan: String
    public var zaman: Date?

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        id = kimlik
        tarih = a["tarih"]?.metinDegeri ?? ""
        switch a["tutar"] {
        case .tam(let n)?: tutar = Double(n)
        case .ondalik(let d)?: tutar = d
        default: tutar = nil
        }
        paraBirimi = a["paraBirimi"]?.metinDegeri ?? ""
        yontem = a["yontem"]?.metinDegeri ?? ""
        onayKodu = a["onayKodu"]?.metinDegeri ?? ""
        aciklama = a["aciklama"]?.metinDegeri ?? ""
        dosyaId = a["dosyaId"]?.metinDegeri
        yazan = a["byName"]?.metinDegeri ?? ""
        zaman = a["at"]?.zamanDegeri
    }

    public var dekontDurumu: String { dosyaId == nil ? "Dekont girilmedi" : "Dekont var" }
}

/// Müşteriye verilen fiyat (private/fiyat).
public struct Fiyat: Equatable {
    public var tutar: Double
    public var paraBirimi: String
    public var aciklama: String
    public var yazan: String
    public var zaman: Date?

    public init?(alanlar a: [String: FSDeger]?) {
        guard let a else { return nil }
        switch a["tutar"] {
        case .tam(let n)?: tutar = Double(n)
        case .ondalik(let d)?: tutar = d
        default: return nil
        }
        paraBirimi = a["paraBirimi"]?.metinDegeri ?? "TRY"
        aciklama = a["aciklama"]?.metinDegeri ?? ""
        yazan = a["byName"]?.metinDegeri ?? ""
        zaman = a["updatedAt"]?.zamanDegeri
    }
}

// MARK: - Dosyalar

/// Başvuru belgesi bilgisi (applications/{id}/dosyalar); baytlar dosyaIcerik'te parça parça.
public struct DosyaBilgisi: Equatable, Identifiable {
    public var id: String
    public var tur: String
    public var ad: String
    public var mime: String
    public var boyut: Int
    public var parca: Int
    public var yazan: String
    public var zaman: Date?

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        id = kimlik
        tur = a["tur"]?.metinDegeri ?? ""
        ad = a["ad"]?.metinDegeri ?? "belge"
        mime = a["mime"]?.metinDegeri ?? ""
        boyut = a["boyut"]?.tamDegeri ?? 0
        parca = max(1, a["parca"]?.tamDegeri ?? 1)
        yazan = a["byName"]?.metinDegeri ?? ""
        zaman = a["at"]?.zamanDegeri
    }

    public var turAdi: String { Dosya.turAdlari[tur] ?? tur }
    public var pdf: Bool { mime == "application/pdf" }
    /// Parçaların yolları (sırayla).
    public func parcaYollari(ust: String) -> [String] { (0..<parca).map { "\(ust)/dosyaIcerik/\(id)_\($0)" } }
}

/// Yüklenecek dosya: hazırlanmış (küçültülmüş) baytlar.
public struct HazirDosya: Equatable {
    public var ad: String
    public var mime: String
    public var bayt: Data
    public init(ad: String, mime: String, bayt: Data) { self.ad = ad; self.mime = mime; self.bayt = bayt }
}

public enum Dosya {
    public static let turAdlari = ["randevu": "Randevu kağıdı", "odeme": "Dekont / slip", "takip": "Pasaport teslim fişi",
                                   "diger": "Diğer belge", "fis": "Fiş / makbuz"]
    public static let mimeler = ["application/pdf", "image/jpeg", "image/png", "image/webp"]
    public static let parcaBoyutu = 900_000
    public static let enCokParca = 6
    public static var enCok: Int { parcaBoyutu * enCokParca }
    /// Bundan büyük belge yüklenirken küçültülür.
    public static let kucultmeSiniri = 5_000_000

    /// Yüklenecek dosyanın sorunu (boş: uygun).
    public static func sorun(mime: String, boyut: Int) -> String {
        if !mimeler.contains(mime) { return "Yalnız PDF ya da fotoğraf (JPEG, PNG, WebP) yüklenebilir." }
        if boyut == 0 { return "Dosya boş." }
        if boyut > enCok { return "Dosya küçültüldükten sonra da 5 MB'tan büyük; daha az sayfalı ya da daha düşük çözünürlüklü bir kopya yükleyin." }
        return ""
    }

    /// Güvenli dosya adı (indirme için).
    public static func adTemizle(_ ad: String, yedek: String = "belge") -> String {
        let t = String(ad.precomposedStringWithCanonicalMapping.degistir("[\\\\/:*?\"<>|\\u0000-\\u001f]+", "-").kirpik.prefix(120))
        return t.isEmpty ? yedek : t
    }

    public static func boyutYazi(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1f MB", Double(n) / 1e6).replacingOccurrences(of: ".", with: ",")
            : "\(max(1, Int((Double(n) / 1e3).rounded()))) KB"
    }

    /// Bilgi ve parçaların yazımları (aynı yazmada eklenir; kurallar böyle istiyor).
    /// `ust`: "applications/<id>" ya da "kasa/<id>".
    public static func ekle(ust: String, tur: String, dosya: HazirDosya, calisan c: Calisan, kimlik: String = FirestoreIstemci.yeniKimlik())
        -> (id: String, yazimlar: [FirestoreIstemci.Yazim]) {
        var y: [FirestoreIstemci.Yazim] = []
        var i = 0, bas = 0
        while bas < dosya.bayt.count {
            let son = min(bas + parcaBoyutu, dosya.bayt.count)
            y.append(.olustur(yol: "\(ust)/dosyaIcerik/\(kimlik)_\(i)", alanlar: [
                "dosyaId": .metin(kimlik), "sira": .tam(i), "veri": .bayt(dosya.bayt.subdata(in: bas..<son)),
            ]))
            i += 1; bas = son
        }
        y.append(.olustur(yol: "\(ust)/dosyalar/\(kimlik)", alanlar: [
            "tur": .metin(tur), "ad": .metin(String(dosya.ad.prefix(120))), "mime": .metin(dosya.mime),
            "boyut": .tam(dosya.bayt.count), "parca": .tam(i),
            "by": .metin(c.uid), "byName": .metin(String(c.gorunenAd.prefix(80))),
        ], zaman: ["at"]))
        return (kimlik, y)
    }

    /// Parçaları ve bilgiyi siler.
    public static func sil(ust: String, _ d: DosyaBilgisi) -> [FirestoreIstemci.Yazim] {
        d.parcaYollari(ust: ust).map { .sil(yol: $0) } + [.sil(yol: "\(ust)/dosyalar/\(d.id)")]
    }

    /// Parça belgelerinden dosyanın baytları (sırayla); eksik parça varsa nil.
    public static func birlestir(_ parcalar: [[String: FSDeger]?]) -> Data? {
        var d = Data()
        for p in parcalar {
            guard let v = p?["veri"]?.baytDegeri else { return nil }
            d.append(v)
        }
        return d
    }
}

// MARK: - Konsolosluk takip kodu

public enum KonsoloslukKodu {
    /// Boşlukları atar, büyük harf yapar.
    public static func temizle(_ s: String) -> String { s.kirpik.filter { !$0.isWhitespace }.uppercased() }
    public static func gecerli(_ s: String) -> Bool { s.eslesir("^[A-Za-z0-9][A-Za-z0-9/._-]{2,59}$") }
}

// MARK: - Otomatik statü

extension Basvuru {
    /// Hedef statü yalnız ileriyse (başvuru zaten orada ya da ilerideyse, son adımdaysa nil).
    public func ileriStatu(_ statuler: [Statu], hedefId: String) -> Statu? {
        guard let hedef = statuler.first(where: { $0.id == hedefId }), !hedef.son else { return nil }
        guard let simdiki = statuler.first(where: { $0.id == statuId }) else { return hedef }
        if simdiki.id == hedef.id || simdiki.son { return nil }
        return simdiki.sira < hedef.sira ? hedef : nil
    }
}

// MARK: - Yazımlar

extension BasvuruIslemi {
    static func ust(_ b: Basvuru) -> String { "applications/\(b.kimlik)" }

    public struct OdemeGirdisi: Equatable {
        public var tarih: String
        public var tutar: Double?
        public var paraBirimi: String
        public var yontem: String
        public var onayKodu: String
        public var aciklama: String
        public init(tarih: String, tutar: Double?, paraBirimi: String, yontem: String, onayKodu: String, aciklama: String) {
            self.tarih = tarih; self.tutar = tutar; self.paraBirimi = paraBirimi; self.yontem = yontem
            self.onayKodu = onayKodu; self.aciklama = aciklama
        }
    }

    public struct OdemeSonucu {
        public var yazimlar: [FirestoreIstemci.Yazim]
        public var odemeId: String
        /// Ödemeyle birlikte geçilen statü ("Randevu Takipte"), yoksa nil.
        public var statu: Statu?
    }

    /// "Ödemeyi kaydet": (dekont) + ödeme + kasa defterine gelir + sayaç
    /// (+ yetki ve anahtar varsa "Randevu Takipte"ye geçiş, takip sayfası) + geçmiş + işlem kaydı.
    public static func odeme(
        _ b: Basvuru, _ o: OdemeGirdisi, dekont: HazirDosya?, statuler: [Statu], statuDegistirir: Bool,
        takipId: String?, acikNotlar: [BasvuruNotu], saklamaGun: Int, calisan c: Calisan, simdi: Date = Date()
    ) -> OdemeSonucu {
        var y: [FirestoreIstemci.Yazim] = []
        var dosyaId: String?
        if let d = dekont {
            let r = Dosya.ekle(ust: ust(b), tur: "odeme", dosya: d, calisan: c)
            y += r.yazimlar
            dosyaId = r.id
        }
        let odemeId = FirestoreIstemci.yeniKimlik()
        let tutar = OdemeKurali.tutarDegeri(o.tutar)
        let ad = String(c.gorunenAd.prefix(80))
        y.append(.olustur(yol: "\(ust(b))/odemeler/\(odemeId)", alanlar: [
            "tarih": .metin(o.tarih), "tutar": tutar, "paraBirimi": .metin(o.paraBirimi), "yontem": .metin(o.yontem),
            "onayKodu": .metin(String(o.onayKodu.kirpik.prefix(80))), "aciklama": .metin(String(o.aciklama.kirpik.prefix(300))),
            "dosyaId": dosyaId.map { .metin($0) } ?? .bos, "by": .metin(c.uid), "byName": .metin(ad),
        ], zaman: ["at"]))
        // Kasa defteri: aynı kimlikle gelir satırı (başvuru silinse de kalır).
        y.append(.olustur(yol: "kasa/\(odemeId)", alanlar: [
            "tur": .metin("gelir"), "kapsam": .metin("musteri"), "kategori": .metin("Müşteri ödemesi"),
            "tutar": tutar, "paraBirimi": .metin(o.paraBirimi), "yontem": .metin(o.yontem), "tarih": .metin(o.tarih),
            "aciklama": .metin(String(o.aciklama.kirpik.prefix(300))), "appId": .metin(b.kimlik),
            "takipKodu": .metin(b.takipKodu), "musteriAd": .metin(String("\(b.ad) \(b.soyad)".kirpik.prefix(160))),
            "odemeId": .metin(odemeId), "by": .metin(c.uid), "byName": .metin(ad), "iptal": .mantik(false),
        ], zaman: ["at"]))
        var alanlar: [String: FSDeger] = [
            "odemeSayisi": .tam(b.odemeSayisi + 1), "sonOdemeId": .metin(odemeId), "updatedBy": .metin(c.uid),
        ]
        var zaman = ["updatedAt"]
        // Ödeme girilince başvuru kendiliğinden "Randevu Takipte"ye geçer (yalnız ileri).
        var statu: Statu?
        if statuDegistirir, let t = takipId, let hedef = b.ileriStatu(statuler, hedefId: "randevu-takip") {
            var sonra = b
            sonra.odemeSayisi += 1
            if sonra.gecisEngelleri(hedef).isEmpty {
                let g = b.statuGecisi(hedef, saklamaGun: saklamaGun, simdi: simdi)
                alanlar.merge(g.alanlar) { $1 }
                zaman += g.zaman
                y.append(gecmis(b, tur: "status", metin: "\(b.statuAdi.isEmpty ? "—" : b.statuAdi) → \(hedef.ad) (ödeme alındı, otomatik)",
                                statu: hedef, c))
                y.append(takip(t, b, hedef, statuler, acikNotlar, simdi))
                statu = hedef
            }
        }
        y.append(.guncelle(yol: ust(b), alanlar: alanlar, zaman: zaman))
        let tutarYazi = o.tutar.map { " · \(OdemeKurali.sayiYazi($0)) \(o.paraBirimi)" } ?? ""
        let kod = o.onayKodu.kirpik.isEmpty ? "" : " · onay \(o.onayKodu.kirpik)"
        y.append(gecmis(b, tur: "odeme", metin: "Ödeme girildi: \(o.tarih)\(tutarYazi) · \(OdemeKurali.yontemAdi(o.yontem))\(kod)"
                        + (dekont == nil ? " · dekont girilmedi" : " · dekont eklendi"), c))
        y.append(kayit("app.odeme", b, "\(o.tarih) \(o.tutar.map { OdemeKurali.sayiYazi($0) } ?? "") \(o.paraBirimi)".kirpik, c))
        return OdemeSonucu(yazimlar: y, odemeId: odemeId, statu: statu)
    }

    /// Dekontu girilmemiş ödemeye sonradan dekont (bir kez).
    public static func sonradanDekont(_ b: Basvuru, _ o: Odeme, dekont: HazirDosya, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let r = Dosya.ekle(ust: ust(b), tur: "odeme", dosya: dekont, calisan: c)
        let tutarYazi = o.tutar.map { " · \(OdemeKurali.sayiYazi($0)) \(o.paraBirimi)" } ?? ""
        return r.yazimlar + [
            .guncelle(yol: "\(ust(b))/odemeler/\(o.id)", alanlar: [
                "dosyaId": .metin(r.id), "dekontBy": .metin(c.uid), "dekontByName": .metin(String(c.gorunenAd.prefix(80))),
            ], zaman: ["dekontAt"]),
            gecmis(b, tur: "odeme", metin: "Dekont sonradan eklendi: \(o.tarih)\(tutarYazi)", c),
            kayit("app.dekont", b, o.id, c),
        ]
    }

    /// Müşteriye verilen fiyat (her değişiklik geçmişe yazılır).
    public static func fiyat(_ b: Basvuru, tutar: Double, paraBirimi: String, aciklama: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let t = (tutar * 100).rounded() / 100
        let a = String(aciklama.kirpik.prefix(300))
        return [
            .yaz(yol: "\(ust(b))/private/fiyat", alanlar: [
                "tutar": OdemeKurali.tutarDegeri(t), "paraBirimi": .metin(paraBirimi), "aciklama": .metin(a),
                "byName": .metin(String(c.gorunenAd.prefix(80))), "updatedBy": .metin(c.uid),
            ], zaman: ["updatedAt"]),
            gecmis(b, tur: "fiyat", metin: "Fiyat verildi: \(OdemeKurali.sayiYazi(t)) \(paraBirimi)\(a.isEmpty ? "" : " · \(a)")", c),
            kayit("app.fiyat", b, "\(OdemeKurali.sayiYazi(t)) \(paraBirimi)", c),
        ]
    }

    /// Konsolosluk / aracı kurum takip kodu (boş: silinir).
    public static func konsolosluk(_ b: Basvuru, kod: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let k = KonsoloslukKodu.temizle(kod)
        var alanlar: [String: FSDeger] = ["konsTakipKodu": .metin(k), "updatedBy": .metin(c.uid)]
        if k.isEmpty { alanlar["konsTakipTarih"] = .bos }
        return [
            .guncelle(yol: ust(b), alanlar: alanlar, zaman: k.isEmpty ? ["updatedAt"] : ["konsTakipTarih", "updatedAt"]),
            gecmis(b, tur: "konsTakip", metin: k.isEmpty ? "Konsolosluk takip kodu silindi" : "Konsolosluk takip kodu: \(k)", c),
            kayit("app.konsTakip", b, k, c),
        ]
    }

    /// Belge ekle (randevu kağıdı dışındakiler: pasaport teslim fişi, diğer belge).
    public static func belge(_ b: Basvuru, tur: String, dosya: HazirDosya, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        Dosya.ekle(ust: ust(b), tur: tur, dosya: dosya, calisan: c).yazimlar + [
            gecmis(b, tur: "dosya", metin: "Belge eklendi: \(Dosya.turAdlari[tur] ?? tur) — \(dosya.ad)", c),
        ] + (tur == "takip" ? [] : [kayit("app.dosya", b, "\(tur): \(dosya.ad)", c)])
    }

    public static func belgeSil(_ b: Basvuru, _ d: DosyaBilgisi, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        Dosya.sil(ust: ust(b), d) + [gecmis(b, tur: "dosya", metin: "Belge silindi: \(d.turAdi) — \(d.ad)", c)]
    }

    /// Pasaport teslim fişinden sonra "Konsoloslukta İşlemde"ye geçiş (yalnız ileri).
    /// Statünün öteki şartları eksikse engel metni döner, yazım yok.
    public static func fisSonrasi(
        _ b: Basvuru, statuler: [Statu], takipId: String, acikNotlar: [BasvuruNotu], evrakTamam: Bool,
        saklamaGun: Int, calisan c: Calisan, simdi: Date = Date()
    ) -> (yazimlar: [FirestoreIstemci.Yazim], statu: Statu?, engel: String) {
        guard let hedef = b.ileriStatu(statuler, hedefId: "konsoloslukta") else { return ([], nil, "") }
        let engel = Basvuru.gecisMesaji(hedef, b.gecisEngelleri(hedef, evrakTamam: evrakTamam, fisVar: true))
        if !engel.isEmpty { return ([], nil, engel) }
        let g = b.statuGecisi(hedef, saklamaGun: saklamaGun, simdi: simdi)
        return ([
            .guncelle(yol: ust(b), alanlar: g.alanlar.merging(["updatedBy": .metin(c.uid)]) { $1 }, zaman: g.zaman + ["updatedAt"]),
            gecmis(b, tur: "status", metin: "\(b.statuAdi.isEmpty ? "—" : b.statuAdi) → \(hedef.ad) (pasaport teslim fişi alındı, otomatik)",
                   statu: hedef, c),
            takip(takipId, b, hedef, statuler, acikNotlar, simdi),
            kayit("app.status", b, "\(b.statuAdi) → \(hedef.ad) (fiş)", c),
        ], hedef, "")
    }
}
