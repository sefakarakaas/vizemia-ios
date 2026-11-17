import Foundation
import Observation
import VizeMiaCekirdek

/// Ekip ekranlarının ortak verisi: açık talepler, destek talepleri, takvim.
/// Ana sayfa, Talepler ve Takvim aynı listeyi kullanır; bir talep
/// güncellenince hepsi birlikte değişir.
@MainActor
@Observable
final class EkipVerisi {
    private(set) var talepler: [Talep] = []
    private(set) var kapananlar: [Talep] = []
    private(set) var destek: [DestekTalebi] = []
    private(set) var takvim: [TakvimIsi] = []
    private(set) var yukleniyor = false
    private(set) var hata: String?
    private(set) var sonYukleme: Date?

    var bugun: String { Mesai.trSimdi().iso }
    var ozet: TalepOzeti { TalepOzeti(talepler, bugun: bugun) }
    var acikDestek: Int { destek.filter { $0.durum == "new" }.count }

    /// Takvimin başvuru kısmı (randevular, tekrar aramalar): yalnız Takvim açılınca okunur.
    private var randevular: [Basvuru] = []
    private var tekrarlar: [Basvuru] = []
    private var takvimYuklemesi: Date?
    /// Başvurular listesi: ekrandan çıkıp girince yeniden okunmasın diye burada.
    let basvurular = BasvuruListesiVerisi()
    /// Bir ekrandan ötekine taşınan bilgi (ör. kaydedilen formdan sonra ayrıntıda gösterilir).
    var sonMesaj: String?

    /// Firestore'un ücretsiz planında günde 50.000 belge okuma var ve panel,
    /// site ve zamanlanmış işler de aynı kotayı kullanıyor. Her okunan belge
    /// sayılıyor; bu yüzden ekranlar arasında gezinirken liste yeniden okunmaz:
    /// en çok 5 dakikada bir (aşağı çekerek yenileme her zaman okur).
    static let tazelik: TimeInterval = 5 * 60

