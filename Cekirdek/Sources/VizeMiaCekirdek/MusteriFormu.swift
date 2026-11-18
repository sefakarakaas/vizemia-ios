import Foundation

// Müşteri formu: danışman telefonda birkaç bilgi alır, müşteriye bir bağlantı
// gönderir; müşteri takip kodu + pasaport numarasıyla açar, kalanını doldurur.
// Panel karşılıkları:
//   panel/js/musteri-formu.js      soru listesi, ön dolgu, formu kurma/kapama, cevap aktarma
//   panel/js/pages/form-panel.js   başvuru ayrıntısındaki bölüm
//   panel/js/form-gonderim.js      formun ne zaman gideceği (kural)
//   panel/js/bildirim.js           planFormLinki (kurala göre bildirim planı)
// Sorular gönderim anında belgeye kopyalanır (settings/forms müşteriye açık değil;
// müşteri doldururken ayar değişirse formun altından kaymasın).

// MARK: - Gönderim kuralı

public struct FormGonderimKurali: Equatable {
    /// Danışmana görünen adlar (panel: GONDERIM_MODLARI).
    public static let modlar: [(id: String, ad: String)] = [
        ("onay", "Başvuru onaylanınca hemen"),
        ("randevu-once", "Randevudan N gün önce"),
        ("baslangic-sonra", "Süreç başladıktan N gün sonra"),
        ("elle", "Elle — danışman gönderir"),
    ]
    /// Gün sayısı isteyen modlar.
    public static let gunIsteyen: Set<String> = ["randevu-once", "baslangic-sonra"]

    public enum Kaynak: String { case basvuru, ulke, varsayilan
        public var ad: String {
            switch self {
            case .basvuru: return "bu başvuru için ayarlandı"
            case .ulke: return "ülke varsayılanı"
            case .varsayilan: return "kural tanımlı değil"
            }
        }
    }

    public var mod: String
    public var gun: Int

    /// Tanınmayan mod "elle" sayılır: bozuk ayar yüzünden form beklenmedik anda gitmesin (panel: normalizeKural).
    public init(mod: String, gun: Int) {
        let m = Self.modlar.contains { $0.id == mod } ? mod : "elle"
        self.mod = m
        self.gun = Self.gunIsteyen.contains(m) ? min(365, max(0, abs(gun))) : 0
    }

    /// Kayıttan; mod tanınmıyorsa nil (üst kural geçerli olsun diye).
    public init?(alanlar a: [String: FSDeger]) {
        guard let m = a["mod"]?.metinDegeri, Self.modlar.contains(where: { $0.id == m }) else { return nil }
        var g = 0
        if let t = a["gun"]?.tamDegeri { g = t }
        if case .ondalik(let v)? = a["gun"] { g = Int(v) }
        if case .metin(let s)? = a["gun"] { g = Int(s) ?? 0 }
        self.init(mod: m, gun: g)
    }

    public static let varsayilan = FormGonderimKurali(mod: "elle", gun: 0)

    /// Bu başvurunun kuralı ve nereden geldiği (panel: kuralFor).
    public static func gecerli(basvuru: FormGonderimKurali?, ulke: FormGonderimKurali?) -> (kural: FormGonderimKurali, kaynak: Kaynak) {
        if let b = basvuru { return (b, .basvuru) }
        if let u = ulke { return (u, .ulke) }
        return (varsayilan, .varsayilan)
    }

    public var alanlar: [String: FSDeger] { ["mod": .metin(mod), "gun": .tam(gun)] }

    /// Tek cümle (panel: kuralOzet).
    public var ozet: String {
        if mod == "randevu-once" { return "Randevudan \(gun) gün önce" }
        if mod == "baslangic-sonra" { return "Süreç başladıktan \(gun) gün sonra" }
        return Self.modlar.first { $0.id == mod }?.ad ?? mod
    }

