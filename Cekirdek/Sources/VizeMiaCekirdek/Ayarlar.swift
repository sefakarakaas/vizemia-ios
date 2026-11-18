import Foundation

// Ayarlar (panel: pages/admin.js, pages/mesai-saatleri.js, mesai-ayar.js).
// Uygulamada telefondan sık değişenler: mesai saatleri ve tatil günleri,
// genel ayarlar, rol izinleri, kasa listeleri, bildirim / SMS anahtarları.
// Yalnız düzenlenen alanlar yazılır (belgedeki öteki ayarlar olduğu gibi kalır).

public enum Ayarlar {
    static func kayit(_ eylem: String, _ hedef: String, _ ayrinti: String, _ c: Calisan) -> FirestoreIstemci.Yazim {
        IslemKaydiYazimi.yaz(eylem, hedef, ayrinti, c)
    }

    // MARK: Mesai saatleri

    public static let enErken = 7 * 60
    public static let enGec = 23 * 60
    public static let tatilEnCok = 60

    static func aralikGecerli(_ a: [Int]) -> Bool {
        a.count == 2 && a.allSatisfy { $0 >= enErken && $0 <= enGec && $0 % 30 == 0 } && a[0] < a[1]
    }

    /// Ayar formu hataları (panel: mesaiHatalari).
    public static func mesaiHatalari(_ m: Mesai) -> [String] {
        var h: [String] = []
        for i in 0..<7 {
            if let a = m.calisma[i], !aralikGecerli(a) {
                h.append("\(Mesai.gunAdi[i]): açılış kapanıştan önce olmalı, saatler \(Mesai.hhmm(enErken))–\(Mesai.hhmm(enGec)) arasında.")
            }
        }
        if m.calisma.values.isEmpty { h.append("En az bir gün açık olmalı; yoksa sitede hep \"kapalıyız\" yazar.") }
        if m.tatiller.count > tatilEnCok { h.append("En çok \(tatilEnCok) tatil günü girilebilir.") }
        return h
    }

    /// "Hafta içi 09:00–18:00, Cumartesi 10:00–14:00" (panel: mesaiTekSatir).
    public static func mesaiTekSatir(_ m: Mesai) -> String {
        func aralik(_ a: [Int]?) -> String { a.map { "\(Mesai.hhmm($0[0]))–\(Mesai.hhmm($0[1]))" } ?? "Kapalı" }
        var l: [(String, String)] = []
        let hi = (1...5).map { aralik(m.calisma[$0]) }
        if hi.allSatisfy({ $0 == hi[0] }) { l.append(("Hafta içi", hi[0])) } else { for i in 1...5 { l.append((Mesai.gunAdi[i], aralik(m.calisma[i]))) } }
        l.append(("Cumartesi", aralik(m.calisma[6])))
        l.append(("Pazar", aralik(m.calisma[0])))
        return l.filter { $0.1 != "Kapalı" }.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }

    public static func mesaiYaz(_ m: Mesai, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        var g: [String: FSDeger] = [:]
        for i in 0..<7 { g[String(i)] = m.calisma[i].map { a in .dizi(a.map { FSDeger.tam($0) }) } ?? .bos }
        let tatiller = Array(m.tatiller.sorted().suffix(tatilEnCok))
        return [
            .yaz(yol: "settings/mesai", alanlar: ["gunler": .harita(g), "tatiller": .dizi(tatiller.map { FSDeger.metin($0) }),
                                                  "updatedBy": .metin(c.uid)], zaman: ["updatedAt"]),
            kayit("settings.mesai", "mesai", "\(mesaiTekSatir(m)); \(tatiller.count) tatil günü", c),
        ]
    }

    /// settings/mesai belgesi (yoksa varsayılan).
    public static func mesai(belge a: [String: FSDeger]?) -> Mesai {
        guard let a else { return .varsayilan }
        var gunler: [String: [Int]?] = [:]
        for (k, v) in a["gunler"]?.haritaDegeri ?? [:] {
            if case .bos = v { gunler[k] = .some(nil) } else if let l = v.diziDegeri { gunler[k] = .some(l.compactMap { $0.tamDegeri }) }
        }
        let tatiller = (a["tatiller"]?.diziDegeri ?? []).compactMap { $0.metinDegeri }
        return Mesai(ayar: MesaiAyari(gunler: gunler, tatiller: tatiller))
    }

