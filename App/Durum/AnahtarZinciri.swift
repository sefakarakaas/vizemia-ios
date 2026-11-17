import Foundation
import Security

/// Anahtar Zinciri'nde küçük kayıtlar (JSON). Cihazdan çıkmaz, iCloud'a
/// yedeklenmez; ilk kilit açılışından sonra okunabilir (arka plan işleri için).
enum AnahtarZinciri {
    private static func sorgu(_ servis: String, _ hesap: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: servis,
         kSecAttrAccount as String: hesap]
    }

    static func oku<T: Decodable>(_ tur: T.Type, servis: String, hesap: String) -> T? {
        var s = sorgu(servis, hesap)
        s[kSecReturnData as String] = true
        s[kSecMatchLimit as String] = kSecMatchLimitOne
        var sonuc: CFTypeRef?
        guard SecItemCopyMatching(s as CFDictionary, &sonuc) == errSecSuccess, let veri = sonuc as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: veri)
    }

    static func yaz<T: Encodable>(_ deger: T, servis: String, hesap: String) {
        guard let veri = try? JSONEncoder().encode(deger) else { return }
        SecItemDelete(sorgu(servis, hesap) as CFDictionary)
        var s = sorgu(servis, hesap)
        s[kSecValueData as String] = veri
        s[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(s as CFDictionary, nil)
    }

    static func sil(servis: String, hesap: String) {
        SecItemDelete(sorgu(servis, hesap) as CFDictionary)
    }
}