    /// Formun gideceği an; nil: kendiliğinden gitmeyecek (elle) ya da gereken tarih
    /// henüz yok. `gecti`: hesaplanan an geçmiş, ilk uygun saate çekildi (panel: gonderimZamani).
    public func zaman(baslangic: String?, randevu: String?, simdi: Date, bas: Int, son: Int) -> (an: Date, gecti: Bool)? {
        if mod == "elle" { return nil }
        if mod == "onay" { return (BildirimZamani.pencereye(simdi, bas: bas, son: son), false) }
        let taban = mod == "randevu-once" ? randevu : baslangic
        guard let t = taban, Tr.tarih(t) != nil else { return nil }
        let an = BildirimZamani.an(Tr.gunEkle(t, mod == "randevu-once" ? -gun : gun), saat: bas)
        if an <= simdi { return (BildirimZamani.pencereye(simdi, bas: bas, son: son), true) }
        return (an, false)
    }
}

// MARK: - Form kaydı (formlar/{takipId})

public struct MusteriFormuKaydi: Equatable {
    public static let durumAdlari = [
        "gonderildi": "Gönderildi, bekleniyor", "taslak": "Müşteri dolduruyor",
        "tamamlandi": "Müşteri tamamladı", "kapandi": "Kapatıldı",
    ]

    public struct Soru: Equatable {
        public var key: String
        public var label: String
        public var options: [FormSecenegi]
        /// Koşullu soru (Hollanda): ne zaman sorulduğu. Ham hâliyle tutulur.
        public var kosul: FSDeger?
        public var varsayilan: String
    }

    /// Müşterinin sorusu ve (varsa) cevabımız.
    public struct MusteriSorusu: Equatable {
        public var alan: String
        public var metin: String
        public var zaman: String
        public var cevap: String
        public var cevapZamani: String
        public var cevaplayan: String
    }

    public var durum: String
    public var sorular: [Soru]
    public var onDolgu: [String: String]
    public var cevaplar: [String: String]
    public var musteriSorulari: [MusteriSorusu]
    /// questionsAsked'ın okunan hâli: cevap yazılırken öteki maddeler aynen geri yazılır.
    public var hamSorular: [FSDeger]
    public var aramaModu: String
    public var aramaGunu: String
    public var aramaSaatleri: [String]
    public var guncelleme: Date?

    public var durumAdi: String { Self.durumAdlari[durum] ?? durum }

    public init(alanlar a: [String: FSDeger]) {
        func metin(_ d: FSDeger?) -> String {
            switch d {
            case .metin(let s)?: return s
            case .tam(let n)?: return String(n)
            case .ondalik(let v)?: return v == v.rounded() ? String(Int(v)) : String(v)
            case .mantik(let b)?: return b ? "true" : "false"
            default: return ""
            }
        }
        durum = a["status"]?.metinDegeri ?? ""
        sorular = (a["questions"]?.diziDegeri ?? []).compactMap { d in
            guard let h = d.haritaDegeri, let k = h["key"]?.metinDegeri else { return nil }
            let o = (h["options"]?.diziDegeri ?? []).compactMap { x -> FormSecenegi? in
                guard let m = x.haritaDegeri else { return nil }
                return FormSecenegi(value: metin(m["value"]), label: metin(m["label"]))
            }
            return Soru(key: k, label: h["label"]?.metinDegeri ?? k, options: o, kosul: h["showIf"], varsayilan: metin(h["default"]))
        }
        onDolgu = (a["prefill"]?.haritaDegeri ?? [:]).mapValues { metin($0) }
        cevaplar = (a["answers"]?.haritaDegeri ?? [:]).mapValues { metin($0) }
        hamSorular = a["questionsAsked"]?.diziDegeri ?? []
        musteriSorulari = hamSorular.compactMap { d in
            guard let h = d.haritaDegeri else { return nil }
            return MusteriSorusu(alan: metin(h["field"]), metin: metin(h["text"]), zaman: metin(h["at"]),
                                 cevap: metin(h["reply"]), cevapZamani: metin(h["repliedAt"]), cevaplayan: metin(h["repliedBy"]))
        }
        aramaModu = a["callMode"]?.metinDegeri ?? ""
        aramaGunu = a["callDate"]?.metinDegeri ?? ""
        aramaSaatleri = (a["callTimes"]?.diziDegeri ?? []).compactMap { $0.metinDegeri }
        guncelleme = a["updatedAt"]?.zamanDegeri
    }

