import Foundation

/// Pasaport kontrolü sonucu (applications/{id}/private/passport).
/// Panel: panel/js/pages/passport-scan.js. Yalnız sonuç saklanır; MRZ metni ve
/// fotoğraf hiçbir yere yazılmaz (fotoğraf telefonda okunur, bellekte kalır).
public struct PasaportKontrolu: Equatable {
    public enum Durum: String, CaseIterable {
        case otomatik = "auto"
        case danisman = "manual"
        case uyusmuyor = "mismatch"

        /// Panelin VERDICT sözlüğü; geçmiş satırında da bu metin yazılır.
        public var ad: String {
            switch self {
            case .otomatik: return "Otomatik onaylandı"
            case .danisman: return "Danışman onayladı"
            case .uyusmuyor: return "Uyuşmuyor"
            }
        }
    }

    public var durumKodu: String
    public var uyusmayanlar: [String]
    public var bakilanlar: [String]
    public var zaman: Date?
    public var yapan: String
    public var onaylayan: String
    public var onayZamani: Date?

    public var durum: Durum? { Durum(rawValue: durumKodu) }
    public var durumAdi: String { durum?.ad ?? durumKodu }

    public init(alanlar a: [String: FSDeger]) {
        durumKodu = a["status"]?.metinDegeri ?? ""
        uyusmayanlar = (a["mismatches"]?.diziDegeri ?? []).compactMap { $0.metinDegeri }
        bakilanlar = (a["checked"]?.diziDegeri ?? []).compactMap { $0.metinDegeri }
        zaman = a["at"]?.zamanDegeri
        yapan = a["byName"]?.metinDegeri ?? ""
        onaylayan = a["approvedByName"]?.metinDegeri ?? ""
        onayZamani = a["approvedAt"]?.zamanDegeri
    }
}

/// Karşılaştırmanın özeti: panelde düğmeyi (otomatik / elle) bu belirler.
public struct PasaportDegerlendirmesi: Equatable {
    public var satirlar: [Mrz.Karsilastirma]
    /// 44 karakter olmayan satırlar (1 ya da 2) ve uzunlukları.
    public var yanlisUzunluk: [(satir: Int, uzunluk: Int)]
    public var sonuc: Mrz.Sonuc
    /// Okuma kusursuz ve formdaki her dolu alan pasaportla aynı.
    public var hepsiUyuyor: Bool
    /// Pasaportta okunup formdakiyle aynı çıkmayan alanların etiketleri.
    public var uyusmayanlar: [String]
    public var guvenilmez: Bool { !yanlisUzunluk.isEmpty || !sonuc.tamam }

    public static func == (l: Self, r: Self) -> Bool {
        l.satirlar == r.satirlar && l.sonuc == r.sonuc && l.hepsiUyuyor == r.hepsiUyuyor
            && l.uyusmayanlar == r.uyusmayanlar && l.yanlisUzunluk.map { [$0.satir, $0.uzunluk] } == r.yanlisUzunluk.map { [$0.satir, $0.uzunluk] }
    }

    /// Panel: compare(). Satırlar elle düzeltilmiş olabilir; boş satırlar atlanır.
    public static func degerlendir(metin: String, form: [String: String], simdi: Date = Date()) -> PasaportDegerlendirmesi? {
        let satirlar = metin.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard satirlar.count >= 2 else { return nil }
        var yanlis: [(satir: Int, uzunluk: Int)] = []
        for (i, s) in satirlar.prefix(2).enumerated() where s.count != 44 { yanlis.append((i + 1, s.count)) }
        let sonuc = Mrz.coz(satirlar[0], satirlar[1], simdi: simdi)
        let k = Mrz.karsilastir(sonuc.alanlar, form: form)
        let hepsi = sonuc.tamam && yanlis.isEmpty && k.allSatisfy { $0.uyuyor || ($0.eksik && $0.mrz.isEmpty) }
        let uyusmayan = k.filter { !$0.uyuyor && !$0.mrz.isEmpty }.map(\.etiket)
        return PasaportDegerlendirmesi(satirlar: k, yanlisUzunluk: yanlis, sonuc: sonuc, hepsiUyuyor: hepsi, uyusmayanlar: uyusmayan)
    }
}

