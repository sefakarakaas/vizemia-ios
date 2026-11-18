import Foundation

// İyi niyet mektubu (dilekçe). Panel karşılıkları: mektup.js (bilgiler, prompt,
// cevap okuma, yerleşim), pages/mektup.js (ekran ve kayıt), mektup-pdf.js (PDF),
// data/mektup-*.js (uygulama.json → mektup).
// Akış: bilgiler tamamlanır → prompt kopyalanıp yapay zekâya verilir → gelen
// cevap yapıştırılır, Türkçe ve İngilizce paragraflar ayrılır → PDF (önce
// Türkçe, İngilizce yeni sayfadan; Calibri ölçülerindeki Carlito Bold 11).
// Kayıt: applications/{id}/private/mektup { bilgiler, not, secilenler, metin }.

/// uygulama.json → mektup.
public struct MektupVerisi: Decodable, Equatable {
    public struct Cumle: Decodable, Equatable, Identifiable {
        public var id: String
        public var kategori: String
        public var metin: String
        public init(id: String, kategori: String, metin: String) { self.id = id; self.kategori = kategori; self.metin = metin }
    }
    public struct Ayar: Decodable, Equatable {
        public var paragraf: Int
        public var min: Int
        public var max: Int
        public var ekTalimat: String
        public init(paragraf: Int = 8, min: Int = 40, max: Int = 50, ekTalimat: String = "") {
            self.paragraf = paragraf; self.min = min; self.max = max; self.ekTalimat = ekTalimat
        }
    }

    /// Ülke kimliği → [Türkçe ad, İngilizce ad].
    public var hitaplar: [String: [String]]
    public var kategoriler: [String]
    public var cumleler: [Cumle]
    public var vizeTurleri: [FormSecenegi]
    public var ayar: Ayar

    enum Anahtar: String, CodingKey { case hitaplar, kategoriler, cumleler, vizeTurleri, ayar }
    public init(from decoder: Decoder) throws {
        let c = Coz(c: try decoder.container(keyedBy: Anahtar.self))
        hitaplar = c.nesne(.hitaplar) ?? [:]
        kategoriler = c.dizi(.kategoriler)
        cumleler = c.dizi(.cumleler)
        vizeTurleri = c.dizi(.vizeTurleri)
        ayar = c.nesne(.ayar) ?? Ayar()
    }

    /// settings/mektup üstüne yazar: kayıtlı cümle listesi varsa o, ayar alanları tek tek
    /// (panel: cumleListesi, { ...VARSAYILAN_AYAR, ...state.mektup }).
    public func ayarla(_ b: [String: FSDeger]?) -> (cumleler: [Cumle], ayar: Ayar, sehir: String) {
        guard let b else { return (cumleler, ayar, "ANKARA") }
        let kayitli = (b["cumleler"]?.diziDegeri ?? []).compactMap { d -> Cumle? in
            guard let m = d.haritaDegeri, let id = m["id"]?.metinDegeri, let metin = m["metin"]?.metinDegeri else { return nil }
            return Cumle(id: id, kategori: m["kategori"]?.metinDegeri ?? "", metin: metin)
        }
        func sayi(_ k: String, _ v: Int) -> Int {
            if let t = b[k]?.tamDegeri { return t }
            if case .ondalik(let x)? = b[k] { return Int(x) }
            return v
        }
        let a = Ayar(paragraf: sayi("paragraf", ayar.paragraf), min: sayi("min", ayar.min), max: sayi("max", ayar.max),
                     ekTalimat: b["ekTalimat"]?.metinDegeri ?? ayar.ekTalimat)
        return (kayitli.isEmpty ? cumleler : kayitli, a, b["sehir"]?.metinDegeri ?? "ANKARA")
    }

    /// Hitap bloğu: Ankara'da büyükelçilik, İstanbul'da başkonsolosluk (panel: hitapBlogu).
    public func hitap(_ ulke: String, sehir: String) -> (tr: [String], en: [String]) {
        let ad = hitaplar[ulke] ?? []
        let tr = ad.first ?? "", en = ad.count > 1 ? ad[1] : ""
        let ist = sehir == "İSTANBUL"
        let trKurum = ist ? "BAŞKONSOLOSLUĞU" : "BÜYÜKELÇİLİĞİ"
        let enKurum = ist ? "CONSULATE GENERAL OF" : "EMBASSY OF"
        return ([tr.isEmpty ? trKurum : "\(tr) \(trKurum)", "VİZE DEPARTMANI", ist ? "İSTANBUL" : "ANKARA"],
                [en.isEmpty ? (ist ? "CONSULATE GENERAL" : "EMBASSY") : "\(enKurum) \(en)", "VISA DEPARTMENT", ist ? "ISTANBUL" : "ANKARA"])
    }
}

