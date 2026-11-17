import SwiftUI
import VizeMiaCekirdek

/// Başvurular (panel: #/basvurular): arama, statü / ülke süzgeci, aranacaklar,
/// yakında silinecekler; aynı gruptakiler tek başlık altında.
struct BasvurularEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @State private var suzgec: BasvuruListesiVerisi.Suzgec = .hepsi
    @State private var ulke = ""
    @State private var arama = ""
    @State private var acikGruplar: Set<String> = []
    @State private var acilacak: String?

    private var veri: BasvuruListesiVerisi { ekipVerisi.basvurular }
    private var liste: [Basvuru] { veri.gorunen(terim: arama, ulke: ulke, statuler: ekip.statuSozlugu) }

    var body: some View {
        Group {
            if !ekip.yapabilir("app.view") {
                YetkiYok(ad: "Başvurular")
            } else {
                List {
                    Section { suzgecSatiri }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    if veri.bulunanlar != nil {
                        Section {
                            Button {
                                withAnimation(Hareket.yay) { veri.bulunanlariTemizle() }
                            } label: {
                                Label("Arama sonucu gösteriliyor · tüm liste", systemImage: "xmark.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    Section {
                        if let h = veri.hata { HataMetni(metin: h).listRowInsets(EdgeInsets()) }
                        if liste.isEmpty && veri.hata == nil {
                            Text(veri.yukleniyor ? "Yükleniyor…" : "Eşleşen başvuru bulunamadı.")
                                .font(.subheadline)
                                .foregroundStyle(Tema.govde)
                        }
                        ForEach(BasvuruListesi.grupla(liste)) { satir in
                            switch satir {
                            case .tek(let a):
                                basvuruSatiri(a, uye: false)
                            case let .grup(id, ad, uyeler):
                                grupBasligi(id: id, ad: ad, uyeler: uyeler)
                                if acikGruplar.contains(id) || !arama.isEmpty {
                                    ForEach(uyeler) { basvuruSatiri($0, uye: true) }
                                }
                            }
                        }
                    } header: {
                        Text(sayiMetni).font(.caption).foregroundStyle(Tema.govde).textCase(nil)
                    }
                    if !veri.bitti && veri.bulunanlar == nil && !liste.isEmpty {
                        Section {
                            Button {
                                Task { await veri.yukle(ekip, suzgec: suzgec, sifirla: false) }
                            } label: {
                                HStack {
                                    Spacer()
                                    if veri.yukleniyor { ProgressView() } else { Text("Daha fazla yükle").fontWeight(.semibold) }
                                    Spacer()
                                }
                            }
                            .disabled(veri.yukleniyor)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $arama, prompt: "Ad, takip kodu ya da pasaport")
                .onSubmit(of: .search) {
                    Task {
                        if let a = await veri.tamAra(arama, ekip: ekip) { acilacak = a.kimlik }
                    }
                }
                .refreshable { await veri.yukle(ekip, suzgec: suzgec) }
                .animation(Hareket.yay, value: liste.map(\.id))
                .navigationDestination(item: $acilacak) { BasvuruDetayi(kimlik: $0) }
            }
        }
        .navigationTitle("Başvurular")
        .toolbar {
            if ekip.yapabilir("app.create") {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: EkipRota.yeniBasvuru(talep: nil)) {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .accessibilityLabel("Yeni başvuru")
                }
            }
        }
        .task {
            // Ekrana dönülünce yeniden okunmaz (okuma kotası); süzgeç kaldığı yerden.
            if suzgec != veri.suzgec { suzgec = veri.suzgec }
            if veri.satirlar.isEmpty || veri.eskidi { await veri.yukle(ekip, suzgec: suzgec) }
        }
        .onChange(of: suzgec) { _, yeni in
            if yeni != veri.suzgec { Task { await veri.yukle(ekip, suzgec: yeni) } }
        }
    }

    private var sayiMetni: String {
        let n = liste.count
        return "\(n) başvuru" + (veri.bitti || veri.bulunanlar != nil ? "" : " (daha fazlası var)")
    }

    // MARK: Süzgeçler

    private var suzgecSatiri: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                cip("Tümü", secili: suzgec == .hepsi) { suzgec = .hepsi }
                if ekip.statuler.contains(where: \.tekrarAranir) {
                    cip("Aranacaklar", simge: "phone.arrow.up.right", secili: suzgec == .aranacak) { suzgec = .aranacak }
                }
                cip("Yakında silinecek", simge: "trash", secili: suzgec == .silinecek) { suzgec = .silinecek }
                Menu {
                    Button("Tüm statüler") { suzgec = .hepsi }
                    ForEach(ekip.statuler) { s in
                        Button(s.ad) { suzgec = .statu(s.id) }
                    }
                } label: {
                    cipGovde(statuAdi ?? "Statü", simge: "line.3.horizontal.decrease", secili: statuAdi != nil)
                }
                Menu {
                    Button("Tüm ülkeler") { ulke = "" }
                    ForEach(Array(ulkeler.enumerated()), id: \.offset) { _, u in
                        Button(u.1) { ulke = u.0 }
                    }
                } label: {
                    cipGovde(ulkeler.first { $0.0 == ulke }?.1 ?? "Ülke", simge: "globe.europe.africa", secili: !ulke.isEmpty)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var statuAdi: String? {
        if case .statu(let id) = suzgec { return ekip.statuSozlugu[id]?.ad ?? id }
        return nil
    }

    /// Yüklenen başvurulardaki ülkeler (ada göre).
    private var ulkeler: [(String, String)] {
        var gorulen: [String: String] = [:]
        for a in veri.bulunanlar ?? veri.satirlar where !a.ulke.isEmpty { gorulen[a.ulke] = a.ulkeAdi }
        return gorulen.map { ($0.key, $0.value) }.sorted { $0.1.compare($1.1, locale: Tr.yerel) == .orderedAscending }
    }

    private func cip(_ ad: String, simge: String? = nil, secili: Bool, _ eylem: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Hareket.yay) { eylem() }
        } label: {
            cipGovde(ad, simge: simge, secili: secili)
        }
        .buttonStyle(.plain)
    }

    private func cipGovde(_ ad: String, simge: String?, secili: Bool) -> some View {
        HStack(spacing: 5) {
            if let simge { Image(systemName: simge).font(.caption.weight(.bold)) }
            Text(ad).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(secili ? Color.white : Tema.lacivert)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(secili ? Tema.lacivert : Tema.zemin, in: Capsule())
        .overlay(Capsule().stroke(secili ? Tema.lacivert : Tema.soluk, lineWidth: 1))
    }

    // MARK: Satırlar

    private func basvuruSatiri(_ a: Basvuru, uye: Bool) -> some View {
        NavigationLink(value: EkipRota.basvuru(a.kimlik)) {
            BasvuruSatiri(basvuru: a, statu: ekip.statuSozlugu[a.statuId], uyariGun: ekip.uyariGun, uye: uye)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: uye ? 22 : 4, bottom: 0, trailing: 12))
    }

    private func grupBasligi(id: String, ad: String, uyeler: [Basvuru]) -> some View {
        let acik = acikGruplar.contains(id) || !arama.isEmpty
        let randevu = uyeler.compactMap(\.randevu).min()
        let tarih = randevu.map { "randevu \(Tr.kisaTarih($0))" } ?? (uyeler.first?.olusturma).map { Tr.kisaTarih($0) } ?? ""
        return Button {
            withAnimation(Hareket.yay) {
                if acikGruplar.contains(id) { acikGruplar.remove(id) } else { acikGruplar.insert(id) }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Tema.altin.opacity(0.16))
                    Image(systemName: "person.3.fill").font(.caption.weight(.bold)).foregroundStyle(Tema.altin)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                    Text([String(uyeler.count) + " kişi", BasvuruListesi.grupUlkesi(uyeler), tarih].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Tema.govde)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Tema.silik)
                    .rotationEffect(.degrees(acik ? 90 : 0))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 12))
        .accessibilityLabel("\(ad), \(uyeler.count) kişi, \(acik ? "açık" : "kapalı")")
    }
}

