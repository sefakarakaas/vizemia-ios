import Foundation

/// Bildirim yolları: randevu alındığında ve evrak hatırlatmalarında hangi
/// yoldan yazılacak (site/assets/kanal-secimi.js). En az biri açık olmalı —
/// hiçbiri seçili değilse müşteri randevu gününü hiç öğrenemez.
public struct Kanallar: Equatable {
    public var wa: Bool
    public var sms: Bool
    public var email: Bool

    public init(wa: Bool = true, sms: Bool = true, email: Bool = true) {
        self.wa = wa; self.sms = sms; self.email = email
    }

    /// Gönderilecek değer: e-posta yalnız geçerli bir adres varsa açık sayılır.
    public func gecerli(eposta: String) -> Kanallar {
        Kanallar(wa: wa, sms: sms, email: email && Harf.epostaGecerli(Harf.eposta(eposta)))
    }

    public var bos: Bool { !wa && !sms && !email }

    var deger: FSDeger {
        .harita(["wa": .mantik(wa), "sms": .mantik(sms), "email": .mantik(email)])
    }
}

public struct VizeTuru: Equatable, Identifiable, Hashable {
    public var id: String
    public var ad: String

    /// Güvenlik kuralındaki liste ile aynı (firestore.rules → applicationRequests).
    public static let hepsi: [VizeTuru] = [
        VizeTuru(id: "turistik", ad: "Turistik"),
        VizeTuru(id: "ticari", ad: "Ticari"),
        VizeTuru(id: "ziyaret", ad: "Aile / arkadaş ziyareti"),
        VizeTuru(id: "ogrenci", ad: "Öğrenci"),
        VizeTuru(id: "transit", ad: "Transit"),
        VizeTuru(id: "bilmiyorum", ad: "Emin değilim"),
    ]
}

/// Formda hata çıkan alan (ekran oraya kaydırır).
public enum BasvuruAlani: String, Equatable {
    case ad, soyad, telefon, eposta, ulke, vizeTuru, seyahat, kanal, arama
    case pasaportNo, tckn, dogum, gecerlilik, kvkk
}

public struct FormHatasi: Error, Equatable {
    public var mesaj: String
    public var alan: BasvuruAlani?
}

/// "Sizi Arayalım" formu — site/assets/basvuru.js ile aynı alanlar ve kurallar.
/// Firestore `applicationRequests` koleksiyonuna yazılır; panelde Talepler'e düşer.
public struct BasvuruFormu: Equatable {
    public var ad = ""
    public var soyad = ""
    public var telefon = ""
    public var eposta = ""
    /// Ülke kimliği (ör. "almanya") ve görünen adı.
    public var ulke = ""
    public var ulkeAdi = ""
    public var vizeTuru = ""
    /// YYYY-AA-GG ya da boş.
    public var seyahat = ""
    public var mesaj = ""
    public var kanallar = Kanallar()
    // Pasaport bölümü isteğe bağlı: ya hepsi boş ya hepsi geçerli.
    public var pasaportNo = ""
    public var tckn = ""
    public var dogum = ""
    public var gecerlilik = ""
    public var kvkk = false
    public var kampanya = false

    public init() {}

    var temizAd: String { Harf.adSoyad(ad, ulke: ulke).kirpik.ilk(60) }
    var temizSoyad: String { Harf.adSoyad(soyad, ulke: ulke).kirpik.ilk(60) }
    var temizEposta: String { Harf.eposta(eposta) }

    /// Pasaport bölümüne bir şey yazıldı mı? Yazıldıysa hepsi doğrulanır.
    public var pasaportGirildi: Bool {
        ![pasaportNo, tckn, dogum, gecerlilik].allSatisfy { $0.kirpik.isEmpty }
    }

    private var adDeseni: String {
        Harf.ouKorunur(ulke) ? "^[A-ZÖÜ][A-ZÖÜ -]{0,59}$" : "^[A-Z][A-Z -]{0,59}$"
    }

    /// İlk hatayı döner; form tamamsa nil.
    public func hata(arama: AramaSecimi, bugun: String = Tr.bugun()) -> FormHatasi? {
        if !temizAd.eslesir(adDeseni) { return FormHatasi(mesaj: "Adınızı yazın.", alan: .ad) }
        if !temizSoyad.eslesir(adDeseni) { return FormHatasi(mesaj: "Soyadınızı yazın.", alan: .soyad) }
        if Harf.telefonHaneleri(telefon) == nil {
            return FormHatasi(mesaj: "Geçerli bir telefon numarası yazın (ör. 05xx xxx xx xx).", alan: .telefon)
        }
        if !temizEposta.isEmpty && !Harf.epostaGecerli(temizEposta) {
            return FormHatasi(mesaj: "Geçerli bir e-posta adresi yazın ya da boş bırakın.", alan: .eposta)
        }
        if ulke.count < 2 || ulkeAdi.count < 2 { return FormHatasi(mesaj: "Gideceğiniz ülkeyi seçin.", alan: .ulke) }
        if !VizeTuru.hepsi.contains(where: { $0.id == vizeTuru }) {
            return FormHatasi(mesaj: "Vize türünü seçin.", alan: .vizeTuru)
        }
        if !seyahat.isEmpty && seyahat < bugun {
            return FormHatasi(mesaj: "Seyahat tarihi bugünden önce olamaz.", alan: .seyahat)
        }
        if kanallar.gecerli(eposta: eposta).bos {
            return FormHatasi(mesaj: "Size nasıl haber verelim? En az bir yol seçin.", alan: .kanal)
        }
        if let h = arama.hata { return FormHatasi(mesaj: h, alan: .arama) }
        if pasaportGirildi, let h = pasaportHatasi(bugun: bugun) { return h }
        if !kvkk { return FormHatasi(mesaj: "Devam etmek için onay kutusunu işaretleyin.", alan: .kvkk) }
        return nil
    }