    // MARK: Genel

    public struct Genel: Equatable {
        public var saklamaGun = 60
        public var uyariGun = 7
        public var bosDakika = 30
        public var firmaAdi = ""
        public var firmaAdres = ""
        public var firmaEposta = ""
        public var firmaTelefon = ""
        public var firmaSehir = ""
        public var firmaWeb = ""

        public init() {}
        public init(belge a: [String: FSDeger]?) {
            saklamaGun = a?["retentionDays"]?.tamDegeri ?? 60
            uyariGun = a?["warnDays"]?.tamDegeri ?? 7
            bosDakika = a?["idleMinutes"]?.tamDegeri ?? 30
            firmaAdi = a?["firmaAdi"]?.metinDegeri ?? ""
            firmaAdres = a?["firmaAdres"]?.metinDegeri ?? ""
            firmaEposta = a?["firmaEposta"]?.metinDegeri ?? ""
            firmaTelefon = a?["firmaTelefon"]?.metinDegeri ?? ""
            firmaSehir = a?["firmaSehir"]?.metinDegeri ?? ""
            firmaWeb = a?["firmaWeb"]?.metinDegeri ?? ""
        }

        public var hatalar: [String] {
            var h: [String] = []
            if !(1...3650).contains(saklamaGun) { h.append("Saklama süresi 1–3650 gün olmalı.") }
            if uyariGun < 1 { h.append("Uyarı süresi geçersiz.") }
            if !(5...240).contains(bosDakika) { h.append("Oturum süresi 5–240 dakika olmalı.") }
            return h
        }
    }

    /// Sosyal medya hesapları (ve şifreleri) bu yazımda yok: belgede olduğu gibi kalır.
    public static func genelYaz(_ g: Genel, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let a: [String: FSDeger] = [
            "retentionDays": .tam(g.saklamaGun), "warnDays": .tam(g.uyariGun), "idleMinutes": .tam(g.bosDakika),
            "firmaAdi": .metin(String(g.firmaAdi.kirpik.prefix(120))), "firmaAdres": .metin(String(g.firmaAdres.kirpik.prefix(200))),
            "firmaEposta": .metin(String(g.firmaEposta.kirpik.prefix(120))), "firmaTelefon": .metin(String(g.firmaTelefon.kirpik.prefix(40))),
            "firmaSehir": .metin(String(g.firmaSehir.kirpik.prefix(60))), "firmaWeb": .metin(String(g.firmaWeb.kirpik.prefix(120))),
        ]
        return [.birlestir(yol: "settings/general", alanlar: a),
                kayit("settings.general", "", "saklama \(g.saklamaGun) gün, uyarı \(g.uyariGun) gün, oturum \(g.bosDakika) dk; şirket bilgileri", c)]
    }

    // MARK: Rol izinleri

    public struct Izin: Equatable, Identifiable {
        public var id: String
        public var ad: String
        public var grup: String
    }

