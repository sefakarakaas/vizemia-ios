import SwiftUI
import UserNotifications
import VizeMiaCekirdek

@main
struct VizeMiaApp: App {
    @State private var icerik = IcerikDeposu()
    @State private var gezinti = Gezinti()
    @State private var hafiza = TakipHafizasi()
    @Environment(\.scenePhase) private var sahne

    init() {
        // Bildirime dokunulunca haber alabilmek için açılışta bağlanır.
        UNUserNotificationCenter.current().delegate = Bildirimler.temsilci
    }

    var body: some Scene {
        WindowGroup {
            KokGorunum()
                .environment(icerik)
                .environment(gezinti)
                .environment(hafiza)
                .environment(\.locale, Locale(identifier: "tr_TR"))
                // Site yalnız açık temada; uygulama da öyle.
                .preferredColorScheme(.light)
                .tint(Tema.lacivert)
                .task {
                    // Aşama bildirimine dokunan müşteri doğrudan sürecini görür.
                    Bildirimler.temsilci.dokunuldu = { gezinti.ac(.takip(kod: "")) }
                    await icerik.yenile()
                    await hafiza.yenile()
                }
                .onChange(of: sahne) { _, yeni in
                    switch yeni {
                    case .active:
                        hafiza.disktenOku()
                        Task {
                            await icerik.yenile()
                            await hafiza.yenile()
                        }
                    case .background:
                        // Uygulama kapalıyken durum denetimi: yalnız "Beni unutma" diyenler için.
                        if hafiza.hatirlaniyor { Bildirimler.sonrakiDenetimiPlanla() }
                    default:
                        break
                    }
                }
                // vizemia.com bağlantısıyla açılırsa (Universal Link) ilgili ekrana git.
                .onOpenURL { url in
                    gezinti.ac(link: url.absoluteString, sayfaYollari: icerik.sayfaYollari)
                }
        }
        // iOS'un uygun gördüğü zamanlarda arka planda çalışır: durum değiştiyse bildirim gösterir.
        .backgroundTask(.appRefresh(Bildirimler.gorevKimligi)) {
            await TakipHafizasi.arkaPlandaDenetle()
        }
    }
}