    /// Cevap satırları: müşterinin cevabı ya da telefonda alınan; boşlar atlanır.
    public var satirlar: [(soru: String, cevap: String, musteriden: Bool)] {
        sorular.compactMap { q in
            let v = cevaplar[q.key] ?? onDolgu[q.key] ?? ""
            guard !v.kirpik.isEmpty else { return nil }
            let gorunen = q.options.first { $0.value == v }?.label ?? v
            return (q.label, gorunen, cevaplar[q.key] != nil)
        }
    }

    /// KVKK açık rızası (müşteri formundaki onay kutusu; answers.kvkk_riza ISO zaman).
    public var rizaZamani: Date? {
        guard let s = cevaplar["kvkk_riza"], !s.isEmpty else { return nil }
        return MusteriFormuKaydi.isoOku(s)
    }

    static func isoOku(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Kaç soru dolu; koşulu sağlanmayan sorular sayılmaz (panel: fillRatio).
    public func doluluk(bugun: String = Tr.bugun()) -> (dolu: Int, toplam: Int) {
        var degerler: [String: String] = [:]
        for q in sorular where !q.varsayilan.isEmpty { degerler[q.key] = q.varsayilan }
        for (k, v) in onDolgu { degerler[k] = v }
        for (k, v) in cevaplar { degerler[k] = v }
        let acik = FormKosulu.gorunenler(sorular.map { ($0.key, $0.kosul) }, degerler, bugun: bugun)
        let gorunen = sorular.filter { acik.contains($0.key) }
        return (gorunen.filter { !(degerler[$0.key] ?? "").kirpik.isEmpty }.count, gorunen.count)
    }

    /// Müşterinin cevaplarından başvuru formuna yazılacaklar: yalnız ülkenin bilinen
    /// alanları (uydurma anahtar sızmasın), 500 karakter; formdakiyle aynı olanlar
    /// atlanır (panel: answersIntoForm + transferRow).
    public func aktarilacaklar(alanlar: [FormAlani], form: [String: FSDeger]) -> [(key: String, etiket: String, deger: String)] {
        let bilinen = Set(alanlar.map(\.key))
        return cevaplar.keys.sorted().compactMap { k in
            guard bilinen.contains(k), let v = cevaplar[k] else { return nil }
            let d = String(v.prefix(500))
            guard (form[k]?.metinDegeri ?? "") != d else { return nil }
            let etiket = sorular.first { $0.key == k }?.label ?? alanlar.first { $0.key == k }?.label ?? k
            return (k, etiket, d)
        }
    }

    /// Cevaplanmamış müşteri soruları.
    public var acikSorular: Int { musteriSorulari.filter { $0.cevap.isEmpty }.count }

    /// "Hemen aranmak istiyor" ya da "2026-11-20 · 10:00, 10:30".
    public var aramaMetni: String? {
        guard !aramaModu.isEmpty else { return nil }
        return aramaModu == "hemen" ? "Hemen aranmak istiyor" : "\(aramaGunu) · \(aramaSaatleri.joined(separator: ", "))"
    }
}

// MARK: - Koşullu sorular (form-kosul.js)

/// Hangi sorunun sorulacağı (panel ve site: form-kosul.js → gorunenler). Sorular
/// sırayla değerlendirilir; gizli sorunun cevabı boş sayılır.
public enum FormKosulu {
    public static func gorunenler(_ sorular: [(key: String, kosul: FSDeger?)], _ degerler: [String: String], bugun: String) -> Set<String> {
        var etkin = degerler
        var acik = Set<String>()
        for q in sorular {
            if saglaniyor(q.kosul, etkin, bugun: bugun) { acik.insert(q.key) } else { etkin[q.key] = "" }
        }
        return acik
    }

