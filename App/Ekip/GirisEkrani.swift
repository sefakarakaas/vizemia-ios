import SwiftUI
import VizeMiaCekirdek

/// Çalışan girişi: panelin kullanıcı adı ve şifresi. Bir kez girilir.
struct GirisEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(\.dismiss) private var kapat
    @State private var ad = ""
    @State private var sifre = ""
    @State private var hata: String?
    @State private var bekliyor = false
    @FocusState private var odak: Kutu?

    private enum Kutu { case ad, sifre }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 46)
                        .padding(.top, 24)
                        .belirme(0)
                    VStack(spacing: 6) {
                        Text("Çalışan girişi").font(.title2.weight(.heavy)).foregroundStyle(Tema.lacivert)
                        Text("Paneldeki kullanıcı adınız ve şifrenizle girin. Bu telefonda hatırlanır.")
                            .font(.subheadline).foregroundStyle(Tema.govde).multilineTextAlignment(.center)
                    }
                    .belirme(1)

                    VStack(spacing: 14) {
                        Alan(etiket: "Kullanıcı adı") {
                            TextField("ör. sefa", text: $ad)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($odak, equals: .ad)
                                .submitLabel(.next)
                                .onSubmit { odak = .sifre }
                                .accessibilityIdentifier("giris-ad")
                                .kutu()
                        }
                        Alan(etiket: "Şifre") {
                            SecureField("", text: $sifre)
                                .textContentType(.password)
                                .focused($odak, equals: .sifre)
                                .submitLabel(.go)
                                .onSubmit { Task { await gir() } }
                                .accessibilityIdentifier("giris-sifre")
                                .kutu()
                        }
                        if let h = hata {
                            HataMetni(metin: h).transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        Button {
                            Task { await gir() }
                        } label: {
                            if bekliyor {
                                HStack(spacing: 8) { ProgressView().tint(.white); Text("Giriş yapılıyor…") }
                            } else {
                                Text("Giriş yap")
                            }
                        }
                        .buttonStyle(AnaDugme())
                        .disabled(bekliyor)
                    }
                    .kart()
                    .belirme(2)
                }
                .padding(Tema.bosluk)
                .animation(Hareket.yay, value: hata)
            }
            .formKlavyesi()
            .ekranZemini()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
            }
            .onAppear { odak = .ad }
        }
    }

    private func gir() async {
        hata = nil
        guard !ad.kirpik.isEmpty, !sifre.isEmpty else {
            hata = "Kullanıcı adı ve şifre gerekli."
            return
        }
        bekliyor = true
        defer { bekliyor = false }
        do {
            try await ekip.giris(kullaniciAdi: ad, sifre: sifre)
            sifre = ""
            kapat()
        } catch let h as KimlikIstemci.Hata {
            hata = h.mesaj
        } catch let h as FirestoreHatasi {
            hata = h.mesaj
        } catch {
            hata = "Giriş yapılamadı. Lütfen yeniden deneyin."
        }
    }
}
