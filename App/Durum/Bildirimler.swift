import Foundation
import UIKit
import UserNotifications
import BackgroundTasks
import VizeMiaCekirdek

/// Aşama değişince gösterilen bildirimler ("Beni unutma" diyen müşteri için).
///
/// Bildirimi sunucu göndermiyor: uygulama arka planda belirli aralıklarla
/// durumu kendisi denetler, son görülenden farklıysa bildirimi telefonda üretir.
/// Sunucu, anahtar ya da cihaz kaydı gerekmez. Denetimin ne zaman çalışacağına
/// iOS karar verir (kullanım sıklığı, pil, düşük güç modu); bu yüzden bildirim
/// birkaç saat gecikebilir, uygulama elle kapatıldıysa hiç gelmeyebilir.
/// Anında bildirim için sunucudan gönderim (APNs) gerekir; sıradaki adım.
enum Bildirimler {
    /// Yapi/Info.plist → BGTaskSchedulerPermittedIdentifiers ile aynı olmalı.
    static let gorevKimligi = "com.vizemia.app.takip-yenile"
    static let temsilci = BildirimTemsilcisi()

    static func izinVerildi() async -> Bool {
        let durum = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return durum == .authorized || durum == .provisional || durum == .ephemeral
    }

    static func reddedildi() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// İzin daha önce sorulmadıysa sorar. Dönen: bildirim gösterilebiliyor mu.
    static func izinIste() async -> Bool {
        let merkez = UNUserNotificationCenter.current()
        let durum = await merkez.notificationSettings().authorizationStatus
        if durum == .notDetermined {
            return (try? await merkez.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        return durum == .authorized || durum == .provisional || durum == .ephemeral
    }

    /// Bildirimi hemen gösterir.
    static func gonder(_ b: TakipBildirimi) async {
        let icerik = UNMutableNotificationContent()
        icerik.title = b.baslik
        icerik.body = b.govde
        icerik.sound = .default
        icerik.badge = 1
        // Aynı kimlik: okunmamış eski durum bildirimi yenisiyle değişir, üst üste birikmez.
        let istek = UNNotificationRequest(identifier: "takip-durum", content: icerik, trigger: nil)
        try? await UNUserNotificationCenter.current().add(istek)
    }

    static func rozetiSil() {
        let merkez = UNUserNotificationCenter.current()
        merkez.setBadgeCount(0)
        merkez.removeAllDeliveredNotifications()
    }

    /// Bir sonraki arka plan denetimini ister (en erken bir saat sonra).
    /// Simülatörde arka plan görevi yok; hata sessizce geçilir.
    static func sonrakiDenetimiPlanla() {
        let istek = BGAppRefreshTaskRequest(identifier: gorevKimligi)
        istek.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(istek)
    }

    static func planiIptalEt() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: gorevKimligi)
    }

    /// Sistem ayarlarında uygulamanın bildirim sayfasını açar.
    @MainActor
    static func ayarlariAc() {
        if let u = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(u)
        }
    }
}

/// Bildirime dokunulunca Takip sekmesini açar; uygulama açıkken gelen bildirimi de gösterir.
final class BildirimTemsilcisi: NSObject, UNUserNotificationCenterDelegate {
    /// Dokunulan bildirimin hedefi ("basvuru:x", "takip"…) ve sunucudan mı geldiği
    /// (anlık bildirimde "konu" var; telefonun kendi ürettiği durum bildiriminde yok).
    var dokunuldu: (@MainActor (_ hedef: String?, _ sunucudan: Bool) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let bilgi = response.notification.request.content.userInfo
        let hedef = bilgi["hedef"] as? String
        let sunucudan = bilgi["konu"] != nil
        Task { @MainActor in
            self.dokunuldu?(hedef, sunucudan)
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