    static func coklu(_ v: String) -> [String] { v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    static func yas(_ dogum: String, _ bugun: String) -> Int? {
        guard Tr.tarih(dogum) != nil, Tr.tarih(bugun) != nil else { return nil }
        let d = dogum.split(separator: "-").compactMap { Int($0) }, b = bugun.split(separator: "-").compactMap { Int($0) }
        var y = b[0] - d[0]
        if b[1] < d[1] || (b[1] == d[1] && b[2] < d[2]) { y -= 1 }
        return y
    }

    /// Ay ekler; ay sonu taşarsa JS Date gibi sonraki aya kayar.
    static func ayEkle(_ iso: String, _ ay: Int) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        var c = DateComponents(); c.year = p[0]; c.month = p[1] + ay; c.day = p[2]; c.hour = 12
        guard let d = Tr.takvim.date(from: c) else { return iso }
        return Tr.bugun(d)
    }

    static func saglaniyor(_ k: FSDeger?, _ d: [String: String], bugun: String) -> Bool {
        guard let k, let m = k.haritaDegeri else { return true }
        if let l = m["hepsi"]?.diziDegeri { return l.allSatisfy { saglaniyor($0, d, bugun: bugun) } }
        if let l = m["herhangi"]?.diziDegeri { return l.contains { saglaniyor($0, d, bugun: bugun) } }
        func sayi(_ x: FSDeger?) -> Int {
            if let t = x?.tamDegeri { return t }
            if case .ondalik(let v)? = x { return Int(v) }
            return 0
        }
        if let y = m["yasKucuk"]?.haritaDegeri {
            guard let a = yas(d[y["key"]?.metinDegeri ?? ""] ?? "", bugun) else { return false }
            return a < sayi(y["yas"])
        }
        if let y = m["yasEnAz"]?.haritaDegeri {
            guard let a = yas(d[y["key"]?.metinDegeri ?? ""] ?? "", bugun) else { return true }
            return a >= sayi(y["yas"])
        }
        if let y = m["ayIleri"]?.haritaDegeri {
            let v = (d[y["key"]?.metinDegeri ?? ""] ?? "").kirpik
            guard Tr.tarih(v) != nil else { return false }
            return v >= ayEkle(bugun, sayi(y["ay"]))
        }
        let v = (d[m["key"]?.metinDegeri ?? ""] ?? "").kirpik
        if let e = m["esit"] { return v == (e.metinDegeri ?? "") }
        if let l = m["icinde"]?.diziDegeri { return l.compactMap(\.metinDegeri).contains(v) }
        if let l = m["degil"]?.diziDegeri { return !v.isEmpty && !l.compactMap(\.metinDegeri).contains(v) }
        if let e = m["iceriyor"]?.metinDegeri { return coklu(v).contains(e) }
        if m["enAz"] != nil { return coklu(v).count >= sayi(m["enAz"]) }
        return true
    }
}

// MARK: - Yazımlar

public enum MusteriFormu {
    typealias Y = FirestoreIstemci.Yazim

    /// Müşteriye gösterilmeyen alanlar: kendimiz doldurduklarımız.
    static let panelde = Set(["nationalId"])

    /// O ülke için müşteriye sorulacaklar (panel: questionsFor → toQuestion).
    /// Müşteri formu dört tip bilir: text, textarea, select, date. Hollanda'nın
    /// portal şablonu (bölümler, koşullar) uygulamada yok; onu panel gönderir.
    public static func sorular(_ alanlar: [FormAlani], iller: [String]) -> [FSDeger] {
        alanlar.filter { !$0.kapali && !panelde.contains($0.key) }.map { f in
            var q: [String: FSDeger] = ["key": .metin(f.key), "label": .metin(f.label), "required": .mantik(f.required)]
            let secenek = f.options.filter { !$0.value.isEmpty }
            if !f.options.isEmpty {
                q["type"] = .metin("select")
                q["options"] = .dizi(secenek.map { .harita(["value": .metin($0.value), "label": .metin($0.label)]) })
                q["help"] = .metin("")
            } else if f.type == "province" {
                q["type"] = .metin("select")
                q["options"] = .dizi(iller.map { .harita(["value": .metin($0), "label": .metin($0)]) })
                q["help"] = .metin("")
            } else if f.type == "date" || f.type == "textarea" {
                q["type"] = .metin(f.type)
                q["help"] = .metin("")
            } else {
                q["type"] = .metin("text")
                q["help"] = .metin(f.type == "district" ? "İlçe adını yazın." : "")
            }
            return .harita(q)
        }
    }

