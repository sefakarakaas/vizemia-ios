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
            hata = HataAciklamasi.metin(error, "Başvurular yüklenemedi. İnternet bağlantınızı kontrol edin.")
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
            hata = HataAciklamasi.metin(error, "Arama yapılamadı. İnternet bağlantınızı kontrol edin.")
        }
        return nil
    }

    func bulunanlariTemizle() { bulunanlar = nil; hata = nil }

    /// Yeni başvuru açıldı: liste bir sonraki açılışta yeniden okunsun.
    func eskit() { sonYukleme = nil }

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
    /// Pasaport kontrolünün sonucu (private/passport); yapılmadıysa ya da yetki yoksa nil.
    private(set) var pasaport: PasaportKontrolu?
    private(set) var yukleniyor = false
    private(set) var bulunamadi = false
    private(set) var hata: String?
    /// Ödeme izni varsa (app.payment): alınan ödemeler ve verilen fiyat.
    private(set) var odemeler: [Odeme] = []
    private(set) var fiyat: Fiyat?
    /// Görebildiği belgeler (randevu kağıdı, fiş, diğer: app.sensitive; dekont: app.payment).
    private(set) var dosyalar: [DosyaBilgisi] = []
    /// Müşteri için yapılan harcamalar (kasa; görmek için kasa.view ya da app.payment).
    private(set) var giderler: [KasaHareketi] = []
    /// Bu müşteriye giden mailler (eposta.send ya da app.sensitive).
    private(set) var epostalar: [EpostaKaydi] = []
    /// SMS ve WhatsApp geçmişi (sms/ ve mesajKaydi/).
    private(set) var mesajlar: [MesajSatiri] = []
    /// Müşteri formu (formlar/{takipId}); kart açılınca bir kez okunur.
    private(set) var musteriFormu: MusteriFormuKaydi?
    private(set) var musteriFormuOkundu = false

    init(kimlik: String) { self.kimlik = kimlik }

    var yol: String { "applications/\(kimlik)" }

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
            async let pk: [String: FSDeger]? = ekip.yapabilir("app.sensitive") ? f.belge("\(yol)/private/passport") : nil
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
            let pkBelgesi: [String: FSDeger]? = (try? await pk) ?? nil
            pasaport = pkBelgesi.map { PasaportKontrolu(alanlar: $0) }
            let grupBelgeleri: [FirestoreIstemci.Belge] = (try? await uyeler) ?? []
            grup = grupBelgeleri.map { Basvuru(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            await ekleriYukle(ekip, f)
            basvuru = b
            hata = nil
        } catch FirestoreHatasi.izinYok {
            hata = "Bu başvuruyu görme yetkiniz yok."
        } catch KimlikIstemci.Hata.oturumBitti {
            hata = KimlikIstemci.Hata.oturumBitti.mesaj
        } catch {
            hata = HataAciklamasi.metin(error, "Başvuru yüklenemedi. İnternet bağlantınızı kontrol edin.")
        }
    }

    /// Ekranda gösterilen kadar okunur (her belge okuma kotasından düşer).
    static let gecmisSiniri = 60
    static let notSiniri = 100

    enum Parca { case basvuru, gecmis, notlar, ustNotlar, odemeler, fiyat, dosyalar, pasaport, giderler, epostalar, mesajlar, grup }

    /// Ödemeler, fiyat ve belge bilgileri (baytlar açılınca indirilir).
    private func ekleriYukle(_ ekip: EkipOturumu, _ f: FirestoreIstemci, _ parcalar: Set<Parca> = [.odemeler, .fiyat, .dosyalar, .giderler, .epostalar, .mesajlar]) async {
        let odeme = ekip.yapabilir("app.payment"), hassas = ekip.yapabilir("app.sensitive")
        if parcalar.contains(.epostalar) && (ekip.yapabilir("eposta.send") || hassas),
           let l = try? await f.sorgu(koleksiyon: "eposta", kosullar: [.esit("appId", .metin(kimlik))], sinir: 50) {
            epostalar = l.map { EpostaKaydi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
                .sorted { ($0.olusma ?? .distantPast) > ($1.olusma ?? .distantPast) }
        }
        if parcalar.contains(.mesajlar) {
            // Ekranda en çok 15 satır gösteriliyor; her kaynaktan 20 yeter.
            var l: [MesajSatiri] = []
            if let s = try? await f.sorgu(koleksiyon: "sms", kosullar: [.esit("appId", .metin(kimlik))], sinir: 20) {
                l += s.map { MesajSatiri(sms: $0.kimlik, alanlar: $0.alanlar) }
            }
            if ekip.yapabilir("eposta.send") || hassas || ekip.yapabilir("lead.manage") || ekip.yapabilir("armut.view"),
               let w = try? await f.sorgu(koleksiyon: "mesajKaydi", kosullar: [.esit("appId", .metin(kimlik))], sinir: 20) {
                l += w.map { MesajSatiri(whatsapp: $0.kimlik, alanlar: $0.alanlar) }
            }
            mesajlar = MesajSatiri.birlestir(l)
        }
        if parcalar.contains(.giderler) && (ekip.yapabilir("kasa.view") || odeme),
           let l = try? await f.sorgu(koleksiyon: "kasa", kosullar: [.esit("appId", .metin(kimlik)), .esit("kapsam", .metin("musteri"))], sinir: 200) {
            giderler = l.map { KasaHareketi(kimlik: $0.kimlik, alanlar: $0.alanlar) }.filter { $0.tur == "gider" }.sorted { $0.tarih > $1.tarih }
        }
        if odeme && parcalar.contains(.odemeler),
           let l = try? await f.sorgu(koleksiyon: "odemeler", sirala: ("at", .azalan), sinir: 50, ust: yol) {
            odemeler = l.map { Odeme(kimlik: $0.kimlik, alanlar: $0.alanlar) }
        }
        if odeme && parcalar.contains(.fiyat) { fiyat = Fiyat(alanlar: (try? await f.belge("\(yol)/private/fiyat")) ?? nil) }
        if parcalar.contains(.dosyalar) {
            var l: [DosyaBilgisi] = []
            if hassas, let b = try? await f.sorgu(koleksiyon: "dosyalar", kosullar: [
                .icinde("tur", [.metin("randevu"), .metin("takip"), .metin("diger")])], sinir: 50, ust: yol) {
                l += b.map { DosyaBilgisi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            }
            if odeme, let b = try? await f.sorgu(koleksiyon: "dosyalar", kosullar: [.esit("tur", .metin("odeme"))], sinir: 50, ust: yol) {
                l += b.map { DosyaBilgisi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            }
            dosyalar = l.sorted { ($0.zaman ?? .distantPast) > ($1.zaman ?? .distantPast) }
        }
    }

    /// İşlemden sonra yalnız değişen parçalar yeniden okunur.
    private func yenile(_ parcalar: Set<Parca>, _ f: FirestoreIstemci, _ ekip: EkipOturumu) async {
        let ekler = parcalar.intersection([.odemeler, .fiyat, .dosyalar, .giderler, .epostalar, .mesajlar])
        if !ekler.isEmpty { await ekleriYukle(ekip, f, ekler) }
        if parcalar.contains(.basvuru) || parcalar.contains(.grup), let a = try? await f.belge(yol) { basvuru = Basvuru(kimlik: kimlik, alanlar: a) }
        if parcalar.contains(.grup), let b = basvuru {
            if b.grupId.isEmpty { grup = [] } else if let l = try? await f.sorgu(koleksiyon: "applications", kosullar: [.esit("grupId", .metin(b.grupId))], sinir: 50) {
                grup = l.map { Basvuru(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            }
        }
        if parcalar.contains(.pasaport), let a = try? await f.belge("\(yol)/private/passport") {
            pasaport = PasaportKontrolu(alanlar: a)
        }
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
            await yenile(parcalar, f, ekip)
            return nil
        } catch FirestoreHatasi.izinYok {
            return "Bu işlem için yetkiniz yok ya da başvurunun şartları tamamlanmamış."
        } catch KimlikIstemci.Hata.oturumBitti {
            return KimlikIstemci.Hata.oturumBitti.mesaj
        } catch {
            return HataAciklamasi.metin(error, "Kaydedilemedi. İnternet bağlantınızı kontrol edip yeniden deneyin.")
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

    /// Müşteri harcaması: kasa defterine (fişiyle) ve başvurunun geçmişine tek yazımda.
    func giderEkle(_ g: KasaGirdisi, fis: HazirDosya?, ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        let k = KasaIslemi.kaydet(g, fis: fis, basvuru: b, calisan: c)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return nil }
        #endif
        let h = await isle(k.yazimlar, ekip, yenile: [.giderler, .gecmis])
        if h == nil { ekip.kasaBildir(k.id) }
        return h
    }

    /// Tek müşteriye mail: kuyruğa yazılır, servis varsa hemen gider. Sonuç metni ya da hata.
    func epostaGonder(konu: String, metin: String, ekip: EkipOturumu) async -> (tamam: Bool, mesaj: String) {
        guard let b = basvuru, let c = ekip.calisan else { return (false, "Oturum bulunamadı.") }
        guard let adres = iletisim?.eposta, MusteriBildirimi.epostaGecerli(adres),
              let y = EpostaIslemi.tekli(b, eposta: adres, konu: konu, metin: metin, calisan: c) else {
            return (false, "Konu ve metin boş olamaz; formda geçerli bir e-posta olmalı.")
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return (true, "Mail gönderildi.") }
        #endif
        if let h = await isle(y, ekip, yenile: [.epostalar]) { return (false, h) }
        let gitti = await ekip.epostaHemen()
        if let f = try? await ekip.istemci() { await yenile([.epostalar], f, ekip) }
        return (true, gitti ? "Mail gönderildi." : "Mail sıraya alındı; 15 dakika içinde gider.")
    }

    /// Elle SMS: kuyruğa yazılır (30 dk bekletmeye girmez), SMS görevi gönderir.
    func smsGonder(_ metin: String, ekip: EkipOturumu) async -> (tamam: Bool, mesaj: String) {
        guard let b = basvuru, let c = ekip.calisan else { return (false, "Oturum bulunamadı.") }
        guard let y = MusteriMesaji.sms(b, telefon: iletisim?.telefon ?? "", metin: metin, ayar: ekip.smsAyari, calisan: c) else {
            return (false, "SMS sıraya alınamadı: metin boş ya da telefon hatalı.")
        }
        if let h = await isle(y, ekip, yenile: [.mesajlar]) { return (false, h) }
        return (true, "SMS sıraya alındı; SMS görevi çalışınca gider.")
    }

    /// WhatsApp teyidinden sonra geçmiş yeniden okunur.
    func mesajlariYenile(_ ekip: EkipOturumu) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return }
        #endif
        if let f = try? await ekip.istemci() { await yenile([.mesajlar], f, ekip) }
    }

    func epostaIptal(_ m: EpostaKaydi, ekip: EkipOturumu) async -> String? {
        guard let c = ekip.calisan else { return "Oturum bulunamadı." }
        return await isle(EpostaIslemi.iptal(m, calisan: c), ekip, yenile: [.epostalar])
    }

    // MARK: - Grup

    enum GrupSonucu { case tamam(String), sor(String), hata(String) }

    /// Takip koduyla bulunan başvuruyu bu başvuruyla gruplar (panel: "Mevcut başvuruyla grupla").
    func grupBagla(kod: String, tasimaOnayli: Bool, ekip: EkipOturumu) async -> GrupSonucu {
        guard let b = basvuru, let c = ekip.calisan else { return .hata("Oturum bulunamadı.") }
        guard let k = BasvuruListesi.takipKodu(kod) else { return .hata("Geçerli bir takip kodu yazın.") }
        do {
            let f = try await ekip.istemci()
            guard let h = try await f.sorgu(koleksiyon: "applications", kosullar: [.esit("trackingCode", .metin(k))], sinir: 1).first else {
                return .hata("Bu takip koduyla başvuru bulunamadı.")
            }
            switch GrupIsi.bagla(b, hedef: Basvuru(kimlik: h.kimlik, alanlar: h.alanlar), tasimaOnayli: tasimaOnayli, calisan: c) {
            case .hata(let m): return .hata(m)
            case .tasinsinMi(let ad): return .sor(ad)
            case .tamam(let y, let ad):
                if let hata = await isle(y, ekip, yenile: [.grup]) { return .hata(hata) }
                return .tamam("\"\(ad)\" grubu güncellendi.")
            }
        } catch {
            return .hata(HataAciklamasi.metin(error, "Başvuru aranamadı. İnternet bağlantınızı kontrol edin."))
        }
    }

    func grupAdiDegistir(_ ad: String, ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        guard let y = GrupIsi.adDegistir(b, uyeler: grup, ad: ad, calisan: c) else { return "Grup adı boş olamaz ya da değişmedi." }
        return await isle(y, ekip, yenile: [.grup])
    }

    func gruptanCikar(ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        return await isle(GrupIsi.cikar(b, digerleri: grup.filter { $0.kimlik != b.kimlik }, calisan: c), ekip, yenile: [.grup])
    }

    // MARK: - Müşteri formu

    func musteriFormuYukle(_ ekip: EkipOturumu) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { musteriFormuOkundu = true; return }
        #endif
        guard let t = takipId, let f = try? await ekip.istemci() else { return }
        let a: [String: FSDeger]? = (try? await f.belge("formlar/\(t)")) ?? nil
        musteriFormu = a.map { MusteriFormuKaydi(alanlar: $0) }
        musteriFormuOkundu = true
    }

    /// Formu kurar / yeniler; istenirse SMS'le gönderir.
    func musteriFormuHazirla(sms: Bool, sema: FormSemasi, ekip: EkipOturumu) async -> (tamam: Bool, mesaj: String) {
        guard let b = basvuru, let c = ekip.calisan else { return (false, "Oturum bulunamadı.") }
        guard let t = takipId, let fm = form else { return (false, "Takip anahtarı yok; önce pasaport numarasını kaydedin.") }
        let alanlar = sema.panelAlanlari(b.ulke, kayitli: ekip.ulkeFormlari)
        let sorular = MusteriFormu.sorular(alanlar, iller: sema.iller.map(\.ad))
        // Yenilemeden hemen önce son hâli okunur: müşteri bu arada doldurmaya başlamış olabilir.
        if let f = try? await ekip.istemci() {
            let a: [String: FSDeger]? = (try? await f.belge("formlar/\(t)")) ?? nil
            musteriFormu = a.map { MusteriFormuKaydi(alanlar: $0) }
        }
        let h = MusteriFormu.hazirla(b, form: fm, takipId: t, onceki: musteriFormu, sorular: sorular, sms: sms,
                                     smsAyari: ekip.smsAyari, calisan: c)
        if let hata = await isle(h.yazimlar, ekip, yenile: [.gecmis, .mesajlar]) { return (false, hata) }
        await musteriFormuYukle(ekip)
        if h.smsAlinamadi { return (true, "Form hazırlandı; SMS sıraya alınamadı (telefon ya da SMS ayarı eksik).") }
        return (true, sms ? "Form hazırlandı, SMS sıraya alındı." : "Form hazırlandı. Bağlantıyı kendiniz iletebilirsiniz.")
    }

    func musteriFormuKapat(ekip: EkipOturumu) async -> String? {
        guard let c = ekip.calisan, let t = takipId else { return "Oturum bulunamadı." }
        let h = await isle(MusteriFormu.kapat(takipId: t, calisan: c), ekip, yenile: [])
        if h == nil { await musteriFormuYukle(ekip) }
        return h
    }

    func musteriSorusunuCevapla(_ sira: Int, metin: String, ekip: EkipOturumu) async -> String? {
        guard let c = ekip.calisan, let t = takipId else { return "Oturum bulunamadı." }
        // Müşterinin yeni sorusu ezilmesin: liste yazmadan hemen önce okunur.
        await musteriFormuYukle(ekip)
        guard let k = musteriFormu, let y = MusteriFormu.cevapla(takipId: t, kayit: k, sira: sira, metin: metin, calisan: c) else {
            return "Cevap boş olamaz."
        }
        let h = await isle(y, ekip, yenile: [])
        if h == nil { await musteriFormuYukle(ekip) }
        return h
    }

    func musteriCevaplariniAktar(_ l: [(key: String, etiket: String, deger: String)], ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return nil }
        #endif
        let h = await isle(MusteriFormu.aktar(b, l, calisan: c), ekip, yenile: [.gecmis])
        if h == nil, let f = try? await ekip.istemci() {
            let v: [String: FSDeger]? = (try? await f.belge("\(yol)/private/data")) ?? nil
            form = v.map { $0["form"]?.haritaDegeri ?? [:] }
        }
        return h
    }

    /// Bu başvurunun form gönderim kuralı + yeniden planlama. Sonuç metni ya da hata.
    func formKuraliKaydet(_ kural: FormGonderimKurali, ekip: EkipOturumu) async -> (tamam: Bool, mesaj: String) {
        guard let b = basvuru, let c = ekip.calisan else { return (false, "Oturum bulunamadı.") }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return (true, kural.ozet) }
        #endif
        do {
            let f = try await ekip.istemci()
            let mevcut = try await f.sorgu(koleksiyon: "bildirimler", kosullar: [.esit("appId", .metin(b.kimlik))], sinir: 50)
                .map { BildirimKaydi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            let r = MusteriFormu.kuralKaydet(b, kural: kural, iletisim: iletisim ?? MusteriIletisimi(form: nil), ayar: ekip.bildirimAyari,
                                             mevcut: mevcut, calisan: c)
            if let h = await isle(r.yazimlar, ekip, yenile: [.basvuru]) { return (false, h) }
            return (true, r.durum)
        } catch {
            return (false, HataAciklamasi.metin(error, "Kaydedilemedi. İnternet bağlantınızı kontrol edip yeniden deneyin."))
        }
    }

    /// Formdaki metin değerleri (pasaport karşılaştırması için).
    var formMetinleri: [String: String] {
        var d: [String: String] = [:]
        for (k, v) in form ?? [:] { if let m = v.metinDegeri { d[k] = m } }
        return d
    }

    /// Pasaport kontrolünü kaydeder (sonuç + geçmiş + işlem kaydı). MRZ ve fotoğraf yazılmaz.
    func pasaportKaydet(_ durum: PasaportKontrolu.Durum, _ d: PasaportDegerlendirmesi, ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        let y = BasvuruIslemi.pasaportKontrolu(b, durum: durum, bakilanlar: d.satirlar.map(\.etiket),
                                               uyusmayanlar: d.uyusmayanlar, calisan: c)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") {
            var a: [String: FSDeger] = ["status": .metin(durum.rawValue), "byName": .metin(c.gorunenAd), "at": .zaman(Date())]
            a["mismatches"] = .dizi(d.uyusmayanlar.map { FSDeger.metin($0) })
            pasaport = PasaportKontrolu(alanlar: a)
            return nil
        }
        #endif
        return await isle(y, ekip, yenile: [.pasaport, .gecmis])
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

    // MARK: Ödeme, fiyat, belgeler

    func odemeKaydet(_ o: BasvuruIslemi.OdemeGirdisi, dekont: HazirDosya?, ekip: EkipOturumu) async -> (tamam: Bool, mesaj: String) {
        guard let b = basvuru, let c = ekip.calisan else { return (false, "Oturum bulunamadı.") }
        let hatalar = OdemeKurali.hatalar(tarih: o.tarih, tutar: o.tutar, paraBirimi: o.paraBirimi, yontem: o.yontem,
                                          onayKodu: o.onayKodu, aciklama: o.aciklama, bugun: Tr.bugun())
        if !hatalar.isEmpty { return (false, hatalar.joined(separator: " ")) }
        let r = BasvuruIslemi.odeme(b, o, dekont: dekont, statuler: ekip.statuler, statuDegistirir: ekip.yapabilir("app.status"),
                                    takipId: takipId, acikNotlar: acikNotlar, saklamaGun: ekip.saklamaGun, calisan: c)
        if let h = await isle(r.yazimlar, ekip, yenile: [.basvuru, .gecmis, .odemeler, .dosyalar]) { return (false, h) }
        ekip.kasaBildir(r.odemeId)
        let dekontNotu = dekont == nil ? " Dekont girilmedi: sonradan yükleyebilirsiniz." : ""
        if let s = r.statu { return (true, "Ödeme kaydedildi; başvuru \"\(s.ad)\" statüsüne geçti.\(dekontNotu)") }
        return (true, "Ödeme kaydedildi.\(dekontNotu)")
    }

    func sonradanDekont(_ o: Odeme, dekont: HazirDosya, ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        return await isle(BasvuruIslemi.sonradanDekont(b, o, dekont: dekont, calisan: c), ekip, yenile: [.gecmis, .odemeler, .dosyalar])
    }

    func fiyatKaydet(tutar: Double?, paraBirimi: String, aciklama: String, ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        guard let t = tutar, t > 0, t <= 10_000_000 else { return "Geçerli bir fiyat girin." }
        return await isle(BasvuruIslemi.fiyat(b, tutar: t, paraBirimi: paraBirimi, aciklama: aciklama, calisan: c), ekip, yenile: [.fiyat, .gecmis])
    }

    /// Takip kodu; fiş önceden yüklendiyse ve statü takip kodu bekliyorsa konsolosluğa geçer.
    func konsoloslukKaydet(_ kod: String, evrakTamam: Bool, ekip: EkipOturumu) async -> (tamam: Bool, mesaj: String) {
        guard let b = basvuru, let c = ekip.calisan else { return (false, "Oturum bulunamadı.") }
        let k = KonsoloslukKodu.temizle(kod)
        if !k.isEmpty && !KonsoloslukKodu.gecerli(k) { return (false, "Kod 3–60 karakter; harf, rakam ve / . _ - olabilir.") }
        if k == b.konsTakipKodu { return (false, "Kod değişmedi.") }
        if let h = await isle(BasvuruIslemi.konsolosluk(b, kod: k, calisan: c), ekip, yenile: [.basvuru, .gecmis]) { return (false, h) }
        if !k.isEmpty && dosyalar.contains(where: { $0.tur == "takip" }) {
            return await fisSonrasi(evrakTamam: evrakTamam, ekip: ekip, onEk: "Takip kodu kaydedildi.")
        }
        return (true, "Takip kodu kaydedildi.")
    }

    /// Belge yükle: pasaport teslim fişi ("takip") ya da diğer belge.
    func belgeYukle(tur: String, dosya: HazirDosya, evrakTamam: Bool, ekip: EkipOturumu) async -> (tamam: Bool, mesaj: String) {
        guard let b = basvuru, let c = ekip.calisan else { return (false, "Oturum bulunamadı.") }
        if let h = await isle(BasvuruIslemi.belge(b, tur: tur, dosya: dosya, calisan: c), ekip, yenile: [.gecmis, .dosyalar]) { return (false, h) }
        if tur == "takip" { return await fisSonrasi(evrakTamam: evrakTamam, ekip: ekip, onEk: "Pasaport teslim fişi yüklendi.") }
        return (true, "Belge yüklendi.")
    }

    private func fisSonrasi(evrakTamam: Bool, ekip: EkipOturumu, onEk: String) async -> (tamam: Bool, mesaj: String) {
        guard ekip.yapabilir("app.status"), let b = basvuru, let c = ekip.calisan, let t = takipId else { return (true, onEk) }
        let r = BasvuruIslemi.fisSonrasi(b, statuler: ekip.statuler, takipId: t, acikNotlar: acikNotlar, evrakTamam: evrakTamam,
                                         saklamaGun: ekip.saklamaGun, calisan: c)
        if !r.engel.isEmpty { return (true, "\(onEk) \(r.engel)") }
        guard let s = r.statu else { return (true, onEk) }
        if let h = await isle(r.yazimlar, ekip, yenile: [.basvuru, .gecmis]) {
            return (true, "\(onEk) Statü değiştirilemedi: \(h)")
        }
        return (true, "\(onEk) Başvuru \"\(s.ad)\" statüsüne geçti.")
    }

    /// Randevu kağıdı: belge + randevu bilgileri; sonra müşteriye seçtiği kanallardan
    /// "randevunuz alındı" ve evrak hatırlatması planlanır (panel: syncBildirim).
    func randevuKaydet(_ r: RandevuGirdisi, dosya: HazirDosya, secenekler: RandevuSecenekleri, ekip: EkipOturumu) async -> (tamam: Bool, mesaj: String) {
        guard let b = basvuru, let c = ekip.calisan else { return (false, "Oturum bulunamadı.") }
        let hatalar = RandevuKurali.hatalar(r, secenekler, bugun: Tr.bugun())
        if !hatalar.isEmpty { return (false, hatalar.joined(separator: " ")) }
        let k = RandevuKurali.kayit(r, secenekler, konumlar: ekip.konumlar)
        if let h = await isle(BasvuruIslemi.randevuBelgesi(b, r, kayit: k, dosya: dosya, calisan: c), ekip,
                              yenile: [.basvuru, .gecmis, .dosyalar]) { return (false, h) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return (true, "Randevu kaydedildi.") }
        #endif
        // Bildirim planı: müşterinin iletişim bilgisi (hassas veri) ve statü yetkisi gerekir.
        guard ekip.yapabilir("app.status"), let i = iletisim, let guncel = basvuru else { return (true, "Randevu kaydedildi.") }
        do {
            let f = try await ekip.istemci()
            let mevcut = try await f.sorgu(koleksiyon: "bildirimler", kosullar: [.esit("appId", .metin(kimlik))], sinir: 50)
                .map { BildirimKaydi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            let p = BildirimPlani.planla(guncel, randevu: r, kayit: k, iletisim: i, ayar: ekip.bildirimAyari, mevcut: mevcut, calisan: c)
            if p.atlanan.contains("açık kanal yok") {
                return (true, "Randevu kaydedildi. Bildirim planlanmadı: müşterinin telefonu / e-postası ya da kanal seçimi yok.")
            }
            if p.yazilan.isEmpty { return (true, "Randevu kaydedildi.") }
            try await f.isle(p.yazimlar)
            return (true, "Randevu kaydedildi; müşteriye \(p.yazilan.count) bildirim planlandı.")
        } catch {
            return (true, "Randevu kaydedildi ama otomatik bildirimler planlanamadı; panelden kontrol edin.")
        }
    }

    func belgeSil(_ d: DosyaBilgisi, ekip: EkipOturumu) async -> String? {
        guard let b = basvuru, let c = ekip.calisan else { return "Oturum bulunamadı." }
        return await isle(BasvuruIslemi.belgeSil(b, d, calisan: c), ekip, yenile: [.gecmis, .dosyalar])
    }

    /// Belgenin parçalarını indirip geçici bir dosyaya yazar (önizleme / paylaşma için).
    func belgeDosyasi(_ d: DosyaBilgisi, ekip: EkipOturumu) async throws -> URL {
        let f = try await ekip.istemci()
        var parcalar: [[String: FSDeger]?] = []
        for p in d.parcaYollari(ust: yol) { parcalar.append(try await f.belge(p)) }
        guard let veri = Dosya.birlestir(parcalar) else { throw FirestoreHatasi.sunucu(404) }
        let klasor = FileManager.default.temporaryDirectory.appendingPathComponent("belgeler", isDirectory: true)
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let url = klasor.appendingPathComponent(Dosya.adTemizle(d.ad))
        try veri.write(to: url, options: [.atomic, .completeFileProtection])
        return url
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
        odemeler = [Odeme(kimlik: "o1", alanlar: [
            "tarih": .metin(Tr.bugun(simdi.addingTimeInterval(-2 * 86_400))), "tutar": .tam(2500), "paraBirimi": .metin("TRY"),
            "yontem": .metin("havale"), "onayKodu": .metin("EFT-48213"), "aciklama": .metin("Kapora"), "dosyaId": .bos,
            "byName": .metin("Sefa Karakaş"), "at": .zaman(simdi.addingTimeInterval(-2 * 86_400))])]
        fiyat = Fiyat(alanlar: ["tutar": .tam(4500), "paraBirimi": .metin("TRY"), "aciklama": .metin("Hizmet bedeli, harç hariç"),
                                "byName": .metin("Sefa Karakaş"), "updatedAt": .zaman(simdi.addingTimeInterval(-3 * 86_400))])
        giderler = [KasaHareketi(kimlik: "g1", alanlar: [
            "tur": .metin("gider"), "kapsam": .metin("musteri"), "kategori": .metin("Fotokopi"), "tutar": .ondalik(25.5),
            "paraBirimi": .metin("TRY"), "yontem": .metin("nakit"), "tarih": .metin(Tr.bugun(simdi)), "byName": .metin("Ezgi"),
            "at": .zaman(simdi.addingTimeInterval(-5400)), "iptal": .mantik(false)])]
        dosyalar = [DosyaBilgisi(kimlik: "d1", alanlar: ["tur": .metin("diger"), "ad": .metin("davet-mektubu.pdf"),
                                                        "mime": .metin("application/pdf"), "boyut": .tam(412_000), "parca": .tam(1),
                                                        "byName": .metin("Ezgi"), "at": .zaman(simdi.addingTimeInterval(-86_400))])]
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
