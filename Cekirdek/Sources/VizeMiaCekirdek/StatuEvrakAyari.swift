import Foundation

// Ayarlar → Statüler ve Evrak kontrol listesi (yalnız yönetici).
// Panel karşılıkları: pages/admin.js → StatusesPanel, statusData, refreshApps,
// ChecklistPanel; basvuru-akisi.js → statuAyarlari; data/evraklar.js → eksikEvraklar.

/// Statü düzenleme formu.
public struct StatuGirdisi: Equatable {
    public var ad: String
    public var musteriAdi: String
    public var aciklama: String
    public var renk: String
    public var son: Bool
    public var bildir: Bool
    public var silmeGun: Int?
    public var aramaMin: Int?
    public var aramaMax: Int?
    public var gerekenler: [String]

    public init(_ s: Statu?) {
        ad = s?.ad ?? ""
        musteriAdi = s?.musteriAdi ?? ""
        aciklama = s?.musteriAciklamasi ?? ""
        renk = (s?.renk).flatMap { $0.isEmpty ? nil : $0 } ?? StatuAyari.varsayilanRenk
        son = s?.son ?? false
        bildir = s?.bildirir ?? true
        silmeGun = s?.silmeGun
        aramaMin = s?.aramaMin
        aramaMax = s?.aramaMax
        gerekenler = s?.gerekenler ?? []
    }
}

public enum StatuAyari {
    public static let varsayilanRenk = "#1e2c4d"
    typealias Y = FirestoreIstemci.Yazim

