import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import VizeMiaCekirdek

/// Yüklenecek belgeyi hazırlar (panel: dosya-yukle.js → dosyaHazirla).
/// Fotoğraf JPEG'e çevrilip küçültülür (uzun kenar en çok 2000 px); 5 MB'ı
/// aşarsa adım adım daha küçük. PDF 5 MB'tan büyükse sayfalar resme çevrilip
/// yeni PDF yapılır. Belgeler Firestore'da durduğu için (Storage yok) yer sınırlı.
enum DosyaHazirlama {
    /// Sırayla denenir: uzun kenar (px), JPEG kalitesi.
    static let fotoAdimlari: [(CGFloat, CGFloat)] = [(2000, 0.85), (1600, 0.75), (1200, 0.65), (1000, 0.55)]

    enum Hata: LocalizedError {
        case acilamadi, buyuk(String)
        var errorDescription: String? {
            switch self {
            case .acilamadi: return "Dosya açılamadı (PDF, JPEG ya da PNG deneyin)."
            case .buyuk(let m): return m
            }
        }
    }

    static func foto(_ veri: Data, ad: String) throws -> HazirDosya {
        guard let resim = UIImage(data: veri) else { throw Hata.acilamadi }
        var son = Data()
        for (kenar, kalite) in fotoAdimlari {
            let k = kucult(resim, uzunKenar: kenar)
            guard let j = k.jpegData(compressionQuality: kalite) else { throw Hata.acilamadi }
            son = j
            if j.count <= Dosya.kucultmeSiniri { break }
        }
        let sorun = Dosya.sorun(mime: "image/jpeg", boyut: son.count)
        if !sorun.isEmpty { throw Hata.buyuk(sorun) }
        let temiz = Dosya.adTemizle(ad, yedek: "foto").degistir("\\.[A-Za-z0-9]{2,5}$", "")
        return HazirDosya(ad: "\(temiz).jpg", mime: "image/jpeg", bayt: son)
    }

    static func kucult(_ r: UIImage, uzunKenar: CGFloat) -> UIImage {
        let boyut = r.size
        let oran = min(1, uzunKenar / max(boyut.width, boyut.height))
        let yeni = CGSize(width: (boyut.width * oran).rounded(), height: (boyut.height * oran).rounded())
        let bicim = UIGraphicsImageRendererFormat()
        bicim.scale = 1
        bicim.opaque = true
        return UIGraphicsImageRenderer(size: yeni, format: bicim).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: yeni))
            r.draw(in: CGRect(origin: .zero, size: yeni))
        }
    }

    static func pdf(_ veri: Data, ad: String) throws -> HazirDosya {
        var son = veri
        if veri.count > Dosya.kucultmeSiniri {
            guard let belge = PDFDocument(data: veri), belge.pageCount > 0 else { throw Hata.acilamadi }
            // ~150 DPI'da resme çevrilmiş sayfalar: yazı okunur kalır.
            for (dpi, kalite) in [(150.0, 0.7), (110.0, 0.55)] {
                son = resimliPdf(belge, dpi: dpi, kalite: kalite)
                if son.count <= Dosya.enCok { break }
            }
        }
        let sorun = Dosya.sorun(mime: "application/pdf", boyut: son.count)
        if !sorun.isEmpty { throw Hata.buyuk(sorun) }
        var temiz = Dosya.adTemizle(ad, yedek: "belge")
        if !temiz.lowercased().hasSuffix(".pdf") { temiz += ".pdf" }
        return HazirDosya(ad: temiz, mime: "application/pdf", bayt: son)
    }

    static func resimliPdf(_ belge: PDFDocument, dpi: Double, kalite: CGFloat) -> Data {
        let ilk = belge.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: ilk).pdfData { baglam in
            for i in 0..<min(belge.pageCount, 60) {
                guard let sayfa = belge.page(at: i) else { continue }
                let kutu = sayfa.bounds(for: .mediaBox)
                let olcek = CGFloat(dpi / 72)
                let resim = sayfa.thumbnail(of: CGSize(width: kutu.width * olcek, height: kutu.height * olcek), for: .mediaBox)
                guard let j = resim.jpegData(compressionQuality: kalite), let r = UIImage(data: j) else { continue }
                baglam.beginPage(withBounds: kutu, pageInfo: [:])
                r.draw(in: kutu)
            }
        }
    }
}