/// Mektubun bilgileri (private/mektup.bilgiler).
public struct MektupBilgileri: Equatable {
    public struct Eslik: Equatable, Identifiable {
        public var id = UUID()
        public var ad = ""
        public var yakinlik = ""
        public var pasaport = ""
        public init(ad: String = "", yakinlik: String = "", pasaport: String = "") { self.ad = ad; self.yakinlik = yakinlik; self.pasaport = pasaport }
        public static func == (a: Eslik, b: Eslik) -> Bool { a.ad == b.ad && a.yakinlik == b.yakinlik && a.pasaport == b.pasaport }
    }

    public var adSoyad = "", pasaportNo = "", uyruk = "Türkiye Cumhuriyeti", sehir = "ANKARA"
    public var hitapTr = ["", "", ""], hitapEn = ["", "", ""], tarih = ""
    public var giris = "", cikis = "", amac = "", amacDetay = "", vizeTuru = ""
    public var eslikEdenler: [Eslik] = []
    public var davetEden = "", davetYakinlik = "", oncekiVize = ""
    public var meslek = "", isyeri = "", calismaSuresi = ""
    public var masraf = "", finansal = ""
    public var mulk = "", egitim = "", bakmakla = "", evcil = "", diger = ""

    public init() {}

    static let metinAlanlari: [WritableKeyPath<MektupBilgileri, String>: String] = [
        \.adSoyad: "adSoyad", \.pasaportNo: "pasaportNo", \.uyruk: "uyruk", \.sehir: "sehir", \.tarih: "tarih",
        \.giris: "giris", \.cikis: "cikis", \.amac: "amac", \.amacDetay: "amacDetay", \.vizeTuru: "vizeTuru",
        \.davetEden: "davetEden", \.davetYakinlik: "davetYakinlik", \.oncekiVize: "oncekiVize",
        \.meslek: "meslek", \.isyeri: "isyeri", \.calismaSuresi: "calismaSuresi", \.masraf: "masraf", \.finansal: "finansal",
        \.mulk: "mulk", \.egitim: "egitim", \.bakmakla: "bakmakla", \.evcil: "evcil", \.diger: "diger",
    ]

    /// Kayıtlı bilgiler (eksik alan boş).
    public init(alanlar a: [String: FSDeger]) {
        for (yol, k) in Self.metinAlanlari { if let v = a[k]?.metinDegeri { self[keyPath: yol] = v } }
        func uc(_ d: FSDeger?) -> [String]? {
            guard let l = d?.diziDegeri else { return nil }
            let s = l.map { $0.metinDegeri ?? "" }
            return Array((s + ["", "", ""]).prefix(3))
        }
        hitapTr = uc(a["hitapTr"]) ?? hitapTr
        hitapEn = uc(a["hitapEn"]) ?? hitapEn
        eslikEdenler = (a["eslikEdenler"]?.diziDegeri ?? []).compactMap { $0.haritaDegeri }.map {
            Eslik(ad: $0["ad"]?.metinDegeri ?? "", yakinlik: $0["yakinlik"]?.metinDegeri ?? "", pasaport: $0["pasaport"]?.metinDegeri ?? "")
        }
    }

    public var alanlar: [String: FSDeger] {
        var a: [String: FSDeger] = [:]
        for (yol, k) in Self.metinAlanlari { a[k] = .metin(String(self[keyPath: yol].prefix(2000))) }
        a["hitapTr"] = .dizi(hitapTr.map { FSDeger.metin(String($0.prefix(200))) })
        a["hitapEn"] = .dizi(hitapEn.map { FSDeger.metin(String($0.prefix(200))) })
        a["eslikEdenler"] = .dizi(eslikEdenler.prefix(20).map {
            .harita(["ad": .metin(String($0.ad.prefix(120))), "yakinlik": .metin(String($0.yakinlik.prefix(120))), "pasaport": .metin(String($0.pasaport.prefix(20)))])
        })
        return a
    }
}

