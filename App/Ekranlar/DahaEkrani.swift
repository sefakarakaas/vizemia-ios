import SwiftUI
import MapKit
import VizeMiaCekirdek

/// Sitenin alt menüsündeki sayfalar: rehberler, blog, SSS, destek, iletişim, kurumsal.
struct DahaEkrani: View {
    @Environment(IcerikDeposu.self) private var icerik
    @Environment(Gezinti.self) private var gezinti

    var body: some View {
        List {
            Section("Rehber") {
                NavigationLink(value: Rota.rehberler) { Label("Ülke rehberleri", systemImage: "globe.europe.africa.fill") }
                NavigationLink(value: Rota.ulkeler) { Label("Vize gereken ülkeler", systemImage: "list.bullet") }
                NavigationLink(value: Rota.blog) { Label("Blog", systemImage: "book.fill") }
                NavigationLink(value: Rota.sss) { Label("Sıkça sorulan sorular", systemImage: "questionmark.circle.fill") }
            }
            Section("Bize ulaşın") {
                NavigationLink(value: Rota.destek(kod: "")) { Label("Destek formu", systemImage: "envelope.fill") }
                NavigationLink(value: Rota.iletisim) { Label("İletişim ve harita", systemImage: "mappin.and.ellipse") }
                Button {
                    gezinti.whatsapp(icerik.iletisim)
                } label: {
                    Label("WhatsApp'tan yazın", systemImage: "message.fill")
                }
                Button {
                    gezinti.ara(icerik.iletisim, mesai: icerik.mesai)
                } label: {
                    Label("Arayın: \(icerik.iletisim.telefonGorunen)", systemImage: "phone.fill")
                }
            }
            Section("VizeMia") {
                if icerik.akis.sayfa("/hakkimizda") != nil {
                    NavigationLink(value: Rota.sayfa("/hakkimizda")) { Label("Hakkımızda", systemImage: "building.2.fill") }
                }
                Button {
                    gezinti.ac(link: "/gizlilik", sayfaYollari: icerik.sayfaYollari)
                } label: {
                    Label("Gizlilik ve KVKK", systemImage: "lock.shield.fill")
                }
                Button {
                    if let u = URL(string: icerik.iletisim.instagram) { gezinti.disAc(u) }
                } label: {
                    Label("Instagram: @vizemiacom", systemImage: "camera.fill")
                }
                Button {
                    if let u = URL(string: icerik.iletisim.googleProfil) { gezinti.disAc(u) }
                } label: {
                    Label("Google'da değerlendirin", systemImage: "star.fill")
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(icerik.iletisim.unvan)
                    Text("Ankara, Türkiye · Sürüm \(surum)")
                    Text("VizeMia resmî bir kurum değildir; vize kararını yalnız ilgili ülkenin makamları verir.")
                }
                .font(.caption)
                .foregroundStyle(Tema.govde)
                .listRowBackground(Color.clear)
            }
        }
        .foregroundStyle(Tema.lacivert)
        .navigationTitle("Daha")
    }

    private var surum: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}

/// Blog: rehber yazıları ve panelden yayımlanan yazılar.
struct BlogEkrani: View {
    @Environment(IcerikDeposu.self) private var icerik

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Blog").ustBaslik()
                    Text("Vize rehberi").bolumBasligi()
                    Text("Başvuru öncesi bilmeniz gerekenleri anlatan rehber yazılarımız.").govdeMetni()
                }
                ForEach(icerik.akis.yazilar) { y in
                    NavigationLink(value: Rota.sayfa(y.yol)) { YaziSatiri(sayfa: y) }
                        .buttonStyle(.plain)
                }
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("Blog")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await icerik.yenile() }
    }
}

