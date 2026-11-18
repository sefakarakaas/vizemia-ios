import Foundation

// Grup başvurusu (panel/js/grup.js, applications.js → GrupPanel).
// Grup yalnız BİR ARADA GÖSTERME ve HIZLI AÇMA içindir: her kişinin başvurusu,
// evrakı, ödemesi ve statüsü ayrı kalır. Grup ayrı koleksiyon değil; üyelerin
// başvuru belgesinde iki alan: grupId ('g_' + 20 harf/rakam) ve grupAdi.
// Kural: firestore.rules → applications (grupKeys, validGrup).

public enum GrupIsi {
    /// Gruptaki yeni kişiye ilk kişiden kopyalanan ortak yolculuk alanları.
    public static let ortakAlanlar = [
        "travelPurpose", "travelPurposeOther", "purposeInfo", "mainDestinationOther", "firstEntryCountry",
        "entryDate", "exitDate", "entries",
        "hostName", "hostAddress", "hostEmail", "hostPhone", "companyName", "companyContact", "companyPhone",
    ]
    /// İstenirse kopyalanan iletişim alanları.
    public static let iletisimAlanlari = ["phone", "email", "addressStreet", "addressCity", "addressPostcode"]

    public static func gecerliId(_ s: String) -> Bool { s.eslesir("^g_[A-Za-z0-9]{20}$") }

    public static func yeniId() -> String {
        let harf = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return "g_" + String((0..<20).map { _ in harf[Int.random(in: 0..<harf.count)] })
    }

    /// "ÖZTÜRK" → "Öztürk grubu".
    public static func varsayilanAd(_ soyad: String) -> String {
        let kucuk = soyad.kirpik.lowercased(with: Tr.yerel)
        var s = ""
        var basta = true
        for ch in kucuk {
            if basta && ch.isLetter { s += String(ch).uppercased(with: Tr.yerel); basta = false } else { s.append(ch) }
            if ch == " " || ch == "-" { basta = true }
        }
        return String((s.isEmpty ? "Grup" : "\(s) grubu").prefix(80))
    }

    public static func adTemizle(_ ad: String) -> String {
        String(ad.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(80))
    }

    static func damga(_ c: Calisan) -> [String: FSDeger] { ["updatedBy": .metin(c.uid)] }

    static func uyelik(_ b: Basvuru, id: String, ad: String, _ c: Calisan) -> FirestoreIstemci.Yazim {
        .guncelle(yol: "applications/\(b.kimlik)", alanlar: damga(c).merging(["grupId": .metin(id), "grupAdi": .metin(ad)]) { $1 },
                  zaman: ["updatedAt"])
    }

    public enum BaglaSonucu: Equatable {
        case tamam(yazimlar: [FirestoreIstemci.Yazim], ad: String)
        /// Hedef başka grupta: taşımadan önce sorulur.
        case tasinsinMi(grupAdi: String)
        case hata(String)
    }

    /// Açık başvuruyu takip koduyla bulunan başvuruyla gruplar (panel: "Mevcut başvuruyla grupla").
    /// Açık olan gruptaysa hedef o gruba alınır; değilse hedefin grubuna katılır;
    /// ikisi de grupsuzsa yeni grup kurulur.
    public static func bagla(_ acik: Basvuru, hedef: Basvuru, tasimaOnayli: Bool = false, calisan c: Calisan) -> BaglaSonucu {
        if hedef.kimlik == acik.kimlik { return .hata("Bu zaten açık olan başvuru.") }
        var y: [FirestoreIstemci.Yazim] = []
        let ad: String
        if gecerliId(acik.grupId) {
            if hedef.grupId == acik.grupId { return .hata("Bu başvuru zaten bu grupta.") }
            if !hedef.grupId.isEmpty && !tasimaOnayli { return .tasinsinMi(grupAdi: hedef.grupAdi) }
            ad = acik.grupAdi.isEmpty ? varsayilanAd(acik.soyad) : acik.grupAdi
            y.append(uyelik(hedef, id: acik.grupId, ad: ad, c))
        } else if gecerliId(hedef.grupId) {
            ad = hedef.grupAdi.isEmpty ? varsayilanAd(hedef.soyad) : hedef.grupAdi
            y.append(uyelik(acik, id: hedef.grupId, ad: ad, c))
        } else {
            let id = yeniId()
            ad = varsayilanAd(acik.soyad)
            y.append(uyelik(acik, id: id, ad: ad, c))
            y.append(uyelik(hedef, id: id, ad: ad, c))
        }
        y.append(BasvuruIslemi.kayit("app.grup", acik, "\(ad): \(hedef.takipKodu)", c))
        return .tamam(yazimlar: y, ad: ad)
    }

