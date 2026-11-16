import SwiftUI
import VizeMiaCekirdek

@main
struct VizeMiaApp: App {
    @State private var icerik = IcerikDeposu()
    @State private var gezinti = Gezinti()
    @Environment(\.scenePhase) private var sahne

    var body: some Scene {
        WindowGroup {
            KokGorunum()
                .environment(icerik)
                .environment(gezinti)
                .environment(\.locale, Locale(identifier: "tr_TR"))
                // Site yalnız açık temada; uygulama da öyle.
                .preferredColorScheme(.light)
                .tint(Tema.lacivert)
                .task { await icerik.yenile() }
                .onChange(of: sahne) { _, yeni in
                    if yeni == .active { Task { await icerik.yenile() } }
                }
                // vizemia.com bağlantısıyla açılırsa (Universal Link) ilgili ekrana git.
                .onOpenURL { url in
                    gezinti.ac(link: url.absoluteString, sayfaYollari: icerik.sayfaYollari)
                }
        }
    }
}