extension BasvuruIslemi {
    /// "Otomatik onayla" / "Elle onaylıyorum" / "Uyuşmuyor olarak kaydet": sonuç +
    /// geçmiş + işlem kaydı tek yazımda (panel işlem kaydını ayrı yazıyor; burada
    /// biri yazılıp öteki yazılmamış kalmasın diye birlikte).
    public static func pasaportKontrolu(
        _ b: Basvuru, durum: PasaportKontrolu.Durum, bakilanlar: [String], uyusmayanlar: [String], calisan c: Calisan
    ) -> [FirestoreIstemci.Yazim] {
        let ad = FSDeger.metin(String(c.gorunenAd.prefix(80)))
        var alanlar: [String: FSDeger] = [:]
        alanlar["status"] = .metin(durum.rawValue)
        alanlar["mismatches"] = .dizi(uyusmayanlar.prefix(20).map { FSDeger.metin($0) })
        alanlar["checked"] = .dizi(bakilanlar.prefix(20).map { FSDeger.metin($0) })
        alanlar["by"] = .metin(c.uid)
        alanlar["byName"] = ad
        var zaman = ["at"]
        if durum != .otomatik {
            alanlar["approvedBy"] = .metin(c.uid)
            alanlar["approvedByName"] = ad
            zaman.append("approvedAt")
        }
        let ek = uyusmayanlar.isEmpty ? "" : " (\(uyusmayanlar.joined(separator: ", ")))"
        return [
            .yaz(yol: "\(yol(b))/private/passport", alanlar: alanlar, zaman: zaman),
            gecmis(b, tur: "passport", metin: String("Pasaport kontrolü: \(durum.ad)\(ek)".prefix(500)), c),
            kayit("app.passport", b, String("\(durum.rawValue): \(uyusmayanlar.joined(separator: ", "))".prefix(500)), c),
        ]
    }
}

/// Yeni / düzenle formunun "Pasaporttan doldur" kuralı (panel: applyPassport).
/// Boş alan doldurulur; dolu ve farklı alan çelişki olarak bildirilir, ancak
/// "Pasaporttakiyle değiştir" denirse (zorla) üzerine yazılır. Bu ülkenin
/// formunda sorulmayan alana dokunulmaz.
///
/// Veriliş tarihi MRZ'de yok ve tahmin edilmez (panel: pasaport 6 ay ile 10 yıl
/// arasında düzenlenebiliyor; resmî belgeye tahmin yazmak boş bırakmaktan kötü).
/// Bu yüzden doldurma, tarih alanlarının birbirini ±10 yılla tamamlamasını da
/// tetiklemez: değerler doğrudan yazılır.
public enum PasaporttanDoldurma {
    public static let alanlar: [(key: String, etiket: String)] = [
        ("firstName", "İsim"), ("lastName", "Soyisim"), ("passportNo", "Pasaport no"), ("nationalId", "T.C. kimlik no"),
        ("birthDate", "Doğum tarihi"), ("passportExpires", "Geçerlilik tarihi"), ("passportIssued", "Veriliş (düzenleme) tarihi"),
        ("sex", "Cinsiyet"),
    ]

    public struct Celiski: Equatable, Identifiable {
        public var key: String
        public var etiket: String
        public var simdiki: String
        public var yeni: String
        public var id: String { key }
    }

    public struct Sonuc: Equatable {
        public var degerler: [String: String]
        public var dolan: [String]
        public var celiskiler: [Celiski]
    }

    public static func uygula(_ gelen: [String: String], degerler: [String: String], sorulan: Set<String>, zorla: Bool = false) -> Sonuc {
        var d = degerler
        var dolan: [String] = []
        var celiski: [Celiski] = []
        for (k, etiket) in alanlar {
            guard let yeni = gelen[k], !yeni.isEmpty, sorulan.contains(k) else { continue }
            let simdiki = (d[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !simdiki.isEmpty && simdiki != yeni && !zorla {
                celiski.append(Celiski(key: k, etiket: etiket, simdiki: simdiki, yeni: yeni))
                continue
            }
            if simdiki == yeni { continue }
            d[k] = yeni
            dolan.append(etiket)
        }
        return Sonuc(degerler: d, dolan: dolan, celiskiler: celiski)
    }
}
