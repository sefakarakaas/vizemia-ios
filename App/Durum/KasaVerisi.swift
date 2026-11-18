import Foundation
import Observation
import VizeMiaCekirdek

/// Kasa ve raporlar (panel: #/kasa). Rapor yalnız seçilen dönemi okur; bir
/// kayıt eklenince ya da iptal edilince yalnız o belge yeniden okunur
/// (okuma kotası: CLAUDE.md).
@MainActor
@Observable
final class KasaVerisi {
    // Rapor
    var aralikTuru = "bugun"
    var ozelBas = Date()
    var ozelBit = Date()
    private(set) var bas = ""
    private(set) var bit = ""
    private(set) var hareketler: [KasaHareketi] = []
    private(set) var ozet = KasaOzeti([])
    private(set) var raporYukleniyor = false
    private(set) var raporHata: String?
    private(set) var raporYuklemesi: Date?
    // Rutin ödemeler
    private(set) var rutinler: [RutinOdeme] = []
    private(set) var odenenler: [KasaHareketi] = []
    private(set) var rutinHata: String?
    private(set) var rutinYuklemesi: Date?

    /// Rapor en çok bu kadar hareket okur (panel 3000; bir ay için bol bol yeter).
    static let raporSiniri = 1000

    var sinirDoldu: Bool { hareketler.count >= Self.raporSiniri }
    var tekGun: Bool { bas == bit }

    var bekleyenler: (geciken: [RutinOdeme.Vade], bugun: [RutinOdeme.Vade], yaklasan: [RutinOdeme.Vade]) {
        RutinOdeme.bekleyenler(rutinler.filter(\.aktif), odenenler: odenenler, bugun: Tr.bugun())
    }

    private func aralikHesapla() {
        let r = KasaKurali.aralik(aralikTuru, bugun: Tr.bugun(),
                                  ozelBas: Tr.isoGun(ozelBas, takvim: Tr.takvim), ozelBit: Tr.isoGun(ozelBit, takvim: Tr.takvim))
        bas = r.bas
        bit = r.bit
    }

    /// Başka ekrandan (başvuru) kayıt eklenince rapor bir sonraki açılışta yeniden okunsun.
    func eskit() { raporYuklemesi = nil }

    // MARK: Okuma

