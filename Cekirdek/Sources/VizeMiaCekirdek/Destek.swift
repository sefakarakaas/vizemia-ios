import Foundation

/// Destek talebi (support): siteden ve uygulamadan gelen yazılı sorular.
public struct DestekTalebi: Equatable, Identifiable {
    public var kimlik: String
    public var ad: String
    public var eposta: String
    public var telefon: String
    public var takipKodu: String
    public var konu: String
    public var mesaj: String
    public var durum: String
    public var icNot: String
    public var olusturma: Date?
    public var id: String { kimlik }

    public static let durumlar = [("new", "Yeni"), ("open", "İşlemde"), ("closed", "Kapatıldı")]

    public init(kimlik: String, alanlar a: [String: FSDeger]) {
        self.kimlik = kimlik
        let m = { (k: String) in a[k]?.metinDegeri ?? "" }
        ad = m("name"); eposta = m("email"); telefon = m("phone"); takipKodu = m("trackingCode")
        konu = m("subject"); mesaj = m("message"); durum = m("status"); icNot = m("internalNote")
        olusturma = a["createdAt"]?.zamanDegeri
    }

    public var durumAdi: String { DestekTalebi.durumlar.first { $0.0 == durum }?.1 ?? durum }

    /// Kural: yalnız status, internalNote, handledAt (sunucu), handledBy.
    public static func durumAlanlari(durum: String, icNot: String, uid: String) -> [String: FSDeger] {
        ["status": .metin(durum), "internalNote": .metin(String(icNot.kirpik.prefix(2000))), "handledBy": .metin(uid)]
    }
}