public enum Mektup {
    static let trAylar = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
    static let enAylar = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    static func parcala(_ iso: String) -> (y: String, a: Int, g: String)? {
        let p = iso.prefix(10).split(separator: "-")
        guard p.count == 3, p[0].count == 4, let a = Int(p[1]), (1...12).contains(a), p[2].count == 2 else { return nil }
        return (String(p[0]), a, String(p[2]))
    }
    /// "05.10.2026"
    public static func tarihNoktali(_ iso: String) -> String { parcala(iso).map { "\($0.g).\(String(format: "%02d", $0.a)).\($0.y)" } ?? "" }
    /// "05 Mart 2027"
    public static func tarihTr(_ iso: String) -> String { parcala(iso).map { "\($0.g) \(trAylar[$0.a - 1]) \($0.y)" } ?? "" }
    /// "05 March 2027"
    public static func tarihEn(_ iso: String) -> String { parcala(iso).map { "\($0.g) \(enAylar[$0.a - 1]) \($0.y)" } ?? "" }

    /// "GONCA AKKUŞ KÜNDEM" → "Gonca Akkuş Kündem"; yabancı ad için dil "en" (I → i).
    public static func ozelAd(_ s: String, dil: String = "tr") -> String {
        let yer = Locale(identifier: dil == "tr" ? "tr_TR" : "en_US")
        return s.split(whereSeparator: \.isWhitespace).map { k -> String in
            let kucuk = k.lowercased(with: yer)
            return kucuk.prefix(1).uppercased(with: yer) + kucuk.dropFirst()
        }.joined(separator: " ")
    }

    /// "GONCA AKKUŞ KÜNDEM DİLEKÇE.pdf"
    public static func dosyaAdi(_ adSoyad: String) -> String {
        let ad = adSoyad.split(whereSeparator: \.isWhitespace).joined(separator: " ").uppercased(with: Tr.yerel)
            .filter { !"\\/:*?\"<>|".contains($0) }
        return "\(ad.isEmpty ? "MÜŞTERİ" : ad) DİLEKÇE.pdf"
    }

    public static func kelimeSay(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }

    static let amaclar = ["Turistik": "turistik gezi", "Ticari": "iş / ticari görüşme", "Aile_Arkadasi": "aile / arkadaş ziyareti",
                          "Kulturel": "kültürel etkinlik", "Sportif": "sportif etkinlik", "ResmiZiyaret": "resmî ziyaret",
                          "Saglik": "sağlık / tedavi", "Ogrenim": "eğitim", "HavalimaniTransit": "havalimanı transiti", "Diger": ""]

    /// Başvurudan doldurur; kayıtlı bilgi önce gelir, boş kalanlar başvurudan (panel: bilgileriDoldur).
    public static func doldur(form f: [String: FSDeger], ulke: String, kayit: MektupBilgileri?, veri: MektupVerisi?, bugun: String) -> MektupBilgileri {
        var b = kayit ?? MektupBilgileri()
        func m(_ k: String) -> String { f[k]?.metinDegeri ?? "" }
        func doldur(_ yol: WritableKeyPath<MektupBilgileri, String>, _ v: String) {
            if b[keyPath: yol].isEmpty && !v.isEmpty { b[keyPath: yol] = v }
        }
        doldur(\.adSoyad, ozelAd("\(m("firstName")) \(m("lastName"))"))
        doldur(\.pasaportNo, m("passportNo").uppercased())
        doldur(\.giris, m("entryDate"))
        doldur(\.cikis, m("exitDate"))
        doldur(\.amac, amaclar[m("travelPurpose")].flatMap { $0.isEmpty ? nil : $0 } ?? m("travelPurposeOther"))
        doldur(\.amacDetay, m("purposeInfo"))
        doldur(\.vizeTuru, m("entries") == "M" ? "cok" : "tek")
        let host = m("hostName")
        doldur(\.davetEden, !host.isEmpty && host.range(of: "hotel|otel", options: [.regularExpression, .caseInsensitive]) == nil ? ozelAd(host, dil: "en") : "")
        doldur(\.meslek, ozelAd(m("occupation")))
        doldur(\.isyeri, ozelAd(m("employerName")))
        let masraf = m("costCoveredBy") == "Kendim" ? "Tüm masrafları kendim karşılayacağım."
            : (m("costCoveredBy") == "Sponsor" ? "Masrafları sponsorum karşılayacak.\(m("sponsorOther").isEmpty ? "" : " (\(m("sponsorOther")))")" : "")
        doldur(\.masraf, masraf)
        if m("fingerprintsBefore") == "Evet" { doldur(\.oncekiVize, "Daha önce Schengen vizesi aldım ve parmak izi verdim.") }
        doldur(\.oncekiVize, [m("x_abd_onceki_ziyaret_detay"), m("x_uk_onceki_ziyaret_detay"), m("x_kanada_onceki_ziyaret_detay")].first { !$0.isEmpty } ?? "")
        let aile = [m("x_es_bilgileri").isEmpty ? "" : "Eş: \(m("x_es_bilgileri"))", m("x_cocuk_bilgileri").isEmpty ? "" : "Çocuklar: \(m("x_cocuk_bilgileri"))"]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        doldur(\.bakmakla, aile)
        if let v = veri {
            let h = v.hitap(ulke, sehir: b.sehir)
            if b.hitapTr.allSatisfy({ $0.isEmpty }) { b.hitapTr = h.tr }
            if b.hitapEn.allSatisfy({ $0.isEmpty }) { b.hitapEn = h.en }
        }
        doldur(\.tarih, bugun)
        if b.vizeTuru.isEmpty { b.vizeTuru = "tek" }
        return b
    }

