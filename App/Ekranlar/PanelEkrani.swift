import SwiftUI
import WebKit
import UIKit

/// Çalışan paneli (vizemia-yonetim-k7q2x9.web.app) uygulama içinde, tam ekran.
///
/// Panel zaten telefona uyumlu bir web uygulaması; aynı kodu ikinci kez
/// yazmak yerine burada açılıyor. Giriş panelin kendi kullanıcı adı / şifre
/// ekranıyla yapılır ve cihazda hatırlanır (web verisi kalıcı depoda).
/// Panelde yapılan her değişiklik uygulamada da anında geçerlidir.
struct PanelEkrani: View {
    static let adres = URL(string: "https://vizemia-yonetim-k7q2x9.web.app/")!

    @Environment(\.dismiss) private var kapat
    @State private var denetci = PanelDenetcisi()

    var body: some View {
        NavigationStack {
            PanelWebGorunumu(denetci: denetci)
                .ignoresSafeArea(edges: .bottom)
                .overlay {
                    if denetci.yukleniyor && !denetci.ilkYuklemeBitti {
                        ProgressView("Panel açılıyor…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .overlay {
                    if let h = denetci.hata {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(Tema.silik)
                            Text(h).multilineTextAlignment(.center).foregroundStyle(Tema.govde)
                            Button("Yeniden dene") { denetci.yenile() }.buttonStyle(AnaDugme(tamGenislik: false))
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Tema.zemin)
                    }
                }
                .navigationTitle("Panel")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Kapat") { kapat() }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            denetci.geri()
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .disabled(!denetci.geriGidebilir)
                        .accessibilityLabel("Geri")
                        Button {
                            denetci.yenile()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Yenile")
                    }
                }
        }
        .sheet(item: $denetci.paylasilacak) { dosya in
            PaylasimSayfasi(ogeler: [dosya.url])
        }
    }
}

