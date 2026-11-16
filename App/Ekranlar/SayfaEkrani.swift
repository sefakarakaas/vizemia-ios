import SwiftUI
import VizeMiaCekirdek

/// Ülke rehberi, blog yazısı ya da kurumsal sayfa. İçerik siteden gelir;
/// sitedeki sayfayla aynı bölümler, aynı sırayla çizilir.
struct SayfaEkrani: View {
    var yol: String
    @Environment(IcerikDeposu.self) private var icerik

    var body: some View {
        if let s = icerik.akis.sayfa(yol) {
            SayfaGovdesi(sayfa: s)
        } else {
            // İçerik yenilenirken sayfa kalkmış olabilir (yayından alınan yazı).
            ContentUnavailableView("Sayfa bulunamadı", systemImage: "doc.questionmark",
                                   description: Text("Bu içerik artık yayında değil."))
        }
    }
}

struct SayfaGovdesi: View {
    var sayfa: Sayfa

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !sayfa.gorsel.isEmpty {
                    UzakGorsel(yol: sayfa.gorsel)
                        .frame(height: 220)
                        .accessibilityLabel(sayfa.alt)
                }
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sayfa.tur == "ulke" ? "Ülke rehberi" : sayfa.tur == "yazi" ? "Blog" : "VizeMia").ustBaslik()
                        Text(sayfa.baslik)
                            .font(.vitrin(28))
                            .foregroundStyle(Tema.lacivert)
                            .accessibilityAddTraits(.isHeader)
                        if !meta.isEmpty {
                            Text(meta).font(.caption).foregroundStyle(Tema.silik)
                        }
                    }
                    ForEach(Array(sayfa.bloklar.enumerated()), id: \.offset) { _, blok in
                        BlokGorunumu(blok: blok)
                    }
                    if sayfa.tur != "kurumsal" { ResmiDegilUyarisi() }
                }
                .padding(Tema.bosluk)
            }
        }
        .background(Tema.zemin.ignoresSafeArea())
        .navigationTitle(sayfa.ad)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: URL(string: Hedef.site.absoluteString + sayfa.yol) ?? Hedef.site) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Paylaş")
            }
        }
    }

    private var meta: String {
        var p: [String] = []
        if !sayfa.tarih.isEmpty { p.append(Tr.uzunTarih(sayfa.tarih)) }
        if !sayfa.guncelleme.isEmpty { p.append("Son güncelleme: \(Tr.uzunTarih(sayfa.guncelleme))") }
        return p.joined(separator: " · ")
    }
}

struct BlokGorunumu: View {
    var blok: Blok

    var body: some View {
        switch blok {
        case .metin(let md):
            MarkdownMetin(md: md)

        case .ozet(let md):
            (Text("Kısaca: ").fontWeight(.heavy).foregroundStyle(Tema.lacivert) + Text(AttributedString(md: md)).foregroundStyle(Tema.govde))
                .font(.subheadline)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tema.soluk, in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Tema.turkuaz).frame(width: 4)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }

        case .cta(let baslik, let metin, let ulke):
            BasvurKutusu(baslik: baslik, metin: metin, ulke: ulke)

        case .tablo(let baslik, let satirlar, let not):
            VStack(alignment: .leading, spacing: 10) {
                if !baslik.isEmpty {
                    Text(baslik).font(.title3.weight(.heavy)).foregroundStyle(Tema.lacivert).accessibilityAddTraits(.isHeader)
                }
                VStack(spacing: 0) {
                    ForEach(Array(satirlar.enumerated()), id: \.offset) { i, satir in
                        if satir.count >= 2 {
                            HStack(alignment: .firstTextBaseline) {
                                Text(satir[0]).font(.subheadline).foregroundStyle(Tema.govde)
                                Spacer(minLength: 12)
                                Text(satir[1]).font(.subheadline.weight(.heavy)).foregroundStyle(Tema.lacivert)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(i % 2 == 0 ? Tema.zeminYumusak : Tema.zemin)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous).stroke(Tema.soluk, lineWidth: 1))
                if !not.isEmpty {
                    Text(AttributedString(md: not)).font(.caption).foregroundStyle(Tema.govde)
                }
            }

        case .karsilastirma(let baslik, let sutunlar, let satirlar, let not):
            VStack(alignment: .leading, spacing: 10) {
                if !baslik.isEmpty {
                    Text(baslik).font(.title3.weight(.heavy)).foregroundStyle(Tema.lacivert).accessibilityAddTraits(.isHeader)
                }
                // Dar ekranda tablo kendi içinde yana kayar.
                ScrollView(.horizontal, showsIndicators: true) {
                    Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            ForEach(Array(sutunlar.enumerated()), id: \.offset) { _, s in
                                Text(s)
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .frame(width: 150, alignment: .topLeading)
                                    .frame(maxHeight: .infinity, alignment: .topLeading)
                                    .background(Tema.lacivert)
                            }
                        }
                        ForEach(Array(satirlar.enumerated()), id: \.offset) { i, satir in
                            GridRow {
                                ForEach(Array(satir.enumerated()), id: \.offset) { j, hucre in
                                    Text(hucre)
                                        .font(j == 0 ? .caption.weight(.bold) : .caption)
                                        .foregroundStyle(j == 0 ? Tema.lacivert : Tema.govde)
                                        .padding(10)
                                        .frame(width: 150, alignment: .topLeading)
                                        .frame(maxHeight: .infinity, alignment: .topLeading)
                                        .background(i % 2 == 0 ? Tema.zeminYumusak : Tema.zemin)
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
                }
                if !not.isEmpty {
                    Text(AttributedString(md: not)).font(.caption).foregroundStyle(Tema.govde)
                }
            }

        case .acilir(let baslik, let ogeler):
            VStack(alignment: .leading, spacing: 10) {
                if !baslik.isEmpty {
                    Text(baslik).font(.title3.weight(.heavy)).foregroundStyle(Tema.lacivert).accessibilityAddTraits(.isHeader)
                }
                ForEach(Array(ogeler.enumerated()), id: \.offset) { _, o in
                    AcilirKutu(baslik: o.baslik, md: o.md)
                }
            }

        case .kaynaklar(let ogeler):
            VStack(alignment: .leading, spacing: 8) {
                Text("Resmî kaynaklar").font(.headline).foregroundStyle(Tema.lacivert)
                ForEach(Array(ogeler.enumerated()), id: \.offset) { _, o in
                    if o.count >= 2, let u = URL(string: o[1]) {
                        Link(destination: u) {
                            Label(o[0], systemImage: "arrow.up.right.square")
                                .font(.subheadline)
                                .foregroundStyle(Tema.mavi)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .kartSoluk(dolgu: 14)

        case .bilinmeyen:
            EmptyView()
        }
    }
}
