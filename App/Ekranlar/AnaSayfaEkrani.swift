import SwiftUI
import VizeMiaCekirdek

/// Ana sayfa: sitedeki sırayla vitrin, hızlı işlemler, ülkeler, rehberler,
/// süreç, SSS, blog ve iletişim.
struct AnaSayfaEkrani: View {
    @Environment(IcerikDeposu.self) private var icerik
    @Environment(Gezinti.self) private var gezinti

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VitrinGorunumu(slaytlar: icerik.vitrin)

                VStack(spacing: 28) {
                    hizliIslemler
                    MesaiSeridi()
                    kitalar
                    rehberler
                    surec
                    sss
                    blog
                    IletisimKarti()
                }
                .padding(.horizontal, Tema.bosluk)
                .padding(.bottom, 32)
            }
        }
        .ekranZemini()
        .refreshable { await icerik.yenile() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
                    .accessibilityLabel("VizeMia")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    gezinti.ara(icerik.iletisim, mesai: icerik.mesai)
                } label: {
                    Image(systemName: "phone.fill")
                }
                .accessibilityLabel("VizeMia'yı arayın: \(icerik.iletisim.telefonGorunen)")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Tema.zemin, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Bölümler

    private var hizliIslemler: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            HizliKutu(baslik: "Başvur", alt: "Sizi arayalım", simge: "phone.arrow.down.left.fill", dolu: true) {
                gezinti.ac(.basvuru(ulke: ""))
            }
            HizliKutu(baslik: "Başvuru takibi", alt: "Kod ve pasaportla", simge: "doc.text.magnifyingglass") {
                gezinti.ac(.takip)
            }
            HizliKutu(baslik: "Harç & Kur", alt: "Güncel tutarlar", simge: "eurosign.circle.fill") {
                gezinti.ac(.harclar)
            }
            HizliKutu(baslik: "WhatsApp", alt: "Hemen yazın", simge: "message.fill") {
                gezinti.whatsapp(icerik.iletisim)
            }
        }
    }

    private var kitalar: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ülkeler").ustBaslik()
                Text("Nereye gidiyorsunuz?").bolumBasligi()
                Text("Türk pasaportuyla vize gereken ülkeler. Ülkeyi seçin, sizi arayıp süreci anlatalım.").govdeMetni()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(icerik.akis.kitalar) { kita in
                    NavigationLink(value: Rota.ulkeler) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(kita.ulkeler.prefix(4).map { $0.bayrak }.joined(separator: " "))
                                .font(.title3)
                            Text(kita.ad).font(.headline).foregroundStyle(Tema.lacivert)
                            Text("\(kita.ulkeler.count) ülke").font(.caption).foregroundStyle(Tema.govde)
                        }
                        .kart(dolgu: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var rehberler: some View {
        let liste = icerik.akis.ulkeRehberleri
        if !liste.isEmpty {
            VStack(spacing: 14) {
                BolumBasi(ust: "Ülke rehberleri", baslik: "Evrak, süre ve harç", tumu: .rehberler)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(liste) { s in
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
                                .frame(width: 180, height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Tema.bosluk)
                }
                .padding(.horizontal, -Tema.bosluk)
            }
        }
    }

    @ViewBuilder private var surec: some View {
        if let s = icerik.akis.surec {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Süreç").ustBaslik()
                    Text(s.baslik).bolumBasligi()
                    if !s.aciklama.isEmpty { Text(s.aciklama).govdeMetni() }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(s.adimlar.enumerated()), id: \.offset) { i, adim in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 0) {
                                Text("\(i + 1)")
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Tema.lacivert, in: Circle())
                                if i < s.adimlar.count - 1 {
                                    Rectangle().fill(Tema.soluk).frame(width: 2).frame(maxHeight: .infinity)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(adim.baslik).font(.headline).foregroundStyle(Tema.lacivert)
                                if !adim.metin.isEmpty { Text(adim.metin).govdeMetni() }
                            }
                            .padding(.bottom, 18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // Soldaki çizgi, sağdaki metnin yüksekliği kadar uzasın.
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .kart()
            }
        }
    }

    @ViewBuilder private var sss: some View {
        let sorular = icerik.akis.sss
        if !sorular.isEmpty {
            VStack(spacing: 12) {
                BolumBasi(ust: "Destek", baslik: "Sıkça sorulan sorular", tumu: sorular.count > 4 ? .sss : nil)
                ForEach(sorular.prefix(4)) { s in
                    AcilirKutu(baslik: s.soru, md: s.cevap)
                }
            }
        }
    }

    @ViewBuilder private var blog: some View {
        let yazilar = icerik.akis.yazilar
        if !yazilar.isEmpty {
            VStack(spacing: 12) {
                BolumBasi(ust: "Blog", baslik: "Vize rehberi", tumu: .blog)
                ForEach(yazilar.prefix(3)) { y in
                    NavigationLink(value: Rota.sayfa(y.yol)) { YaziSatiri(sayfa: y) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Bölüm başlığı ve sağında "Tümü" bağlantısı.
struct BolumBasi: View {
    var ust: String
    var baslik: String
    var tumu: Rota?

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ust).ustBaslik()
                Text(baslik).bolumBasligi()
            }
            if let r = tumu {
                NavigationLink(value: r) {
                    Text("Tümü").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.mavi)
                }
            }
        }
    }
}

struct HizliKutu: View {
    var baslik: String
    var alt: String
    var simge: String
    var dolu = false
    var islem: () -> Void

