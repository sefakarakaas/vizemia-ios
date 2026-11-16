import Foundation
import Security
import VizeMiaCekirdek

/// "Beni unutma" diyen müşterinin takip bilgisi (kod + pasaport numarası) ve
/// son gördüğü durum, cihazın Anahtar Zinciri'nde saklanır. Yalnız müşteri
/// düğmeye basarsa yazılır; cihazdan çıkmaz, iCloud'a yedeklenmez.
///
/// Erişim "ilk kilit açılışından sonra": arka plandaki durum denetimi telefon
/// kilitliyken de çalışabilsin diye. Telefon yeniden başlatılıp hiç açılmadıysa
/// okunamaz.
enum Kasa {
    private static let servis = "com.vizemia.app.takip"
    private static let hesap = "son-sorgu"

    struct Kayit: Codable, Equatable {
        var kod: String
        var pasaport: String
        /// Son görülen durum: açılıştaki karşılamada ve çevrimdışıyken gösterilir;
        /// değişiklik bildirimi bununla karşılaştırılarak üretilir.
        var son: TakipKaydi?
    }

    private static var sorgu: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servis,
            kSecAttrAccount as String: hesap,
        ]
    }

    static func oku() -> Kayit? {
        var s = sorgu
        s[kSecReturnData as String] = true
        s[kSecMatchLimit as String] = kSecMatchLimitOne
        var sonuc: CFTypeRef?
        guard SecItemCopyMatching(s as CFDictionary, &sonuc) == errSecSuccess,
              let veri = sonuc as? Data else { return nil }
        return try? JSONDecoder().decode(Kayit.self, from: veri)
    }

    static func yaz(_ kayit: Kayit) {
        guard let veri = try? JSONEncoder().encode(kayit) else { return }
        SecItemDelete(sorgu as CFDictionary)
        var s = sorgu
        s[kSecValueData as String] = veri
        s[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(s as CFDictionary, nil)
    }

    static func sil() {
        SecItemDelete(sorgu as CFDictionary)
    }
}