    /// Grubun adını bütün üyelerde değiştirir.
    public static func adDegistir(_ acik: Basvuru, uyeler: [Basvuru], ad: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim]? {
        let a = adTemizle(ad)
        guard !a.isEmpty, a != acik.grupAdi else { return nil }
        let liste = uyeler.isEmpty ? [acik] : uyeler
        return liste.map {
            .guncelle(yol: "applications/\($0.kimlik)", alanlar: damga(c).merging(["grupAdi": .metin(a)]) { $1 }, zaman: ["updatedAt"])
        } + [BasvuruIslemi.kayit("app.grup", acik, "ad: \(a)", c)]
    }

    /// Kişiyi gruptan çıkarır; geriye tek kişi kalırsa grup da kalkar. Başvurular olduğu gibi kalır.
    public static func cikar(_ acik: Basvuru, digerleri: [Basvuru], calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let bos: [String: FSDeger] = ["grupId": .metin(""), "grupAdi": .metin("")]
        var y: [FirestoreIstemci.Yazim] = [
            .guncelle(yol: "applications/\(acik.kimlik)", alanlar: damga(c).merging(bos) { $1 }, zaman: ["updatedAt"]),
        ]
        if digerleri.count == 1 {
            y.append(.guncelle(yol: "applications/\(digerleri[0].kimlik)", alanlar: damga(c).merging(bos) { $1 }, zaman: ["updatedAt"]))
        }
        y.append(BasvuruIslemi.kayit("app.grup", acik, "çıkarıldı: \(acik.grupAdi)", c))
        return y
    }
}

/// "Gruba kişi ekle": yeni başvuru formunun ön dolgusu (panel: grupTohum).
/// Ülke, randevu ve ortak yolculuk alanları ilk kişiden; kişisel alanlar boş.
public struct GrupTohumu: Equatable {
    public var ulke: String
    public var randevu: String
    public var degerler: [String: String]
    public var id: String
    public var ad: String
    public var kaynakId: String
    public var kaynakAd: String
    /// İlk kişi henüz grupta değilse yeni başvuruyla aynı yazımda gruba alınır.
    public var kaynakGrubaAlinsin: Bool
    /// "İletişim bilgisini ilk kişiden kopyala" ile doldurulanlar.
    public var iletisim: [String: String]
    public var kanallar: FSDeger?

    public init(_ b: Basvuru, form: [String: FSDeger], randevu: String) {
        var d: [String: String] = [:]
        for k in GrupIsi.ortakAlanlar { if let v = form[k]?.metinDegeri, !v.isEmpty { d[k] = v } }
        var i: [String: String] = [:]
        for k in GrupIsi.iletisimAlanlari { if let v = form[k]?.metinDegeri, !v.isEmpty { i[k] = v } }
        let grupVar = GrupIsi.gecerliId(b.grupId)
        ulke = b.ulke
        self.randevu = randevu
        degerler = d
        id = grupVar ? b.grupId : GrupIsi.yeniId()
        ad = grupVar ? (b.grupAdi.isEmpty ? GrupIsi.varsayilanAd(b.soyad) : b.grupAdi) : GrupIsi.varsayilanAd(b.soyad)
        kaynakId = b.kimlik
        kaynakAd = "\(b.ad) \(b.soyad)".kirpik
        kaynakGrubaAlinsin = !grupVar
        iletisim = i
        kanallar = form["channels"]
    }
}