    /// Ret riski taşıyan boş başlıklar (uyarı; engel değil).
    public static func eksikler(_ b: MektupBilgileri) -> [String] {
        func bos(_ s: String) -> Bool { s.kirpik.isEmpty }
        var o: [String] = []
        if bos(b.adSoyad) { o.append("Ad soyad") }
        if bos(b.pasaportNo) { o.append("Pasaport numarası") }
        if bos(b.giris) || bos(b.cikis) { o.append("Seyahat tarihleri") }
        if bos(b.amac) { o.append("Seyahat amacı") }
        if bos(b.meslek) && bos(b.isyeri) && bos(b.egitim) && bos(b.diger) { o.append("Meslek / işyeri (ya da öğrenci, emekli bilgisi)") }
        if bos(b.masraf) { o.append("Masrafları kim karşılıyor") }
        if bos(b.oncekiVize) { o.append("Önceki vize / ziyaret bilgisi (yoksa \"ilk başvuru\" yazın)") }
        if b.amac.range(of: "aile|arkada|ziyaret", options: [.regularExpression, .caseInsensitive]) != nil && bos(b.davetEden) {
            o.append("Davet eden kişi ve yakınlığı")
        }
        for (i, e) in b.eslikEdenler.enumerated() where bos(e.ad) || bos(e.pasaport) { o.append("\(i + 1). eşlik eden: ad ve pasaport no") }
        if !b.hitapTr.contains(where: { !bos($0) }) { o.append("Hitap bloğu (temsilcilik)") }
        return o
    }

