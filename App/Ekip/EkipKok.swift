import SwiftUI
import VizeMiaCekirdek

enum EkipSekme: Hashable { case ana, talepler, takvim, hesap }

/// Ekip içinde açılan ekranlar.
enum EkipRota: Hashable {
    case talep(String)          // talep yolu: "callback/abc"
    case talepler
    case destekler
    case destek(String)
    case takvim
    case basvurular
    case basvuru(String)        // başvuru kimliği
    case yeniBasvuru(talep: String?)   // talep yolu verilirse form talepten dolu gelir
    case basvuruDuzenle(String)
    case arsiv
    case arsivdenBasvuru(String)    // arşiv kaydının kimliği: yeni başvuru formu onunla dolu
    case grubaEkle(String)          // ilk kişinin başvurusu: yeni başvuru ortak yolculuk bilgileriyle dolu
    case kasa
    case bildirimler
    case eposta
    case firma
    case surec
    case icerikler
    case icerik(String?)        // nil: yeni içerik
    case vitrin
    case slayt(String?)         // nil: yeni slayt
    case havuz
    case sosyal
    case sifre
    case kullanicilar
    case islemKayitlari
    case armut
    case ayarlar
    case kasaRutinler
    case bolum(String)          // ana sayfa kutusu: "musteriler", "kasa" …
    case yakinda(String)        // henüz uygulamada olmayan panel ekranı
}

/// Çalışan girişi yapılınca uygulama bu görünüme geçer: panelin uygulama hâli.
struct EkipKok: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var veri
    @Environment(\.scenePhase) private var sahne
    @State private var sekme: EkipSekme = .ana
    @State private var yollar: [EkipSekme: [EkipRota]] = [:]

    var body: some View {
        ZStack {
            TabView(selection: $sekme) {
                yigin(.ana) { EkipAnaSayfa(sekme: $sekme) }
                    .tabItem { Label("Ana Sayfa", systemImage: "square.grid.2x2.fill") }
                    .tag(EkipSekme.ana)
                yigin(.talepler) { TaleplerEkrani() }
                    .tabItem { Label("Talepler", systemImage: "phone.badge.waveform.fill") }
                    .tag(EkipSekme.talepler)
                    .badge(veri.ozet.acil + veri.ozet.geciken)
                yigin(.takvim) { TakvimEkrani() }
                    .tabItem { Label("Takvim", systemImage: "calendar") }
                    .tag(EkipSekme.takvim)
                yigin(.hesap) { HesapEkrani() }
                    .tabItem { Label("Hesabım", systemImage: "person.crop.circle.fill") }
                    .tag(EkipSekme.hesap)
            }
            .task { await veri.yukle(ekip) }
            .onChange(of: sahne) { _, yeni in
                if yeni == .active { Task { await veri.yukle(ekip) } }
            }

            if ekip.kilitli {
                KilitEkrani()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(Hareket.yay, value: ekip.kilitli)
        // WhatsApp açıldıysa dönünce "Gönderdim / Göndermedim" sorulur; kapatılamaz.
        .sheet(isPresented: Binding(get: { ekip.bekleyenWa != nil && !ekip.kilitli }, set: { _ in })) {
            WaTeyitSayfasi()
        }
    }

    private func yigin<Govde: View>(_ s: EkipSekme, @ViewBuilder _ govde: () -> Govde) -> some View {
        NavigationStack(path: Binding(get: { yollar[s] ?? [] }, set: { yollar[s] = $0 })) {
            govde()
                .navigationDestination(for: EkipRota.self) { rota in
                    switch rota {
                    case .talep(let yol): TalepDetayi(yol: yol)
                    case .talepler: TaleplerEkrani()
                    case .destekler: DestekTalepleriEkrani()
                    case .destek(let id): DestekDetayi(kimlik: id)
                    case .takvim: TakvimEkrani()
                    case .basvurular: BasvurularEkrani()
                    case .basvuru(let id): BasvuruDetayi(kimlik: id)
                    case .yeniBasvuru(let talep): BasvuruFormuEkrani(kimlik: nil, talepYolu: talep)
                    case .basvuruDuzenle(let id): BasvuruFormuEkrani(kimlik: id, talepYolu: nil)
                    case .arsiv: ArsivEkrani()
                    case .arsivdenBasvuru(let id): BasvuruFormuEkrani(kimlik: nil, talepYolu: nil, arsivId: id)
                    case .grubaEkle(let id): BasvuruFormuEkrani(kimlik: nil, talepYolu: nil, grupKaynak: id)
                    case .kasa: KasaEkrani()
                    case .bildirimler: BildirimlerEkrani()
                    case .eposta: EpostaEkrani()
                    case .firma: FirmaMailiEkrani()
                    case .surec: SurecEkrani()
                    case .icerikler: IcerikListesiEkrani()
                    case .icerik(let id): IcerikDuzenleEkrani(kimlik: id)
                    case .vitrin: VitrinListesiEkrani()
                    case .slayt(let id): VitrinDuzenleEkrani(kimlik: id)
                    case .havuz: HavuzEkrani()
                    case .sosyal: SosyalEkrani()
                    case .sifre: SifreDegistirEkrani()
                    case .kullanicilar: KullanicilarEkrani()
                    case .islemKayitlari: IslemKayitlariEkrani()
                    case .armut: ArmutEkrani()
                    case .ayarlar: AyarlarEkrani()
                    case .kasaRutinler: RutinOdemelerEkrani()
                    case .bolum(let id): BolumEkrani(id: id)
                    case .yakinda(let ad): YakindaEkrani(ad: ad)
                    }
                }
        }
        // Kaydedilen formun yerine ayrıntısı açılsın (geri dönünce form değil liste gelsin).
        .environment(\.ekipYerDegistir, { rota in
            var p = yollar[s] ?? []
            if !p.isEmpty { p.removeLast() }
            p.append(rota)
            yollar[s] = p
        })
    }
}

/// Face ID ile açılan kilit (boşta kalma süresi dolunca).
struct KilitEkrani: View {
    @Environment(EkipOturumu.self) private var ekip

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54))
                .foregroundStyle(Tema.turkuaz)
                .symbolEffect(.pulse, options: .repeating)
            Text(Selamlama.cumle(saat: Calendar.current.component(.hour, from: Date()), ad: ekip.calisan?.ilkAd ?? ""))
                .font(.vitrin(28))
                .foregroundStyle(.white)
            Text("Uygulama bir süredir kullanılmadı. Devam etmek için kimliğinizi doğrulayın.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await ekip.kilidiAc() }
            } label: {
                Label("Kilidi aç", systemImage: "faceid")
            }
            .buttonStyle(AnaDugme(renk: Tema.turkuaz, tamGenislik: false))
            .padding(.top, 8)
            Spacer()
            Button("Çıkış yap") { ekip.cikis() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tema.lacivert.ignoresSafeArea())
        .task { await ekip.kilidiAc() }
    }
}