    /// Panelin PERMISSIONS listesi (aynı metinler ve gruplar).
    public static let izinler: [Izin] = [
        Izin(id: "app.view", ad: "Başvuruları görüntüleme", grup: "Başvurular"),
        Izin(id: "app.create", ad: "Yeni başvuru ekleme", grup: "Başvurular"),
        Izin(id: "app.edit", ad: "Başvuru bilgilerini düzenleme", grup: "Başvurular"),
        Izin(id: "app.status", ad: "Statü değiştirme / müşteriye not", grup: "Başvurular"),
        Izin(id: "app.sensitive", ad: "TCKN, pasaport ve iletişim bilgilerini görme (Bildirimler sayfası ve iyi niyet mektubu dahil)", grup: "Başvurular"),
        Izin(id: "app.checklist", ad: "Evrak kontrol listesini işaretleme", grup: "Başvurular"),
        Izin(id: "app.payment", ad: "Ödeme bilgisi girme ve görme (dekont, slip, onay kodu)", grup: "Başvurular"),
        Izin(id: "note.add", ad: "İç not ekleme", grup: "Başvurular"),
        Izin(id: "lead.view", ad: "Geri arama ve başvuru taleplerini görme", grup: "Talepler"),
        Izin(id: "lead.manage", ad: "Talepleri işleme / kapatma", grup: "Talepler"),
        Izin(id: "armut.view", ad: "Armut.com'dan gelen işleri görme (müşteri adı, telefon, mesajlar)", grup: "Armut"),
        Izin(id: "armut.manage", ad: "Armut işlerini işleme: incelendi / ilgisiz, iç not, WhatsApp, Talepler'e aktarma", grup: "Armut"),
        Izin(id: "arsiv.view", ad: "Silinmiş başvuruların arşivini görme (ad, telefon, e-posta, son vize, işlemler, fiyat ve ödemeler)", grup: "Müşteri arşivi"),
        Izin(id: "eposta.send", ad: "Müşteriye mesaj gönderme: e-posta, WhatsApp, SMS (tek müşteri) ve toplu bilgilendirme e-postası; iletişim bilgilerini görür", grup: "E-posta"),
        Izin(id: "eposta.kampanya", ad: "Kampanya e-postası gönderme (yalnız izin verenlere; İYS kaydı tamamlanınca)", grup: "E-posta"),
        Izin(id: "firma.view", ad: "Firma veritabanını ve gönderilen firma maillerini görme (kurumsal e-posta adresleri)", grup: "Firma maili"),
        Izin(id: "firma.send", ad: "Firma listesi yükleme, şablon düzenleme ve firma maili gönderme (İYS kaydı ve MERSİS girilince)", grup: "Firma maili"),
        Izin(id: "kasa.view", ad: "Kasa raporlarını görme (gelir, gider, gün sonu, haftalık/aylık rapor, Excel)", grup: "Kasa ve raporlar"),
        Izin(id: "kasa.gider", ad: "Harcama girme (müşteri için ve genel giderler: fotokopi, market…)", grup: "Kasa ve raporlar"),
        Izin(id: "kasa.rutin", ad: "Rutin ödemeleri tanımlama (fatura, kira, haftalık ücret…)", grup: "Kasa ve raporlar"),
        Izin(id: "support.view", ad: "Destek taleplerini görme", grup: "Destek talepleri"),
        Izin(id: "support.manage", ad: "Destek taleplerini yanıtlama / kapatma", grup: "Destek talepleri"),
        Izin(id: "content.draft", ad: "Blog / SSS taslağı yazma", grup: "Blog ve SSS"),
        Izin(id: "content.publish", ad: "Blog / SSS yayınlama ve silme", grup: "Blog ve SSS"),
        Izin(id: "vitrin.edit", ad: "Slaytları görme ve taslak düzenleme", grup: "Vitrin (ana sayfa)"),
        Izin(id: "vitrin.publish", ad: "Slaytları yayınlama ve silme", grup: "Vitrin (ana sayfa)"),
        Izin(id: "havuz.manage", ad: "Fotoğraf ekleme, düzenleme ve silme (görme vitrin izniyle de olur)", grup: "Fotoğraf havuzu"),
        Izin(id: "surec.edit", ad: "\"5 adımda başvuru\" metnini düzenleme ve yayınlama (görme vitrin izniyle de olur)", grup: "Süreç adımları"),
        Izin(id: "social.view", ad: "Postları görme, metin kopyalama, görsel indirme", grup: "Sosyal medya"),
        Izin(id: "social.share", ad: "\"Paylaştım\" işaretleme, geri alma ve post isteği yazma", grup: "Sosyal medya"),
        Izin(id: "social.upload", ad: "Elle post yükleme (kendi görseli ve kanal metinleriyle)", grup: "Sosyal medya"),
        Izin(id: "social.instagram", ad: "Instagram'a otomatik paylaşma (@vizemiacom hesabına gönderir)", grup: "Sosyal medya"),
        Izin(id: "social.delete", ad: "Postu silme (görselleriyle; Instagram'dan silmez)", grup: "Sosyal medya")
    ]
    public static let roller = ["writer", "reader", "intern"]
    /// Göç sürümü (panel: izinler.js → IZIN_SURUMU): kaldırılan izin geri eklenmesin.
    public static let izinSurumu = 2

