import SwiftUI
import VizeMiaCekirdek

/// Hesabım: kim girişli, rolü, müşteri görünümüne geçiş, çıkış.
struct HesapEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var veri
    @State private var cikisSoruluyor = false

    var body: some View {
        List {
            if let c = ekip.calisan {
                Section {
                    HStack(spacing: 14) {
                        Text(String(c.ilkAd.prefix(1)).uppercased())
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Tema.lacivert, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.adSoyad.isEmpty ? c.kullaniciAdi : c.adSoyad).font(.headline).foregroundStyle(Tema.lacivert)
                            Text("\(c.rolAdi) · @\(c.kullaniciAdi)").font(.caption).foregroundStyle(Tema.govde)
                        }
                    }
                    .padding(.vertical, 6)
                    .belirme(0)
                }
            }
            Section {
                Button {
                    withAnimation(Hareket.yay) { ekip.ekipGorunumu = false }
                } label: {
                    Label("Müşteri görünümüne geç", systemImage: "person.fill.viewfinder")
                }
            } footer: {
                Text("Uygulamayı müşterinin gördüğü hâliyle açar. Ekibe dönmek için Daha → Ekip görünümü.")
            }
            Section {
                Label("Giriş bu telefonda hatırlanıyor. Uygulama bir süre kullanılmayınca Face ID ile kilitlenir.", systemImage: "faceid")
                    .font(.footnote)
                    .foregroundStyle(Tema.govde)
            }
            Section {
                Button(role: .destructive) { cikisSoruluyor = true } label: {
                    Label("Çıkış yap", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Hesabım")
        .confirmationDialog("Çıkış yapılsın mı?", isPresented: $cikisSoruluyor, titleVisibility: .visible) {
            Button("Çıkış yap", role: .destructive) {
                veri.temizle()
                ekip.cikis()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bir dahaki girişte kullanıcı adı ve şifre sorulur.")
        }
    }
}
