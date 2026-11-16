import SwiftUI
import VizeMiaCekirdek

/// Alt sekmeler: sitenin üst menüsünün karşılığı.
struct KokGorunum: View {
    @Environment(IcerikDeposu.self) private var icerik
    @Environment(Gezinti.self) private var gezinti
    @Environment(TakipHafizasi.self) private var hafiza

    var body: some View {
        @Bindable var gezinti = gezinti
        TabView(selection: $gezinti.sekme) {
            sekme(.anaSayfa) { AnaSayfaEkrani() }
                .tabItem { Label("Ana Sayfa", systemImage: "house.fill") }
                .tag(Sekme.anaSayfa)
            sekme(.takip) { TakipEkrani() }
                .tabItem { Label("Takip", systemImage: "doc.text.magnifyingglass") }
                .tag(Sekme.takip)
                // Müşterinin henüz görmediği bir aşama değişikliği varsa rozet.
                .badge(hafiza.yeniVar ? 1 : 0)
            sekme(.basvuru) { BasvuruEkrani() }
                .tabItem { Label("Başvur", systemImage: "phone.arrow.down.left.fill") }
                .tag(Sekme.basvuru)
            sekme(.harclar) { HarclarEkrani() }
                .tabItem { Label("Harç & Kur", systemImage: "eurosign.circle.fill") }
                .tag(Sekme.harclar)
            sekme(.daha) { DahaEkrani() }
                .tabItem { Label("Daha", systemImage: "ellipsis.circle.fill") }
                .tag(Sekme.daha)
        }
        // İçerikteki bağlantılar ("/takip", "/blog/…") uygulamanın kendi ekranına gider.
        .environment(\.openURL, OpenURLAction { url in
            gezinti.ac(link: url.absoluteString, sayfaYollari: icerik.sayfaYollari)
            return .handled
        })
        .sheet(item: $gezinti.web) { adres in
            SafariGorunumu(url: adres.url).ignoresSafeArea()
        }
        .alert(
            gezinti.aramaUyarisi?.baslik ?? "",
            isPresented: Binding(get: { gezinti.aramaUyarisi != nil }, set: { if !$0 { gezinti.aramaUyarisi = nil } }),
            presenting: gezinti.aramaUyarisi
        ) { _ in
            Button("Talep bırak") { gezinti.ac(.basvuru(ulke: "")) }
            Button("WhatsApp'tan yaz") { gezinti.whatsapp(icerik.iletisim) }
            Button("Yine de ara") { gezinti.yineDeAra(icerik.iletisim) }
            Button("Vazgeç", role: .cancel) {}
        } message: { uyari in
            Text(uyari.metin)
        }
    }

    /// Her sekmenin kendi gezinme yığını var; bağlantılar bulunulan sekmede açılır.
    private func sekme<Govde: View>(_ s: Sekme, @ViewBuilder _ govde: () -> Govde) -> some View {
        NavigationStack(path: gezinti.yol(s)) {
            govde()
                .navigationDestination(for: Rota.self) { rota in
                    switch rota {
                    case .sayfa(let yol): SayfaEkrani(yol: yol)
                    case .blog: BlogEkrani()
                    case .rehberler: RehberlerEkrani()
                    case .ulkeler: UlkelerEkrani()
                    case .sss: SssEkrani()
                    case .destek(let kod): DestekEkrani(kod: kod)
                    case .iletisim: IletisimEkrani()
                    case .takipSorgu: TakipSorgusu()
                    }
                }
        }
    }
}