    /// Açık talepleri ve açık destek taleplerini okur. Yetkisi olmayan bölüm boş kalır.
    func yukle(_ ekip: EkipOturumu, zorla: Bool = false) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { ornekVeri(); return }
        #endif
        if !zorla, let s = sonYukleme, Date().timeIntervalSince(s) < Self.tazelik { return }
        guard !yukleniyor else { return }
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let f = try await ekip.istemci()
            let acik = Talep.acikDurumlar.map { FSDeger.metin($0) }
            // Panelle aynı sınır (Talepler: koleksiyon başına 200).
            async let cb: [FirestoreIstemci.Belge] = ekip.yapabilir("lead.view")
                ? f.sorgu(koleksiyon: "callback", kosullar: [.icinde("status", acik)], sirala: ("createdAt", .azalan), sinir: 200) : []
            async let ar: [FirestoreIstemci.Belge] = ekip.yapabilir("lead.view")
                ? f.sorgu(koleksiyon: "applicationRequests", kosullar: [.icinde("status", acik)], sirala: ("createdAt", .azalan), sinir: 200) : []
            async let ds: [FirestoreIstemci.Belge] = ekip.yapabilir("support.view")
                ? f.sorgu(koleksiyon: "support", kosullar: [.icinde("status", [.metin("new"), .metin("open")])], sirala: ("createdAt", .azalan), sinir: 100) : []
            let t = try await cb.map { Talep(tur: .geriArama, kimlik: $0.kimlik, alanlar: $0.alanlar) }
                + (try await ar).map { Talep(tur: .basvuru, kimlik: $0.kimlik, alanlar: $0.alanlar) }
            talepler = Talep.sirala(t.filter { !$0.silindi })
            destek = try await ds.map { DestekTalebi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            hata = nil
            sonYukleme = Date()
            takvimiKur(ekip)
        } catch KimlikIstemci.Hata.oturumBitti {
            hata = KimlikIstemci.Hata.oturumBitti.mesaj
        } catch FirestoreHatasi.izinYok {
            hata = "Bu bilgileri görme yetkiniz yok."
        } catch FirestoreHatasi.sunucu(429) {
            hata = "Veritabanının günlük okuma sınırı doldu; sınır her gün 11.00'de yenilenir."
        } catch {
            hata = "Bilgiler yüklenemedi. İnternet bağlantınızı kontrol edin."
        }
    }

    /// Takvim ekranı açılınca: randevular (son bir hafta – önümüzdeki iki ay) ve
    /// tekrar arama aralığındaki başvurular. 15 dakikada bir okunur.
    func takvimiYukle(_ ekip: EkipOturumu, zorla: Bool = false) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return }
        #endif
        await yukle(ekip, zorla: zorla)
        if !zorla, let s = takvimYuklemesi, Date().timeIntervalSince(s) < 3 * Self.tazelik { return }
        guard ekip.yapabilir("app.view"), let f = try? await ekip.istemci() else { return }
        let simdi = Date()
        let bas = simdi.addingTimeInterval(-7 * 86_400), son = simdi.addingTimeInterval(62 * 86_400)
        if let r = try? await f.sorgu(koleksiyon: "applications", kosullar: [
            .enAz("appointmentAt", .zaman(bas)), .kucuk("appointmentAt", .zaman(son))], sinir: 200) {
            randevular = r.map { Basvuru(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        }
        let aranir = ekip.statuler.filter { $0.tekrarAranir }.map { FSDeger.metin($0.id) }.prefix(30)
        if !aranir.isEmpty, let r = try? await f.sorgu(koleksiyon: "applications",
                                                      kosullar: [.icinde("statusId", Array(aranir))], sinir: 200) {
            tekrarlar = r.map { Basvuru(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        }
        takvimYuklemesi = Date()
        takvimiKur(ekip)
    }

    private func takvimiKur(_ ekip: EkipOturumu) {
        takvim = TakvimIsi.olustur(talepler: talepler, randevular: randevular, tekrarlar: tekrarlar,
                                   statuler: ekip.statuSozlugu, bugun: bugun)
    }

    /// Kapanmış talepler (onaylanan, iptal, kapatılan): yalnız istenince.
    func kapananlariYukle(_ ekip: EkipOturumu) async {
        guard ekip.yapabilir("lead.view"), let f = try? await ekip.istemci() else { return }
        let kapali = ["approved", "cancelled", "closed", "converted"].map { FSDeger.metin($0) }
        async let cb = try? f.sorgu(koleksiyon: "callback", kosullar: [.icinde("status", kapali)], sirala: ("createdAt", .azalan), sinir: 100)
        async let ar = try? f.sorgu(koleksiyon: "applicationRequests", kosullar: [.icinde("status", kapali)], sirala: ("createdAt", .azalan), sinir: 100)
        let t = (await cb ?? []).map { Talep(tur: .geriArama, kimlik: $0.kimlik, alanlar: $0.alanlar) }
            + (await ar ?? []).map { Talep(tur: .basvuru, kimlik: $0.kimlik, alanlar: $0.alanlar) }
        kapananlar = t.filter { !$0.silindi }.sorted { ($0.olusturma ?? .distantPast) > ($1.olusturma ?? .distantPast) }
    }

    /// Talebin durumunu değiştirir; işlem kaydına yazar. Panelle aynı yazı.
    func talepGuncelle(_ t: Talep, durum: String, icNot: String, iptalSebebi: String? = nil, ekip: EkipOturumu) async throws {
        guard let c = ekip.calisan else { throw KimlikIstemci.Hata.oturumBitti }
        let f = try await ekip.istemci()
        try await f.guncelle(t.yol, alanlar: Talep.durumAlanlari(durum: durum, icNot: icNot, iptalSebebi: iptalSebebi, uid: c.uid),
                             zamanAlanlari: ["handledAt"])
        let eylem = iptalSebebi == nil ? "update" : "cancel"
        let ayrinti = iptalSebebi.map { "\(t.ad) — \($0)" } ?? durum
        _ = try? await f.ekle(koleksiyon: "audit", alanlar: IslemKaydi.alanlar(
            eylem: "\(t.tur.rawValue).\(eylem)", hedef: t.kimlik, ayrinti: ayrinti, calisan: c), zamanAlani: "at")
        // Listeyi yerinde güncelle (yeniden yüklemeyi beklemeden).
        var yeni = t
        yeni.durum = durum
        yeni.icNot = icNot.trimmingCharacters(in: .whitespacesAndNewlines)
        if Talep.acikDurumlar.contains(durum) {
            talepler = Talep.sirala(talepler.map { $0.id == t.id ? yeni : $0 })
        } else {
            talepler.removeAll { $0.id == t.id }
            kapananlar.insert(yeni, at: 0)
        }
        takvim.removeAll { $0.bag == "talep:\(t.yol)" && !["new", "called"].contains(durum) }
    }

    func destekGuncelle(_ d: DestekTalebi, durum: String, icNot: String, ekip: EkipOturumu) async throws {
        guard let c = ekip.calisan else { throw KimlikIstemci.Hata.oturumBitti }
        let f = try await ekip.istemci()
        try await f.guncelle("support/\(d.kimlik)", alanlar: DestekTalebi.durumAlanlari(durum: durum, icNot: icNot, uid: c.uid),
                             zamanAlanlari: ["handledAt"])
        _ = try? await f.ekle(koleksiyon: "audit", alanlar: IslemKaydi.alanlar(
            eylem: "support.update", hedef: d.kimlik, ayrinti: durum, calisan: c), zamanAlani: "at")
        var yeni = d
        yeni.durum = durum
        yeni.icNot = icNot
        destek = destek.map { $0.id == d.id ? yeni : $0 }
    }

    #if DEBUG
    /// Ekran testleri için örnek veri (ağa bağlanmaz).
    private func ornekVeri() {
        guard talepler.isEmpty else { return }
        let b = bugun, yarin = Tr.gunEkle(b, 1), dun = Tr.gunEkle(b, -1)
        func t(_ tur: Talep.Tur, _ id: String, _ a: [String: FSDeger]) -> Talep { Talep(tur: tur, kimlik: id, alanlar: a) }
        talepler = Talep.sirala([
            t(.basvuru, "o1", ["firstName": .metin("AYSE"), "lastName": .metin("OZTURK"), "phone": .metin("+905000000001"),
                              "countryName": .metin("Almanya"), "visaType": .metin("ziyaret"), "callbackMode": .metin("hemen"),
                              "callbackDate": .metin(b), "callbackTimes": .dizi([.metin("11:00")]), "status": .metin("new"),
                              "message": .metin("Münih'teki kızımı ziyaret edeceğim, mart başında."), "email": .metin("ayse@example.com")]),
            t(.geriArama, "o2", ["name": .metin("Mehmet Yılmaz"), "phone": .metin("+905000000002"), "countryName": .metin("Fransa"),
                                "mode": .metin("saat"), "date": .metin(b), "times": .dizi([.metin("14:00"), .metin("14:30")]), "status": .metin("new")]),
            t(.geriArama, "o3", ["name": .metin("Elif Kaya"), "phone": .metin("+905000000003"), "countryName": .metin("İtalya"),
                                "mode": .metin("saat"), "date": .metin(dun), "times": .dizi([.metin("10:00")]), "status": .metin("new")]),
            t(.geriArama, "o4", ["name": .metin("Can Demir"), "phone": .metin("+905000000004"), "countryName": .metin("Birleşik Krallık"),
                                "mode": .metin("saat"), "date": .metin(yarin), "times": .dizi([.metin("09:30")]), "status": .metin("called"),
                                "internalNote": .metin("Açmadı, yarın sabah yeniden.")]),
            t(.geriArama, "o5", ["name": .metin("Zeynep Arslan"), "phone": .metin("+905000000005"), "countryName": .metin("ABD"),
                                "mode": .metin("saat"), "date": .metin(dun), "times": .dizi([.metin("16:00")]), "status": .metin("reached"),
                                "kaynak": .metin("armut")]),
        ])
        destek = [DestekTalebi(kimlik: "d1", alanlar: ["name": .metin("Ahmet Şahin"), "email": .metin("ahmet@example.com"),
                                                       "subject": .metin("Randevu tarihim değişebilir mi?"), "status": .metin("new"),
                                                       "message": .metin("Merhaba, iş yoğunluğu nedeniyle randevumu bir hafta ileri alabilir miyiz?")])]
        let randevu = Basvuru(kimlik: "r1", alanlar: ["firstName": .metin("MURAT"), "lastName": .metin("ACAR"), "countryName": .metin("Hollanda"),
                                                     "appointmentAt": .zaman(Date().addingTimeInterval(86_400)), "randevuSaati": .metin("10:30"),
                                                     "randevuYeri": .metin("VFS Global")])
        takvim = TakvimIsi.olustur(talepler: talepler, randevular: [randevu], tekrarlar: [], statuler: [:], bugun: b)
        sonYukleme = Date()
    }
    #endif

    func talep(_ yol: String) -> Talep? { (talepler + kapananlar).first { $0.yol == yol } }

    func temizle() {
        talepler = []; kapananlar = []; destek = []; takvim = []; sonYukleme = nil; hata = nil
        randevular = []; tekrarlar = []; takvimYuklemesi = nil
    }
}
