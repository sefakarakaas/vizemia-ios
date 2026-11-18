import Foundation
import Observation
import VizeMiaCekirdek

/// Siteden gelen içerik (rehberler, blog, SSS, harçlar, vitrin, kur, mesai).
/// Uygulamayla gelen kopyayla açılır; cihazdaki son kopya ve siteden taze
/// inen onun yerini alır. Site değişince uygulama da değişir.
@MainActor
@Observable
final class IcerikDeposu {
    private(set) var akis: Akis
    private(set) var slaytlar: [Slayt]
    private(set) var kur: KurVerisi?
    private(set) var sonYenileme: Date?

    private let kaynak: IcerikKaynagi
    /// Uygulamayla gelen evrak kataloğu: siteden inen dosya eskiyse (alan yoksa) bu kullanılır.
    private let gomuluEvrak: EvrakKatalogu?
    private let gomuluRandevu: RandevuSecenekleri?
    private let gomuluForm: FormSemasi?
    private let gomuluRehber: GorusmeRehberi?
    private let gomuluMektup: MektupVerisi?

    /// İyi niyet mektubunun hazır verisi (settings/mektup üstüne yazar).
    var mektup: MektupVerisi? { akis.mektup ?? gomuluMektup }

    /// Görüşme rehberinin varsayılanı (Ayarlar'dan kaydedilen settings/rehber üstüne yazar).
    var rehber: GorusmeRehberi? { akis.rehber ?? gomuluRehber }

    /// Başvuru formunun şeması (ekip: yeni başvuru / düzenle).
    var formSemasi: FormSemasi? { akis.form ?? gomuluForm }

    /// Randevu kağıdı girişinin seçenekleri (merkezler, iller, saatler, temsilcilikler).
    var randevu: RandevuSecenekleri {
        akis.randevu ?? gomuluRandevu ?? RandevuSecenekleri(merkezler: [], temsilcilikTurleri: [], sehirler: [], sikSehirSayisi: 0,
                                                             saatler: [], temsilcilikler: [], merkezHaritalari: [:])
    }

    /// Panelin evrak kataloğu (ekip ekranı, evrak kontrol listesi).
    var evrak: EvrakKatalogu {
        akis.evrak ?? gomuluEvrak ?? EvrakKatalogu(etiketler: [:], genel: [], kosullu: [], ulkeler: [:])
    }

    var mesai: Mesai { Mesai(ayar: akis.mesai) }
    var iletisim: Iletisim { akis.iletisim }
    var sayfaYollari: Set<String> { Set(akis.sayfalar.map { $0.yol }) }

    init() {
        let klasor = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("icerik", isDirectory: true)
        let kaynak = IcerikKaynagi(onbellek: klasor)
        self.kaynak = kaynak

        // Uygulamayla gelen ve cihazdaki kopyadan yenisi kazanır (uygulama
        // güncellenmiş ama cihaz uzun süredir çevrimdışıysa gömülü daha yenidir).
        let gomulu: Akis? = IcerikKaynagi.gomulu(.uygulama)
        gomuluEvrak = gomulu?.evrak
        gomuluRandevu = gomulu?.randevu
        gomuluForm = gomulu?.form
        gomuluRehber = gomulu?.rehber
        gomuluMektup = gomulu?.mektup
        let kayitli: Akis? = kaynak.kayitli(.uygulama)
        if let k = kayitli, k.surum == 1, !k.sayfalar.isEmpty, k.uretim >= (gomulu?.uretim ?? "") {
            akis = k
        } else if let g = gomulu {
            akis = g
        } else {
            // Gömülü dosya her zaman vardır; yine de boş içerikle açılabilsin.
            akis = try! JSONDecoder().decode(Akis.self, from: Data("{}".utf8))
        }

        let v: VitrinDosyasi? = kaynak.kayitli(.vitrin) ?? IcerikKaynagi.gomulu(.vitrin)
        slaytlar = v?.slaytlar ?? []

        let kr: KurVerisi? = kaynak.kayitli(.kur) ?? IcerikKaynagi.gomulu(.kur)
        kur = (kr?.gecerli ?? false) ? kr : nil
    }

    /// Siteden tazeler. Bağlantı yoksa eldeki içerik kalır.
    func yenile() async {
        // Art arda açılışlarda siteyi yormamak için en çok 2 dakikada bir.
        if let s = sonYenileme, Date().timeIntervalSince(s) < 120 { return }
        sonYenileme = Date()

        let kaynak = self.kaynak
        async let yeniAkis: Akis? = kaynak.indir(.uygulama)
        async let yeniVitrin: VitrinDosyasi? = kaynak.indir(.vitrin)
        async let yeniKur: KurVerisi? = kaynak.indir(.kur)

        if let a = await yeniAkis, a.surum == 1, !a.sayfalar.isEmpty { akis = a }
        if let v = await yeniVitrin, !v.slaytlar.isEmpty { slaytlar = v.slaytlar }
        if let k = await yeniKur, k.gecerli, kur == nil || kur?.kaynak == "TCMB" { kur = k }
        await canliKur()
    }

    /// Anlık kur (Apps Script servisi, Google Finance). Gelmezse TCMB kuru kalır.
    func canliKur() async {
        guard !akis.servisUrl.isEmpty, let u = URL(string: akis.servisUrl + "?islem=kur") else { return }
        let k: KurVerisi? = await kaynak.indir(u)
        if let k, k.gecerli { kur = k }
    }

    /// Yeni talep bildirimi (ekibe Telegram / e-posta).
    func bildir(tur: String, kimlik: String) {
        let servis = akis.servisUrl
        Task.detached { await Bildirim.gonder(servis: servis, tur: tur, kimlik: kimlik) }
    }

    /// Bugün gösterilecek slaytlar.
    var vitrin: [Slayt] { Vitrin.gosterilecekler(slaytlar) }

    func rehber(ulke slug: String) -> Sayfa? {
        slug.isEmpty ? nil : akis.ulkeRehberleri.first { $0.ulke == slug }
    }
}