/// Ülke rehberleri.
struct RehberlerEkrani: View {
    @Environment(IcerikDeposu.self) private var icerik

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(icerik.akis.ulkeRehberleri) { s in
                    NavigationLink(value: Rota.sayfa(s.yol)) {
                        ZStack(alignment: .bottomLeading) {
                            UzakGorsel(yol: s.gorsel)
                            LinearGradient(colors: [.clear, Tema.lacivertKoyu.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                            Text(s.baslik)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .padding(12)
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("Ülke rehberleri")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Türk pasaportuyla vize gereken ülkeler. Rehberi olan ülkede rehber açılır;
/// olmayanda başvuru formu o ülke seçili gelir.
struct UlkelerEkrani: View {
    @Environment(IcerikDeposu.self) private var icerik
    @Environment(Gezinti.self) private var gezinti
    @State private var arama = ""

    var body: some View {
        List {
            ForEach(icerik.akis.kitalar) { kita in
                let liste = suz(kita.ulkeler)
                if !liste.isEmpty {
                    Section {
                        ForEach(liste) { u in
                            Button {
                                if let r = icerik.rehber(ulke: u.slug) {
                                    gezinti.it(.sayfa(r.yol))
                                } else {
                                    gezinti.ac(.basvuru(ulke: u.slug))
                                }
                            } label: {
                                HStack {
                                    Text(u.bayrak)
                                    Text(u.ad).foregroundStyle(Tema.lacivert)
                                    Spacer()
                                    Text(icerik.rehber(ulke: u.slug) != nil ? "Rehber" : "Başvur")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Tema.mavi)
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
                                }
                            }
                        }
                    } header: {
                        Text(kita.ad)
                    } footer: {
                        Text(kita.not)
                    }
                }
            }
            Section {
                Text("Yalnız Türk pasaportuyla vize gereken ülkeler listelenir. Vize kuralları sık değişir; bu liste yol göstericidir, resmî kaynak değildir.")
                    .font(.caption)
                    .foregroundStyle(Tema.govde)
                    .listRowBackground(Color.clear)
            }
        }
        .searchable(text: $arama, prompt: "Ülke ara")
        .navigationTitle("Ülkeler")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func suz(_ ulkeler: [Ulke]) -> [Ulke] {
        let q = arama.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return ulkeler }
        let ara = Harf.latinBuyuk(q)
        return ulkeler.filter { Harf.latinBuyuk($0.ad).contains(ara) }
    }
}

/// Sıkça sorulan sorular: ana sayfadakiler ve panelden yayımlananlar.
struct SssEkrani: View {
    @Environment(IcerikDeposu.self) private var icerik

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Destek").ustBaslik()
                    Text("Sıkça sorulan sorular").bolumBasligi()
                }
                ForEach(icerik.akis.sss) { s in
                    AcilirKutu(baslik: s.soru, md: s.cevap)
                }
                BasvurKutusu(baslik: "Sorunuzun cevabı burada yok mu?",
                             metin: "Bilgilerinizi bırakın, uygun saatinizde sizi arayıp sorularınızı cevaplayalım.")
                    .padding(.top, 8)
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("SSS")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Destek formu (sitedeki /destek). Panelde Destek talepleri'ne düşer.
struct DestekEkrani: View {
    var kod: String
    @State private var form = DestekFormu()
    @State private var hata: String?
    @State private var gonderiliyor = false
    @State private var gonderildi = false
    @State private var sonGonderim: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if gonderildi {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Tema.olumlu)
                        Text("Talebiniz bize ulaştı.").font(.title2.weight(.heavy)).foregroundStyle(Tema.olumluKoyu)
                        Text("En kısa sürede e-posta adresinizden size dönüş yapacağız.").font(.subheadline).foregroundStyle(Tema.govde)
                    }
                    .padding(Tema.bosluk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tema.olumlu.opacity(0.12), in: RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Destek").ustBaslik()
                        Text("Bize yazın").bolumBasligi()
                        Text("Sorunuzu yazın; e-posta adresinizden size dönüş yapalım.").govdeMetni()
                    }
                    VStack(spacing: 16) {
                        Alan(etiket: "Adınız *") {
                            TextField("", text: $form.ad).textContentType(.name).kutu()
                        }
                        Alan(etiket: "E-posta *") {
                            TextField("", text: $form.eposta)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .kutu()
                        }
                        Alan(etiket: "Telefon", istegeBagli: true) {
                            TextField("", text: $form.telefon).textContentType(.telephoneNumber).keyboardType(.phonePad).kutu()
                        }
                        Alan(etiket: "Takip kodu", istegeBagli: true) {
                            TextField("2026-091234", text: $form.takipKodu).keyboardType(.numbersAndPunctuation).kutu()
                        }
                        Alan(etiket: "Konu *") {
                            TextField("", text: $form.konu).kutu()
                        }
                        Alan(etiket: "Mesajınız *") {
                            TextField("", text: $form.mesaj, axis: .vertical).lineLimit(5...10).kutu()
                        }
                        IsaretKutusu(secili: $form.onay, metin: "Bilgilerimin destek talebimin yanıtlanması amacıyla işlenmesini kabul ediyorum. *")
                        if let h = hata { HataMetni(metin: h) }
                        Button {
                            Task { await gonder() }
                        } label: {
                            if gonderiliyor {
                                HStack(spacing: 8) { ProgressView().tint(.white); Text("Gönderiliyor…") }
                            } else {
                                Text("Gönder")
                            }
                        }
                        .buttonStyle(AnaDugme())
                        .disabled(gonderiliyor)
                    }
                    .kart()
                }
            }
            .padding(Tema.bosluk)
        }
        .scrollDismissesKeyboard(.interactively)
        .ekranZemini()
        .navigationTitle("Destek")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if form.takipKodu.isEmpty, kod.range(of: "^[0-9]{4}-[0-9]{6}$", options: .regularExpression) != nil {
                form.takipKodu = kod
            }
        }
    }

    private func gonder() async {
        hata = nil
        if let h = form.hata { hata = h; return }
        if let son = sonGonderim, Date().timeIntervalSince(son) < 60 {
            hata = "Az önce bir talep gönderdiniz. Lütfen bir dakika bekleyin."
            return
        }
        gonderiliyor = true
        defer { gonderiliyor = false }
        do {
            try await FirestoreIstemci().ekle(koleksiyon: "support", alanlar: form.alanlar)
            sonGonderim = Date()
            withAnimation { gonderildi = true }
        } catch {
            hata = "Talebiniz gönderilemedi. Lütfen daha sonra tekrar deneyin."
        }
    }
}