    /// Başvuruda dolu olan değerler → müşteriye "telefonda söylediğiniz" (panel: prefillFrom).
    public static func onDolgu(_ form: [String: FSDeger], sorular: [FSDeger]) -> [String: FSDeger] {
        var o: [String: FSDeger] = [:]
        for q in sorular {
            guard let k = q.haritaDegeri?["key"]?.metinDegeri else { continue }
            let v: String
            switch form[k] {
            case .metin(let s)?: v = s
            case .tam(let n)?: v = String(n)
            case .mantik(let b)?: v = b ? "true" : "false"
            default: v = ""
            }
            if !v.kirpik.isEmpty { o[k] = .metin(String(v.prefix(1000))) }
        }
        return o
    }

    /// Müşteriye giden hazır SMS (panel: formSmsText; ASCII, tek parça kalsın diye).
    public static func smsMetni(_ b: Basvuru) -> String {
        "Sayin \(b.ad), VizeMia basvuru formunuz hazir: \(BildirimMetni.formBaglantisi(b.takipKodu)) "
            + "Formu acmak icin pasaport numaranizi yazmaniz yeterli. Takip kodu: \(b.takipKodu)"
    }

    public struct Hazirlik {
        public var yazimlar: [FirestoreIstemci.Yazim]
        /// SMS istendi ama sıraya alınamadı (telefon ya da SMS ayarı eksik).
        public var smsAlinamadi: Bool
    }

    /// Formu kurar ya da yeniler; müşterinin cevaplarına ve sorularına dokunulmaz
    /// (panel: upsertForm). Yenilemede yalnız değişen alanlar yazılır: kapalı form
    /// yeniden "gönderildi" olur, müşteri doldurmaya başladıysa durum geri alınmaz.
    public static func hazirla(
        _ b: Basvuru, form: [String: FSDeger], takipId: String, onceki: MusteriFormuKaydi?, sorular: [FSDeger],
        sms: Bool, smsAyari: SmsAyari, calisan c: Calisan
    ) -> Hazirlik {
        let yol = "formlar/\(takipId)"
        var a: [String: FSDeger] = [
            "appId": .metin(b.kimlik), "code": .metin(String(b.takipKodu.prefix(20))),
            "countryName": .metin(String(b.ulkeAdi.prefix(60))),
            "questions": .dizi(Array(sorular.prefix(150))), "prefill": .harita(onDolgu(form, sorular: sorular)),
            "updatedBy": .metin(c.uid),
        ]
        var y: [Y] = []
        if let o = onceki {
            if o.durum == "kapandi" { a["status"] = .metin("gonderildi") }
            y.append(.guncelle(yol: yol, alanlar: a, zaman: ["updatedAt"]))
        } else {
            a["answers"] = .harita([:])
            a["questionsAsked"] = .dizi([])
            a["status"] = .metin("gonderildi")
            a["createdBy"] = .metin(c.uid)
            y.append(.olustur(yol: yol, alanlar: a, zaman: ["createdAt", "updatedAt"]))
        }
        var kuyrukta = false
        if sms {
            let to = MusteriBildirimi.e164(form["phone"]?.metinDegeri ?? "")
            let metin = String(MusteriBildirimi.ascii(smsMetni(b)).prefix(MusteriMesaji.smsEnCok))
            if smsAyari.acik, !to.isEmpty {
                y.append(.olustur(yol: "sms/\(FirestoreIstemci.yeniKimlik())", alanlar: [
                    "to": .metin(to), "text": .metin(metin), "appId": .metin(b.kimlik), "trackingCode": .metin(b.takipKodu),
                    "status": .metin("queued"), "attempts": .tam(0), "tur": .metin("form"),
                    "createdBy": .metin(c.uid), "byName": .metin(String(c.gorunenAd.prefix(80))),
                ], zaman: ["createdAt"]))
                kuyrukta = true
            }
        }
        y.append(BasvuruIslemi.gecmis(b, tur: "form", metin: kuyrukta ? "Müşteri formu gönderildi (SMS)." : "Müşteri formu hazırlandı.", c))
        y.append(BasvuruIslemi.kayit("form.send", b, kuyrukta ? "sms" : "link", c))
        return Hazirlik(yazimlar: y, smsAlinamadi: sms && !kuyrukta)
    }

