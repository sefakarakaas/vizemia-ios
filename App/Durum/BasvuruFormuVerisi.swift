import Foundation
import Observation
import VizeMiaCekirdek

/// Yeni başvuru / düzenle formunun verisi (panel: #/basvuru/yeni, #/basvuru/<id>/duzenle).
@MainActor
@Observable
final class BasvuruFormuVerisi {
    let kimlik: String?
    let talepYolu: String?
    /// Müşteri arşivinden yeniden başvuru: arşiv kaydının kimliği.
    let arsivId: String?

    var ulke = ""
    var randevu: Date?
    var acilis = Date()
    var kampanyaIzni = false
    var degerler: [String: String] = [:]
    /// Kutucuğu işaretlenip açılan kapalı alanlar.
    var acikKapalilar: Set<String> = []

    private(set) var basvuru: Basvuru?
    private(set) var eskiForm: [String: FSDeger] = [:]
    private(set) var anahtar: (takipId: String, pasaportOzeti: String)?
    private(set) var acikNotlar: [BasvuruNotu] = []
    /// Alan tanımı dışında korunan veri: bildirim kanalları, kampanya izni (panel: collect).
    private(set) var korunan: [String: FSDeger] = [:]
    private(set) var talep: Talep?
    private(set) var yukleniyor = false
    private(set) var hazir = false
    private(set) var hata: String?
    var kaydediliyor = false

    init(kimlik: String?, talepYolu: String?, arsivId: String? = nil) {
        self.kimlik = kimlik
        self.talepYolu = talepYolu
        self.arsivId = arsivId
    }

    var duzenleme: Bool { kimlik != nil }