/// Belge seçimi: kamera, fotoğraflar ya da PDF. Seçilen hazırlanıp bağlanır.
struct DosyaSecDugmeleri: View {
    @Binding var secilen: HazirDosya?
    var pdfOlur = true
    @State private var fotoSecimi: PhotosPickerItem?
    @State private var kameraAcik = false
    @State private var dosyaAcik = false
    @State private var hazirlaniyor = false
    @State private var hata: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { kameraAcik = true } label: { Label("Fotoğraf çek", systemImage: "camera.fill") }
                        .buttonStyle(KucukDugme())
                }
                PhotosPicker(selection: $fotoSecimi, matching: .images) {
                    Label("Fotoğraflar", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(KucukDugme())
                if pdfOlur {
                    Button { dosyaAcik = true } label: { Label("PDF", systemImage: "doc.fill") }
                        .buttonStyle(KucukDugme())
                }
            }
            if hazirlaniyor {
                HStack(spacing: 6) { ProgressView(); Text("Hazırlanıyor…").font(.caption).foregroundStyle(Tema.govde) }
            } else if let s = secilen {
                HStack(spacing: 8) {
                    Image(systemName: s.mime == "application/pdf" ? "doc.richtext" : "photo")
                        .foregroundStyle(Tema.turkuaz)
                    Text("\(s.ad) · \(Dosya.boyutYazi(s.bayt.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Tema.lacivert)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button { secilen = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.silik) }
                        .accessibilityLabel("Seçimi kaldır")
                }
            }
            if let h = hata { AlanHatasi(metin: h) }
        }
        .onChange(of: fotoSecimi) { _, yeni in
            guard let yeni else { return }
            Task {
                await hazirla {
                    guard let v = try await yeni.loadTransferable(type: Data.self) else { throw DosyaHazirlama.Hata.acilamadi }
                    return try DosyaHazirlama.foto(v, ad: "foto")
                }
                fotoSecimi = nil
            }
        }
        .fullScreenCover(isPresented: $kameraAcik) {
            KameraGorunumu { resim in
                kameraAcik = false
                guard let resim, let v = resim.jpegData(compressionQuality: 0.95) else { return }
                Task { await hazirla { try DosyaHazirlama.foto(v, ad: "kamera") } }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $dosyaAcik, allowedContentTypes: [UTType.pdf, UTType.image]) { sonuc in
            guard case .success(let url) = sonuc else { return }
            Task {
                await hazirla {
                    let erisim = url.startAccessingSecurityScopedResource()
                    defer { if erisim { url.stopAccessingSecurityScopedResource() } }
                    let v = try Data(contentsOf: url)
                    let pdf = url.pathExtension.lowercased() == "pdf"
                    return pdf ? try DosyaHazirlama.pdf(v, ad: url.lastPathComponent)
                        : try DosyaHazirlama.foto(v, ad: url.lastPathComponent)
                }
            }
        }
    }

    private func hazirla(_ is_: @escaping () async throws -> HazirDosya) async {
        hata = nil
        hazirlaniyor = true
        defer { hazirlaniyor = false }
        do {
            let d = try await is_()
            withAnimation(Hareket.yay) { secilen = d }
        } catch {
            hata = (error as? LocalizedError)?.errorDescription ?? "Dosya hazırlanamadı."
        }
    }
}

/// Kamera (UIImagePickerController).
struct KameraGorunumu: UIViewControllerRepresentable {
    let bitti: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Koordinator { Koordinator(bitti: bitti) }

    final class Koordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let bitti: (UIImage?) -> Void
        init(bitti: @escaping (UIImage?) -> Void) { self.bitti = bitti }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            bitti(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { bitti(nil) }
    }
}

/// Küçük, açık zeminli düğme (dosya seçimi, satır işlemleri).
struct KucukDugme: ButtonStyle {
    var renk: Color = Tema.lacivert

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(renk)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Tema.soluk.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
            .lineLimit(1)
    }
}
