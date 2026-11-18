import Foundation

// Pasaport makine okunabilir alanı (MRZ) — TD3: 2 satır × 44 karakter.
// Panelin karşılığı: panel/js/mrz.js (aynı onarım kuralları; testler
// tests/mrz-parse.test.mjs, tests/mrz-band.test.mjs örnekleriyle).
// Hiçbir veri dışarı gönderilmez; okuma telefonda yapılır.

public enum Mrz {
    static func deger(_ c: Character) -> Int {
        if let v = c.asciiValue {
            if v >= 48 && v <= 57 { return Int(v) - 48 }
            if v >= 65 && v <= 90 { return Int(v) - 55 }
        }
        return 0   // '<' ve tanınmayanlar
    }

    public static func kontrolHanesi(_ s: String) -> String {
        let a = [7, 3, 1]
        var t = 0
        for (i, c) in s.enumerated() { t += deger(c) * a[i % 3] }
        return String(t % 10)
    }

    /// OCR'ın sık karıştırdığı karakterleri MRZ alfabesine çeker.
    public static func temizle(_ satir: String) -> String {
        String(satir.uppercased().map { c -> Character in
            if c == "«" || c == "»" || c.isWhitespace { return "<" }
            if let v = c.asciiValue, (v >= 65 && v <= 90) || (v >= 48 && v <= 57) || c == "<" { return c }
            return "<"
        })
    }

    // MARK: Yardımcılar (karakter dizisiyle konum işlemleri)

    static func dilim(_ s: String, _ a: Int, _ b: Int) -> String {
        let k = Array(s)
        let x = max(0, min(a, k.count)), y = max(x, min(b, k.count))
        return String(k[x..<y])
    }
    static func karakter(_ s: String, _ i: Int) -> String {
        let k = Array(s)
        return i >= 0 && i < k.count ? String(k[i]) : ""
    }
    static func koy(_ s: String, _ a: Int, _ b: Int, _ v: String) -> String { dilim(s, 0, a) + v + dilim(s, b, Int.max) }
    static func doldur(_ s: String) -> String {
        let k = Array(s)
        return k.count >= 44 ? String(k.prefix(44)) : s + String(repeating: "<", count: 44 - k.count)
    }

    static let rakama: [Character: Character] = ["O": "0", "Q": "0", "D": "0", "U": "0", "I": "1", "L": "1", "Z": "2", "S": "5", "B": "8", "G": "6"]
    static let harfe: [Character: Character] = ["0": "O", "1": "I", "2": "Z", "5": "S", "8": "B", "6": "G"]
    static func rakamaZorla(_ s: String) -> String { String(s.map { $0.isNumber ? $0 : (rakama[$0] ?? $0) }) }
    static func harfeZorla(_ s: String) -> String {
        String(s.map { ($0.isLetter && $0.isUppercase) || $0 == "<" ? $0 : (harfe[$0] ?? $0) })
    }

    /// OCR'ın karıştırdığı karakterler (pasaport numarası onarımı; panel: CONFUSABLE).
    static let karisan: [Character: [Character]] = [
        "0": ["O", "D", "Q", "U"], "O": ["0", "D", "Q", "U"], "D": ["0", "O", "Q", "U"],
        "Q": ["0", "O", "D", "U"], "U": ["0", "O", "D", "Q", "V"], "V": ["U", "Y"],
        "1": ["I", "L"], "I": ["1", "L", "T"], "L": ["1", "I"],
        "2": ["Z"], "Z": ["2"], "5": ["S"], "S": ["5", "8"],
        "6": ["G"], "G": ["6", "C"], "C": ["G", "0"],
        "8": ["B", "S"], "B": ["8"], "4": ["A"], "A": ["4"], "7": ["T"], "T": ["7", "I"],
    ]
    static let harfler = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let rakamlar = Array("0123456789")

    // MARK: Onarım

    /// Pasaport numarasını kontrol hanesiyle onarır; yalnız tek aday tutuyorsa değiştirir.
    public static func pasaportNoOnar(_ satir: String) -> String {
        let alan = dilim(satir, 0, 9), kh = karakter(satir, 9)
        let turk = dilim(satir, 10, 13) == "TUR"
        let makul = { (t: String) in !turk || t.eslesir("^[A-Z][0-9]{8}$") }
        if kontrolHanesi(alan) == kh && makul(alan) { return satir }
        var bulunan = Set<String>()
        let k = Array(alan)
        for i in 0..<k.count {
            let adaylar = k[i] == "<" ? harfler + rakamlar : (karisan[k[i]] ?? [])
            for a in adaylar {
                var t = k; t[i] = a
                let s = String(t)
                if kontrolHanesi(s) == kh && makul(s) { bulunan.insert(s) }
            }
        }
        guard bulunan.count == 1, let tek = bulunan.first else { return satir }
        return tek + dilim(satir, 9, Int.max)
    }