/// Listedeki başvuru satırı.
struct BasvuruSatiri: View {
    let basvuru: Basvuru
    let statu: Statu?
    let uyariGun: Int
    var uye = false

    var body: some View {
        let a = basvuru
        let arama = statu.flatMap { a.aramaDurumu($0) }
        let kalan = BasvuruListesi.kalanGun(a.silinecek)
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(renk.opacity(0.14))
                Text(String(a.ad.prefix(1)))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(renk)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(a.adSoyad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert).lineLimit(1)
                    if !uye && !a.grupId.isEmpty { Etiket(metin: "Grup", renk: Tema.altin) }
                }
                Text([a.ulkeAdi, a.takipKodu, a.pasaportSon3.isEmpty ? "" : "•••\(a.pasaportSon3)"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Tema.govde)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Etiket(metin: statu?.ad ?? (a.statuAdi.isEmpty ? "Belirtilmemiş" : a.statuAdi), renk: renk)
                    if a.odemeSayisi > 0 { Etiket(metin: "Ödeme alındı", renk: Tema.olumlu) }
                }
                if let arama, arama.durum != .bekle {
                    Label(Basvuru.aramaEtiketi(arama), systemImage: "phone.arrow.up.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(arama.durum == .gecikti ? Color(hex: 0xb36b00) : Tema.turkuaz)
                }
                if a.bekletiliyor {
                    Label("Silme bekletiliyor", systemImage: "pause.circle").font(.caption2).foregroundStyle(Tema.govde)
                } else if let k = kalan, k <= uyariGun {
                    Label(k <= 0 ? "Bugün silinecek" : "\(k) gün sonra silinecek", systemImage: "trash")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Tema.olumsuz)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private var renk: Color { statu.flatMap { Color(kod: $0.renk) } ?? Tema.mavi }
}