/// Web görünümünün durumu ve komutları.
///
/// Temsilci yöntemleri async biçimleriyle yazıldı: tamamlama bloklu biçimlerin
/// imzası SDK sürümüne göre değişiyor (@MainActor, @Sendable); uyuşmazsa derleyici
/// yalnız uyarı verir ve yöntem hiç çağrılmaz.
@MainActor
@Observable
final class PanelDenetcisi: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    struct Dosya: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    var yukleniyor = false
    var ilkYuklemeBitti = false
    var geriGidebilir = false
    var hata: String?
    /// İndirilen dosya (PDF, CSV): paylaşım sayfasıyla kaydedilir ya da gönderilir.
    var paylasilacak: Dosya?

    @ObservationIgnored weak var web: WKWebView?
    @ObservationIgnored private var indirmeYollari: [ObjectIdentifier: URL] = [:]

    func geri() { web?.goBack() }

    func yenile() {
        hata = nil
        if web?.url == nil { web?.load(URLRequest(url: PanelEkrani.adres)) } else { web?.reload() }
    }

    private func durumuGuncelle(_ w: WKWebView) {
        geriGidebilir = w.canGoBack
    }

    // MARK: Gezinme

    func webView(_ w: WKWebView, decidePolicyFor eylem: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Blob ya da "indir" bağlantısı: dosya olarak indir.
        if eylem.shouldPerformDownload { return .download }
        guard let url = eylem.request.url, let sema = url.scheme?.lowercased() else { return .allow }
        // Telefon, e-posta, WhatsApp: telefonun kendi uygulamasında.
        if ["tel", "mailto", "sms", "whatsapp"].contains(sema) {
            _ = await UIApplication.shared.open(url)
            return .cancel
        }
        // Panel dışındaki adresler (WhatsApp web, Instagram, konsolosluk portalı) Safari'de;
        // giriş için Firebase'in kendi sayfaları panelin içinde kalır.
        if sema == "http" || sema == "https", eylem.targetFrame?.isMainFrame ?? true {
            let host = url.host?.lowercased() ?? ""
            let ic = host == PanelEkrani.adres.host || host.hasSuffix(".firebaseapp.com") || host.hasSuffix(".googleapis.com")
            if !ic {
                _ = await UIApplication.shared.open(url)
                return .cancel
            }
        }
        return .allow
    }

    func webView(_ w: WKWebView, decidePolicyFor yanit: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        yanit.canShowMIMEType ? .allow : .download
    }

    func webView(_ w: WKWebView, navigationAction: WKNavigationAction, didBecome indirme: WKDownload) {
        indirme.delegate = self
    }

    func webView(_ w: WKWebView, navigationResponse: WKNavigationResponse, didBecome indirme: WKDownload) {
        indirme.delegate = self
    }

    func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) {
        yukleniyor = true
        hata = nil
    }

    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        yukleniyor = false
        ilkYuklemeBitti = true
        durumuGuncelle(w)
    }

    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) {
        yukleniyor = false
        durumuGuncelle(w)
    }

    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        yukleniyor = false
        let kod = (e as NSError).code
        // İndirmeye dönen gezinme ve iptal hata sayılmaz.
        if kod == NSURLErrorCancelled || kod == 102 { return }
        if !ilkYuklemeBitti { hata = "Panele ulaşılamadı. İnternet bağlantınızı kontrol edip yeniden deneyin." }
    }

    // MARK: Yeni pencere, uyarılar

    /// target="_blank" ve window.open: aynı görünümde değil, telefonun ilgili uygulamasında açılır.
    func webView(_ w: WKWebView, createWebViewWith ayar: WKWebViewConfiguration, for eylem: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = eylem.request.url {
            let host = url.host?.lowercased() ?? ""
            if host == PanelEkrani.adres.host { w.load(eylem.request) } else { UIApplication.shared.open(url) }
        }
        return nil
    }

    func webView(_ w: WKWebView, runJavaScriptAlertPanelWithMessage mesaj: String, initiatedByFrame f: WKFrameInfo) async {
        await withCheckedContinuation { (devam: CheckedContinuation<Void, Never>) in
            let a = UIAlertController(title: nil, message: mesaj, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Tamam", style: .default) { _ in devam.resume() })
            if !PanelDenetcisi.goster(a) { devam.resume() }
        }
    }

    func webView(_ w: WKWebView, runJavaScriptConfirmPanelWithMessage mesaj: String, initiatedByFrame f: WKFrameInfo) async -> Bool {
        await withCheckedContinuation { (devam: CheckedContinuation<Bool, Never>) in
            let a = UIAlertController(title: nil, message: mesaj, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Vazgeç", style: .cancel) { _ in devam.resume(returning: false) })
            a.addAction(UIAlertAction(title: "Tamam", style: .default) { _ in devam.resume(returning: true) })
            if !PanelDenetcisi.goster(a) { devam.resume(returning: false) }
        }
    }

    func webView(_ w: WKWebView, runJavaScriptTextInputPanelWithPrompt soru: String, defaultText: String?, initiatedByFrame f: WKFrameInfo) async -> String? {
        await withCheckedContinuation { (devam: CheckedContinuation<String?, Never>) in
            let a = UIAlertController(title: nil, message: soru, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText }
            a.addAction(UIAlertAction(title: "Vazgeç", style: .cancel) { _ in devam.resume(returning: nil) })
            a.addAction(UIAlertAction(title: "Tamam", style: .default) { _ in devam.resume(returning: a.textFields?.first?.text) })
            if !PanelDenetcisi.goster(a) { devam.resume(returning: nil) }
        }
    }

    /// Kamera ve mikrofon izni (pasaport okutma): panel izin isterse sistem sorar.
    func webView(_ w: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy f: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        origin.host == PanelEkrani.adres.host ? .prompt : .deny
    }

    @discardableResult
    static func goster(_ a: UIAlertController) -> Bool {
        let sahne = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard var ust = sahne?.keyWindow?.rootViewController else { return false }
        while let s = ust.presentedViewController { ust = s }
        ust.present(a, animated: true)
        return true
    }

    // MARK: İndirme

    func download(_ indirme: WKDownload, decideDestinationUsing yanit: URLResponse, suggestedFilename ad: String) async -> URL? {
        let klasor = FileManager.default.temporaryDirectory.appendingPathComponent("panel-indirme", isDirectory: true)
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let temiz = ad.replacingOccurrences(of: "/", with: "-")
        let hedef = klasor.appendingPathComponent(temiz.isEmpty ? "dosya" : temiz)
        try? FileManager.default.removeItem(at: hedef)
        indirmeYollari[ObjectIdentifier(indirme)] = hedef
        return hedef
    }

    func downloadDidFinish(_ indirme: WKDownload) {
        if let yol = indirmeYollari.removeValue(forKey: ObjectIdentifier(indirme)) {
            paylasilacak = Dosya(url: yol)
        }
    }

    func download(_ indirme: WKDownload, didFailWithError e: Error, resumeData: Data?) {
        indirmeYollari.removeValue(forKey: ObjectIdentifier(indirme))
    }
}

struct PanelWebGorunumu: UIViewRepresentable {
    let denetci: PanelDenetcisi

    func makeUIView(context: Context) -> WKWebView {
        let ayar = WKWebViewConfiguration()
        // Kalıcı veri deposu: giriş bir kez yapılır, uygulama kapanınca da hatırlanır.
        ayar.websiteDataStore = .default()
        ayar.allowsInlineMediaPlayback = true
        let w = WKWebView(frame: .zero, configuration: ayar)
        w.navigationDelegate = denetci
        w.uiDelegate = denetci
        w.allowsBackForwardNavigationGestures = true
        w.scrollView.contentInsetAdjustmentBehavior = .automatic
        // Aşağı çekince yenile.
        let yenile = UIRefreshControl()
        yenile.addAction(UIAction { [weak w] eylem in
            w?.reload()
            (eylem.sender as? UIRefreshControl)?.endRefreshing()
        }, for: .valueChanged)
        w.scrollView.refreshControl = yenile
        denetci.web = w
        w.load(URLRequest(url: PanelEkrani.adres))
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {}
}

/// Sistem paylaşım sayfası (Dosyalar'a kaydet, WhatsApp'la gönder, yazdır).
struct PaylasimSayfasi: UIViewControllerRepresentable {
    let ogeler: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: ogeler, applicationActivities: nil)
    }

    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}