    /// Danışmanın kopyalayıp yapay zekâya vereceği metin (panel: promptOlustur).
    public static func prompt(_ b: MektupBilgileri, ulkeAdi: String, not: String, cumleler: [String], ayar a: MektupVerisi.Ayar,
                              vizeTurleri: [FormSecenegi]) -> String {
        var satir: [String] = []
        func ekle(_ e: String, _ d: String) { if !d.kirpik.isEmpty { satir.append("- \(e): \(d.kirpik)") } }
        ekle("Ad soyad", b.adSoyad)
        ekle("Pasaport numarası", b.pasaportNo)
        ekle("Uyruk", b.uyruk)
        ekle("Gidilecek ülke", ulkeAdi)
        ekle("Seyahat tarihleri", !b.giris.isEmpty && !b.cikis.isEmpty
             ? "\(tarihTr(b.giris)) – \(tarihTr(b.cikis)) (İngilizce: \(tarihEn(b.giris)) – \(tarihEn(b.cikis)))" : "")
        ekle("Seyahat amacı", b.amac)
        ekle("Amaçla ilgili ayrıntı", b.amacDetay)
        ekle("İstenen vize türü", vizeTurleri.first { $0.value == b.vizeTuru }?.label ?? "")
        for e in b.eslikEdenler {
            ekle("Eşlik eden kişi", [e.ad, e.yakinlik.isEmpty ? "" : "(\(e.yakinlik))", e.pasaport.isEmpty ? "" : "Pasaport No: \(e.pasaport)"]
                .filter { !$0.isEmpty }.joined(separator: " "))
        }
        ekle("Davet eden kişi", [b.davetEden, b.davetYakinlik.isEmpty ? "" : "— yakınlığı: \(b.davetYakinlik)"].filter { !$0.isEmpty }.joined(separator: " "))
        ekle("Önceki vizeler / ziyaretler", b.oncekiVize)
        ekle("Meslek / görev", b.meslek)
        ekle("İşyeri", b.isyeri)
        ekle("Çalışma süresi", b.calismaSuresi)
        ekle("Masraflar", b.masraf)
        ekle("Finansal durum / belgeler", b.finansal)
        ekle("Türkiye'deki mülkler", b.mulk)
        ekle("Eğitim", b.egitim)
        ekle("Bakmakla yükümlü olunanlar / aile", b.bakmakla)
        ekle("Evcil hayvan", b.evcil)
        ekle("Diğer bağlar", b.diger)
        let cok = b.vizeTuru == "uzun-cok" || b.vizeTuru == "cok"
        let kurallar = [
            "Mektup tam \(a.paragraf) paragraf olsun; her paragraf \(a.min)–\(a.max) kelime.",
            "Birinci tekil şahıs, resmî, saygılı ve samimi bir dille yaz.",
            "Yukarıdaki BÜTÜN bilgileri kullan. Ad soyad, pasaport numaraları, kişi adları ve tarihleri AYNEN yaz; değiştirme, kısaltma.",
            "İlk paragraf ad soyad, pasaport numarası, Türkiye Cumhuriyeti vatandaşlığı, gidilecek ülke, seyahat tarihleri ve amaçla başlasın.",
            "Eşlik eden kişileri adları ve pasaport numaralarıyla an; davet eden kişiyi ve yakınlığını yaz.",
            cok ? "Çok girişli vize talebini gerekçesiyle yaz; uzun süre kalmak amacı olmadığını ve 180 günde 90 gün kuralına uyulacağını belirt." : "",
            "Türkiye'ye dönüşü gösteren bağları (iş, aile, mülk, eğitim) ve dönüş taahhüdünü vurgula.",
            "Verilmeyen bilgi UYDURMA (kurum adı, rakam, tarih ekleme).",
            "Hitap bloğu, tarih, \"Sayın Yetkili\" / \"Dear Sir/Madam\" selamlaması, \"Saygılarımla\" / \"Yours faithfully\" kapanışı ve imza YAZMA; onları sistem ekliyor.",
            "Türkçe ve İngilizce metin aynı içerikte olsun; İngilizcede \"Türkiye\" yaz.",
        ].filter { !$0.isEmpty }
        var l = ["Bir vize başvurusu için konsolosluğa verilecek iyi niyet mektubu (dilekçe) yaz.", "", "BAŞVURU SAHİBİNİN BİLGİLERİ"] + satir
        if !cumleler.isEmpty { l += ["", "MEKTUPTA MUTLAKA YER ALSIN (anlamını koruyarak, akışa uygun yerleştir)"] + cumleler.map { "- \($0)" } }
        if !not.kirpik.isEmpty { l += ["", "DANIŞMAN NOTU (bu bilgileri de kullan)", not.kirpik] }
        l += ["", "KURALLAR"] + kurallar.enumerated().map { "\($0.offset + 1). \($0.element)" }
        if !a.ekTalimat.kirpik.isEmpty { l.append("\(kurallar.count + 1). \(a.ekTalimat.kirpik)") }
        l += ["", "CEVAP BİÇİMİ (başka hiçbir açıklama, başlık ya da markdown yazma):", "[TR]",
              "<Türkçe \(a.paragraf) paragraf, aralarında boş satır>", "[EN]", "<İngilizce \(a.paragraf) paragraf, aralarında boş satır>"]
        return l.joined(separator: "\n")
    }

    // MARK: Cevap okuma