    /// Türk pasaport numarasının baştaki harfi okunamadığında olası harfler.
    public static func harfSecenekleri(_ satir: String) -> [String] {
        let alan = dilim(satir, 0, 9), kh = karakter(satir, 9)
        if alan.eslesir("^[A-Z][0-9]{8}$") && kontrolHanesi(alan) == kh { return [] }
        let geri = dilim(alan, 1, 9)
        guard geri.eslesir("^[0-9]{8}$") else { return [] }
        return harfler.map(String.init).filter { kontrolHanesi($0 + geri) == kh }
    }

    static func gecerliYYAAGG(_ s: String) -> Bool {
        guard s.eslesir("^[0-9]{6}$"), let ay = Int(dilim(s, 2, 4)), let gun = Int(dilim(s, 4, 6)) else { return false }
        return ay >= 1 && ay <= 12 && gun >= 1 && gun <= 31
    }

    /// Tarih alanındaki okunamamış (en çok iki) haneyi kontrol hanesinden geri kazanır.
    public static func tarihOnar(_ satir: String, _ bas: Int) -> String {
        let alan = dilim(satir, bas, bas + 6), kh = karakter(satir, bas + 6)
        if gecerliYYAAGG(alan) && kontrolHanesi(alan) == kh { return satir }
        let k = Array(alan)
        let bilinmeyen = k.indices.filter { !k[$0].isNumber }
        if bilinmeyen.isEmpty || bilinmeyen.count > 2 || k.count < 6 { return satir }
        var bulunan = Set<String>()
        func dene(_ cur: [Character], _ idx: Int) {
            if idx == bilinmeyen.count {
                let s = String(cur)
                if gecerliYYAAGG(s) && kontrolHanesi(s) == kh { bulunan.insert(s) }
                return
            }
            for d in rakamlar { var c = cur; c[bilinmeyen[idx]] = d; dene(c, idx + 1) }
        }
        dene(k, 0)
        guard bulunan.count == 1, let tek = bulunan.first else { return satir }
        return koy(satir, bas, bas + 6, tek)
    }

    /// İkinci satırda konuma göre rakam/harf düzeltmesi; tarihler ve pasaport no kontrol haneleriyle.
    public static func satir2Onar(_ satir: String) -> String {
        var b = satir
        b = koy(b, 9, 10, rakamaZorla(dilim(b, 9, 10)))
        b = koy(b, 10, 13, harfeZorla(dilim(b, 10, 13)))
        b = koy(b, 13, 20, rakamaZorla(dilim(b, 13, 20)))
        b = koy(b, 21, 28, rakamaZorla(dilim(b, 21, 28)))
        b = koy(b, 42, 44, rakamaZorla(dilim(b, 42, 44)))
        if dilim(b, 10, 13) == "TUR" { b = koy(b, 28, 42, rakamaZorla(dilim(b, 28, 42))) }
        b = tarihOnar(b, 13)
        b = tarihOnar(b, 21)
        b = pasaportNoOnar(b)
        return b
    }

    /// Kontrol hanelerinden kaçı tutuyor (0–5).
    public static func tutanSayisi(_ b: String) -> Int {
        var n = 0
        if kontrolHanesi(dilim(b, 0, 9)) == karakter(b, 9) { n += 1 }
        if kontrolHanesi(dilim(b, 13, 19)) == karakter(b, 19) { n += 1 }
        if kontrolHanesi(dilim(b, 21, 27)) == karakter(b, 27) { n += 1 }
        if kontrolHanesi(dilim(b, 28, 42)) == karakter(b, 42) { n += 1 }
        if kontrolHanesi(dilim(b, 0, 10) + dilim(b, 13, 20) + dilim(b, 21, 43)) == karakter(b, 43) { n += 1 }
        return n
    }

