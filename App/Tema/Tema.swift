import SwiftUI

/// Sitenin tasarım sistemi (site/assets/vizemia.css → :root): koyu lacivert
/// ağırlıklı, turkuaz yalnız küçük vurgu.
enum Tema {
    static let lacivert = Color(hex: 0x03244c)        // --primary / --ink
    static let lacivertAcik = Color(hex: 0x0e3563)    // --primary-active
    static let lacivertKoyu = Color(hex: 0x021a38)    // --ink-darker
    static let soluk = Color(hex: 0xe3ebf5)           // --primary-pale
    static let turkuaz = Color(hex: 0x14a9b0)         // --accent
    static let mavi = Color(hex: 0x1a4b8c)            // --ink-deep
    static let govde = Color(hex: 0x4a5568)           // --body
    static let silik = Color(hex: 0x8792a2)           // --mute
    static let zemin = Color.white                    // --canvas
    static let zeminYumusak = Color(hex: 0xe9eff4)    // --canvas-soft
    static let olumlu = Color(hex: 0x2ead4b)          // --positive
    static let olumluKoyu = Color(hex: 0x054d28)      // --positive-deep
    static let olumsuz = Color(hex: 0xd03238)         // --negative
    static let uyari = Color(hex: 0x4a3b1c)           // --warning-content
    static let uyariZemin = Color(hex: 0xfff4d6)
    static let whatsapp = Color(hex: 0x25d366)
    static let altin = Color(hex: 0xc9a54b)

    static let kose: CGFloat = 16
    static let koseKucuk: CGFloat = 12
    static let bosluk: CGFloat = 16
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1)
    }

    /// Panelden gelen "#14a9b0" ya da "#1ab" biçimindeki renk.
    init?(kod: String) {
        var s = kod.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 || s.count == 4 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let n = UInt64(s, radix: 16) else { return nil }
        let rgb = s.count == 8 ? UInt32(n >> 8) : UInt32(n)
        self.init(hex: rgb)
    }
}

// MARK: - Yazı

extension Font {
    /// Sitedeki büyük başlıklar (Inter 900) → sistem yazısının en kalın hâli.
    static func vitrin(_ boyut: CGFloat) -> Font { .system(size: boyut, weight: .heavy, design: .default) }
}

extension View {
    /// Küçük, aralıklı üst başlık ("REHBER", "SÜREÇ").
    func ustBaslik() -> some View {
        self.font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(Tema.turkuaz)
    }

    func bolumBasligi() -> some View {
        self.font(.title2.weight(.heavy))
            .foregroundStyle(Tema.lacivert)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func govdeMetni() -> some View {
        self.font(.subheadline).foregroundStyle(Tema.govde)
    }

    /// Beyaz, ince kenarlıklı kart.
    func kart(dolgu: CGFloat = Tema.bosluk) -> some View {
        self.padding(dolgu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.zemin, in: RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tema.kose, style: .continuous).stroke(Tema.soluk, lineWidth: 1))
    }

    /// Açık mavi zeminli kart.
    func kartSoluk(dolgu: CGFloat = Tema.bosluk) -> some View {
        self.padding(dolgu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.soluk, in: RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
    }
}

// MARK: - Düğmeler

/// Lacivert dolgulu ana düğme.
struct AnaDugme: ButtonStyle {
    var renk: Color = Tema.lacivert
    var tamGenislik = true
    @Environment(\.isEnabled) private var etkin

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: tamGenislik ? .infinity : nil)
            .background(renk.opacity(etkin ? (configuration.isPressed ? 0.85 : 1) : 0.45), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Açık zeminli ikincil düğme.
struct IkincilDugme: ButtonStyle {
    var tamGenislik = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Tema.lacivert)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: tamGenislik ? .infinity : nil)
            .background(Tema.soluk.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Seçilebilir küçük kutu (saat aralığı, gün, hazır tutar).
struct SecimKutusu: ButtonStyle {
    var secili: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(secili ? Color.white : Tema.lacivert)
            .padding(.vertical, 11)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(secili ? Tema.lacivert : Tema.zemin, in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous).stroke(secili ? Tema.lacivert : Tema.soluk, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Form parçaları

/// Etiketli metin kutusu.
struct Alan<Govde: View>: View {
    var etiket: String
    var istegeBagli = false
    var yardim: String? = nil
    /// Bu alandaki doğrulama hatası; varsa yardım metninin yerine gösterilir.
    var hata: String? = nil
    @ViewBuilder var icerik: () -> Govde

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(etiket).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                if istegeBagli { Text("(isteğe bağlı)").font(.caption).foregroundStyle(Tema.govde) }
            }
            icerik()
            if let h = hata {
                AlanHatasi(metin: h)
            } else if let y = yardim {
                Text(y).font(.caption).foregroundStyle(Tema.govde)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Alanın hemen altındaki kısa hata satırı.
struct AlanHatasi: View {
    var metin: String

    var body: some View {
        Label(metin, systemImage: "exclamationmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Tema.olumsuz)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Form ekranlarında klavye: kaydırınca kapanır ve üstünde "Bitti" düğmesi
    /// olur. Rakam klavyesinde kapatma tuşu yok; bu olmadan klavye ekranın alt
    /// yarısını ve sekme çubuğunu kapatıp kalıyor.
    func formKlavyesi() -> some View {
        self.scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Bitti") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
            }
    }

    /// Metin kutusunun çerçevesi.
    func kutu() -> some View {
        self.padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Tema.zemin, in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous).stroke(Tema.silik.opacity(0.55), lineWidth: 1))
    }
}

/// İşaret kutusu (onay metinleri uzun olduğu için Toggle yerine).
struct IsaretKutusu: View {
    @Binding var secili: Bool
    var metin: String
    var etkin = true

    var body: some View {
        // Kullanılamayan kutu işaretsiz görünür: adresi olmayan e-posta kanalını
        // seçili göstermek "seçtim ama gelmedi" demek.
        let isaretli = secili && etkin
        Button {
            secili.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isaretli ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isaretli ? Tema.lacivert : Tema.silik)
                Text(metin)
                    .font(.footnote)
                    .foregroundStyle(Tema.govde)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!etkin)
        .opacity(etkin ? 1 : 0.45)
        .accessibilityAddTraits(isaretli ? .isSelected : [])
    }
}

/// Hata ya da bilgi satırı.
struct HataMetni: View {
    var metin: String

    var body: some View {
        Label(metin, systemImage: "exclamationmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Tema.olumsuz)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Tema.olumsuz.opacity(0.08), in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
    }
}
