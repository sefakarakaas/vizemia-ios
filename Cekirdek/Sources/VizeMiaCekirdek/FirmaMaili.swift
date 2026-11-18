import Foundation

// Firma maili (panel: pages/firma.js, firma-mail.js). Tacir firmalara
// pazarlama@vizemia.com'dan tanıtım; gönderimi ayrı Apps Script yapar.
// Uygulamada: gönderilenler (tanıtım + cevap) ve firmaya cevap. Toplu tanıtım
// gönderimi (TXT yükleme, İYS kaydı) masaüstü işi; panelde kalır.

/// firmaMailleri/{firmaId} (tanıtım) ya da firmaYanitlari/{id} (cevap).
public struct FirmaMaili: Equatable, Identifiable {
    public static let durumAdlari = ["kuyrukta": "Kuyrukta", "gonderildi": "Gönderildi", "hata": "Hata",
                                     "engelli": "Gönderilmedi (listeden çıkmış)"]
    public static let gonderen = "pazarlama@vizemia.com"

    public var id: String
    /// "tanitim" | "yanit"
    public var tur: String
    public var firmaId: String
    public var firma: String
    public var eposta: String
    public var konu: String
    public var govde: String
    public var durum: String
    public var hata: String
    public var yazan: String
    public var zaman: Date?
    public var gonderilme: Date?

    public init(kimlik: String, tur: String, alanlar a: [String: FSDeger]) {
        func m(_ k: String) -> String { a[k]?.metinDegeri ?? "" }
        id = kimlik
        self.tur = tur
        firmaId = tur == "tanitim" ? kimlik : m("firmaId")
        firma = m("firma"); eposta = m("eposta"); konu = m("konu"); govde = m("govde"); durum = m("durum"); hata = m("hata")
        yazan = m("byName"); zaman = a["at"]?.zamanDegeri; gonderilme = a["gonderildi"]?.zamanDegeri
    }

    public var durumAdi: String { Self.durumAdlari[durum] ?? durum }
    public var turAdi: String { tur == "yanit" ? "Cevap" : "Tanıtım" }
}

/// Altbilgideki iletişim bilgileri (Ayarlar → Genel: firmaTelefon, firmaEposta, firmaWeb, firmaAdres).
public struct FirmaIletisimi: Equatable {
    public var telefon = ""
    public var eposta = ""
    public var web = ""
    public var adres = ""

    public init() {}
    public init(genel g: [String: FSDeger]?) {
        telefon = g?["firmaTelefon"]?.metinDegeri ?? ""
        eposta = g?["firmaEposta"]?.metinDegeri ?? ""
        web = g?["firmaWeb"]?.metinDegeri ?? ""
        adres = g?["firmaAdres"]?.metinDegeri ?? ""
    }
}

public enum FirmaMailMetni {
    public static let konuEnCok = 160
    public static let govdeEnCok = 4000
    static let logo = "https://vizemia.com/assets/img/logo-beyaz.png"
    static let p = "margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.55;color:#03244c"

    public static func kacis(_ s: String) -> String {
        var o = ""
        for c in s {
            switch c {
            case "&": o += "&amp;"
            case "<": o += "&lt;"
            case ">": o += "&gt;"
            case "\"": o += "&quot;"
            case "'": o += "&#39;"
            default: o.append(c)
            }
        }
        return o
    }

    /// Düz metin → güvenli HTML: boş satır paragraf, "•", "-", "*" ile başlayan satırlar liste (panel: govdeHtml).
    public static func govdeHtml(_ metin: String) -> String {
        let bloklar = metin.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n\n")
        // JS split(/\n{2,}/): ikiden çok satır sonu da tek ayraç; boş kalan bloklar düşer.
        return bloklar.map { blok -> String in
            let satirlar = blok.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if satirlar.isEmpty { return "" }
            var parca: [String] = [], liste: [String] = [], duz: [String] = []
            func duzBitir() { if !duz.isEmpty { parca.append("<p style=\"\(p)\">\(duz.map(kacis).joined(separator: "<br>"))</p>") }; duz = [] }
            func listeBitir() {
                if !liste.isEmpty {
                    parca.append("<ul style=\"\(p);padding-left:22px\">" + liste.map { "<li style=\"margin:0 0 4px\">\(kacis($0))</li>" }.joined() + "</ul>")
                }
                liste = []
            }
            for s in satirlar {
                if let m = listeOgesi(s) { duzBitir(); liste.append(m) } else { listeBitir(); duz.append(s) }
            }
            duzBitir(); listeBitir()
            return parca.joined()
        }.joined()
    }

    /// /^\s*[•\-*]\s+(.*)$/
    static func listeOgesi(_ s: String) -> String? {
        var i = s.startIndex
        while i < s.endIndex, s[i].isWhitespace { i = s.index(after: i) }
        guard i < s.endIndex, "•-*".contains(s[i]) else { return nil }
        var j = s.index(after: i)
        guard j < s.endIndex, s[j].isWhitespace else { return nil }
        while j < s.endIndex, s[j].isWhitespace { j = s.index(after: j) }
        return String(s[j...])
    }

    struct Satir { var tur: String; var metin: String; var url = "" }

