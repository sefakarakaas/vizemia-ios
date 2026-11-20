import SwiftUI
import UserNotifications
import VizeMiaCekirdek

@main
struct VizeMiaApp: App {
    // Anlık bildirim: Firebase açılışta başlar, APNs jetonu buradan gelir.
    @UIApplicationDelegateAdaptor(UygulamaTemsilcisi.self) private var uygulamaTemsilcisi
    @State private var icerik = IcerikDeposu()
    @State private var gezinti = Gezinti()
    @State private var hafiza = TakipHafizasi()
    @State private var ekip = EkipOturumu()
    @State private var ekipVerisi = EkipVerisi()
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
                .environment(ekip)
                .environment(ekipVerisi)
                .environment(\.locale, Locale(identifier: "tr_TR"))
                // Site yalnız açık temada; uygulama da öyle.
                .preferredColorScheme(.light)
                .tint(Tema.lacivert)
                .task {
                    // Aşama bildirimine dokunan müşteri doğrudan sürecini görür; danışmana
                    // gelen anlık bildirim ilgili ekip ekranını açar (EkipKok işler).
                    Bildirimler.temsilci.dokunuldu = { hedef, sunucudan in
                        let h = AnlikBildirim.Hedef(hedef)
                        switch h {
                        case .takip: gezinti.ac(.takip(kod: ""))
                        case .yok: if !sunucudan { gezinti.ac(.takip(kod: "")) }
                        default:
                            if ekip.girisli { ekip.ekipGorunumu = true }
                            AnlikBildirimMerkezi.ortak.bekleyenHedef = h
                        }
                    }
                    // Hatırlanan başvuru varsa telefon müşteri olarak da kayıtlı kalsın (jeton değişebilir).
                    if let k = hafiza.kayit {
                        await AnlikBildirimMerkezi.ortak.musteri(takipId: Takip.kimlik(kod: k.kod, pasaport: k.pasaport))
                    }
                    await icerik.yenile()
                    await hafiza.yenile()
                }
                .onChange(of: sahne) { _, yeni in
                    switch yeni {
                    case .active:
                        ekip.oneGeldi()
                        hafiza.disktenOku()
                        Task {
                            await icerik.yenile()
                            await hafiza.yenile()
                        }
                    case .background:
                        ekip.arkaPlanaGecti()
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