    static func kayit(_ eylem: String, _ hedef: String, _ ayrinti: String, _ c: Calisan) -> Y {
        .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                 alanlar: IslemKaydi.alanlar(eylem: eylem, hedef: hedef, ayrinti: String(ayrinti.prefix(500)), calisan: c), zaman: ["at"])
    }

    static func gun(_ n: Int?, _ enCok: Int) -> Int? { n.flatMap { $0 >= 1 && $0 <= enCok ? $0 : nil } }

    /// Yeni statünün kimliği: addan; çakışırsa sonuna zaman (panel: slugify + Date.now().toString(36)).
    public static func kimlik(ad: String, olanlar: [String], simdi: Date = Date()) -> String {
        let ms = Int(simdi.timeIntervalSince1970 * 1000)
        let s = Icerik.slug(ad)
        let id = s.isEmpty ? "statu-\(ms)" : s
        return olanlar.contains(id) ? "\(id)-\(String(ms, radix: 36))" : id
    }

    /// Statü belgesi (panel: statusData + statuAyarlari). Son adımda silme süresi olmaz
    /// (genel saklama süresi geçerli); arama aralığı tek uçluysa öteki de aynı, tersse yer değişir.
    public static func belge(_ g: StatuGirdisi, sira: Int, calisan c: Calisan) -> [String: FSDeger] {
        var aMin = gun(g.aramaMin, 365), aMax = gun(g.aramaMax, 365)
        if aMin != nil && aMax == nil { aMax = aMin }
        if aMax != nil && aMin == nil { aMin = aMax }
        if let x = aMin, let y = aMax, x > y { aMin = y; aMax = x }
        let sartlar = GecisSarti.allCases.map(\.rawValue).filter { g.gerekenler.contains($0) }
        let ad = String(g.ad.kirpik.prefix(60))
        let musteri = String(g.musteriAdi.kirpik.prefix(60))
        func sayi(_ n: Int?) -> FSDeger { n.map { .tam($0) } ?? .bos }
        return [
            "name": .metin(ad), "publicName": .metin(musteri.isEmpty ? ad : musteri),
            "publicDescription": .metin(String(g.aciklama.kirpik.prefix(400))),
            "color": .metin(String((g.renk.isEmpty ? varsayilanRenk : g.renk).prefix(20))),
            "order": .tam(sira), "isFinal": .mantik(g.son), "notifyCustomer": .mantik(g.bildir),
            "silmeGun": g.son ? .bos : sayi(gun(g.silmeGun, 3650)),
            "aramaMin": sayi(aMin), "aramaMax": sayi(aMax),
            "gerekenler": .dizi(sartlar.map { FSDeger.metin($0) }), "odemeGerekli": .mantik(sartlar.contains("odeme")),
            "updatedBy": .metin(c.uid),
        ]
    }

    /// Yeni ya da düzenlenen statü. Ad boşsa nil. Yeni statü listenin sonuna eklenir.
    public static func kaydet(_ g: StatuGirdisi, mevcut: Statu?, statuler: [Statu], calisan c: Calisan, simdi: Date = Date())
        -> (id: String, yazimlar: [FirestoreIstemci.Yazim])? {
        guard !g.ad.kirpik.isEmpty else { return nil }
        let id = mevcut?.id ?? kimlik(ad: g.ad, olanlar: statuler.map(\.id), simdi: simdi)
        let sira = mevcut.map { Int($0.sira.rounded()) } ?? (Int((statuler.map(\.sira).max() ?? 0).rounded()) + 10)
        let a = belge(g, sira: sira, calisan: c)
        return (id, [
            .yaz(yol: "statuses/\(id)", alanlar: a, zaman: ["updatedAt"]),
            kayit(mevcut == nil ? "status.create" : "status.update", id, a["name"]?.metinDegeri ?? "", c),
        ])
    }

    /// Müşteriye görünen bir şey değişti mi (o statüdeki takip sayfaları tazelenir).
    public static func musteriyeGorunenDegisti(_ eski: Statu, _ g: StatuGirdisi) -> Bool {
        let ad = g.ad.kirpik, musteri = g.musteriAdi.kirpik
        return eski.musteriAdi != (musteri.isEmpty ? ad : musteri) || eski.musteriAciklamasi != g.aciklama.kirpik
            || eski.renk != g.renk || eski.son != g.son
    }

    /// İki statünün sırasını değiştirir (yalnız sıra yazılır).
    public static func yerDegistir(_ a: Statu, _ b: Statu, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        var sa = Int(a.sira.rounded()), sb = Int(b.sira.rounded())
        // Eşit sıradaysa ayrışsın diye birine bir eklenir.
        if sa == sb { sb += 1 }
        swap(&sa, &sb)
        return [
            .guncelle(yol: "statuses/\(a.id)", alanlar: ["order": .tam(sa), "updatedBy": .metin(c.uid)], zaman: ["updatedAt"]),
            .guncelle(yol: "statuses/\(b.id)", alanlar: ["order": .tam(sb), "updatedBy": .metin(c.uid)], zaman: ["updatedAt"]),
        ]
    }

    public static func sil(_ s: Statu, ayrinti: String? = nil, calisan c: Calisan) -> [FirestoreIstemci.Yazim] {
        [.sil(yol: "statuses/\(s.id)"), kayit("status.delete", s.id, ayrinti ?? s.ad, c)]
    }

    /// Müşteri sayfasını (takip/{id}) statünün yeni hâliyle yeniden yazar; müşteriye
    /// görünen notlar okunduğu gibi korunur (panel: refreshApps).
    public static func takipTazele(_ b: Basvuru, takipId: String, notlar: FSDeger?, hedef: Statu, statuler: [Statu]) -> FirestoreIstemci.Yazim {
        var a = TakipBelgesi.alanlar(basvuru: b, statu: hedef, statuler: statuler, notlar: [])
        a["notes"] = notlar ?? .dizi([])
        return .yaz(yol: "takip/\(takipId)", alanlar: a, zaman: ["updatedAt"])
    }

    /// Silinen statüdeki başvuruyu başka statüye taşır: statü alanları (saklama kuralı
    /// dahil), geçmiş satırı ve müşteri sayfası (panel: refreshApps(move=true)).
    public static func tasi(_ b: Basvuru, takipId: String?, notlar: FSDeger?, hedef: Statu, statuler: [Statu], saklamaGun: Int,
                            calisan c: Calisan, simdi: Date = Date()) -> [FirestoreIstemci.Yazim] {
        let g = b.statuGecisi(hedef, saklamaGun: saklamaGun, simdi: simdi)
        var alanlar = g.alanlar
        alanlar["updatedBy"] = .metin(c.uid)
        var y: [FirestoreIstemci.Yazim] = [
            .guncelle(yol: "applications/\(b.kimlik)", alanlar: alanlar, zaman: g.zaman + ["updatedAt"]),
            BasvuruIslemi.gecmis(b, tur: "status", metin: "\(b.statuAdi) → \(hedef.ad) (statü silindiği için)", statu: hedef, c),
        ]
        if let t = takipId {
            var yeni = b
            yeni.statuId = hedef.id
            y.append(takipTazele(yeni, takipId: t, notlar: notlar, hedef: hedef, statuler: statuler))
        }
        return y
    }
}

