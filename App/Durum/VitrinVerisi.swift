import Foundation
import Observation
import UIKit
import VizeMiaCekirdek

/// Vitrin slaytları ve fotoğraf havuzu (Vitrin ve Fotoğraf havuzu ekranları
/// aynı veriyi kullanır). Havuz belgeleri görselin kendisini taşıdığı için
/// büyüktür: en çok 5 dakikada bir okunur (aşağı çekince her zaman).
@MainActor
@Observable
final class VitrinVerisi {
    private(set) var slaytlar: [VitrinSlayti] = []
    private(set) var eklenenler: [FotoHavuzu.Eklenen] = []
    private(set) var yukleniyor = false
    private(set) var hata: String?
    private var sonYukleme: Date?

    var havuz: [FotoHavuzu.Foto] { FotoHavuzu.kur(eklenenler) }
    /// Sitede şu an yayında olanlar (otomatik arka plan bunlara göre seçilir).
    func komsular(haric id: String) -> [FotoHavuzu.SlaytGirdisi] {
        slaytlar.filter { $0.id != id && $0.sitede() }.map(\.girdi)
    }

    func yukle(_ ekip: EkipOturumu, zorla: Bool = false) async {
        if !zorla, let s = sonYukleme, Date().timeIntervalSince(s) < EkipVerisi.tazelik { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { ornek(); return }
        #endif
        guard !yukleniyor else { return }
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let f = try await ekip.istemci()
            async let s: [FirestoreIstemci.Belge] = (ekip.yapabilir("vitrin.edit") || ekip.yapabilir("vitrin.publish"))
                ? f.sorgu(koleksiyon: "vitrin", sirala: ("sira", .artan), sinir: 100) : []
            async let h = f.sorgu(koleksiyon: "fotoHavuzu", sinir: 100)
            slaytlar = try await s.map { VitrinSlayti(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            eklenenler = try await h.map { FotoHavuzu.Eklenen(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            hata = nil
            sonYukleme = Date()
        } catch {
            hata = KasaVerisi.mesaj(error, "Yüklenemedi. İnternet bağlantınızı kontrol edin.")
        }
    }

    /// Yazar; sonra listeleri yeniden okur ve site yayınını başlatır. Hata metni ya da yayın mesajı.
    func isle(_ y: [FirestoreIstemci.Yazim], ekip: EkipOturumu) async -> (tamam: Bool, mesaj: String) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return (true, SiteYayini.mesaj(basladi: true)) }
        #endif
        do {
            try await ekip.istemci().isle(y)
            let yayin = await ekip.siteyiGuncelle()
            await yukle(ekip, zorla: true)
            return (true, SiteYayini.mesaj(basladi: yayin))
        } catch {
            return (false, KasaVerisi.mesaj(error, "Kaydedilemedi."))
        }
    }

    #if DEBUG
    private func ornek() {
        var a = VitrinSlayti(id: "s1")
        a.baslik = "Noel'i Almanya'da geçirmek ister misin?"; a.ust = "Almanya · Aralık"; a.metin = "Randevular hızla doluyor, vizeni şimdiden al."
        a.ulke = "almanya"; a.durum = "yayinda"; a.sira = 1; a.kayitli = true
        var b = VitrinSlayti(id: "icerik-c1")
        b.baslik = "Schengen vizesi için banka dökümü"; b.ust = "Blog"; b.dugme = "Yazıyı oku"; b.link = "/blog/banka"
        b.durum = "taslak"; b.sira = 50; b.kayitli = true
        slaytlar = [a, b]
        eklenenler = []
    }
    #endif
}

/// Görsel yükleme ve gösterme (havuz ve slaytlar).
enum Gorsel {
    private static let onbellek = NSCache<NSString, UIImage>()

    /// data: adresi ya da site adresi → resim (önbellekli).
    static func resim(_ yol: String) async -> UIImage? {
        let anahtar = yol.count > 200 ? "\(yol.count)-\(yol.hashValue)" as NSString : yol as NSString
        if let r = onbellek.object(forKey: anahtar) { return r }
        var r: UIImage?
        if yol.hasPrefix("data:") {
            if let v = yol.range(of: ";base64,"), let d = Data(base64Encoded: String(yol[v.upperBound...])) { r = UIImage(data: d) }
        } else if let u = URL(string: yol), let (d, _) = try? await URLSession.shared.data(from: u) {
            r = UIImage(data: d)
        }
        if let r { onbellek.setObject(r, forKey: anahtar) }
        return r
    }

    /// Fotoğrafı küçültüp kuralın sınırına (700 bin karakter) sığan JPEG data: adresine çevirir (panel: kucult).
    static func kucult(_ r: UIImage) -> String? {
        for (gen, kalite) in [(1600.0, 0.82), (1600.0, 0.7), (1280.0, 0.7), (1024.0, 0.65), (800.0, 0.6)] {
            let oran = min(1, gen / max(r.size.width, 1))
            let boyut = CGSize(width: (r.size.width * oran).rounded(), height: (r.size.height * oran).rounded())
            let bicim = UIGraphicsImageRendererFormat()
            bicim.scale = 1
            let kucuk = UIGraphicsImageRenderer(size: boyut, format: bicim).image { _ in r.draw(in: CGRect(origin: .zero, size: boyut)) }
            guard let jpeg = kucuk.jpegData(compressionQuality: kalite) else { continue }
            let adres = FotoHavuzu.veriAdresi(jpeg: jpeg)
            if adres.count <= FotoHavuzu.gorselSiniri { return adres }
        }
        return nil
    }
}