    /// İkinci satırın sonunu (kimlik no ve son iki kontrol hanesi) onarır: eksik/fazla '<'.
    /// Yalnız beş kontrol hanesinin beşi de tutan ve tek değer veren aday kabul edilir.
    public static func kuyrukOnar(_ satir: String, derin: Bool = false) -> (satir: String, onarildi: Bool) {
        let temel = temizle(satir)
        let bas = doldur(temel)
        let normal = { (t: String) -> String in
            let f = satir2Onar(t)
            return tutanSayisi(f) >= tutanSayisi(t) ? f : t
        }
        if tutanSayisi(normal(bas)) == 5 { return (bas, false) }
        let from = 28
        let k = Array(temel)
        var tohumlar: [String] = [bas]
        var gorulen: Set<String> = [bas]
        func ekle(_ s: String) { if gorulen.insert(s).inserted { tohumlar.append(s) } }
        if from <= k.count { for i in from...k.count { ekle(doldur(String(k[0..<i]) + "<" + String(k[i...]))) } }
        if from < k.count { for i in from..<k.count { ekle(doldur(String(k[0..<i]) + String(k[(i + 1)...]))) } }
        let turk = dilim(temel, 10, 13) == "TUR"
        let tckn = { (t: String) in dilim(t, 28, 42).replacingOccurrences(of: "<", with: "") }
        func kabul(_ ham: String) -> (ham: String, deger: String)? {
            let t = normal(ham)
            guard tutanSayisi(t) == 5 else { return nil }
            let v = tckn(t)
            if turk && !v.isEmpty && !Harf.tcknGecerli(v) { return nil }
            return (ham, v)
        }
        var iyi: [(ham: String, deger: String)] = []
        for c in tohumlar { if let h = kabul(c) { iyi.append(h) } }
        if iyi.isEmpty && derin {
            let alt: [Character: [Character]] = [
                "<": ["0", "C", "K", "X", "4"], "0": ["<", "O", "D", "U", "8"], "O": ["0", "<"], "D": ["0"], "U": ["0"],
                "C": ["<", "0"], "K": ["<"], "X": ["<"], "1": ["I", "7"], "I": ["1"], "7": ["1"], "2": ["Z"], "Z": ["2"],
                "5": ["S"], "S": ["5"], "6": ["G", "8"], "G": ["6"], "8": ["B", "6", "0"], "B": ["8"], "4": ["A", "<"],
                "A": ["4"], "9": ["G", "4"], "3": ["8"],
            ]
            for c in tohumlar {
                let ck = Array(c)
                for i in from..<min(44, ck.count) {
                    for a in alt[ck[i]] ?? [] {
                        var t = ck; t[i] = a
                        if let h = kabul(String(t)) { iyi.append(h) }
                    }
                }
            }
        }
        guard !iyi.isEmpty, Set(iyi.map(\.deger)).count == 1 else { return (bas, false) }
        let kurali = iyi.first { dilim($0.ham, 28, 42).eslesir("^[0-9]*<*$") }?.ham ?? iyi[0].ham
        return (kurali, kurali != bas)
    }

    // MARK: Satırları bulma ve puanlama

    /// Metinden MRZ olabilecek bütün satır çiftleri (fotoğrafta başka yazı da olabilir).
    public static func satirCiftleri(_ metin: String) -> [(String, String)] {
        let adaylar = metin.split(whereSeparator: \.isNewline).map { temizle(String($0)) }
            .filter { l in
                let dolu = l.replacingOccurrences(of: "<", with: "")
                return dolu.count >= 8 && l.count >= 20
            }
        var ciftler: [(String, String)] = []
        if adaylar.count >= 2 { for i in 0..<(adaylar.count - 1) { ciftler.append((doldur(adaylar[i]), doldur(adaylar[i + 1]))) } }
        if ciftler.isEmpty && adaylar.count == 1 { ciftler.append((doldur(adaylar[0]), String(repeating: "<", count: 44))) }
        return ciftler
    }

    /// Bir okumanın ne kadar sağlam olduğu (kontrol haneleri en ağır ölçü).
    public static func puan(_ satir1: String, _ satir2: String) -> Int {
        let a = temizle(satir1), hamB = temizle(satir2)
        if a.isEmpty || hamB.isEmpty { return 0 }
        var b = satir2Onar(doldur(hamB))
        if tutanSayisi(b) < 5 {
            let t = kuyrukOnar(hamB, derin: false)
            if t.onarildi { b = satir2Onar(t.satir) }
        }
        var p = tutanSayisi(b) * 20
        if a.count == 44 { p += 6 }
        if hamB.count == 44 { p += 6 }
        if a.hasPrefix("P") { p += 4 }
        if dilim(b, 10, 13).eslesir("^[A-Z]{3}$") { p += 3 }
        if "MF<".contains(karakter(b, 20)) && !karakter(b, 20).isEmpty { p += 2 }
        if a.contains("<<") { p += 2 }
        if dilim(b, 13, 19).eslesir("^[0-9]{6}$") { p += 2 }
        if dilim(b, 21, 27).eslesir("^[0-9]{6}$") { p += 2 }
        return p
    }

