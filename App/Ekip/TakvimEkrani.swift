import SwiftUI
import VizeMiaCekirdek

/// Takvim: aranacak talepler, randevular, tekrar aramalar (panel: #/takvim).
struct TakvimEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var veri
    @State private var secili = Mesai.trSimdi().iso
    @State private var ayGorunumu = false
    @State private var turlar: Set<TakvimIsi.Tur> = Set(TakvimIsi.Tur.allCases)
    @State private var bilgi: TakvimIsi?

    private var gorunen: [TakvimIsi] { veri.takvim.filter { turlar.contains($0.tur) } }
    private func gunun(_ g: String) -> [TakvimIsi] { TakvimIsi.sirala(gorunen.filter { $0.gun == g }) }

    var body: some View {
        Group {
            if !(ekip.yapabilir("app.view") || ekip.yapabilir("lead.view")) {
                YetkiYok(ad: "Takvim")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Görünüm", selection: $ayGorunumu.animation(Hareket.yay)) {
                            Text("Gün").tag(false)
                            Text("Ay").tag(true)
                        }
                        .pickerStyle(.segmented)

                        if ayGorunumu { ayIzgarasi } else { gunSeridi }

                        turSecici

                        gunListesi
                    }
                    .padding(Tema.bosluk)
                }
                .ekranZemini()
                .refreshable { await veri.yukle(ekip, zorla: true) }
            }
        }
        .navigationTitle("Takvim")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bugün") { withAnimation(Hareket.yay) { secili = veri.bugun } }
                    .disabled(secili == veri.bugun)
            }
        }
        .task { await veri.yukle(ekip) }
        .sheet(item: $bilgi) { is_ in BasvuruOzetiSayfasi(is_: is_).presentationDetents([.medium]) }
    }

    // MARK: Gün şeridi (bugünden ± günler)

    private var gunSeridi: some View {
        ScrollViewReader { kaydir in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(-7..<29, id: \.self) { i in
                        let g = Tr.gunEkle(veri.bugun, i)
                        GunKutusu(gun: g, secili: g == secili, bugun: g == veri.bugun, sayi: gunun(g).count,
                                  gecikmeVar: gunun(g).contains { $0.gecikti })
                            .id(g)
                            .onTapGesture { withAnimation(Hareket.yay) { secili = g } }
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear { kaydir.scrollTo(secili, anchor: .center) }
            .onChange(of: secili) { _, g in withAnimation(Hareket.yay) { kaydir.scrollTo(g, anchor: .center) } }
        }
    }

    // MARK: Ay ızgarası

    private var ayIzgarasi: some View {
        let p = secili.split(separator: "-").compactMap { Int($0) }
        let yil = p.count == 3 ? p[0] : 2026, ay = p.count == 3 ? p[1] : 1
        let gunler = TakvimIsi.ayIzgarasi(yil: yil, ay: ay)
        let ayOnek = String(secili.prefix(7))
        return VStack(spacing: 10) {
            HStack {
                Button { ayDegistir(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text("\(Mesai.ayAdi[ay - 1]) \(yil)").font(.headline).foregroundStyle(Tema.lacivert)
                    .contentTransition(.numericText())
                Spacer()
                Button { ayDegistir(1) } label: { Image(systemName: "chevron.right") }
            }
            .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"], id: \.self) { g in
                    Text(g).font(.caption2.weight(.semibold)).foregroundStyle(Tema.silik)
                }
                ForEach(gunler, id: \.self) { g in
                    let n = gunun(g).count
                    VStack(spacing: 3) {
                        Text(String(Int(g.suffix(2)) ?? 0))
                            .font(.subheadline.weight(g == secili ? .heavy : .regular))
                            .foregroundStyle(g == secili ? Color.white : (g.hasPrefix(ayOnek) ? Tema.lacivert : Tema.silik))
                        Circle().fill(n > 0 ? (g == secili ? Color.white : Tema.turkuaz) : Color.clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(g == secili ? Tema.lacivert : (g == veri.bugun ? Tema.soluk : Color.clear),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(Hareket.yay) { secili = g } }
                    .accessibilityLabel("\(Mesai.gunMetni(g)), \(n) iş")
                }
            }
        }
        .kart(dolgu: 12)
    }

    private func ayDegistir(_ n: Int) {
        let p = secili.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return }
        var y = p[0], a = p[1] + n
        if a < 1 { a = 12; y -= 1 }
        if a > 12 { a = 1; y += 1 }
        withAnimation(Hareket.yay) { secili = Tr.iso(yil: y, ay: a, gun: 1) }
    }

    // MARK: Türler

    private var turSecici: some View {
        HStack(spacing: 8) {
            ForEach(TakvimIsi.Tur.allCases, id: \.self) { t in
                let acik = turlar.contains(t)
                Button {
                    withAnimation(Hareket.yay) { if acik { turlar.remove(t) } else { turlar.insert(t) } }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(TakvimEkrani.renk(t)).frame(width: 8, height: 8)
                        Text(t.ad).font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(acik ? Tema.lacivert : Tema.silik)
                    .background(acik ? Tema.zemin : Tema.zeminYumusak, in: Capsule())
                    .overlay(Capsule().stroke(acik ? Tema.soluk : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    static func renk(_ t: TakvimIsi.Tur) -> Color {
        switch t {
        case .arama: return Tema.turkuaz
        case .randevu: return Color(hex: 0x5a4f9c)
        case .tekrar: return Color(hex: 0xb36b00)
        }
    }

    // MARK: Günün işleri

    private var gunListesi: some View {
        let isler = gunun(secili)
        return VStack(alignment: .leading, spacing: 10) {
            Text(baslik(secili)).font(.headline).foregroundStyle(Tema.lacivert)
                .contentTransition(.opacity)
            if isler.isEmpty {
                Text(veri.yukleniyor ? "Yükleniyor…" : "Bu gün için planlanmış iş yok.")
                    .font(.subheadline).foregroundStyle(Tema.govde)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kart()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(isler.enumerated()), id: \.element.id) { i, x in
                        isSatiri(x)
                        if i < isler.count - 1 { Divider().padding(.leading, 70) }
                    }
                }
                .kart(dolgu: 0)
                .id(secili)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Hareket.yay, value: secili)
    }

    @ViewBuilder private func isSatiri(_ x: TakvimIsi) -> some View {
        let govde = HStack(alignment: .top, spacing: 12) {
            Text(x.saat.isEmpty ? "Gün içi" : x.saat)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(x.gecikti ? Color(hex: 0xb36b00) : Tema.lacivert)
                .frame(width: 50, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(TakvimEkrani.renk(x.tur)).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(x.baslik).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                Text([x.tur.ad, x.alt].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Tema.govde)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
        }
        .padding(12)
        .opacity(x.onemli ? 1 : 0.85)
        .contentShape(Rectangle())

        if x.bag.hasPrefix("talep:") {
            NavigationLink(value: EkipRota.talep(String(x.bag.dropFirst(6)))) { govde }.buttonStyle(.plain)
        } else {
            Button { bilgi = x } label: { govde }.buttonStyle(.plain)
        }
    }

    private func baslik(_ g: String) -> String {
        if g == veri.bugun { return "Bugün · \(Tr.uzunTarih(g))" }
        if g == Tr.gunEkle(veri.bugun, 1) { return "Yarın · \(Tr.uzunTarih(g))" }
        return "\(Mesai.gunAdi[Tr.gunNo(g)]) · \(Tr.uzunTarih(g))"
    }
}

struct GunKutusu: View {
    let gun: String
    let secili: Bool
    let bugun: Bool
    let sayi: Int
    let gecikmeVar: Bool

    var body: some View {
        let p = gun.split(separator: "-").compactMap { Int($0) }
        VStack(spacing: 3) {
            Text(bugun ? "Bugün" : Mesai.gunKisa[Tr.gunNo(gun)]).font(.caption2.weight(.semibold))
            Text(p.count == 3 ? "\(p[2])" : "").font(.title3.weight(.heavy))
            HStack(spacing: 2) {
                if sayi > 0 {
                    Text("\(sayi)").font(.caption2.weight(.bold))
                } else {
                    Text(" ").font(.caption2)
                }
            }
            .foregroundStyle(secili ? Color.white : (gecikmeVar ? Color(hex: 0xb36b00) : Tema.turkuaz))
        }
        .foregroundStyle(secili ? Color.white : Tema.lacivert)
        .frame(width: 56, height: 74)
        .background(secili ? Tema.lacivert : Tema.zemin, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(bugun && !secili ? Tema.turkuaz : Tema.soluk, lineWidth: bugun && !secili ? 1.5 : 1))
        .scaleEffect(secili ? 1.04 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(secili ? .isSelected : [])
    }
}

/// Randevu / tekrar arama: başvuru ekranı gelene kadar kısa bilgi.
struct BasvuruOzetiSayfasi: View {
    let is_: TakvimIsi

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Etiket(metin: is_.tur.ad, renk: TakvimEkrani.renk(is_.tur))
            Text(is_.baslik).font(.title2.weight(.heavy)).foregroundStyle(Tema.lacivert)
            Text([Tr.uzunTarih(is_.gun), is_.saat].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline.weight(.semibold)).foregroundStyle(Tema.govde)
            if !is_.alt.isEmpty { Text(is_.alt).font(.subheadline).foregroundStyle(Tema.govde) }
            Text("Başvuru ayrıntısı, Başvurular bölümüyle birlikte uygulamaya gelecek.")
                .font(.caption).foregroundStyle(Tema.silik)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