    public static var izinGruplari: [String] {
        var l: [String] = []
        for i in izinler where !l.contains(i.grup) { l.append(i.grup) }
        return l
    }

    public static func rolIzinleri(belge a: [String: FSDeger]?) -> [String: Set<String>] {
        var r: [String: Set<String>] = [:]
        let kayitli = a?["roles"]?.haritaDegeri
        for rol in roller {
            if let l = kayitli?[rol]?.diziDegeri { r[rol] = Set(l.compactMap { $0.metinDegeri }) }
            else { r[rol] = Set(Calisan.varsayilanIzinler[rol] ?? []) }
        }
        return r
    }

    public static func izinleriYaz(_ r: [String: Set<String>], calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        var roles: [String: FSDeger] = [:]
        for rol in roller {
            let l = izinler.map(\.id).filter { r[rol]?.contains($0) == true }
            roles[rol] = .dizi(l.map { FSDeger.metin($0) })
        }
        let ozet = roller.map { "\($0): \(r[$0]?.count ?? 0)" }.joined(separator: ", ")
        return [.yaz(yol: "settings/permissions", alanlar: ["roles": .harita(roles), "surum": .tam(izinSurumu)]),
                kayit("settings.permissions", "", ozet, c)]
    }

    // MARK: Kasa listeleri, bildirim ve SMS anahtarları

    public static func kasaListeleriYaz(musteri: [String], genel: [String], burolar: [String], raporSaati: String,
                                        calisan c: Calisan) -> (hata: String?, yazimlar: [FirestoreIstemci.Yazim]) {
        let m = KasaKurali.listeTemizle(musteri), g = KasaKurali.listeTemizle(genel), b = KasaKurali.listeTemizle(burolar, uzunluk: 80)
        if m.isEmpty || g.isEmpty { return ("Kategori listeleri boş olamaz.", []) }
        if !raporSaati.eslesir("^([01]\\d|2[0-3]):[0-5]\\d$") { return ("Rapor saati SS:DD biçiminde olmalı (ör. 20:00).", []) }
        let a: [String: FSDeger] = [
            "musteriGiderleri": .dizi(m.map { FSDeger.metin($0) }), "genelGiderler": .dizi(g.map { FSDeger.metin($0) }),
            "dovizBurolari": .dizi(b.map { FSDeger.metin($0) }), "raporSaati": .metin(raporSaati),
        ]
        return (nil, [.birlestir(yol: "settings/kasa", alanlar: a), kayit("settings.kasa", "", "\(m.count) müşteri, \(g.count) genel kategori, \(b.count) büro", c)])
    }

    /// Otomatik müşteri bildirimleri (randevu, evrak) açık / kapalı ve gönderim penceresi.
    public static func bildirimYaz(acik: Bool, pencereBas: Int, pencereSon: Int, calisan c: Calisan) -> (hata: String?, yazimlar: [FirestoreIstemci.Yazim]) {
        if !(0...23).contains(pencereBas) || !(1...24).contains(pencereSon) || pencereBas >= pencereSon {
            return ("Gönderim penceresi geçersiz (başlangıç bitişten önce olmalı).", [])
        }
        return (nil, [.birlestir(yol: "settings/bildirim", alanlar: ["enabled": .mantik(acik), "windowStart": .tam(pencereBas), "windowEnd": .tam(pencereSon)]),
                      kayit("settings.bildirim", "", "\(acik ? "açık" : "kapalı"), \(pencereBas):00–\(pencereSon):00", c)])
    }

    public static func smsYaz(acik: Bool, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.birlestir(yol: "settings/sms", alanlar: ["enabled": .mantik(acik)]), kayit("settings.sms", "", acik ? "SMS açık" : "SMS kapalı", c)]
    }
}
