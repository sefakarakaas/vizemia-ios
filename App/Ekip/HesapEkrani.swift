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
                NavigationLink(value: EkipRota.bildirimTercihleri) { Label("Bildirimler", systemImage: "bell.badge.fill") }
                NavigationLink(value: EkipRota.bildirimGonder(nil)) { Label("Bildirim gönder", systemImage: "paperplane.fill") }
            }
            Section {
                NavigationLink(value: EkipRota.sifre) { Label("Şifremi değiştir", systemImage: "key.fill") }
                if ekip.calisan?.yonetici == true {
                    NavigationLink(value: EkipRota.kullanicilar) { Label("Kullanıcılar", systemImage: "person.3.fill") }
                    NavigationLink(value: EkipRota.islemKayitlari) { Label("İşlem kayıtları", systemImage: "list.bullet.rectangle.fill") }
                }
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

/// Şifremi değiştir (panel: #/hesabim).
struct SifreDegistirEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(\.dismiss) private var kapat
    @State private var mevcut = ""
    @State private var yeni1 = ""
    @State private var yeni2 = ""
    @State private var hata: String?
    @State private var tamam = false
    @State private var calisiyor = false

    var body: some View {
        Form {
            Section {
                SecureField("Mevcut şifre", text: $mevcut).textContentType(.password)
                SecureField("Yeni şifre", text: $yeni1).textContentType(.newPassword)
                SecureField("Yeni şifre (tekrar)", text: $yeni2).textContentType(.newPassword)
            } footer: {
                Text("En az 12 karakter; büyük harf, küçük harf, rakam ve özel karakter içermeli.")
            }
            if let h = hata { Section { Text(h).foregroundStyle(Tema.olumsuz) } }
            if tamam { Section { Label("Şifreniz değiştirildi.", systemImage: "checkmark.circle.fill").foregroundStyle(Tema.olumluKoyu) } }
            Section {
                Button {
                    Task { await degistir() }
                } label: {
                    if calisiyor { ProgressView() } else { Text("Şifreyi değiştir") }
                }
                .disabled(calisiyor || mevcut.isEmpty || yeni1.isEmpty)
            }
        }
        .navigationTitle("Şifremi değiştir")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: tamam)
    }

    private func degistir() async {
        hata = nil
        tamam = false
        guard yeni1 == yeni2 else { hata = "Yeni şifreler eşleşmiyor."; return }
        calisiyor = true
        defer { calisiyor = false }
        if let h = await ekip.sifreDegistir(mevcut: mevcut, yeni: yeni1) { hata = h; return }
        mevcut = ""; yeni1 = ""; yeni2 = ""
        tamam = true
    }
}