    /// Formu kapatır: müşteri artık değiştiremez.
    public static func kapat(takipId: String, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.guncelle(yol: "formlar/\(takipId)", alanlar: ["status": .metin("kapandi"), "updatedBy": .metin(c.uid)], zaman: ["updatedAt"])]
    }

    /// Müşterinin sorusuna cevap; öteki maddeler okunduğu gibi geri yazılır (panel: replyToQuestion).
    public static func cevapla(takipId: String, kayit: MusteriFormuKaydi, sira: Int, metin: String, calisan c: Calisan,
                               simdi: Date = Date()) -> [FirestoreIstemci.Yazim]? {
        let t = metin.kirpik
        guard !t.isEmpty, kayit.hamSorular.indices.contains(sira), var m = kayit.hamSorular[sira].haritaDegeri else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        m["reply"] = .metin(String(t.prefix(1000)))
        m["repliedAt"] = .metin(f.string(from: simdi))
        m["repliedBy"] = .metin(String(c.gorunenAd.prefix(80)))
        var l = kayit.hamSorular
        l[sira] = .harita(m)
        return [.guncelle(yol: "formlar/\(takipId)", alanlar: ["questionsAsked": .dizi(l), "updatedBy": .metin(c.uid)], zaman: ["updatedAt"])]
    }

    /// Müşterinin cevaplarını başvuru formuna yazar (yalnız değişen alanlar).
    public static func aktar(_ b: Basvuru, _ l: [(key: String, etiket: String, deger: String)], calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        guard !l.isEmpty else { return [] }
        var a: [[String]: FSDeger] = [["updatedBy"]: .metin(c.uid)]
        for x in l { a[["form", x.key]] = .metin(x.deger) }
        return [
            .derin(yol: "applications/\(b.kimlik)/private/data", alanlar: a, zaman: [["updatedAt"]]),
            BasvuruIslemi.gecmis(b, tur: "form", metin: "Müşteri formundan \(l.count) bilgi aktarıldı.", c),
            BasvuruIslemi.kayit("form.transfer", b, String(l.count), c),
        ]
    }

    /// Bu başvurunun gönderim kuralını kaydeder ve form bağlantısını yeniden planlar
    /// (panel: zamanBlock → planFormLinki). `durum` danışmana gösterilir.
    public static func kuralKaydet(
        _ b: Basvuru, kural: FormGonderimKurali, iletisim: MusteriIletisimi, ayar: BildirimAyari,
        mevcut: [BildirimKaydi], calisan c: Calisan, simdi: Date = Date()
    ) -> (yazimlar: [FirestoreIstemci.Yazim], durum: String) {
        var y: [Y] = [
            .guncelle(yol: "applications/\(b.kimlik)", alanlar: ["formGonderim": .harita(kural.alanlar), "updatedBy": .metin(c.uid)],
                      zaman: ["updatedAt"]),
            BasvuruIslemi.kayit("form.kural", b, "\(kural.mod)/\(kural.gun)", c),
        ]
        let p = BildirimPlani.formLinki(b, kural: kural, iletisim: iletisim, ayar: ayar, mevcut: mevcut, calisan: c, simdi: simdi)
        y += p.yazimlar
        let durum: String
        if let an = p.an {
            durum = "\(kural.ozet) — \(Tr.tarihSaat(an))\(p.gecti ? " (zamanı geçtiği için ilk fırsatta)" : "")"
        } else {
            durum = "\(kural.ozet) — \(p.durum)."
        }
        return (y, durum)
    }
}

