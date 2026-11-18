import Foundation

// Kullanıcılar ve işlem kayıtları (panel: pages/admin.js → UsersPage, AuditPage).

/// Çalışan kaydı (employees/{uid}) — yönetici ekranı için.
public struct CalisanKaydi: Equatable, Identifiable {
    public static let roller: [(id: String, ad: String)] = [("admin", "Yönetici"), ("writer", "Operasyon"), ("reader", "İzleyici"), ("intern", "Stajyer")]
    public static let alanAdi = "panel.vizemia.local"

    public var id: String
    public var kullaniciAdi: String
    public var ad: String
    public var eposta: String
    public var rol: String
    public var aktif: Bool
    public var talepBildirimi: Bool

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        id = kimlik
        kullaniciAdi = a["username"]?.metinDegeri ?? ""
        ad = a["displayName"]?.metinDegeri ?? ""
        eposta = a["email"]?.metinDegeri ?? ""
        rol = a["role"]?.metinDegeri ?? "reader"
        aktif = a["active"]?.mantikDegeri ?? false
        talepBildirimi = a["notifyLeads"]?.mantikDegeri == true
    }

    public static func rolAdi(_ r: String) -> String { roller.first { $0.id == r }?.ad ?? r }

    public static func epostaHatasiAcik(_ e: String) -> String? { epostaHatasi(e) }
    static func epostaHatasi(_ e: String) -> String? {
        let x = e.kirpik.lowercased()
        return x.isEmpty || MusteriBildirimi.epostaGecerli(x) ? nil : "E-posta geçersiz."
    }

    /// Satırdaki "Kaydet": ad, e-posta, rol, aktif, talep bildirimi (izleyiciye bildirim gitmez).
    public static func guncelle(_ k: CalisanKaydi, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let bildirim = k.rol == "reader" ? false : k.talepBildirimi
        let ad = k.ad.kirpik.isEmpty ? k.kullaniciAdi : String(k.ad.kirpik.prefix(80))
        return [
            .guncelle(yol: "employees/\(k.id)", alanlar: [
                "displayName": .metin(ad), "email": .metin(k.eposta.kirpik.lowercased()), "notifyLeads": .mantik(bildirim),
                "role": .metin(k.rol), "active": .mantik(k.aktif), "updatedBy": .metin(c.uid),
            ], zaman: ["updatedAt"]),
            IslemKaydiYazimi.yaz("user.update", k.id,
                                "\(k.kullaniciAdi): \(k.rol), \(k.aktif ? "aktif" : "pasif"), bildirim: \(bildirim ? "açık" : "kapalı")", c),
        ]
    }

    /// Yeni kullanıcı: giriş hesabı Firebase konsolunda açılır, UID buraya yazılır.
    public static func ekle(uid: String, kullaniciAdi: String, ad: String, eposta: String, rol: String, mevcut: [CalisanKaydi],
                            calisan c: Calisan) -> (hata: String?, yazimlar: [FirestoreIstemci.Yazim]) {
        let u = kullaniciAdi.kirpik
        let id = uid.kirpik
        if !u.eslesir("^[a-z0-9._-]{3,40}$") { return ("Kullanıcı adı 3–40 karakter; küçük harf, rakam, nokta, tire.", []) }
        if !id.eslesir("^[A-Za-z0-9]{20,128}$") { return ("UID geçersiz görünüyor.", []) }
        if mevcut.contains(where: { $0.kullaniciAdi == u }) { return ("Bu kullanıcı adı zaten var.", []) }
        if let h = epostaHatasi(eposta) { return (h, []) }
        let a: [String: FSDeger] = [
            "username": .metin(u), "displayName": .metin(ad.kirpik.isEmpty ? u : String(ad.kirpik.prefix(80))),
            "email": .metin(eposta.kirpik.lowercased()), "notifyLeads": .mantik(rol != "reader"),
            "role": .metin(rol), "active": .mantik(true), "createdBy": .metin(c.uid), "updatedBy": .metin(c.uid),
        ]
        return (nil, [.olustur(yol: "employees/\(id)", alanlar: a, zaman: ["createdAt", "updatedAt"]),
                      IslemKaydiYazimi.yaz("user.create", id, "\(u) (\(rol))", c)])
    }

    public static func sil(_ k: CalisanKaydi, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.sil(yol: "employees/\(k.id)"), IslemKaydiYazimi.yaz("user.delete", k.id, "\(k.kullaniciAdi) silindi", c)]
    }
}

