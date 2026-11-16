import SwiftUI
import SafariServices
import VizeMiaCekirdek

/// Uygulama içi tarayıcı (resmî kaynaklar, gizlilik sayfası).
struct SafariGorunumu: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let c = SFSafariViewController(url: url)
        c.preferredControlTintColor = UIColor(Tema.lacivert)
        return c
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Siteden yüklenen görsel; çerçeveyi doldurur, odak noktasına göre kırpılır.
/// Yüklenene kadar (ya da bağlantı yokken) lacivert geçiş görünür.
struct UzakGorsel: View {
    var yol: String
    var odak: UnitPoint = .center

    var body: some View {
        Color.clear
            .overlay(alignment: Alignment(horizontal: yatay, vertical: dikey)) {
                if let url = Hedef.gorsel(yol) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { evre in
                        if let g = evre.image {
                            g.resizable().scaledToFill()
                        } else {
                            yerTutucu
                        }
                    }
                } else {
                    yerTutucu
                }
            }
            .background(yerTutucu)
            .clipped()
            .accessibilityHidden(true)
    }

    private var yerTutucu: some View {
        LinearGradient(colors: [Tema.lacivertAcik, Tema.lacivertKoyu], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var yatay: HorizontalAlignment { odak.x < 0.34 ? .leading : odak.x > 0.66 ? .trailing : .center }
    private var dikey: VerticalAlignment { odak.y < 0.34 ? .top : odak.y > 0.66 ? .bottom : .center }
}

// MARK: - Markdown

extension AttributedString {
    /// Sitenin satır içi biçimi: **kalın** ve [bağlantı](adres).
    init(parcalar: [MdParca]) {
        self.init()
        for p in parcalar {
            switch p {
            case .duz(let t):
                self += AttributedString(t)
            case .kalin(let t):
                var a = AttributedString(t)
                a.inlinePresentationIntent = .stronglyEmphasized
                a.foregroundColor = Tema.lacivert
                self += a
            case .bag(let metin, let adres):
                var a = AttributedString(metin)
                // Site içi yol tam adrese çevrilir; açılırken uygulamanın ekranına döner.
                if let u = URL(string: adres.hasPrefix("/") ? Hedef.site.absoluteString + adres : adres) {
                    a.link = u
                    a.foregroundColor = Tema.mavi
                    a.underlineStyle = Text.LineStyle.single
                }
                self += a
            }
        }
    }

    init(md: String) {
        self.init(parcalar: Markdown.satirIci(md))
    }
}

/// Sitenin basit Markdown'ını çizer: başlık, paragraf, madde ve sıralı liste.
struct MarkdownMetin: View {
    var md: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Markdown.coz(md).enumerated()), id: \.offset) { _, blok in
                switch blok {
                case .baslik(let seviye, let p):
                    Text(AttributedString(parcalar: p))
                        .font(seviye <= 2 ? .title3.weight(.heavy) : .headline)
                        .foregroundStyle(Tema.lacivert)
                        .padding(.top, seviye <= 2 ? 10 : 4)
                        .accessibilityAddTraits(.isHeader)
                case .paragraf(let p):
                    Text(AttributedString(parcalar: p))
                        .font(.body)
                        .foregroundStyle(Tema.govde)
                        .lineSpacing(3)
                case .liste(let sirali, let ogeler):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(ogeler.enumerated()), id: \.offset) { i, p in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(sirali ? "\(i + 1)." : "•")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(Tema.turkuaz)
                                    .frame(minWidth: 18, alignment: .leading)
                                Text(AttributedString(parcalar: p))
                                    .font(.body)
                                    .foregroundStyle(Tema.govde)
                                    .lineSpacing(3)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

/// Açılır soru kutusu (SSS, mesleğe göre evrak).
struct AcilirKutu: View {
    var baslik: String
    var md: String
    @State private var acik = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { acik.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(baslik)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tema.lacivert)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Tema.turkuaz)
                        .rotationEffect(.degrees(acik ? 180 : 0))
                        .padding(.top, 3)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(acik ? "Kapat" : "Aç")

            if acik {
                MarkdownMetin(md: md)
                    .padding([.horizontal, .bottom], 14)
            }
        }
        .background(Tema.zemin, in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous).stroke(Tema.soluk, lineWidth: 1))
    }
}

/// "Ücretsiz ön değerlendirme" çağrısı.
struct BasvurKutusu: View {
    var baslik: String
    var metin: String
    var ulke: String = ""
    @Environment(Gezinti.self) private var gezinti

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(baslik).font(.headline).foregroundStyle(.white)
            if !metin.isEmpty {
                Text(metin).font(.subheadline).foregroundStyle(.white.opacity(0.85))
            }
            Button("Ücretsiz ön değerlendirme al") { gezinti.ac(.basvuru(ulke: ulke)) }
                .buttonStyle(AnaDugme(renk: Tema.turkuaz))
                .padding(.top, 4)
        }
        .padding(Tema.bosluk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.lacivert, in: RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
    }
}

/// Ara / WhatsApp düğme çifti.
struct IletisimDugmeleri: View {
    @Environment(IcerikDeposu.self) private var icerik
    @Environment(Gezinti.self) private var gezinti

    var body: some View {
        HStack(spacing: 10) {
            Button {
                gezinti.ara(icerik.iletisim, mesai: icerik.mesai)
            } label: {
                Label("Ara", systemImage: "phone.fill")
            }
            .buttonStyle(IkincilDugme())
            .accessibilityLabel("VizeMia'yı arayın: \(icerik.iletisim.telefonGorunen)")

            Button {
                gezinti.whatsapp(icerik.iletisim)
            } label: {
                Label("WhatsApp", systemImage: "message.fill")
            }
            .buttonStyle(AnaDugme(renk: Tema.whatsapp))
        }
    }
}

/// Sitedeki genel uyarı (ülke rehberi ve yazıların altında).
struct ResmiDegilUyarisi: View {
    var body: some View {
        Text("Bu sayfa genel bilgilendirme amaçlıdır. Vize kuralları, evrak listeleri ve harçlar değişebilir; başvurmadan önce ilgili ülkenin büyükelçiliği ve başvuru merkezinin güncel duyurularını kontrol edin. VizeMia resmî bir kurum değildir.")
            .font(.caption)
            .foregroundStyle(Tema.govde)
    }
}

extension View {
    /// Ekranın ortak zemini ve kenar boşluğu.
    func ekranZemini() -> some View {
        self.background(Tema.zeminYumusak.ignoresSafeArea())
    }
}