/// İletişim: adres, harita, çalışma saatleri.
struct IletisimEkrani: View {
    @Environment(IcerikDeposu.self) private var icerik
    @Environment(Gezinti.self) private var gezinti

    var body: some View {
        let i = icerik.iletisim
        let konum = CLLocationCoordinate2D(latitude: i.enlem, longitude: i.boylam)
        ScrollView {
            VStack(spacing: 16) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: konum, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))) {
                    Marker("VizeMia", coordinate: konum).tint(Tema.lacivert)
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("VizeMia Ankara ofisi").font(.headline).foregroundStyle(Tema.lacivert)
                    Label(i.adres, systemImage: "mappin.and.ellipse").govdeMetni()
                    Label(i.telefonGorunen, systemImage: "phone").govdeMetni()
                    Label(i.eposta, systemImage: "envelope").govdeMetni()
                    Label(icerik.mesai.metin(), systemImage: "clock").govdeMetni()
                    Button {
                        gezinti.yolTarifi(i)
                    } label: {
                        Label("Yol tarifi al", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(AnaDugme())
                    Button {
                        if let u = URL(string: i.googleProfil) { gezinti.disAc(u) }
                    } label: {
                        Label("Google Haritalar'da aç", systemImage: "map.fill")
                    }
                    .buttonStyle(IkincilDugme())
                    IletisimDugmeleri()
                    Button {
                        gezinti.eposta(i)
                    } label: {
                        Label("E-posta yazın", systemImage: "envelope.fill")
                    }
                    .buttonStyle(IkincilDugme())
                }
                .kart()
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("İletişim")
        .navigationBarTitleDisplayMode(.inline)
    }
}