    func raporYukle(_ ekip: EkipOturumu, zorla: Bool = true) async {
        guard ekip.yapabilir("kasa.view") else { return }
        if !zorla, let s = raporYuklemesi, Date().timeIntervalSince(s) < EkipVerisi.tazelik { return }
        aralikHesapla()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { ornek(); return }
        #endif
        raporYukleniyor = true
        defer { raporYukleniyor = false }
        do {
            let f = try await ekip.istemci()
            let l = try await f.sorgu(koleksiyon: "kasa", kosullar: [.enAz("tarih", .metin(bas)), .enCok("tarih", .metin(bit))],
                                      sirala: ("tarih", .azalan), sinir: Self.raporSiniri)
            hareketler = l.map { KasaHareketi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            ozet = KasaOzeti(hareketler)
            raporHata = nil
            raporYuklemesi = Date()
        } catch {
            raporHata = Self.mesaj(error, "Rapor yüklenemedi. İnternet bağlantınızı kontrol edin.")
        }
    }

    /// Rutin ödemeler ve (kasayı görebiliyorsa) son 63 günün ödenmiş vadeleri.
    func rutinleriYukle(_ ekip: EkipOturumu, zorla: Bool = true) async {
        guard ekip.yapabilir("kasa.view") || ekip.yapabilir("kasa.gider") || ekip.yapabilir("kasa.rutin") else { return }
        if !zorla, let s = rutinYuklemesi, Date().timeIntervalSince(s) < EkipVerisi.tazelik { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { ornek(); return }
        #endif
        do {
            let f = try await ekip.istemci()
            let bas = Tr.gunEkle(Tr.bugun(), -(RutinOdeme.geriyeGun + 1))
            async let r = f.sorgu(koleksiyon: "kasaRutin", sirala: ("ad", .artan), sinir: 200)
            async let o: [FirestoreIstemci.Belge] = ekip.yapabilir("kasa.view")
                ? f.sorgu(koleksiyon: "kasa", kosullar: [.enAz("rutinVade", .metin(bas))], sinir: 500) : []
            rutinler = try await r.map { RutinOdeme(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            odenenler = try await o.map { KasaHareketi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            rutinHata = nil
            rutinYuklemesi = Date()
        } catch {
            rutinHata = Self.mesaj(error, "Rutin ödemeler yüklenemedi.")
        }
    }

    // MARK: Yazma

    /// Harcama / çevrim / rutin vadesi. Hata metni döner (nil: tamam).
    func kaydet(_ g: KasaGirdisi, fis: HazirDosya?, kimlik: String? = nil, ekip: EkipOturumu) async -> String? {
        guard let c = ekip.calisan else { return "Oturum bulunamadı." }
        let k = kimlik.map { KasaIslemi.kaydet(g, fis: fis, kimlik: $0, calisan: c) } ?? KasaIslemi.kaydet(g, fis: fis, calisan: c)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return nil }
        #endif
        do {
            let f = try await ekip.istemci()
            try await f.isle(k.yazimlar)
            ekip.kasaBildir(k.id)
            await tekKayit(k.id, f, ekip)
            return nil
        } catch {
            return Self.mesaj(error, "Kaydedilemedi. İnternet bağlantınızı kontrol edip yeniden deneyin.")
        }
    }

    /// Yeni / iptal edilen kaydı yeniden okur ve listelere yerleştirir (tek okuma).
    private func tekKayit(_ id: String, _ f: FirestoreIstemci, _ ekip: EkipOturumu) async {
        guard ekip.yapabilir("kasa.view"), let a = try? await f.belge("kasa/\(id)") else { return }
        let x = KasaHareketi(kimlik: id, alanlar: a)
        if !bas.isEmpty && x.tarih >= bas && x.tarih <= bit {
            hareketler.removeAll { $0.id == id }
            hareketler.append(x)
            hareketler.sort { $0.tarih > $1.tarih }
            ozet = KasaOzeti(hareketler)
        }
        if !x.rutinId.isEmpty {
            odenenler.removeAll { $0.id == id }
            odenenler.append(x)
        }
    }

    func iptal(_ x: KasaHareketi, neden: String, ekip: EkipOturumu) async -> String? {
        guard let c = ekip.calisan else { return "Oturum bulunamadı." }
        let n = neden.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return "İptal nedenini yazın." }
        do {
            let f = try await ekip.istemci()
            try await f.isle(KasaIslemi.iptal(x, neden: n, calisan: c))
            await tekKayit(x.id, f, ekip)
            return nil
        } catch {
            return Self.mesaj(error, "İptal edilemedi.")
        }
    }

    func rutinKaydet(_ r: RutinOdeme, kaydaYaz: Bool = true, ekip: EkipOturumu) async -> String? {
        guard let c = ekip.calisan else { return "Oturum bulunamadı." }
        let k = KasaIslemi.rutinKaydet(r, kaydaYaz: kaydaYaz, calisan: c)
        do {
            let f = try await ekip.istemci()
            try await f.isle(k.yazimlar)
            if let a = try? await f.belge("kasaRutin/\(k.id)") {
                rutinler.removeAll { $0.id == k.id }
                rutinler.append(RutinOdeme(kimlik: k.id, alanlar: a))
                rutinler.sort { $0.ad.compare($1.ad, locale: Tr.yerel) == .orderedAscending }
            }
            return nil
        } catch {
            return Self.mesaj(error, "Kaydedilemedi.")
        }
    }

    func rutinSil(_ r: RutinOdeme, ekip: EkipOturumu) async -> String? {
        guard let c = ekip.calisan else { return "Oturum bulunamadı." }
        do {
            try await ekip.istemci().isle(KasaIslemi.rutinSil(r, calisan: c))
            rutinler.removeAll { $0.id == r.id }
            return nil
        } catch {
            return Self.mesaj(error, "Silinemedi.")
        }
    }

    /// Fiş / dekont fotoğrafını indirir (kasa/{id}/dosyalar + dosyaIcerik).
    static func fisDosyasi(_ x: KasaHareketi, ekip: EkipOturumu) async throws -> URL {
        let f = try await ekip.istemci()
        let ust = "kasa/\(x.id)"
        guard let a = try await f.belge("\(ust)/dosyalar/\(x.fisId)") else { throw FirestoreHatasi.sunucu(404) }
        let d = DosyaBilgisi(kimlik: x.fisId, alanlar: a)
        var parcalar: [[String: FSDeger]?] = []
        for p in d.parcaYollari(ust: ust) { parcalar.append(try await f.belge(p)) }
        guard let veri = Dosya.birlestir(parcalar) else { throw FirestoreHatasi.sunucu(404) }
        let klasor = FileManager.default.temporaryDirectory.appendingPathComponent("belgeler", isDirectory: true)
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let url = klasor.appendingPathComponent(Dosya.adTemizle(d.ad, yedek: "fis"))
        try veri.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Raporun CSV dosyası (Excel'de açılır).
    func csvDosyasi() -> URL? {
        let klasor = FileManager.default.temporaryDirectory.appendingPathComponent("kasa", isDirectory: true)
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let url = klasor.appendingPathComponent("kasa-\(bas)_\(bit).csv")
        guard (try? Data(KasaCsv.metin(hareketler).utf8).write(to: url, options: [.atomic, .completeFileProtection])) != nil else { return nil }
        return url
    }

    static func mesaj(_ e: Error, _ varsayilan: String) -> String { HataAciklamasi.metin(e, varsayilan) }

    #if DEBUG
    private func ornek() {
        let bugun = Tr.bugun()
        func h(_ id: String, _ a: [String: FSDeger]) -> KasaHareketi { KasaHareketi(kimlik: id, alanlar: a) }
        hareketler = [
            h("k1", ["tur": .metin("gelir"), "kapsam": .metin("musteri"), "kategori": .metin("Müşteri ödemesi"), "tutar": .tam(2500),
                     "paraBirimi": .metin("TRY"), "yontem": .metin("havale"), "tarih": .metin(bugun), "musteriAd": .metin("Zeynep Kaya"),
                     "byName": .metin("Sefa Karakaş"), "iptal": .mantik(false)]),
            h("k2", ["tur": .metin("gider"), "kapsam": .metin("musteri"), "kategori": .metin("Fotokopi"), "tutar": .ondalik(25.5),
                     "paraBirimi": .metin("TRY"), "yontem": .metin("nakit"), "tarih": .metin(bugun), "musteriAd": .metin("Zeynep Kaya"),
                     "byName": .metin("Ezgi"), "iptal": .mantik(false)]),
            h("k3", ["tur": .metin("gider"), "kapsam": .metin("genel"), "kategori": .metin("Market alışverişi"), "tutar": .tam(340),
                     "paraBirimi": .metin("TRY"), "yontem": .metin("kart"), "tarih": .metin(bugun), "aciklama": .metin("Çay, kahve"),
                     "fisId": .metin("f1"), "byName": .metin("Ezgi"), "iptal": .mantik(false)]),
            h("k4", ["tur": .metin("cevrim"), "kapsam": .metin("genel"), "kategori": .metin("Döviz çevrimi"), "tutar": .tam(50),
                     "paraBirimi": .metin("EUR"), "hedefTutar": .tam(2425), "hedefParaBirimi": .metin("TRY"), "buro": .metin("Kızılay Döviz"),
                     "yontem": .metin("nakit"), "tarih": .metin(bugun), "byName": .metin("Sefa Karakaş"), "iptal": .mantik(false)]),
        ]
        ozet = KasaOzeti(hareketler)
        var kira = RutinOdeme(id: "r1")
        kira.ad = "Ofis kirası"; kira.kategori = "Kira"; kira.tutar = 20000; kira.siklik = "aylik"
        kira.gun = Int(bugun.suffix(2)) ?? 1; kira.baslangic = Tr.gunEkle(bugun, -90)
        var temizlik = RutinOdeme(id: "r2")
        temizlik.ad = "Temizlik"; temizlik.kategori = "Temizlik"; temizlik.tutar = 1500; temizlik.yontem = "nakit"
        temizlik.siklik = "haftalik"; temizlik.gun = (Tr.gunNo(Tr.gunEkle(bugun, 2)) + 6) % 7 + 1; temizlik.baslangic = Tr.gunEkle(bugun, -10)
        rutinler = [kira, temizlik]
        odenenler = []
    }
    #endif
}