    static func eslesir(_ s: String, _ desen: String) -> Bool {
        s.range(of: desen, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static let selamlama = "^(sayın\\s+(yetkili|konsolosluk|ilgili).*|dear\\s+(sir|madam|consular|visa).*|to whom it may concern.*)$"
    static let kapanis = "^(saygılarımla|saygılarımla arz ederim|yours (faithfully|sincerely)|sincerely|best regards|kind regards)[,.]?$"
    static let sohbet = "^(işte|tabii|elbette|aşağıda|umarım|başka|here is|here's|sure|certainly|i hope|let me know|below is)\\b"

    static func temizle(_ p: String) -> String {
        var s = p.replacingOccurrences(of: "\\*\\*|__|`+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "^\\s*(paragraf|paragraph)\\s*\\d+\\s*[:.)-]\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "^\\s*\\d+\\s*[.)-]\\s+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.kirpik
    }

    static func paragraflar(_ blok: String, adSoyad: String) -> [String] {
        let ad = adSoyad.kirpik.lowercased(with: Tr.yerel)
        var o = blok.components(separatedBy: "\n").reduce(into: [[String]]([[]])) { acc, satir in
            if satir.kirpik.isEmpty { acc.append([]) } else { acc[acc.count - 1].append(satir) }
        }.map { temizle($0.joined(separator: "\n")) }.filter { !$0.isEmpty }
        while let ilk = o.first, eslesir(ilk, selamlama) || eslesir(ilk, sohbet) { o.removeFirst() }
        while let son = o.last {
            if eslesir(son, kapanis) || eslesir(son, sohbet) || (!ad.isEmpty && son.lowercased(with: Tr.yerel) == ad) { o.removeLast(); continue }
            if eslesir(son, "^(saygılarımla|yours faithfully|yours sincerely)[,.]?\\s+(.+)$") { o.removeLast(); continue }
            break
        }
        return o
    }

    /// Yapay zekânın cevabını Türkçe ve İngilizce paragraflara ayırır (panel: cevapOku).
    public static func cevapOku(_ metin: String, adSoyad: String, paragraf: Int) -> (tr: [String], en: [String], uyarilar: [String]) {
        let s = metin.replacingOccurrences(of: "\r", with: "")
        var uyari: [String] = []
        let desen = "^\\s*(?:#+\\s*|\\*\\*)?\\s*\\[?\\s*(TR|EN|TÜRKÇE|TURKCE|TURKISH|İNGİLİZCE|INGILIZCE|ENGLISH)\\s*\\]?\\s*(?:\\*\\*)?\\s*:?\\s*$"
        let re = try? NSRegularExpression(pattern: desen, options: [.caseInsensitive, .anchorsMatchLines])
        let ns = s as NSString
        let bulunan: [(dil: String, bas: Int, son: Int)] = (re?.matches(in: s, range: NSRange(location: 0, length: ns.length)) ?? []).map { m in
            let e = ns.substring(with: m.range(at: 1)).uppercased(with: Tr.yerel)
            let tr = ["TR", "TÜRKÇE", "TURKCE", "TURKISH"].contains(e)
            return (tr ? "tr" : "en", m.range.location, m.range.location + m.range.length)
        }
        var tr: [String] = [], en: [String] = []
        if bulunan.isEmpty {
            uyari.append("Cevapta [TR] / [EN] işaretleri yok; metnin tamamı tek dil sayıldı. Diğer dili ayrıca yapıştırın.")
            let tumu = paragraflar(s, adSoyad: adSoyad)
            let birlesik = tumu.joined(separator: " ")
            let turkce = birlesik.range(of: "[ğışçöüİĞŞ]", options: .regularExpression) != nil
                && eslesir(birlesik, "\\b(ve|bir|için|ile)\\b")
            if turkce { tr = tumu } else { en = tumu }
        } else {
            for (i, b) in bulunan.enumerated() {
                let son = i + 1 < bulunan.count ? bulunan[i + 1].bas : ns.length
                let p = paragraflar(ns.substring(with: NSRange(location: b.son, length: max(0, son - b.son))), adSoyad: adSoyad)
                if b.dil == "tr" { tr += p } else { en += p }
            }
        }
        if tr.isEmpty { uyari.append("Türkçe metin bulunamadı.") }
        if en.isEmpty { uyari.append("İngilizce metin bulunamadı.") }
        if !tr.isEmpty && tr.count != paragraf { uyari.append("Türkçe \(tr.count) paragraf (beklenen \(paragraf)).") }
        if !en.isEmpty && en.count != paragraf { uyari.append("İngilizce \(en.count) paragraf (beklenen \(paragraf)).") }
        return (tr, en, uyari)
    }

    // MARK: Yerleşim (örnek dilekçeden ölçülen değerler, pt; y aşağıdan)

    public enum Olcu {
        public static let genislik: Double = 595.32, yukseklik: Double = 841.92, sol: Double = 71, sag: Double = 71, punto: Double = 11
        static let hitapY: [Double] = [761, 738, 716], tarihY: Double = 693, selamY: Double = 671, govdeY: Double = 648
        static let satir: Double = 14.6, paragraf: Double = 22.5, altSinir: Double = 72, ustY: Double = 761
    }

    public struct Satir: Equatable { public var x: Double; public var y: Double; public var metin: String }

    /// Kelime kelime satır kırma.
    public static func satirKir(_ metin: String, olc: (String) -> Double, genislik: Double) -> [String] {
        var satirlar: [String] = []
        var cari = ""
        for k in metin.split(whereSeparator: \.isWhitespace).map(String.init) {
            let aday = cari.isEmpty ? k : "\(cari) \(k)"
            if cari.isEmpty || olc(aday) <= genislik { cari = aday; continue }
            satirlar.append(cari)
            cari = k
        }
        if !cari.isEmpty { satirlar.append(cari) }
        return satirlar
    }

    /// Bir dilin sayfaları (panel: yerlesim; dul/öksüz satır kuralıyla).
    public static func yerlesim(hitap: [String], tarih: String, selam: String, paragraflar: [String], kapanis: String, imza: String,
                                olc: (String) -> Double) -> [[Satir]] {
        typealias O = Olcu
        let genislik = O.genislik - O.sol - O.sag
        var sayfalar: [[Satir]] = [[]]
        func yaz(_ x: Double, _ y: Double, _ m: String) { sayfalar[sayfalar.count - 1].append(Satir(x: x, y: y, metin: m)) }
        for (i, s) in hitap.prefix(3).enumerated() where !s.isEmpty { yaz(O.sol, O.hitapY[i], s) }
        if !tarih.isEmpty { yaz(O.genislik - O.sag - olc(tarih), O.tarihY, tarih) }
        if !selam.isEmpty { yaz(O.sol, O.selamY, selam) }
        var y = O.govdeY + O.satir
        var ilk = true
        func yeniSayfa() { sayfalar.append([]); y = O.ustY + O.satir }
        func sigan(_ yIlk: Double) -> Int { yIlk < O.altSinir ? 0 : Int(floor((yIlk - O.altSinir) / O.satir)) + 1 }
        for p in paragraflar {
            let satirlar = satirKir(p, olc: olc, genislik: genislik)
            y -= ilk ? O.satir : O.paragraf
            ilk = false
            var bolum = min(sigan(y), satirlar.count)
            if bolum < satirlar.count {
                if satirlar.count - bolum == 1 && bolum >= 2 { bolum -= 1 }
                if bolum == 1 && satirlar.count > 1 { bolum = 0 }
            }
            if bolum == 0 { yeniSayfa(); y -= O.satir; bolum = min(sigan(y), satirlar.count) }
            for (i, s) in satirlar.enumerated() {
                if i > 0 { y -= O.satir }
                if i == bolum { yeniSayfa(); y -= O.satir; bolum += sigan(y) }
                yaz(O.sol, y, s)
            }
        }
        for s in [kapanis, imza] where !s.isEmpty {
            y -= O.paragraf
            if y < O.altSinir { yeniSayfa(); y -= O.satir }
            yaz(O.sol, y, s)
        }
        return sayfalar
    }

    /// Kayıt: private/mektup baştan yazılır (panel: kaydet). PDF'ten sonra işlem kaydı da.
    public static func kaydet(_ basvuruId: String, bilgiler: MektupBilgileri, not: String, secilenler: [String], tr: [String], en: [String],
                              pdf: Bool = false, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        var y: [FirestoreIstemci.Yazim] = [
            .yaz(yol: "applications/\(basvuruId)/private/mektup", alanlar: [
                "bilgiler": .harita(bilgiler.alanlar), "not": .metin(String(not.prefix(2000))),
                "secilenler": .dizi(secilenler.prefix(100).map { FSDeger.metin($0) }),
                "metin": .harita(["tr": .dizi(tr.prefix(30).map { FSDeger.metin($0) }), "en": .dizi(en.prefix(30).map { FSDeger.metin($0) })]),
                "updatedBy": .metin(c.uid),
            ], zaman: ["updatedAt"]),
        ]
        if pdf {
            y.append(.olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                              alanlar: IslemKaydi.alanlar(eylem: "app.mektup", hedef: basvuruId,
                                                          ayrinti: "\(tr.filter { !$0.kirpik.isEmpty }.count)+\(en.filter { !$0.kirpik.isEmpty }.count) paragraf", calisan: c),
                              zaman: ["at"]))
        }
        return y
    }
}