// MARK: - Evrak kontrol listesi

public enum EvrakListesiAyari {
    /// Ülkeye özel liste yoksa başlangıç: katalogdaki hazır liste, o da yoksa genel liste.
    public static func baslangic(ulke: String, ayar: EvrakAyari, katalog: EvrakKatalogu) -> [Evrak] {
        if let u = ayar.ulkeler[ulke] { return u }
        if !ulke.isEmpty, let h = katalog.ulkeler[ulke] {
            return h.map { Evrak(id: $0, ad: katalog.etiketler[$0] ?? $0, kosullu: false) }
        }
        return genel(ayar, katalog)
    }

    public static func genel(_ ayar: EvrakAyari, _ katalog: EvrakKatalogu) -> [Evrak] {
        ayar.genel ?? katalog.genel.map { Evrak(id: $0, ad: katalog.etiketler[$0] ?? $0, kosullu: false) }
    }

    public static func hazirVar(_ ulke: String, _ katalog: EvrakKatalogu) -> Bool { !ulke.isEmpty && katalog.ulkeler[ulke] != nil }

    /// Listede olmayan önerilen evraklar (panel: eksikEvraklar): kimliği ya da adı aynı olan atlanır.
    public static func eksikler(_ mevcut: [Evrak], ulke: String, katalog: EvrakKatalogu) -> [Evrak] {
        let idler = Set(mevcut.map(\.id))
        let adlar = Set(mevcut.map { $0.ad.kirpik.lowercased(with: Tr.yerel) })
        let oneri = (ulke.isEmpty ? nil : katalog.ulkeler[ulke]) ?? katalog.genel
        return oneri.map { Evrak(id: $0, ad: katalog.etiketler[$0] ?? $0, kosullu: false) }
            .filter { !idler.contains($0.id) && !adlar.contains($0.ad.lowercased(with: Tr.yerel)) }
    }

    static func temizle(_ l: [Evrak], simdi: Date) -> [FSDeger] {
        let ms = String(Int(simdi.timeIntervalSince1970 * 1000), radix: 36)
        return l.filter { !$0.ad.kirpik.isEmpty }.map { e in
            // Ekranda yeni eklenen satırın geçici kimliği ("yeni-…") kaydedilmez; addan türetilir.
            let id = !e.id.isEmpty && !e.id.hasPrefix("yeni-") ? e.id : (Icerik.slug(e.ad).isEmpty ? "evrak-\(ms)" : Icerik.slug(e.ad))
            return .harita(["id": .metin(id), "label": .metin(String(e.ad.kirpik.prefix(120)))])
        }
    }

    /// settings/checklist'i baştan yazar (panel: save). Boş ülke listesi kaldırılır.
    public static func kaydet(genel: [Evrak], ulkeler: [String: [Evrak]], kapsam: String, calisan c: Calisan,
                              simdi: Date = Date()) -> [FirestoreIstemci.Yazim] {
        var u: [String: FSDeger] = [:]
        for (k, l) in ulkeler {
            let t = temizle(l, simdi: simdi)
            if !t.isEmpty { u[k] = .dizi(t) }
        }
        return [
            .yaz(yol: "settings/checklist", alanlar: ["items": .dizi(temizle(genel, simdi: simdi)), "byCountry": .harita(u)]),
            StatuAyari.kayit("settings.checklist", kapsam.isEmpty ? "genel" : kapsam, "", c),
        ]
    }
}