    public static let enYuksekPuan = 5 * 20 + 6 + 6 + 4 + 3 + 2 + 2 + 2 + 2

    /// Satır başına uydurulmuş 0–3 karakteri atarak en iyi hizalamayı seçer.
    public static func hizala(_ satir1: String, _ satir2: String) -> (satirlar: (String, String), puan: Int, kaydi: Bool) {
        let a0 = temizle(satir1), b0 = temizle(satir2)
        let kes = { (s: String, n: Int) in doldur(dilim(s, n, Int.max)) }
        var en: (satirlar: (String, String), puan: Int, kaydi: Bool) = ((kes(a0, 0), kes(b0, 0)), -1, false)
        for a in 0...3 {
            for b in 0...3 {
                let c1 = kes(a0, a), c2 = kes(b0, b)
                let p = puan(c1, c2)
                if p > en.puan { en = ((c1, c2), p, a > 0 || b > 0) }
            }
        }
        return en
    }

    /// Metinden en iyi okuma (OCR çıktısı satır satır).
    public static func oku(_ metin: String) -> Sonuc? {
        let ciftler = satirCiftleri(metin)
        guard !ciftler.isEmpty else { return nil }
        let en = ciftler.map { hizala($0.0, $0.1) }.max { $0.puan < $1.puan }!
        return coz(en.satirlar.0, en.satirlar.1)
    }

    // MARK: Çözümleme

    public struct Alanlar: Equatable {
        public var soyad: String
        public var ad: String
        public var pasaportNo: String
        public var uyruk: String
        public var veren: String
        public var dogum: String
        public var gecerlilik: String
        public var cinsiyet: String
        public var tckn: String
    }

    public struct Sonuc: Equatable {
        public var tamam: Bool
        public var hatalar: [String]
        public var notlar: [String]
        public var harfSecenekleri: [String]
        public var alanlar: Alanlar
        public var satirlar: [String]
        public var onarildi: Bool
    }

    static func tarih(_ s: String, dogum: Bool, simdi: Date = Date()) -> String {
        guard s.eslesir("^\\d{6}$"), let yy = Int(dilim(s, 0, 2)), let ay = Int(dilim(s, 2, 4)), let gun = Int(dilim(s, 4, 6)),
              ay >= 1, ay <= 12, gun >= 1, gun <= 31 else { return "" }
        let bu = (Tr.takvim.component(.year, from: simdi)) % 100
        let yil = dogum ? (yy > bu ? 1900 + yy : 2000 + yy) : 2000 + yy
        return "\(yil)-\(dilim(s, 2, 4))-\(dilim(s, 4, 6))"
    }

    static func adTemizle(_ s: String) -> String {
        s.replacingOccurrences(of: "<", with: " ").kirpik.degistir("\\s+", " ")
    }