    /// Düzenlemede kaydı, talepten açılışta talebi okur.
    func yukle(_ ekip: EkipOturumu, veri: EkipVerisi, ulkeler: Set<String>) async {
        guard !hazir else { return }
        if let t = talepYolu.flatMap({ veri.talep($0) }) {
            talep = t
            let r = EkipFormu.tohum(t, ulkeler: ulkeler)
            ulke = r.ulke; degerler = r.degerler; korunan = r.korunan
            kampanyaIzni = r.korunan["kampanyaIzni"]?.mantikDegeri == true
        }
        if let a = arsivId {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { degerler = ["firstName": "KEMAL", "lastName": "YILDIZ"]; hazir = true; return }
            #endif
            do {
                let f = try await ekip.istemci()
                if let belge = try await f.belge("musteriArsivi/\(a)") {
                    let k = ArsivKaydi(kimlik: a, alanlar: belge)
                    let t = MusteriArsivi.tohum(k, ulkeler: ulkeler)
                    ulke = t.ulke; degerler = t.degerler
                    if let c = ekip.calisan {
                        _ = try? await f.isle([.olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                                                       alanlar: IslemKaydi.alanlar(eylem: "arsiv.geriAl", hedef: a,
                                                                                  ayrinti: "\(k.adSoyad) \(k.takipKodu)".kirpik, calisan: c),
                                                       zaman: ["at"])])
                    }
                }
            } catch {
                hata = "Arşiv kaydı okunamadı."
                return
            }
        }
        guard let id = kimlik else { hazir = true; return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") {
            basvuru = OrnekEkip.basvurular.first { $0.kimlik == id }
            ulke = basvuru?.ulke ?? ""
            degerler = ["firstName": basvuru?.ad ?? "", "lastName": basvuru?.soyad ?? "", "phone": "+905000000011"]
            hazir = true
            return
        }
        #endif
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let f = try await ekip.istemci()
            let yol = "applications/\(id)"
            async let a = f.belge(yol)
            async let d = f.belge("\(yol)/private/data")
            async let k = f.belge("\(yol)/private/keys")
            async let n = f.sorgu(koleksiyon: "notes", kosullar: [.esit("public", .mantik(true))], sinir: 30, ust: yol)
            guard let alanlar = try await a else { hata = "Başvuru bulunamadı."; return }
            let b = Basvuru(kimlik: id, alanlar: alanlar)
            basvuru = b
            let form = (try await d)?["form"]?.haritaDegeri ?? [:]
            eskiForm = form
            if let kb = try await k, let t = kb["takipId"]?.metinDegeri, let p = kb["passportHash"]?.metinDegeri { anahtar = (t, p) }
            let notlar: [FirestoreIstemci.Belge] = (try? await n) ?? []
            acikNotlar = notlar.map { BasvuruNotu(kimlik: $0.kimlik, alanlar: $0.alanlar) }
                .sorted { ($0.zaman ?? .distantPast) > ($1.zaman ?? .distantPast) }
            ulke = b.ulke
            randevu = b.randevu
            acilis = b.acilis ?? b.olusturma ?? Date()
            for (k, v) in form { if let s = v.metinDegeri { degerler[k] = s } }
            if let c = form["channels"] { korunan["channels"] = c }
            for k in ["kampanyaIzni", "kampanyaIzniKaynak", "kampanyaIzniTarih", "kampanyaIzniKim", "kampanyaIzniSurum"] {
                if let v = form[k] { korunan[k] = v }
            }
            kampanyaIzni = form["kampanyaIzni"]?.mantikDegeri == true
            hazir = true
        } catch FirestoreHatasi.izinYok {
            hata = "Düzenleme için hassas veri görme yetkisi gerekir."
        } catch {
            hata = HataAciklamasi.metin(error, "Başvuru yüklenemedi. İnternet bağlantınızı kontrol edin.")
        }
    }

    /// Kaydeder; başarıda başvurunun kimliğini döner. Sorunlar `sorunlar`a yazılır.
    func kaydet(_ ekip: EkipOturumu, sema: FormSemasi, ulkeListesi: [Ulke], ekipVerisi: EkipVerisi) async -> (kimlik: String?, mesaj: String) {
        guard let c = ekip.calisan else { return (nil, "Oturum bulunamadı.") }
        let alanlar = sema.panelAlanlari(ulke, kayitli: ekip.ulkeFormlari)
        let bugun = Tr.bugun()
        let acilisIso = Tr.isoGun(acilis, takvim: Tr.takvim)
        var korunacak = korunan
        // Kampanya izni: önceki kayıt korunur; yeni işaretlendiyse kim, ne zaman yazılır; kaldırıldıysa silinir.
        if kampanyaIzni {
            if korunacak["kampanyaIzni"]?.mantikDegeri != true {
                korunacak["kampanyaIzni"] = .mantik(true)
                korunacak["kampanyaIzniKaynak"] = .metin("panel")
                korunacak["kampanyaIzniTarih"] = .metin(FSDeger.zamanYaz(Date()))
                korunacak["kampanyaIzniKim"] = .metin(String(c.gorunenAd.prefix(80)))
            }
        } else {
            for k in ["kampanyaIzni", "kampanyaIzniKaynak", "kampanyaIzniTarih", "kampanyaIzniKim", "kampanyaIzniSurum"] { korunacak[k] = nil }
        }
        let r = EkipFormu.topla(degerler, alanlar: alanlar, acikKapalilar: acikKapalilar, ulke: ulke, acilis: acilisIso,
                                bugun: bugun, korunan: korunacak)
        if !r.sorunlar.isEmpty { return (nil, r.sorunlar.joined(separator: " ")) }
        let ulkeKaydi = ulkeListesi.first { $0.slug == ulke }
        let randevuIso = randevu.map { Tr.isoGun($0, takvim: Tr.takvim) } ?? ""
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return (kimlik ?? "b0001", "Kaydedildi.") }
        #endif
        kaydediliyor = true
        defer { kaydediliyor = false }
        do {
            let f = try await ekip.istemci()
            if let b = basvuru {
                try await f.isle(BasvuruIslemi.duzenle(b, eskiForm: eskiForm, yeniVeri: r.veri, alanlar: alanlar, ulkeId: ulke,
                                                       ulke: ulkeKaydi, randevu: randevuIso, acilis: acilisIso, eskiAnahtar: anahtar,
                                                       statuler: ekip.statuler, acikNotlar: acikNotlar, calisan: c))
                // Randevu günü değiştiyse bildirimler yeniden planlanır.
                let eskiGun = b.randevu.map { Tr.isoGun($0, takvim: Tr.takvim) } ?? ""
                var mesaj = "Değişiklikler kaydedildi."
                if !randevuIso.isEmpty && randevuIso != eskiGun {
                    var guncel = b
                    guncel.ulke = ulke; guncel.ulkeAdi = ulkeKaydi?.ad ?? ulke
                    mesaj += await planla(guncel, randevuIso, veri: r.veri, ekip: ekip, f: f, c: c)
                }
                return (b.kimlik, mesaj)
            }
            // Yeni başvuru: kod çakışırsa yeni kodla (en çok 5 deneme).
            let kontrol = talep.map { _ in eksikler(r.veri) } ?? ""
            for deneme in 0..<5 {
                guard let y = BasvuruIslemi.olustur(veri: r.veri, ulkeId: ulke, ulke: ulkeKaydi, randevu: randevuIso, acilis: acilisIso,
                                                    bugun: bugun, statuler: ekip.statuler, calisan: c, kontrolNotu: kontrol) else {
                    return (nil, "Henüz statü tanımlanmamış. Yönetici önce Ayarlar'dan statüleri oluşturmalı.")
                }
                do {
                    try await f.isle(y.yazimlar)
                } catch where BasvuruIslemi.kodCakismasi(error) && deneme < 4 {
                    continue
                }
                var mesaj = "Başvuru oluşturuldu. Takip kodu: \(y.takipKodu)."
                if let t = talep {
                    _ = try? await f.isle([
                        .guncelle(yol: t.yol, alanlar: Talep.onayAlanlari(basvuruId: y.kimlik, uid: c.uid), zaman: ["handledAt"]),
                        .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                                 alanlar: IslemKaydi.alanlar(eylem: "\(t.tur.rawValue).approve", hedef: t.kimlik,
                                                            ayrinti: "\(t.ad) — başvuruya çevrildi", calisan: c), zaman: ["at"]),
                    ])
                    await ekipVerisi.yukle(ekip, zorla: true)
                }
                if !randevuIso.isEmpty {
                    var b = Basvuru(kimlik: y.kimlik, alanlar: y.cekirdek)
                    b.takipKodu = y.takipKodu
                    mesaj += await planla(b, randevuIso, veri: r.veri, ekip: ekip, f: f, c: c)
                }
                ekipVerisi.basvurular.eskit()
                return (y.kimlik, mesaj)
            }
            return (nil, "Başvuru kaydedilemedi. Sorun sürerse yöneticiye bildirin.")
        } catch FirestoreHatasi.izinYok {
            return (nil, "Bu işlem için yetkiniz yok.")
        } catch {
            return (nil, HataAciklamasi.metin(error, "Kaydedilemedi. İnternet bağlantınızı kontrol edip yeniden deneyin."))
        }
    }

    /// Talepten açılan başvuruda boş kalan önemli alanlar ("Bilgileri kontrol edin" uyarısı).
    private func eksikler(_ v: [String: FSDeger]) -> String {
        let alanlar = [("passportNo", "pasaport no"), ("nationalId", "T.C. kimlik no"), ("birthDate", "doğum tarihi"),
                       ("passportExpires", "pasaport geçerlilik"), ("email", "e-posta"), ("entryDate", "planlanan giriş")]
        let bos = alanlar.filter { v[$0.0] == nil }.map(\.1)
        return bos.isEmpty ? "" : "Telefonda açıldı; şu alanlar boş kaldı: \(bos.joined(separator: ", "))."
    }

    /// Randevu tarihi girildi / değişti: otomatik bildirimler (panel: syncBildirim).
    private func planla(_ b: Basvuru, _ gun: String, veri: [String: FSDeger], ekip: EkipOturumu, f: FirestoreIstemci, c: Calisan) async -> String {
        guard ekip.yapabilir("app.status") else { return "" }
        let r = RandevuGirdisi(tarih: gun, saat: b.randevuSaati, merkez: b.randevuMerkezi, sehir: b.randevuSehri, yer: b.randevuYeriAdi, ulke: b.ulke)
        let k = RandevuKurali.Kayit(saat: b.randevuSaati, merkez: b.randevuMerkezi, sehir: b.randevuSehri,
                                    yer: b.randevuYeriAdi, harita: b.randevuHarita)
        do {
            let mevcut = try await f.sorgu(koleksiyon: "bildirimler", kosullar: [.esit("appId", .metin(b.kimlik))], sinir: 50)
                .map { BildirimKaydi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            let p = BildirimPlani.planla(b, randevu: r, kayit: k, iletisim: MusteriIletisimi(form: veri), ayar: ekip.bildirimAyari,
                                         mevcut: mevcut, yenidenGonder: [], calisan: c)
            if p.atlanan.contains("açık kanal yok") { return " Bildirim planlanmadı: müşterinin telefonu / e-postası ya da kanal seçimi yok." }
            if p.yazilan.isEmpty { return "" }
            try await f.isle(p.yazimlar)
            return " Randevu bildirimleri planlandı (\(p.yazilan.count) mesaj)."
        } catch {
            return " Otomatik bildirimler planlanamadı."
        }
    }
}
