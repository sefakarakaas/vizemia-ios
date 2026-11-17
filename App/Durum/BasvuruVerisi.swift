import Foundation
import Observation
import VizeMiaCekirdek

/// Başvurular listesi (panel: #/basvurular). Panelle aynı sorgular, 100'erli sayfa.
@MainActor
@Observable
final class BasvuruListesiVerisi {
    enum Suzgec: Hashable {
        case hepsi
        case statu(String)
        /// Tekrar arama zamanı gelmiş ya da geçmiş olanlar (en acil üstte).
        case aranacak
        /// Silinme tarihi uyarı süresi içinde olanlar.
        case silinecek
    }

    private(set) var satirlar: [Basvuru] = []
    private(set) var bitti = false
    private(set) var yukleniyor = false
    private(set) var hata: String?
    /// Takip kodu / pasaportla bulunanlar: liste yerine bunlar gösterilir.
    private(set) var bulunanlar: [Basvuru]?
    private var sonDeger: FSDeger?
    private(set) var suzgec: Suzgec = .hepsi
    private var sonYukleme: Date?
    static let sayfa = 100

    var eskidi: Bool { sonYukleme.map { Date().timeIntervalSince($0) > EkipVerisi.tazelik } ?? true }

    func yukle(_ ekip: EkipOturumu, suzgec: Suzgec, sifirla: Bool = true) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") {
            satirlar = OrnekEkip.basvurular; bitti = true; self.suzgec = suzgec; return
        }
        #endif
        guard ekip.yapabilir("app.view"), !yukleniyor else { return }
        if sifirla { sonDeger = nil; bitti = false; bulunanlar = nil }
        self.suzgec = suzgec
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let f = try await ekip.istemci()
            var kosullar: [FirestoreIstemci.Kosul] = []
            var sira: (String, FirestoreIstemci.Yon) = ("createdAt", .azalan)
            switch suzgec {
            case .hepsi: break
            case .statu(let id): kosullar = [.esit("statusId", .metin(id))]
            case .aranacak:
                let ids = ekip.statuler.filter(\.tekrarAranir).prefix(30).map { FSDeger.metin($0.id) }
                if ids.isEmpty { satirlar = []; bitti = true; return }
                kosullar = [.icinde("statusId", Array(ids))]
            case .silinecek:
                let sinir = Date().addingTimeInterval(Double(ekip.uyariGun) * 86_400)
                kosullar = [FirestoreIstemci.Kosul("deleteAfter", "LESS_THAN_OR_EQUAL", .zaman(sinir))]
                sira = ("deleteAfter", .artan)
            }
            let b = try await f.sorgu(koleksiyon: "applications", kosullar: kosullar, sirala: sira,
                                      sinir: Self.sayfa, sonra: sifirla ? nil : sonDeger)
            let yeni = b.map { Basvuru(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            satirlar = sifirla ? yeni : satirlar + yeni
            if sifirla { sonYukleme = Date() }
            if let son = b.last { sonDeger = son.alanlar[sira.0] }
            bitti = b.count < Self.sayfa
            hata = nil
        } catch FirestoreHatasi.izinYok {
            hata = "Başvuruları görme yetkiniz yok."
        } catch KimlikIstemci.Hata.oturumBitti {
            hata = KimlikIstemci.Hata.oturumBitti.mesaj
        } catch {
            hata = "Başvurular yüklenemedi. İnternet bağlantınızı kontrol edin."
        }
    }

    /// Ekranda gösterilecekler: ülke ve yazılan terimle süzülmüş; aranacaklarda en acil üstte.
    func gorunen(terim: String, ulke: String, statuler: [String: Statu]) -> [Basvuru] {
        var l = bulunanlar ?? satirlar
        if !ulke.isEmpty { l = l.filter { $0.ulke == ulke } }
        if suzgec == .aranacak {
            l = l.compactMap { a -> (Basvuru, Date)? in
                guard let s = statuler[a.statuId], let d = a.aramaDurumu(s), d.durum != .bekle else { return nil }
                return (a, d.enGec)
            }.sorted { $0.1 < $1.1 }.map(\.0)
        }
        return BasvuruListesi.suz(l, terim)
    }

    /// Klavyede "Ara": tam takip kodu ya da pasaport numarasıyla bulur.
    /// Tek sonuç varsa onu döner (ayrıntı açılsın).
    func tamAra(_ metin: String, ekip: EkipOturumu) async -> Basvuru? {
        let ham = metin.trimmingCharacters(in: .whitespaces)
        do {
            let f = try await ekip.istemci()
            var bulunan: [Basvuru] = []
            if let kod = BasvuruListesi.takipKodu(ham) {
                bulunan = try await f.sorgu(koleksiyon: "applications", kosullar: [.esit("trackingCode", .metin(kod))], sinir: 5)
                    .map { Basvuru(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            } else if BasvuruListesi.pasaportGibi(ham), ekip.yapabilir("app.sensitive") {
                let l = try await f.belge("lookup/\(BasvuruListesi.pasaportOzeti(ham))")
                let ids = (l?["apps"]?.diziDegeri ?? []).compactMap { $0.metinDegeri }.prefix(20)
                for id in ids {
                    if let a = try? await f.belge("applications/\(id)") { bulunan.append(Basvuru(kimlik: id, alanlar: a)) }
                }
            } else {
                return nil
            }
            if bulunan.count == 1 { return bulunan[0] }
            bulunanlar = bulunan
            hata = bulunan.isEmpty ? "Kayıt bulunamadı." : nil
        } catch {
            hata = "Arama yapılamadı. İnternet bağlantınızı kontrol edin."
        }
        return nil
    }

    func bulunanlariTemizle() { bulunanlar = nil; hata = nil }

    /// Ayrıntıda değişen başvuruyu listede de değiştirir (yeniden okumadan).
    func guncelle(_ b: Basvuru) {
        if let i = satirlar.firstIndex(where: { $0.kimlik == b.kimlik }), satirlar[i] != b { satirlar[i] = b }
        if let i = bulunanlar?.firstIndex(where: { $0.kimlik == b.kimlik }), bulunanlar?[i] != b { bulunanlar?[i] = b }
    }
}

/// Bir başvurunun ayrıntısı ve üzerindeki işlemler (panel: #/basvuru/<id>).
@MainActor
@Observable
final class BasvuruDetayVerisi {
    let kimlik: String
    private(set) var basvuru: Basvuru?
    private(set) var gecmis: [GecmisSatiri] = []
    private(set) var notlar: [BasvuruNotu] = []
    private(set) var ustNotlar: [UstNot] = []
    private(set) var grup: [Basvuru] = []
    private(set) var takipId: String?
    /// Hassas bilgiler (private/data → form); yetki yoksa nil.
    private(set) var form: [String: FSDeger]?
    private(set) var yukleniyor = false
    private(set) var bulunamadi = false
    private(set) var hata: String?

    init(kimlik: String) { self.kimlik = kimlik }

    var iletisim: MusteriIletisimi? { form.map { MusteriIletisimi(form: $0) } }
    var acikNotlar: [BasvuruNotu] { notlar.filter(\.musteriyeGorunur) }

    func yukle(_ ekip: EkipOturumu) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { ornek(); return }
        #endif
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let f = try await ekip.istemci()
            let yol = "applications/\(kimlik)"
            guard let a = try await f.belge(yol) else { bulunamadi = true; return }
            let b = Basvuru(kimlik: kimlik, alanlar: a)
            let anahtarGorur = ekip.yapabilir("app.sensitive") || ekip.yapabilir("app.status") || ekip.yapabilir("app.edit")
            async let log = f.sorgu(koleksiyon: "log", sirala: ("at", .azalan), sinir: BasvuruDetayVerisi.gecmisSiniri, ust: yol)
            async let not = f.sorgu(koleksiyon: "notes", sirala: ("at", .azalan), sinir: BasvuruDetayVerisi.notSiniri, ust: yol)
            async let ust: [FirestoreIstemci.Belge] = f.sorgu(koleksiyon: "ustNotlar", sirala: ("at", .azalan), sinir: 50, ust: yol)
            async let anahtar: [String: FSDeger]? = anahtarGorur ? f.belge("\(yol)/private/keys") : nil
            async let veri: [String: FSDeger]? = ekip.yapabilir("app.sensitive") ? f.belge("\(yol)/private/data") : nil
            async let uyeler: [FirestoreIstemci.Belge] = b.grupId.isEmpty ? []
                : f.sorgu(koleksiyon: "applications", kosullar: [.esit("grupId", .metin(b.grupId))], sinir: 50)
            gecmis = try await log.map { GecmisSatiri(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            notlar = try await not.map { BasvuruNotu(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            let ustBelgeler: [FirestoreIstemci.Belge] = (try? await ust) ?? []
            ustNotlar = ustBelgeler.map { UstNot(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            let anahtarBelgesi: [String: FSDeger]? = (try? await anahtar) ?? nil
            takipId = anahtarBelgesi?["takipId"]?.metinDegeri
            // Yetki yoksa ya da form kaydı yoksa nil (panel: form null).
            let veriBelgesi: [String: FSDeger]? = (try? await veri) ?? nil
            form = veriBelgesi.map { $0["form"]?.haritaDegeri ?? [:] }
            let grupBelgeleri: [FirestoreIstemci.Belge] = (try? await uyeler) ?? []
            grup = grupBelgeleri.map { Basvuru(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            basvuru = b
            hata = nil
        } catch FirestoreHatasi.izinYok {
            hata = "Bu başvuruyu görme yetkiniz yok."
        } catch KimlikIstemci.Hata.oturumBitti {
            hata = KimlikIstemci.Hata.oturumBitti.mesaj
        } catch {
            hata = "Başvuru yüklenemedi. İnternet bağlantınızı kontrol edin."
        }
    }

    /// Ekranda gösterilen kadar okunur (her belge okuma kotasından düşer).
    static let gecmisSiniri = 60
    static let notSiniri = 100

    enum Parca { case basvuru, gecmis, notlar, ustNotlar }

    /// İşlemden sonra yalnız değişen parçalar yeniden okunur.
    private func yenile(_ parcalar: Set<Parca>, _ f: FirestoreIstemci) async {
        let yol = "applications/\(kimlik)"
        if parcalar.contains(.basvuru), let a = try? await f.belge(yol) { basvuru = Basvuru(kimlik: kimlik, alanlar: a) }
        if parcalar.contains(.gecmis),
           let l = try? await f.sorgu(koleksiyon: "log", sirala: ("at", .azalan), sinir: Self.gecmisSiniri, ust: yol) {
            gecmis = l.map { GecmisSatiri(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        }
        if parcalar.contains(.notlar),
           let l = try? await f.sorgu(koleksiyon: "notes", sirala: ("at", .azalan), sinir: Self.notSiniri, ust: yol) {
            notlar = l.map { BasvuruNotu(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        }
        if parcalar.contains(.ustNotlar),
           let l = try? await f.sorgu(koleksiyon: "ustNotlar", sirala: ("at", .azalan), sinir: 50, ust: yol) {
            ustNotlar = l.map { UstNot(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        }
    }

    /// Yazımları gönderir, sonra değişen parçaları yeniden okur. Hata metni döner (nil: tamam).
    private func isle(_ y: [FirestoreIstemci.Yazim], _ ekip: EkipOturumu, yenile parcalar: Set<Parca>) async -> String? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return nil }
        #endif
        do {
            let f = try await ekip.istemci()
            try await f.isle(y)
            await yenile(parcalar, f)
            return nil
        } catch FirestoreHatasi.izinYok {
            return "Bu işlem için yetkiniz yok ya da başvurunun şartları tamamlanmamış."
        } catch KimlikIstemci.Hata.oturumBitti {
            return KimlikIstemci.Hata.oturumBitti.mesaj
        } catch {
            return "Kaydedilemedi. İnternet bağlantınızı kontrol edip yeniden deneyin."
        }
    }

    /// Statü değiştir ve/veya müşteriye not. Sonuç metni ya da hata.
    func statuKaydet(_ hedef: Statu, not: String, sms: Bool, evrakTamam: Bool, ekip: EkipOturumu) async -> (tamam: Bool, mesaj: String) {
        guard let b = basvuru, let c = ekip.calisan else { return (false, "Oturum bulunamadı.") }
        let not = not.trimmingCharacters(in: .whitespacesAndNewlines)
        if hedef.id == b.statuId && not.isEmpty { return (false, "Statü değişmedi.") }
        if hedef.id != b.statuId {
            // Geçiş şartları (Ayarlar → Statüler): randevu kağıdı ve fiş dosyalardan bakılır.
            var randevuVar: Bool?, fisVar: Bool?
            if ekip.yapabilir("app.sensitive"), let f = try? await ekip.istemci() {
                if hedef.gerekenler.contains("randevu") { randevuVar = await dosyaVar(f, tur: "randevu") }
                if hedef.gerekenler.contains("fis") { fisVar = await dosyaVar(f, tur: "takip") }
            }
            let engel = Basvuru.gecisMesaji(hedef, b.gecisEngelleri(hedef, evrakTamam: evrakTamam, randevuVar: randevuVar, fisVar: fisVar))
            if !engel.isEmpty { return (false, engel) }
        }
        guard let t = takipId else {
            return (false, "Takip anahtarı bulunamadı; müşteri sorgusu çalışmayabilir. Başvuruyu panelden düzenleyip kaydedin.")
        }
        let r = BasvuruIslemi.statu(b, hedef: hedef, statuler: ekip.statuler, musteriNotu: not, acikNotlar: acikNotlar,
                                    takipId: t, calisan: c, saklamaGun: ekip.saklamaGun, eposta: ekip.epostaAyari,
                                    sms: ekip.smsAyari, smsGonder: sms, iletisim: iletisim)
        if let h = await isle(r.yazimlar, ekip, yenile: not.isEmpty ? [.basvuru, .gecmis, .notlar] : [.basvuru, .gecmis]) { return (false, h) }
        let kanal = [r.sms ? "SMS" : "", r.eposta ? "e-posta" : ""].filter { !$0.isEmpty }.joined(separator: " ve ")
        return (true, kanal.isEmpty ? "Statü güncellendi."
                : "Statü güncellendi. Müşteriye \(kanal) 30 dk sonra gider; bu sürede statü değişirse gitmez.")
    }

    private func dosyaVar(_ f: FirestoreIstemci, tur: String) async -> Bool? {
        guard let l = try? await f.sorgu(koleksiyon: "dosyalar", kosullar: [.esit("tur", .metin(tur))], sinir: 1,
                                         ust: "applications/\(kimlik)") else { return nil }
        return !l.isEmpty
    }

    func notEkle(_ metin: String, musteriye: Bool, sms: Bool, ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        if musteriye && takipId == nil { return "Takip anahtarı bulunamadı; müşteriye görünür not eklenemiyor." }
        let gorunur = musteriye && ekip.yapabilir("app.status")
        return await isle(BasvuruIslemi.not(b, metin: metin, musteriyeGorunur: gorunur, statu: ekip.statuSozlugu[b.statuId],
                                            statuler: ekip.statuler, acikNotlar: acikNotlar, takipId: takipId, calisan: c,
                                            sms: ekip.smsAyari, smsGonder: sms && gorunur, iletisim: iletisim), ekip, yenile: [.notlar])
    }

    func evrak(_ e: Evrak, geldi: Bool, ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        // Ekranda hemen işaretlensin; hata olursa yeniden okununca geri döner.
        basvuru?.evraklar[e.id] = geldi
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return nil }
        #endif
        do {
            try await ekip.istemci().isle(BasvuruIslemi.evrak(b, e, geldi: geldi, calisan: c))
            return nil
        } catch {
            basvuru?.evraklar[e.id] = !geldi
            return (error as? FirestoreHatasi) == .izinYok ? "Evrak listesini değiştirme yetkiniz yok." : "Kaydedilemedi. İnternet bağlantınızı kontrol edin."
        }
    }

    func arandi(not: String, ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        return await isle(BasvuruIslemi.arandi(b, not: not, calisan: c), ekip, yenile: [.basvuru, .gecmis])
    }

    func ustNotEkle(_ metin: String, ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        return await isle(BasvuruIslemi.ustNotEkle(b, metin: metin, calisan: c), ekip, yenile: [.ustNotlar, .gecmis])
    }

    func ustNotSil(_ n: UstNot, ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        return await isle(BasvuruIslemi.ustNotSil(b, n, calisan: c), ekip, yenile: [.ustNotlar])
    }

    func kontrolEdildi(ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        return await isle(BasvuruIslemi.kontrolEdildi(b, calisan: c), ekip, yenile: [.basvuru])
    }

    #if DEBUG
    private func ornek() {
        guard basvuru == nil else { return }
        basvuru = OrnekEkip.basvurular.first { $0.kimlik == kimlik } ?? OrnekEkip.basvurular[0]
        takipId = String(repeating: "a", count: 64)
        form = ["phone": .metin("+905000000011"), "email": .metin("zeynep@example.com")]
        let simdi = Date()
        notlar = [BasvuruNotu(id: "n1", metin: "Evrak listesini WhatsApp'tan ilettik.", musteriyeGorunur: true, yazan: "Sefa Karakaş",
                              zaman: simdi.addingTimeInterval(-86_400)),
                  BasvuruNotu(id: "n2", metin: "Banka dökümünü cuma getirecek.", musteriyeGorunur: false, yazan: "Ezgi",
                              zaman: simdi.addingTimeInterval(-3 * 3600))]
        ustNotlar = [UstNot(kimlik: "u1", alanlar: ["metin": .metin("Yalnız öğleden sonra aranmalı."), "by": .metin("x"),
                                                    "byName": .metin("Ezgi"), "at": .zaman(simdi.addingTimeInterval(-7200))])]
        gecmis = [
            GecmisSatiri(kimlik: "g1", alanlar: ["type": .metin("checklist"), "text": .metin("Pasaport: geldi"), "byName": .metin("Ezgi"),
                                                 "at": .zaman(simdi.addingTimeInterval(-3600))]),
            GecmisSatiri(kimlik: "g2", alanlar: ["type": .metin("status"), "text": .metin("Randevu Takipte → Evrak Bekleniyor"),
                                                 "byName": .metin("Sefa Karakaş"), "at": .zaman(simdi.addingTimeInterval(-86_400))]),
            GecmisSatiri(kimlik: "g3", alanlar: ["type": .metin("created"), "text": .metin("Başvuru açıldı"),
                                                 "byName": .metin("Sefa Karakaş"), "at": .zaman(simdi.addingTimeInterval(-9 * 86_400))]),
        ]
    }
    #endif
}

#if DEBUG
/// Ekran testleri için örnek ekip verisi (ağa bağlanmaz; ad ve numaralar uydurma).
enum OrnekEkip {
    static let statuler: [Statu] = {
        let l: [(String, String, String, String, [String: FSDeger])] = [
            ("potansiyel", "Potansiyel Müşteri", "Görüşme aşamasında", "#7a6a9c", ["silmeGun": .tam(60), "aramaMin": .tam(7), "aramaMax": .tam(14)]),
            ("randevu-takip", "Randevu Takipte", "Randevunuz takip ediliyor", "#2f6f8c", ["gerekenler": .dizi([.metin("odeme")])]),
            ("randevu", "Randevu Alındı", "Randevunuz alındı", "#5a4f9c", [:]),
            ("evrak-bekleniyor", "Evrak Bekleniyor", "Evraklarınız bekleniyor", "#8a7b5c", [:]),
            ("evrak-tamam", "Evraklar Tamamlandı", "Evraklarınız tamam", "#3a6d8c", [:]),
            ("biyometri", "Biyometri Verildi", "Parmak izi verildi", "#5a4f9c", [:]),
            ("konsoloslukta", "Konsoloslukta İşlemde", "Konsoloslukta değerlendiriliyor", "#1e2c4d", ["gerekenler": .dizi([.metin("fis")])]),
            ("sonuc-onay", "Sonuçlandı — Onay", "Sonuçlandı", "#3a7d5c", [:]),
            ("teslim", "Pasaport Teslim Edildi", "Pasaportunuz teslim edildi", "#3a7d5c", ["isFinal": .mantik(true)]),
        ]
        return l.enumerated().map { i, s in
            var a: [String: FSDeger] = ["name": .metin(s.1), "publicName": .metin(s.2), "color": .metin(s.3), "order": .tam((i + 1) * 10)]
            a.merge(s.4) { $1 }
            return Statu(kimlik: s.0, alanlar: a)
        }
    }()

    static let basvurular: [Basvuru] = {
        let gun = 86_400.0, simdi = Date()
        func b(_ id: String, _ ad: String, _ soyad: String, _ ulke: String, _ statu: String, _ ek: [String: FSDeger] = [:]) -> Basvuru {
            let s = statuler.first { $0.id == statu }
            var a: [String: FSDeger] = [
                "firstName": .metin(ad), "lastName": .metin(soyad), "countryName": .metin(ulke), "country": .metin(ulke.lowercased()),
                "trackingCode": .metin("2026-11\(id.suffix(4))"), "statusId": .metin(statu), "statusName": .metin(s?.ad ?? ""),
                "passportLast3": .metin("4\(id.suffix(2))"), "createdAt": .zaman(simdi.addingTimeInterval(-9 * gun)),
                "statusAt": .zaman(simdi.addingTimeInterval(-gun)), "checklist": .harita(["pasaport": .mantik(true), "fotograf": .mantik(true)]),
            ]
            a.merge(ek) { $1 }
            return Basvuru(kimlik: id, alanlar: a)
        }
        return [
            b("b0001", "ZEYNEP", "ARSLAN", "Almanya", "evrak-bekleniyor", ["odemeSayisi": .tam(1), "reviewNote": .metin("Telefonda açıldı: doğum tarihi ve adres eksik.")]),
            b("b0002", "MURAT", "KOÇ", "İtalya", "potansiyel", ["statusAt": .zaman(simdi.addingTimeInterval(-16 * gun)),
                                                               "deleteAfter": .zaman(simdi.addingTimeInterval(4 * gun))]),
            b("b0003", "SELİN", "AKTAŞ", "Fransa", "randevu", ["grupId": .metin("g_ornek"), "grupAdi": .metin("Aktaş ailesi"),
                                                               "appointmentAt": .zaman(simdi.addingTimeInterval(6 * gun)), "randevuSaati": .metin("10:30"),
                                                               "randevuMerkezi": .metin("VFS Global"), "randevuSehri": .metin("Ankara"), "odemeSayisi": .tam(1)]),
            b("b0004", "DENİZ", "AKTAŞ", "Fransa", "randevu", ["grupId": .metin("g_ornek"), "grupAdi": .metin("Aktaş ailesi"), "odemeSayisi": .tam(1)]),
            b("b0005", "EMRE", "ŞAHİN", "Birleşik Krallık", "konsoloslukta", ["odemeSayisi": .tam(1), "konsTakipKodu": .metin("GBANK123")]),
            b("b0006", "HAKAN", "ÇELİK", "Hollanda", "teslim", ["deleteAfter": .zaman(simdi.addingTimeInterval(40 * gun))]),
        ]
    }()
}
#endif