/// Hesap pasif ya da çalışan kaydı yok.
struct YetkisizEkrani: View {
    @Environment(EkipOturumu.self) private var ekip

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.xmark").font(.system(size: 48)).foregroundStyle(Tema.silik)
            Text("Bu hesabın panele erişim yetkisi yok ya da hesap pasif durumda. Yöneticinizle iletişime geçin.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Tema.govde)
            Button("Çıkış yap") { ekip.cikis() }.buttonStyle(IkincilDugme(tamGenislik: false))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ekranZemini()
    }
}

/// Henüz uygulamada olmayan panel ekranı.
struct YakindaEkrani: View {
    let ad: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "hammer.fill").font(.system(size: 40)).foregroundStyle(Tema.turkuaz)
            Text(ad).font(.title2.weight(.heavy)).foregroundStyle(Tema.lacivert)
            Text("Bu bölüm uygulamaya ekleniyor; sonraki sürümlerden birinde burada olacak. O zamana kadar panelden kullanabilirsiniz.")
                .font(.subheadline)
                .foregroundStyle(Tema.govde)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ekranZemini()
        .navigationTitle(ad)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Açık ekranın yerine başka bir ekip ekranı koyar (ör. kaydedilen form → başvuru ayrıntısı).
private struct EkipYerDegistirAnahtari: EnvironmentKey {
    static let defaultValue: (EkipRota) -> Void = { _ in }
}

extension EnvironmentValues {
    var ekipYerDegistir: (EkipRota) -> Void {
        get { self[EkipYerDegistirAnahtari.self] }
        set { self[EkipYerDegistirAnahtari.self] = newValue }
    }
}