extension BildirimPlani {
    /// Form bağlantısını kurala göre planlar (panel: planFormLinki). Gönderilmişse
    /// yeniden planlanmaz; planlı olan iptal edilip yenisi yazılır.
    public static func formLinki(
        _ b: Basvuru, kural: FormGonderimKurali, iletisim: MusteriIletisimi, ayar: BildirimAyari,
        mevcut: [BildirimKaydi], calisan c: Calisan, simdi: Date = Date()
    ) -> (yazimlar: [FirestoreIstemci.Yazim], durum: String, an: Date?, gecti: Bool) {
        guard ayar.acik else { return ([], "bildirimler kapalı", nil, false) }
        guard let t = ayar.sablonlar(ulke: b.ulke)["form-linki"], t.acik else { return ([], "şablon kapalı", nil, false) }
        let k = kanallar(iletisim, ayar)
        guard k.wa || k.sms || k.email else { return ([], "açık kanal yok", nil, false) }
        let baslangic = (b.acilis ?? b.olusturma).map { Tr.bugun($0) }
        let randevu = b.randevu.map { Tr.bugun($0) }
        guard let plan = kural.zaman(baslangic: baslangic, randevu: randevu, simdi: simdi, bas: ayar.pencereBas, son: ayar.pencereSon) else {
            return ([], kural.mod == "elle" ? "elle gönderilecek" : "tarih henüz belli değil", nil, false)
        }
        if mevcut.contains(where: { $0.tur == "form-linki" && $0.durum == "sent" }) { return ([], "zaten gönderilmiş", nil, false) }
        var y: [FirestoreIstemci.Yazim] = mevcut.filter { $0.tur == "form-linki" && $0.durum == "planned" }.map {
            .guncelle(yol: "bildirimler/\($0.id)", alanlar: [
                "status": .metin("cancelled"), "cancelReason": .metin("Gönderim kuralı güncellendi"), "updatedBy": .metin(c.uid),
            ], zaman: ["updatedAt"])
        }
        let sorumlu = b.sorumluUid.isEmpty ? c.uid : b.sorumluUid
        let sorumluAd = b.sorumluUid.isEmpty ? c.gorunenAd : b.sorumlu
        var a: [String: FSDeger] = [:]
        a["appId"] = .metin(b.kimlik)
        a["trackingCode"] = .metin(String(b.takipKodu.prefix(20)))
        a["kind"] = .metin("form-linki")
        a["status"] = .metin("planned")
        a["channels"] = .harita(["wa": .mantik(k.wa), "sms": .mantik(k.sms), "email": .mantik(k.email)])
        a["name"] = .metin(String("\(b.ad) \(b.soyad)".kirpik.prefix(160)))
        a["countryName"] = .metin(String(b.ulkeAdi.prefix(60)))
        a["country"] = .metin(String(b.ulke.prefix(40)))
        // Bu mesaj randevudan bağımsız; tarihler boş geçilebilir (kural form-linki için izin veriyor).
        a["appointmentDate"] = .metin(randevu ?? "")
        a["docDeadline"] = .metin("")
        a["reminderDays"] = .tam(0)
        a["randevuSaati"] = .metin(""); a["randevuMerkezi"] = .metin(""); a["randevuSehri"] = .metin("")
        a["randevuYeri"] = .metin(""); a["randevuHarita"] = .metin("")
        a["phone"] = k.wa || k.sms ? .metin(k.telefon) : .bos
        a["email"] = k.email ? .metin(k.eposta) : .bos
        a["assignedTo"] = .metin(String(sorumlu.prefix(60)))
        a["assignedName"] = .metin(String(sorumluAd.prefix(80)))
        a["waStatus"] = .metin(k.wa ? "pending" : "skipped")
        a["attempts"] = .tam(0)
        a["sentAt"] = .bos
        a["force"] = .mantik(false)
        a["sendAt"] = .zaman(plan.an)
        a["createdBy"] = .metin(c.uid)
        a["updatedBy"] = .metin(c.uid)
        y.append(.olustur(yol: "bildirimler/\(FirestoreIstemci.yeniKimlik())", alanlar: a, zaman: ["createdAt", "updatedAt"]))
        return (y, "planlandı", plan.an, plan.gecti)
    }
}