    private func pasaportHatasi(bugun: String) -> FormHatasi? {
        if !pasaportNo.eslesir("^[A-Z][0-9]{8}$") {
            return FormHatasi(
                mesaj: "Pasaport numarası bir harf ve sekiz rakamdan oluşur (ör. U12345678). Pasaport bilgilerini şimdi girmek istemiyorsanız bu bölümü boş bırakın.",
                alan: .pasaportNo)
        }
        if !tckn.isEmpty && !Harf.tcknGecerli(tckn) {
            return FormHatasi(mesaj: "T.C. kimlik numarası doğrulanamadı; lütfen kontrol edin.", alan: .tckn)
        }
        if Tr.tarih(dogum) == nil { return FormHatasi(mesaj: "Doğum tarihinizi yazın.", alan: .dogum) }
        if Tr.tarih(gecerlilik) == nil { return FormHatasi(mesaj: "Pasaportun geçerlilik tarihini yazın.", alan: .gecerlilik) }
        if gecerlilik < bugun {
            return FormHatasi(mesaj: "Pasaportunuzun geçerlilik tarihi geçmiş görünüyor. Lütfen kontrol edin.", alan: .gecerlilik)
        }
        if dogum >= bugun { return FormHatasi(mesaj: "Doğum tarihi bugünden sonra olamaz.", alan: .dogum) }
        return nil
    }

    /// Firestore'a yazılacak alanlar (`createdAt` sunucuda eklenir).
    /// Alan listesi güvenlik kuralındaki `hasOnly` listesiyle aynı olmalı.
    public func alanlar(arama: AramaSecimi, simdi: Date = Date()) -> [String: FSDeger] {
        let y = arama.yuk(simdi: simdi)
        let p = pasaportGirildi
        return [
            "firstName": .metin(temizAd),
            "lastName": .metin(temizSoyad),
            "passportNo": .metin(p ? pasaportNo.ilk(12) : ""),
            "nationalId": .metin(p ? tckn.ilk(11) : ""),
            "birthDate": .metin(p ? dogum : ""),
            "expiryDate": .metin(p ? gecerlilik : ""),
            "phone": .metin("+90" + (Harf.telefonHaneleri(telefon) ?? "")),
            "email": .metin(temizEposta.ilk(120)),
            "country": .metin(ulke.ilk(60)),
            // Adı da yolluyoruz: panel ülke listesini ayrıca tutmak zorunda kalmasın.
            "countryName": .metin(ulkeAdi.ilk(60)),
            "visaType": .metin(vizeTuru.ilk(20)),
            "travelDate": .metin(seyahat),
            "callbackMode": .metin(y.mod),
            "callbackDate": .metin(y.tarih),
            "callbackTimes": .dizi(y.saatler.map { .metin($0) }),
            "message": .metin(mesaj.kirpik.ilk(1500)),
            "channels": kanallar.gecerli(eposta: eposta).deger,
            "consent": .mantik(true),
            // Kampanya e-postası izni; sürüm kutudaki metni gösterir (panel: KAMPANYA_IZNI_SURUM).
            "kampanyaIzni": .mantik(kampanya),
            "kampanyaIzniSurum": .metin(kampanya ? "v1" : ""),
            "status": .metin("new"),
        ]
    }
}

/// Destek formu — site/assets/destek.js. Firestore `support` koleksiyonuna yazılır.
public struct DestekFormu: Equatable {
    public var ad = ""
    public var eposta = ""
    public var telefon = ""
    public var takipKodu = ""
    public var konu = ""
    public var mesaj = ""
    public var onay = false

    public init() {}

    public var hata: String? {
        if ad.kirpik.count < 2 { return "Adınızı yazın." }
        if !Harf.eposta(eposta).eslesir("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$") { return "Geçerli bir e-posta adresi yazın." }
        if konu.kirpik.isEmpty { return "Konu yazın." }
        if mesaj.kirpik.count < 5 { return "Mesajınızı yazın." }
        if !onay { return "Devam etmek için onay kutusunu işaretleyin." }
        return nil
    }

    public var alanlar: [String: FSDeger] {
        [
            "name": .metin(ad.kirpik.ilk(80)),
            "email": .metin(Harf.eposta(eposta).ilk(120)),
            "phone": .metin(telefon.kirpik.ilk(30)),
            "trackingCode": .metin(takipKodu.kirpik.ilk(20)),
            "subject": .metin(konu.kirpik.ilk(120)),
            "message": .metin(mesaj.kirpik.ilk(3000)),
            "consent": .mantik(true),
            "status": .metin("new"),
        ]
    }
}
