import SwiftUI
import Observation
import VizeMiaCekirdek

enum Sekme: Hashable {
    case anaSayfa, takip, basvuru, harclar, daha
}

/// Bir sekmenin içinde açılan ekranlar.
enum Rota: Hashable {
    case sayfa(String)
    case blog
    case rehberler
    case ulkeler
    case sss
    case destek(kod: String)
    case iletisim
}

struct WebAdresi: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Sekmeler arası geçiş ve içerikteki bağlantıların uygulamadaki karşılığı.
@MainActor
@Observable
final class Gezinti {
    var sekme: Sekme = .anaSayfa
    var yollar: [Sekme: [Rota]] = [:]
    /// Başvuru formunda seçili gelecek ülke kimliği ("almanya").
    var basvuruUlke: String = ""
    /// Uygulama içi tarayıcıda açılan adres.
    var web: WebAdresi?
    /// Mesai dışında "Ara"ya basılınca gösterilen pencere.
    var aramaUyarisi: Mesai.DisiMesaji?

    func yol(_ s: Sekme) -> Binding<[Rota]> {
        Binding(get: { self.yollar[s] ?? [] }, set: { self.yollar[s] = $0 })
    }

    func it(_ rota: Rota) {
        yollar[sekme, default: []].append(rota)
    }

    func ac(_ hedef: Hedef) {
        switch hedef {
        case .anaSayfa:
            sekme = .anaSayfa
            yollar[.anaSayfa] = []
        case .basvuru(let ulke):
            if !ulke.isEmpty { basvuruUlke = ulke }
            yollar[.basvuru] = []
            sekme = .basvuru
        case .takip:
            yollar[.takip] = []
            sekme = .takip
        case .harclar:
            yollar[.harclar] = []
            sekme = .harclar
        case .destek(let kod): it(.destek(kod: kod))
        case .sss: it(.sss)
        case .blog: it(.blog)
        case .sayfa(let yol): it(.sayfa(yol))
        case .dis(let url): disAc(url)
        }
    }

    /// İçerikteki bağlantı ("/takip", "https://…").
    func ac(link: String, sayfaYollari: Set<String>) {
        if let h = Hedef.coz(link, sayfaYollari: sayfaYollari) { ac(h) }
    }

    /// Telefon, e-posta, WhatsApp, harita ve Instagram kendi uygulamasında;
    /// diğer adresler uygulama içi tarayıcıda açılır.
    func disAc(_ url: URL) {
        let sema = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let sistemde = ["wa.me", "api.whatsapp.com", "maps.apple.com", "www.instagram.com", "instagram.com", "maps.app.goo.gl"]
        if sema == "http" || sema == "https" {
            if sistemde.contains(host) || (host.hasSuffix("google.com") && url.path.hasPrefix("/maps")) {
                UIApplication.shared.open(url)
            } else {
                web = WebAdresi(url: url)
            }
        } else if sema == "tel" || sema == "mailto" {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - İletişim kısayolları

    /// Mesai içindeyse doğrudan arar; dışındaysa önce uyarır (talep bırakma önerisi).
    func ara(_ iletisim: Iletisim, mesai: Mesai) {
        if let uyari = mesai.disiMesaji() {
            aramaUyarisi = uyari
        } else {
            yineDeAra(iletisim)
        }
    }

    func yineDeAra(_ iletisim: Iletisim) {
        if let u = URL(string: "tel:\(iletisim.telefon)") { UIApplication.shared.open(u) }
    }

    func whatsapp(_ iletisim: Iletisim) {
        if let u = URL(string: "https://wa.me/\(iletisim.whatsapp)") { UIApplication.shared.open(u) }
    }

    func eposta(_ iletisim: Iletisim) {
        if let u = URL(string: "mailto:\(iletisim.eposta)") { UIApplication.shared.open(u) }
    }

    func yolTarifi(_ iletisim: Iletisim) {
        if let u = URL(string: "https://maps.apple.com/?daddr=\(iletisim.enlem),\(iletisim.boylam)&dirflg=d") {
            UIApplication.shared.open(u)
        }
    }
}