enum IslemKaydiYazimi {
    static func yaz(_ eylem: String, _ hedef: String, _ ayrinti: String, _ c: Calisan) -> FirestoreIstemci.Yazim {
        .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                 alanlar: IslemKaydi.alanlar(eylem: eylem, hedef: hedef, ayrinti: String(ayrinti.prefix(500)), calisan: c), zaman: ["at"])
    }
}

/// İşlem kaydı satırı (audit/{id}; değiştirilemez, silinemez).
public struct IslemSatiri: Equatable, Identifiable {
    public var id: String
    public var eylem: String
    public var hedef: String
    public var ayrinti: String
    public var yapan: String
    public var zaman: Date?

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        id = kimlik
        eylem = a["action"]?.metinDegeri ?? ""
        hedef = a["target"]?.metinDegeri ?? ""
        ayrinti = a["detail"]?.metinDegeri ?? ""
        yapan = a["byName"]?.metinDegeri ?? (a["by"]?.metinDegeri ?? "")
        zaman = a["at"]?.zamanDegeri
    }

    public var eylemAdi: String { Self.eylemAdlari[eylem] ?? eylem }

    /// Kişi, işlem, hedef adı ya da ayrıntıda arar.
    public func eslesir(_ terim: String, hedefAdi: String = "") -> Bool {
        let t = terim.kirpik.lowercased(with: Tr.yerel)
        if t.isEmpty { return true }
        return "\(yapan) \(eylem) \(eylemAdi) \(hedef) \(hedefAdi) \(ayrinti)".lowercased(with: Tr.yerel).contains(t)
    }

    /// Panelin ACTION_LABELS sözlüğü (aynı metinler).
    public static let eylemAdlari: [String: String] = [
        "login": "Giriş yaptı",
        "logout": "Çıkış yaptı",
        "password.change": "Şifresini değiştirdi",
        "app.create": "Başvuru açtı",
        "app.edit": "Başvuruyu düzenledi",
        "app.status": "Statü değiştirdi",
        "app.retention": "Saklama süresini değiştirdi",
        "app.delete": "Başvuruyu sildi",
        "app.passport": "Pasaport kontrolü",
        "app.fiyat": "Fiyat verdi",
        "app.odeme": "Ödeme girdi",
        "app.dekont": "Dekont işlemi",
        "app.dosya": "Belge işlemi",
        "app.mektup": "İyi niyet mektubu",
        "app.konsTakip": "Konsolosluk takip kodu",
        "app.tamamlanan": "Tamamlanan işler",
        "app.arama": "Müşteriyi aradı",
        "app.form": "Müşteri formu",
        "app.grup": "Grup işlemi",
        "app.bildirimTercihi": "Bildirim tercihini değiştirdi",
        "app.ustNot": "Üst not ekledi",
        "app.ustNot.sil": "Üst notu sildi",
        "callback.update": "Geri arama talebini güncelledi",
        "callback.tekrar": "Tekrar arama planladı",
        "callback.approve": "Geri arama talebini başvuruya çevirdi",
        "callback.cancel": "Geri arama talebini iptal etti",
        "callback.delete": "Geri arama talebini sildi",
        "callback.restore": "Silinen geri arama talebini geri aldı",
        "callback.create": "Telefonla gelen talep ekledi",
        "applicationRequests.update": "Başvuru talebini güncelledi",
        "applicationRequests.tekrar": "Tekrar arama planladı",
        "applicationRequests.approve": "Başvuru talebini başvuruya çevirdi",
        "applicationRequests.cancel": "Başvuru talebini iptal etti",
        "applicationRequests.delete": "Başvuru talebini sildi",
        "applicationRequests.restore": "Silinen başvuru talebini geri aldı",
        "arsiv.delete": "Müşteri arşivinden kalıcı sildi",
        "arsiv.geriAl": "Arşivdeki müşteriyle yeni başvuru açtı",
        "arsiv.talebeAl": "Arşivdeki müşteriyi Talepler'e geri aldı",
        "retention.delete": "Otomatik silme (KVKK)",
        "support.update": "Destek talebini güncelledi",
        "support.delete": "Destek talebini sildi",
        "content.create": "İçerik oluşturdu",
        "content.update": "İçerik güncelledi",
        "content.delete": "İçerik sildi",
        "vitrin.delete": "Vitrin slaytını sildi",
        "havuz.create": "Fotoğraf ekledi",
        "havuz.update": "Fotoğrafı düzenledi",
        "havuz.delete": "Fotoğrafı sildi",
        "siteMetin.surec": "\"5 adımda başvuru\" metni",
        "settings.setup": "İlk kurulum",
        "settings.general": "Genel ayarlar",
        "settings.permissions": "Rol izinleri",
        "settings.checklist": "Evrak listesi",
        "settings.forms": "Ülke soruları",
        "settings.sms": "SMS ayarları",
        "settings.formTuru": "Form türü ve alanlar",
        "settings.bildirim": "Bildirim ayarları",
        "settings.mektup": "Mektup ayarları",
        "settings.kasa": "Kasa ayarları",
        "settings.rehber": "Görüşme rehberi",
        "settings.mesai": "Mesai saatleri",
        "settings.konumlar": "Randevu konumları",
        "settings.eposta": "E-posta ayarları",
        "settings.yayin": "Site yayını anahtarı",
        "status.create": "Statü ekledi",
        "status.update": "Statü düzenledi",
        "status.delete": "Statü sildi",
        "user.create": "Kullanıcı ekledi",
        "user.update": "Kullanıcıyı güncelledi",
        "user.delete": "Kullanıcıyı sildi",
        "form.kural": "Form gönderim kuralı",
        "form.send": "Müşteriye form gönderdi",
        "form.transfer": "Form bilgisini aktardı",
        "portalBagi.kaydet": "Portal bağı kaydetti",
        "portalBagi.sil": "Portal bağını sildi",
        "sms.queue": "SMS kuyruğu",
        "mesaj.sms": "SMS gönderdi",
        "wa.templates": "WhatsApp hazır mesajları",
        "bildirim.wa": "WhatsApp bildirimi",
        "bildirim.now": "Bildirimi hemen gönderdi",
        "bildirim.cancel": "Bildirimi iptal etti",
        "eposta.tekli": "E-posta gönderdi",
        "eposta.toplu": "Toplu e-posta gönderdi",
        "eposta.serbest": "Serbest e-posta gönderdi",
        "kasa.iptal": "Kasa kaydını iptal etti",
        "kasa.rutin": "Rutin ödeme",
        "armut.aktar": "Armut müşterisini Talepler'e aktardı",
        "armut.anahtar": "Armut bağlantı anahtarı",
        "social.upload": "Post yükledi",
        "social.request": "Post isteği yazdı",
        "social.request.cancel": "Post isteğini iptal etti",
        "social.instagram": "Instagram'a paylaştı",
        "social.delete": "Postu sildi",
        "firma.yukle": "Firma listesi yükledi",
        "firma.iys": "Firmaları İYS'ye kaydedildi işaretledi",
        "firma.engel": "Firmaları listeden çıkardı",
        "firma.gonder": "Firma maili kuyruğa aldı",
        "firma.cevap": "Firmaya cevap yazdı",
        "firma.sablon": "Firma maili şablonları",
        "firma.ayar": "Firma maili ayarları",
        "yedek.indir": "Veritabanı yedeği indirdi",
        "test.sil": "Test verisini sildi",
        "test.ekle": "Test verisi ekledi",
    ]
}