    var body: some View {
        Button(action: islem) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: simge)
                    .font(.title2)
                    .foregroundStyle(dolu ? Tema.turkuaz : Tema.lacivert)
                VStack(alignment: .leading, spacing: 2) {
                    Text(baslik).font(.headline).foregroundStyle(dolu ? Color.white : Tema.lacivert)
                    Text(alt).font(.caption).foregroundStyle(dolu ? Color.white.opacity(0.8) : Tema.govde)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(dolu ? Tema.lacivert : Tema.zemin, in: RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tema.kose, style: .continuous).stroke(dolu ? Tema.lacivert : Tema.soluk, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// "Şu an açığız" / "kapalıyız" satırı.
struct MesaiSeridi: View {
    @Environment(IcerikDeposu.self) private var icerik

    var body: some View {
        // Dakikada bir yenilenir: açılış/kapanış anında ekran kendiliğinden değişsin.
        TimelineView(.periodic(from: .now, by: 60)) { zaman in
            let mesai = icerik.mesai
            let acik = mesai.acikMi(zaman.date)
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(acik ? Tema.olumlu : Tema.silik)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(acik ? "Şu an açığız" : "Şu an kapalıyız · \(mesai.sonrakiAcilis(zaman.date).metin) açılıyoruz")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tema.lacivert)
                    Text(mesai.metin()).font(.caption).foregroundStyle(Tema.govde)
                }
                Spacer(minLength: 0)
            }
            .kart(dolgu: 12)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Blog listesindeki satır: küçük görsel, başlık, özet.
struct YaziSatiri: View {
    var sayfa: Sayfa

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !sayfa.gorsel.isEmpty {
                UzakGorsel(yol: sayfa.gorsel)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(sayfa.baslik)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Tema.lacivert)
                    .multilineTextAlignment(.leading)
                if !sayfa.ozet.isEmpty {
                    Text(sayfa.ozet).font(.caption).foregroundStyle(Tema.govde).lineLimit(3).multilineTextAlignment(.leading)
                }
                if !sayfa.tarih.isEmpty {
                    Text(Tr.uzunTarih(sayfa.tarih)).font(.caption2).foregroundStyle(Tema.silik)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Tema.silik).padding(.top, 4)
        }
        .kart(dolgu: 12)
    }
}

/// Adres, mesai ve iletişim düğmeleri.
struct IletisimKarti: View {
    @Environment(IcerikDeposu.self) private var icerik
    @Environment(Gezinti.self) private var gezinti

    var body: some View {
        let i = icerik.iletisim
        VStack(alignment: .leading, spacing: 12) {
            Text("İletişim").ustBaslik()
            Text("Ankara ofisimiz").bolumBasligi()
            Label(i.adres, systemImage: "mappin.and.ellipse").govdeMetni()
            Label(icerik.mesai.metin(), systemImage: "clock").govdeMetni()
            Label(i.telefonGorunen, systemImage: "phone").govdeMetni()
            IletisimDugmeleri()
            HStack(spacing: 10) {
                Button {
                    gezinti.yolTarifi(i)
                } label: {
                    Label("Yol tarifi", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(IkincilDugme())
                NavigationLink(value: Rota.iletisim) {
                    Label("Harita", systemImage: "map.fill")
                }
                .buttonStyle(IkincilDugme())
            }
        }
        .kart()
    }
}

// MARK: - Vitrin

/// Ana sayfadaki kayan slaytlar (panel → Vitrin). 6 saniyede bir kayar;
/// cihazda "hareketi azalt" açıksa kendiliğinden kaymaz.
struct VitrinGorunumu: View {
    var slaytlar: [Slayt]
    @State private var secili = 0
    @Environment(\.accessibilityReduceMotion) private var hareketAz
    @Environment(\.scenePhase) private var sahne
    @Environment(\.openURL) private var ac

    var body: some View {
        if slaytlar.isEmpty {
            EmptyView()
        } else {
            TabView(selection: $secili) {
                ForEach(Array(slaytlar.enumerated()), id: \.element.id) { i, s in
                    slayt(s).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: slaytlar.count > 1 ? .always : .never))
            .frame(height: 430)
            .task(id: "\(slaytlar.count)-\(hareketAz)-\(sahne == .active)") {
                guard slaytlar.count > 1, !hareketAz, sahne == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(6))
                    if Task.isCancelled { break }
                    withAnimation(.easeInOut(duration: 0.5)) { secili = (secili + 1) % slaytlar.count }
                }
            }
            .onChange(of: slaytlar.count) { _, _ in secili = 0 }
        }
    }

    private func slayt(_ s: Slayt) -> some View {
        ZStack(alignment: .bottomLeading) {
            UzakGorsel(yol: s.gorsel, odak: UnitPoint(x: s.odakNoktasi.x, y: s.odakNoktasi.y))
            LinearGradient(
                colors: [Tema.lacivertKoyu.opacity(0.15), Tema.lacivertKoyu.opacity(0.55), Tema.lacivertKoyu.opacity(0.92)],
                startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                if !s.ust.isEmpty { Text(s.ust).ustBaslik() }
                Text(s.baslik)
                    .font(.vitrin(30))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                if !s.metin.isEmpty {
                    Text(s.metin).font(.body).foregroundStyle(.white.opacity(0.9))
                }
                if !s.link.isEmpty, !s.dugme.isEmpty, let hedef = baglanti(s.link) {
                    Button(s.dugme) { ac(hedef) }
                        .buttonStyle(AnaDugme(renk: Tema.turkuaz, tamGenislik: false))
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func baglanti(_ link: String) -> URL? {
        URL(string: link.hasPrefix("/") ? Hedef.site.absoluteString + link : link)
    }
}
