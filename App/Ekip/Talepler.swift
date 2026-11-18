import SwiftUI
import VizeMiaCekirdek

/// Talepler: geri arama ve başvuru talepleri (panel: #/talepler).
struct TaleplerEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var veri
    @State private var filtre: Filtre = .acik
    @State private var tur: TurFiltresi = .hepsi
    @State private var arama = ""
    @State private var elleAcik = false
    @State private var elleMesaj: String?

    enum Filtre: String, CaseIterable, Identifiable {
        case acik = "Açık", kapanan = "Kapanan"
        var id: String { rawValue }
    }

    enum TurFiltresi: String, CaseIterable, Identifiable {
        case hepsi = "Tümü", geriArama = "Geri arama", basvuru = "Başvuru talebi"
        var id: String { rawValue }
    }

    private var liste: [Talep] {
        let kaynak = filtre == .acik ? veri.talepler : veri.kapananlar
        let q = Harf.latinBuyuk(arama.trimmingCharacters(in: .whitespaces))
        let rakam = arama.filter { $0.isNumber }
        return kaynak.filter { t in
            let turUyar = tur == .hepsi || (tur == .geriArama ? t.tur == .geriArama : t.tur == .basvuru)
            let aramaUyar = q.isEmpty || Harf.latinBuyuk(t.ad).contains(q) || Harf.latinBuyuk(t.ulkeAdi).contains(q)
                || (rakam.count >= 3 && t.telefon.contains(rakam))
            return turUyar && aramaUyar
        }
    }

    var body: some View {
        Group {
            if !ekip.yapabilir("lead.view") {
                YetkiYok(ad: "Talepler")
            } else {
                List {
                    Section {
                        Picker("Durum", selection: $filtre.animation(Hareket.yay)) {
                            ForEach(Filtre.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    if filtre == .acik, veri.ozet.acik > 0 {
                        Section {
                            ozetSatiri
                        }
                    }
                    Section {
                        if liste.isEmpty {
                            Text(veri.yukleniyor ? "Yükleniyor…" : (arama.isEmpty ? "Bu listede talep yok." : "Aramayla eşleşen talep yok."))
                                .font(.subheadline)
                                .foregroundStyle(Tema.govde)
                        }
                        ForEach(liste) { t in
                            NavigationLink(value: EkipRota.talep(t.yol)) {
                                TalepSatiri(talep: t, bugun: veri.bugun)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 12))
                            .swipeActions(edge: .leading) {
                                if !t.telefon.isEmpty {
                                    Button { ara(t) } label: { Label("Ara", systemImage: "phone.fill") }.tint(Tema.olumlu)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                if !t.whatsappNumarasi.isEmpty {
                                    Button { whatsapp(t) } label: { Label("WhatsApp", systemImage: "message.fill") }.tint(Tema.whatsapp)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $arama, prompt: "Ad, telefon ya da ülke")
                .refreshable {
                    await veri.yukle(ekip, zorla: true)
                    if filtre == .kapanan { await veri.kapananlariYukle(ekip) }
                }
                .onChange(of: filtre) { _, yeni in
                    if yeni == .kapanan { Task { await veri.kapananlariYukle(ekip) } }
                }
                .animation(Hareket.yay, value: liste.map { $0.id })
                .toolbar {
                    if ekip.yapabilir("lead.manage") {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { elleAcik = true } label: { Image(systemName: "phone.badge.plus") }
                                .accessibilityLabel("Telefonla gelen müşteri")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Tür", selection: $tur) {
                                ForEach(TurFiltresi.allCases) { Text($0.rawValue).tag($0) }
                            }
                        } label: {
                            Image(systemName: tur == .hepsi ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }
                        .accessibilityLabel("Talep türü")
                    }
                }
            }
        }
        .navigationTitle("Talepler")
        .task { await veri.yukle(ekip) }
        .sheet(isPresented: $elleAcik) {
            ElleTalepSayfasi { m in
                elleMesaj = m
                Task { await veri.yukle(ekip, zorla: true) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let m = elleMesaj {
                Label(m, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Tema.olumluKoyu, in: Capsule())
                    .padding(.bottom, 8)
                    .task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        elleMesaj = nil
                    }
            }
        }
    }

    private var ozetSatiri: some View {
        let o = veri.ozet
        return HStack(spacing: 0) {
            ozetParca(o.acik, "açık", Tema.lacivert)
            Divider().frame(height: 28)
            ozetParca(o.acil, "hemen", o.acil > 0 ? Tema.olumsuz : Tema.silik)
            Divider().frame(height: 28)
            ozetParca(o.bugun, "bugün", Tema.turkuaz)
            Divider().frame(height: 28)
            ozetParca(o.geciken, "gecikmiş", o.geciken > 0 ? Color(hex: 0xd98a00) : Tema.silik)
        }
    }

    private func ozetParca(_ n: Int, _ ad: String, _ renk: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.headline).foregroundStyle(renk).contentTransition(.numericText())
            Text(ad).font(.caption2).foregroundStyle(Tema.govde)
        }
        .frame(maxWidth: .infinity)
    }

    private func ara(_ t: Talep) {
        if let u = URL(string: "tel:\(t.telefon)") { UIApplication.shared.open(u) }
    }

    private func whatsapp(_ t: Talep) {
        if let u = URL(string: "https://wa.me/\(t.whatsappNumarasi)") { UIApplication.shared.open(u) }
    }
}

/// Listedeki talep satırı.
struct TalepSatiri: View {
    let talep: Talep
    let bugun: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(renk.opacity(0.14))
                Image(systemName: talep.acil ? "bolt.fill" : (talep.tur == .geriArama ? "phone.fill" : "doc.text.fill"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(renk)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(talep.ad.isEmpty ? "—" : talep.ad)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tema.lacivert)
                        .lineLimit(1)
                    if talep.kaynak == "armut" { Etiket(metin: "Armut", renk: Tema.olumlu) }
                }
                Text(talep.aramaMetni(bugun: bugun))
                    .font(.caption.weight(talep.acil || talep.gecikti(bugun: bugun) ? .semibold : .regular))
                    .foregroundStyle(talep.acil ? Tema.olumsuz : (talep.gecikti(bugun: bugun) ? Color(hex: 0xb36b00) : Tema.govde))
                Text([talep.ulkeAdi, talep.turAdi].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(Tema.silik)
            }
            Spacer(minLength: 4)
            Etiket(metin: talep.durumAdi, renk: durumRengi)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private var renk: Color {
        if talep.acil { return Tema.olumsuz }
        if talep.gecikti(bugun: bugun) { return Color(hex: 0xd98a00) }
        return talep.tur == .geriArama ? Tema.turkuaz : Tema.mavi
    }

    private var durumRengi: Color {
        switch talep.durum {
        case "new": return Tema.mavi
        case "called": return Color(hex: 0xb36b00)
        case "reached": return Tema.olumlu
        case "cancelled", "closed": return Tema.silik
        default: return Tema.olumluKoyu
        }
    }
}

struct Etiket: View {
    let metin: String
    let renk: Color

    var body: some View {
        Text(metin)
            .font(.caption2.weight(.bold))
            .foregroundStyle(renk)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(renk.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}

struct YetkiYok: View {
    let ad: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Tema.silik)
            Text("\(ad) için yetkiniz yok.").foregroundStyle(Tema.govde)
            Text("Yöneticiniz Ayarlar → Rol izinleri'nden açabilir.").font(.caption).foregroundStyle(Tema.silik)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ekranZemini()
    }
}

/// Talep ayrıntısı: iletişim, mesaj, durum değiştirme, iç not, iptal.
struct TalepDetayi: View {
    let yol: String
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var veri
    @Environment(\.dismiss) private var geri
    @State private var durum = "new"
    @State private var icNot = ""
    @State private var hazir = false
    @State private var kaydediliyor = false
    @State private var hata: String?
    @State private var kaydedildi = false
    @State private var iptalSoruluyor = false
    @State private var iptalSebebi = Talep.iptalSebepleri[0]

    var body: some View {
        if let t = veri.talep(yol) {
            icerik(t)
        } else {
            ContentUnavailableView("Talep bulunamadı", systemImage: "questionmark.folder",
                                   description: Text("Bu talep başka biri tarafından kapatılmış olabilir."))
        }
    }

    private func icerik(_ t: Talep) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                bas(t).belirme(0)
                iletisim(t).belirme(1)
                if !t.mesaj.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Müşterinin notu").font(.caption.weight(.semibold)).foregroundStyle(Tema.govde)
                        Text(t.mesaj).font(.body).foregroundStyle(Tema.lacivert).textSelection(.enabled)
                    }
                    .kart()
                    .belirme(2)
                }
                if ekip.yapabilir("lead.manage") && t.acik {
                    duzenle(t).belirme(3)
                } else if !t.icNot.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("İç not").font(.caption.weight(.semibold)).foregroundStyle(Tema.govde)
                        Text(t.icNot).foregroundStyle(Tema.lacivert)
                    }
                    .kart()
                }
                if t.acik && ekip.yapabilir("lead.manage") && ekip.yapabilir("app.create") {
                    NavigationLink(value: EkipRota.yeniBasvuru(talep: t.yol)) {
                        Label("Başvuruya çevir", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(AnaDugme(renk: Tema.turkuaz))
                    Text("Başvuru formu talepteki bilgilerle dolu açılır; kaydedince talep \"onaylandı\" olur.")
                        .font(.caption)
                        .foregroundStyle(Tema.silik)
                }
            }
            .padding(Tema.bosluk)
        }
        .formKlavyesi()
        .ekranZemini()
        .navigationTitle(t.turAdi)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hazir else { return }
            hazir = true
            durum = t.durum
            icNot = t.icNot
        }
        .confirmationDialog("Talep iptal edilsin mi?", isPresented: $iptalSoruluyor, titleVisibility: .visible) {
            ForEach(Talep.iptalSebepleri, id: \.self) { s in
                Button(s, role: .destructive) {
                    iptalSebebi = s
                    Task { await kaydet(t, iptal: s) }
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("İptal sebebini seçin. Talep açık listeden çıkar.")
        }
        .sensoryFeedback(.success, trigger: kaydedildi)
    }

    private func bas(_ t: Talep) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Etiket(metin: t.durumAdi, renk: Tema.mavi)
                if t.acil { Etiket(metin: "Hemen", renk: Tema.olumsuz) }
                if t.kaynak == "armut" { Etiket(metin: "Armut", renk: Tema.olumlu) }
            }
            Text(t.ad.isEmpty ? "—" : t.ad).font(.vitrin(26)).foregroundStyle(Tema.lacivert)
            Label(t.aramaMetni(bugun: veri.bugun), systemImage: "clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(t.acil ? Tema.olumsuz : Tema.govde)
            let bilgi = [t.ulkeAdi, VizeTuru.hepsi.first { $0.id == t.vizeTuru }?.ad ?? "", t.olusturma.map { "Geliş: \(Tr.tarihSaat($0))" } ?? ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            if !bilgi.isEmpty { Text(bilgi).font(.caption).foregroundStyle(Tema.govde) }
        }
    }

    private func iletisim(_ t: Talep) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if let u = URL(string: "tel:\(t.telefon)") { UIApplication.shared.open(u) }
                } label: {
                    Label("Ara", systemImage: "phone.fill")
                }
                .buttonStyle(AnaDugme(renk: Tema.olumlu))
                .disabled(t.telefon.isEmpty)
                // Hazır mesaj seçilince WhatsApp metin hazır açılır, dönünce
                // "Gönderdim / Göndermedim" sorulur (panel: Talepler'deki seçici).
                WaMenusu(telefon: t.telefon, degerler: WaSablonu.degerler(talep: t, benimAdim: ekip.calisan?.gorunenAd ?? "")) { m, id in
                    WaTeyidi(talepId: t.kimlik, talepKol: t.tur.rawValue, telefon: t.telefon, ad: t.ad, metin: m, sablon: id)
                } etiket: {
                    Label("WhatsApp", systemImage: "message.fill")
                }
                .buttonStyle(AnaDugme(renk: Tema.whatsapp))
                .disabled(t.telefon.isEmpty)
            }
            VStack(alignment: .leading, spacing: 6) {
                if !t.telefon.isEmpty {
                    Label(t.telefon, systemImage: "phone").font(.subheadline).foregroundStyle(Tema.lacivert).textSelection(.enabled)
                }
                if !t.eposta.isEmpty {
                    Button {
                        if let u = URL(string: "mailto:\(t.eposta)") { UIApplication.shared.open(u) }
                    } label: {
                        Label(t.eposta, systemImage: "envelope").font(.subheadline).foregroundStyle(Tema.mavi)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kart()
    }

    private func duzenle(_ t: Talep) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Görüşme sonucu").font(.headline).foregroundStyle(Tema.lacivert)
            HStack(spacing: 8) {
                ForEach(Talep.acikDurumlar, id: \.self) { d in
                    Button {
                        withAnimation(Hareket.yay) { durum = d }
                    } label: {
                        // "Arandı, ulaşılamadı" tek satıra sığmıyor: iki satır, kutular eş boy.
                        Text(Talep.durumAdi(d, tur: t.tur))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxHeight: .infinity)
                    }
                    .buttonStyle(SecimKutusu(secili: durum == d))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Alan(etiket: "İç not", istegeBagli: true) {
                TextField("Görüşmede ne konuşuldu, ne zaman yeniden aranacak…", text: $icNot, axis: .vertical)
                    .lineLimit(2...6)
                    .kutu()
            }
            if let h = hata { HataMetni(metin: h) }
            Button {
                Task { await kaydet(t, iptal: nil) }
            } label: {
                if kaydediliyor {
                    HStack(spacing: 8) { ProgressView().tint(.white); Text("Kaydediliyor…") }
                } else {
                    Label(kaydedildi ? "Kaydedildi" : "Kaydet", systemImage: kaydedildi ? "checkmark" : "tray.and.arrow.down.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(AnaDugme())
            .disabled(kaydediliyor || (durum == t.durum && icNot.trimmingCharacters(in: .whitespacesAndNewlines) == t.icNot))
            Button(role: .destructive) {
                iptalSoruluyor = true
            } label: {
                Text("Talebi iptal et").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.olumsuz)
            }
            .frame(maxWidth: .infinity)
        }
        .kart()
    }

    private func kaydet(_ t: Talep, iptal: String?) async {
        hata = nil
        kaydediliyor = true
        defer { kaydediliyor = false }
        do {
            try await veri.talepGuncelle(t, durum: iptal == nil ? durum : "cancelled", icNot: icNot, iptalSebebi: iptal, ekip: ekip)
            kaydedildi.toggle()
            if iptal != nil { geri() }
        } catch FirestoreHatasi.izinYok {
            hata = "Bu talebi değiştirme yetkiniz yok."
        } catch {
            hata = "Kaydedilemedi. İnternet bağlantınızı kontrol edip yeniden deneyin."
        }
    }
}
