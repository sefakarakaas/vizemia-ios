import Foundation
import VizeMiaCekirdek

/// Hata → kullanıcıya gösterilecek metin. Kota dolması, yetki ve oturum gibi
/// sebebi belli hatalar kendi açıklamasıyla; ötekiler ekranın varsayılan metniyle.
enum HataAciklamasi {
    static func metin(_ e: Error, _ varsayilan: String) -> String {
        if let h = e as? FirestoreHatasi {
            switch h {
            case .izinYok, .kotaDoldu: return h.mesaj
            default: return varsayilan
            }
        }
        if case KimlikIstemci.Hata.oturumBitti = e { return KimlikIstemci.Hata.oturumBitti.mesaj }
        return varsayilan
    }
}