    static func iletisimSatirlari(_ g: FirmaIletisimi) -> [Satir] {
        let web = g.web.trimmingCharacters(in: .whitespaces)
        var l: [Satir] = []
        if !g.telefon.isEmpty { l.append(Satir(tur: "tel", metin: g.telefon.trimmingCharacters(in: .whitespaces))) }
        if !g.eposta.isEmpty { l.append(Satir(tur: "eposta", metin: g.eposta.trimmingCharacters(in: .whitespaces))) }
        if !web.isEmpty {
            var m = web
            if let r = m.range(of: "^https?://", options: .regularExpression) { m.removeSubrange(r) }
            if m.hasSuffix("/") { m.removeLast() }
            let url = web.range(of: "^https?://", options: .regularExpression) != nil ? web : "https://\(web)"
            l.append(Satir(tur: "web", metin: m, url: url))
        }
        if !g.adres.isEmpty { l.append(Satir(tur: "adres", metin: g.adres.trimmingCharacters(in: .whitespaces))) }
        return l
    }

    /// Cevap mailinin HTML'i: yalnız logo ve iletişim (İYS / MERSİS / listeden çık yok).
    static func yanitHtml(govde: String, genel: FirmaIletisimi) -> String {
        let f = "font-family:Arial,Helvetica,sans-serif"
        let iletisim = iletisimSatirlari(genel).map { s -> String in
            let ic: String
            switch s.tur {
            case "eposta": ic = "<a href=\"mailto:\(kacis(s.metin))\" style=\"color:#ffffff;text-decoration:none\">\(kacis(s.metin))</a>"
            case "web": ic = "<a href=\"\(kacis(s.url))\" style=\"color:#ffffff;text-decoration:none\">\(kacis(s.metin))</a>"
            case "tel":
                let t = s.metin.filter { $0.isNumber || $0 == "+" }
                ic = "<a href=\"tel:\(kacis(t))\" style=\"color:#ffffff;text-decoration:none\">\(kacis(s.metin))</a>"
            default: ic = kacis(s.metin)
            }
            return "<tr><td style=\"\(f);font-size:13px;line-height:1.6;color:#ffffff;padding:0\">\(ic)</td></tr>"
        }.joined()
        return "<!doctype html><html lang=\"tr\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            + "<meta name=\"color-scheme\" content=\"light dark\"><meta name=\"supported-color-schemes\" content=\"light dark\"><title>VizeMia</title></head>"
            + "<body style=\"margin:0;padding:0;background:#eef2f7\">"
            + "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" style=\"background:#eef2f7\"><tr><td align=\"center\" style=\"padding:24px 12px\">"
            + "<table role=\"presentation\" width=\"600\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" style=\"width:100%;max-width:600px;background:#ffffff;border-radius:8px;overflow:hidden\">"
            + "<tr><td style=\"padding:28px 28px 14px\">\(govdeHtml(govde))</td></tr>"
            + "<tr><td style=\"background:#03244c;padding:22px 28px\">"
            + "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\">"
            + "<tr><td style=\"padding:0 0 12px\"><img src=\"\(logo)\" width=\"150\" alt=\"VizeMia\" style=\"display:block;border:0;width:150px;height:auto\"></td></tr>"
            + iletisim
            + "</table></td></tr>"
            + "</table></td></tr></table></body></html>"
    }

    /// Firmaya cevap: konu ve gövde elle yazılır (panel: yanitMaili).
    public static func yanit(konu: String, govde: String, genel: FirmaIletisimi) -> (konu: String, govde: String, html: String, metin: String) {
        let k = String(konu.trimmingCharacters(in: .whitespacesAndNewlines).prefix(konuEnCok))
        let g = String(govde.replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(govdeEnCok))
        let metin = ([g, "", "—"] + iletisimSatirlari(genel).map(\.metin)).joined(separator: "\n")
        return (k, g, yanitHtml(govde: g, genel: genel), metin)
    }

    /// Cevabın varsayılan konusu: tanıtım mailinin konusuna "Ynt:".
    public static func yanitKonusu(_ onceki: String) -> String {
        let k = onceki.trimmingCharacters(in: .whitespaces)
        if k.isEmpty { return "" }
        return k.range(of: "^(ynt|re|yanıt)\\s*:", options: [.regularExpression, .caseInsensitive]) != nil ? k : "Ynt: \(k)"
    }

    public static let varsayilanGovde = "Merhaba,\n\n\n\nSaygılarımla,\nSefa Karakaş\nVizeMia Vize Danışmanlık"
}

extension FirmaMaili {
    /// Firmaya cevap (firmaYanitlari): kural firmanın kayıtlı adresini ister.
    public static func cevap(firmaId: String, firma: String, eposta: String, konu: String, govde: String, genel: FirmaIletisimi,
                             calisan c: Calisan) -> [FirestoreIstemci.Yazim]? {
        let m = FirmaMailMetni.yanit(konu: konu, govde: govde, genel: genel)
        guard !m.konu.isEmpty, !m.govde.isEmpty else { return nil }
        var a: [String: FSDeger] = [:]
        a["firmaId"] = .metin(firmaId)
        a["firma"] = .metin(String(firma.prefix(160)))
        a["eposta"] = .metin(eposta)
        a["konu"] = .metin(m.konu)
        a["govde"] = .metin(m.govde)
        a["html"] = .metin(String(m.html.prefix(30_000)))
        a["metin"] = .metin(String(m.metin.prefix(6000)))
        a["durum"] = .metin("kuyrukta")
        a["by"] = .metin(c.uid)
        a["byName"] = .metin(String(c.gorunenAd.prefix(80)))
        return [
            .olustur(yol: "firmaYanitlari/\(FirestoreIstemci.yeniKimlik())", alanlar: a, zaman: ["at"]),
            .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                     alanlar: IslemKaydi.alanlar(eylem: "firma.cevap", hedef: eposta, ayrinti: m.konu, calisan: c), zaman: ["at"]),
        ]
    }
}
