import Foundation
import Observation
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging
import VizeMiaCekirdek

/// Anlık bildirim (sunucudan): jeton alınır, telefon Firestore'a kaydedilir
/// (cihazlar/), bildirimi site deposundaki Apps Script (Bildirim.gs) FCM ile
/// gönderir. Müşteri: hatırlanan başvurunun takip kimliğiyle; danışman: uid ve
/// seçtiği konularla. Firebase iOS uygulama kimliği derlemede verilmemişse
/// (FIREBASE_IOS_APP_ID boş) hiçbir şey yapılmaz; eski "arka planda denetle"
/// bildirimi çalışmaya devam eder.
@MainActor
@Observable
final class AnlikBildirimMerkezi: NSObject {
    static let ortak = AnlikBildirimMerkezi()

    /// FCM jetonu; alınana kadar nil.
    private(set) var jeton: String?
    private(set) var hazir = false
    /// Bildirime dokunulunca açılacak yer (kök görünüm işler, sonra sıfırlar).
    var bekleyenHedef: AnlikBildirim.Hedef?

    /// Kayıt için son istenen durum: jeton sonradan gelirse bunlar yazılır.
    private var musteriTakipId: String?
    /// İstemci her yazımda yeniden alınır: çalışanın belirteci bir saatte yenilenir.
    private var ekipKaydi: (istemci: () async throws -> FirestoreIstemci, calisan: Calisan, konular: [String])?

    static let konuAnahtari = "anlik.konular"

    /// Seçili konular (telefona özel). Hiç seçilmediyse hepsi açık.
    static var seciliKonular: [String] {
        get { UserDefaults.standard.stringArray(forKey: konuAnahtari) ?? BildirimKonusu.hepsi.map(\.id) }
        set { UserDefaults.standard.set(newValue, forKey: konuAnahtari) }
    }

    /// Uygulama açılışında (AppDelegate). Kimlik yoksa sessizce kapalı kalır.
    func baslat() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") || ProcessInfo.processInfo.arguments.contains("-ornek-takip") { return }
        #endif
        guard !hazir, FirebaseApp.app() == nil,
              let kimlik = Bundle.main.object(forInfoDictionaryKey: "VizeMiaFirebaseAppID") as? String,
              kimlik.hasPrefix("1:") else { return }
        let o = FirebaseOptions(googleAppID: kimlik, gcmSenderID: "860575979771")
        o.apiKey = KimlikIstemci.apiAnahtari
        o.projectID = "vieze-941cf"
        o.bundleID = Bundle.main.bundleIdentifier ?? "com.vizemia.app"
        FirebaseApp.configure(options: o)
        Messaging.messaging().delegate = self
        hazir = true
        // İzin daha önce verildiyse APNs kaydı her açılışta yenilenir (jeton değişmiş olabilir).
        Task {
            if await Bildirimler.izinVerildi() { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// İzin ister (sorulmadıysa) ve APNs'e kaydolur. Dönen: izin var mı.
    @discardableResult
    func izinIsteVeKaydol() async -> Bool {
        guard hazir else { return false }
        let izin = await Bildirimler.izinIste()
        if izin { UIApplication.shared.registerForRemoteNotifications() }
        return izin
    }

    func apnsJetonu(_ d: Data) {
        guard hazir else { return }
        Messaging.messaging().apnsToken = d
    }

    fileprivate func yeniJeton(_ j: String?) {
        guard let j, !j.isEmpty, j != jeton else { return }
        jeton = j
        Task { await kayitlariYaz() }
    }

    // MARK: Kayıt

    /// Hatırlanan başvuru için (nil: müşteri kaydı silinir).
    func musteri(takipId: String?) async {
        let eski = musteriTakipId
        musteriTakipId = takipId
        guard hazir, let j = jeton else { return }
        if takipId == nil && eski != nil {
            try? await FirestoreIstemci().isle([AnlikBildirim.kaydiSil(jeton: j, tur: "musteri")])
        } else {
            await kayitlariYaz()
        }
    }

    /// Danışman girişi (nil: çıkış; kayıt silinir — silme kuralı girişsiz de izin verir).
    func ekip(istemci: (() async throws -> FirestoreIstemci)?, calisan: Calisan?) async {
        let vardi = ekipKaydi != nil
        if let i = istemci, let c = calisan {
            ekipKaydi = (i, c, Self.seciliKonular)
        } else {
            ekipKaydi = nil
        }
        guard hazir, let j = jeton else { return }
        if ekipKaydi == nil {
            if vardi { try? await FirestoreIstemci().isle([AnlikBildirim.kaydiSil(jeton: j, tur: "ekip")]) }
        } else {
            await kayitlariYaz()
        }
    }

    /// Konu seçimi değişti: kayıt yenilenir.
    func konulariKaydet(_ l: [String]) async {
        Self.seciliKonular = l
        if let e = ekipKaydi { ekipKaydi = (e.istemci, e.calisan, l) }
        await kayitlariYaz()
    }

    private func kayitlariYaz() async {
        guard let j = jeton else { return }
        if let t = musteriTakipId {
            try? await FirestoreIstemci().isle([AnlikBildirim.musteriKaydi(jeton: j, takipId: t)])
        }
        if let e = ekipKaydi, let f = try? await e.istemci() {
            try? await f.isle([AnlikBildirim.ekipKaydi(jeton: j, calisan: e.calisan, konular: e.konular)])
        }
    }
}

extension AnlikBildirimMerkezi: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in AnlikBildirimMerkezi.ortak.yeniJeton(fcmToken) }
    }
}

/// UIKit yaşam döngüsü: Firebase'i başlatır, APNs jetonunu iletir.
final class UygulamaTemsilcisi: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { AnlikBildirimMerkezi.ortak.baslat() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { AnlikBildirimMerkezi.ortak.apnsJetonu(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simülatörde ya da izin yokken: sessizce geçilir; eski denetimli bildirim sürer.
    }
}
