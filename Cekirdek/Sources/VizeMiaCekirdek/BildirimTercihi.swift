import Foundation

// Müşterinin bildirim tercihleri (panel: bildirim-tercih.js, pages/bildirim-tercih.js).
// Hangi yoldan otomatik mesaj gider: WhatsApp, SMS, e-posta. Kayıt:
// applications/{id}/private/data → form.channels { wa, sms, email } ve form.email.
// Tercih randevu / evrak / form bağlantısı bildirimlerine ve statü mesajlarına
// uygulanır; danışmanın elle yazdığı mesajlar danışmanın seçimidir.

public enum BildirimTercihi {
    public static let kanalAdlari: [(id: String, ad: String)] = [("wa", "WhatsApp"), ("sms", "SMS"), ("email", "E-posta")]

    public static func epostaDuzelt(_ s: String) -> String { String(s.kirpik.lowercased().prefix(120)) }
    public static func epostaGecerli(_ s: String) -> Bool { epostaDuzelt(s).eslesir("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$") }

    /// Kaydetmeden önce denetim (panel: tercihHatalari).
    public static func hatalar(_ k: Kanallar, eposta: String, telefon: String) -> [String] {
        var h: [String] = []
        if k.email && !epostaGecerli(eposta) { h.append("E-posta açık: geçerli bir e-posta adresi girin.") }
        if !k.email && !eposta.kirpik.isEmpty && !epostaGecerli(eposta) { h.append("E-posta adresi geçersiz.") }
        if (k.wa || k.sms) && telefon.kirpik.isEmpty { h.append("WhatsApp ve SMS için telefon numarası gerekli (Düzenle'den ekleyin).") }
        return h
    }

    /// "WhatsApp açık · SMS kapalı · E-posta açık".
    public static func ozet(_ k: Kanallar) -> String {
        [("WhatsApp", k.wa), ("SMS", k.sms), ("E-posta", k.email)].map { "\($0.0) \($0.1 ? "açık" : "kapalı")" }.joined(separator: " · ")
    }

    /// Kayıtlı tercih (yoksa üçü de açık) — eski kayıtta seçim olmayabilir.
    public static func oku(_ form: [String: FSDeger]?) -> (kanallar: Kanallar, kayitli: Bool) {
        guard let c = form?["channels"]?.haritaDegeri else { return (Kanallar(), false) }
        return (Kanallar(wa: c["wa"]?.mantikDegeri == true, sms: c["sms"]?.mantikDegeri == true, email: c["email"]?.mantikDegeri == true), true)
    }

    public static func degisti(_ form: [String: FSDeger]?, _ k: Kanallar, eposta: String) -> Bool {
        let e = oku(form)
        return !e.kayitli || e.kanallar != k || epostaDuzelt(form?["email"]?.metinDegeri ?? "") != epostaDuzelt(eposta)
    }

    /// Yalnız tercih ve e-posta yazılır, formun geri kalanına dokunulmaz; geçmiş + işlem kaydı.
    public static func kaydet(_ b: Basvuru, _ k: Kanallar, eposta: String, epostaDegisti: Bool, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        let o = ozet(k)
        return [
            .derin(yol: "applications/\(b.kimlik)/private/data", alanlar: [
                ["form", "channels"]: k.deger, ["form", "email"]: .metin(epostaDuzelt(eposta)), ["updatedBy"]: .metin(c.uid),
            ], zaman: [["updatedAt"]]),
            BasvuruIslemi.gecmis(b, tur: "edit", metin: String("Bildirim tercihi: \(o)".prefix(500)), c),
            BasvuruIslemi.kayit("app.bildirimTercihi", b,
                                "\(b.ad) \(b.soyad) — \(o)\(epostaDegisti ? " · e-posta güncellendi" : "")".kirpik, c),
        ]
    }

    /// Planlanmış (henüz gitmemiş) otomatik bildirimleri yeni tercihe göre yeniden kurar
    /// (panel: bildirimleriYenile). Planlılar iptal edilir; randevu tarihi varsa randevu
    /// bildirimleri, form bağlantısı planlıysa o da kurala göre yeniden yazılır.
    public static func yenidenPlanla(
        _ b: Basvuru, iletisim: MusteriIletisimi, ayar: BildirimAyari, mevcut: [BildirimKaydi],
        formKurali: FormGonderimKurali, calisan c: Calisan, simdi: Date = Date()
    ) -> (yazimlar: [FirestoreIstemci.Yazim], adet: Int) {
        let planli = mevcut.filter { $0.durum == "planned" }
        guard !planli.isEmpty else { return ([], 0) }
        var y: [FirestoreIstemci.Yazim] = planli.map {
            .guncelle(yol: "bildirimler/\($0.id)", alanlar: [
                "status": .metin("cancelled"), "cancelReason": .metin("Bildirim tercihi değişti"), "updatedBy": .metin(c.uid),
            ], zaman: ["updatedAt"])
        }
        // İptal edilenler aşağıdaki planlayıcılara bir daha verilmez.
        let kalan = mevcut.filter { $0.durum != "planned" }
        if planli.contains(where: { $0.tur != "form-linki" }), let r = b.randevu {
            let gun = Tr.bugun(r)
            let ri = RandevuGirdisi(tarih: gun, saat: b.randevuSaati, merkez: b.randevuMerkezi, sehir: b.randevuSehri, yer: b.randevuYeriAdi, ulke: b.ulke)
            let k = RandevuKurali.Kayit(saat: b.randevuSaati, merkez: b.randevuMerkezi, sehir: b.randevuSehri, yer: b.randevuYeriAdi, harita: b.randevuHarita)
            y += BildirimPlani.planla(b, randevu: ri, kayit: k, iletisim: iletisim, ayar: ayar, mevcut: kalan, yenidenGonder: [],
                                     calisan: c, simdi: simdi).yazimlar
        }
        if planli.contains(where: { $0.tur == "form-linki" }) {
            y += BildirimPlani.formLinki(b, kural: formKurali, iletisim: iletisim, ayar: ayar, mevcut: kalan, calisan: c, simdi: simdi).yazimlar
        }
        return (y, planli.count)
    }
}