    /// İki MRZ satırını çözümler (panel: parseMrz).
    public static func coz(_ satir1: String, _ satir2: String, simdi: Date = Date()) -> Sonuc {
        let a = doldur(temizle(satir1))
        let kuyruk = kuyrukOnar(satir2, derin: true)
        let ham = kuyruk.satir
        let duzeltilmis = satir2Onar(ham)
        let b = tutanSayisi(duzeltilmis) >= tutanSayisi(ham) ? duzeltilmis : ham
        var hatalar: [String] = []
        if !a.hasPrefix("P") { hatalar.append("Birinci satır \"P\" ile başlamıyor — pasaport MRZ'si okunamadı.") }
        let veren = dilim(a, 2, 5).replacingOccurrences(of: "<", with: "")
        let isim = dilim(a, 5, 44)
        let parcalar = isim.components(separatedBy: "<<")
        let soy = parcalar.first ?? "", ad = parcalar.count > 1 ? parcalar[1...].joined(separator: "<<") : ""
        let pasaportNo = dilim(b, 0, 9).replacingOccurrences(of: "<", with: "")
        let hamPasaport = dilim(ham, 0, 9)
        let tahmin = hamPasaport != dilim(b, 0, 9)
        let dogumHam = dilim(b, 13, 19), gecerHam = dilim(b, 21, 27)
        let kisisel = dilim(b, 28, 42).replacingOccurrences(of: "<", with: "")
        let kontroller: [(Bool, String)] = [
            (kontrolHanesi(dilim(b, 0, 9)) == karakter(b, 9), "pasaport no"),
            (kontrolHanesi(dogumHam) == karakter(b, 19), "doğum tarihi"),
            (kontrolHanesi(gecerHam) == karakter(b, 27), "geçerlilik tarihi"),
            (kisisel.isEmpty || kontrolHanesi(dilim(b, 28, 42)) == karakter(b, 42), "kimlik no"),
            (kontrolHanesi(dilim(b, 0, 10) + dilim(b, 13, 20) + dilim(b, 21, 43)) == karakter(b, 43), "bütün satır"),
        ]
        for (tuttu, ad) in kontroller where !tuttu { hatalar.append("MRZ kontrol hanesi tutmadı: \(ad).") }
        let turk = dilim(b, 10, 13) == "TUR"
        let secenek = turk ? harfSecenekleri(b) : []
        if turk && !pasaportNo.eslesir("^[A-Z][0-9]{8}$") {
            hatalar.append(secenek.isEmpty
                ? "Pasaport numarası okunamadı: Türk pasaportlarında bir harf ve sekiz rakam olmalı. Baştaki harfi elle yazın."
                : "Pasaport numarasının baştaki harfi okunamadı. Kontrol hanesine göre yalnızca şunlar olabilir: \(secenek.joined(separator: ", ")). Pasaporttan bakıp seçin.")
        }
        let cins = karakter(b, 20)
        let alanlar = Alanlar(soyad: adTemizle(soy), ad: adTemizle(ad), pasaportNo: pasaportNo,
                              uyruk: dilim(b, 10, 13).replacingOccurrences(of: "<", with: ""), veren: veren,
                              dogum: tarih(dogumHam, dogum: true, simdi: simdi), gecerlilik: tarih(gecerHam, dogum: false, simdi: simdi),
                              cinsiyet: cins == "M" || cins == "F" ? cins : "", tckn: kisisel.eslesir("^\\d{11}$") ? kisisel : "")
        var notlar: [String] = []
        if kuyruk.onarildi {
            notlar.append("İkinci satırın sonundaki \"<\" işaretleri eksik/fazla okunmuştu; pasaporttaki kontrol hanelerine göre tamamlandı. Satırı bir kez gözden geçirin.")
        }
        if tahmin {
            notlar.append("Pasaport numarasının okunuşu düzeltildi (\"\(hamPasaport.replacingOccurrences(of: "<", with: "·"))\" → \"\(pasaportNo)\"). Lütfen pasaporttan doğrulayın.")
        }
        return Sonuc(tamam: hatalar.isEmpty, hatalar: hatalar, notlar: notlar, harfSecenekleri: secenek, alanlar: alanlar,
                     satirlar: [a, b], onarildi: b != ham)
    }

    /// Formla karşılaştırma (panel: compareWithForm).
    public struct Karsilastirma: Equatable, Identifiable {
        public var key: String
        public var etiket: String
        public var mrz: String
        public var form: String
        public var eksik: Bool
        public var uyuyor: Bool
        public var id: String { key }
    }

    public static func karsilastir(_ a: Alanlar, form: [String: String]) -> [Karsilastirma] {
        let alanlar: [(String, String, String)] = [
            ("firstName", "İsim", a.ad), ("lastName", "Soyisim", a.soyad), ("passportNo", "Pasaport no", a.pasaportNo),
            ("birthDate", "Doğum tarihi", a.dogum), ("passportExpires", "Geçerlilik tarihi", a.gecerlilik),
            ("sex", "Cinsiyet", a.cinsiyet), ("nationalId", "T.C. kimlik no", a.tckn),
        ]
        let norm = { (s: String) in s.uppercased().filter { ($0.isLetter && $0.isASCII) || $0.isNumber || $0 == "-" } }
        return alanlar.map { k, e, m in
            let f = form[k] ?? ""
            return Karsilastirma(key: k, etiket: e, mrz: m, form: f, eksik: f.isEmpty, uyuyor: !m.isEmpty && norm(m) == norm(f))
        }
    }

    /// Okunan alanların forma yazılacak hâli (panel: PREFILL_FIELDS).
    public static func formDegerleri(_ a: Alanlar) -> [String: String] {
        var d: [String: String] = [:]
        let alanlar: [(String, String)] = [("firstName", a.ad), ("lastName", a.soyad), ("passportNo", a.pasaportNo), ("birthDate", a.dogum),
                                           ("passportExpires", a.gecerlilik), ("sex", a.cinsiyet), ("nationalId", a.tckn)]
        for (k, v) in alanlar where !v.isEmpty { d[k] = v }
        return d
    }
}
