import SwiftUI
import PhotosUI
import VizeMiaCekirdek

/// Fotoğraf havuzu (panel: #/havuz): görsel yüklenmemiş slaytların arka planları.
/// Hazır fotoğraflar salt okunur; eklenenlerin görünen alanı değiştirilir ya da silinir.
struct HavuzEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @Environment(IcerikDeposu.self) private var depo
    @State private var ekleAcik = false
    @State private var duzenlenen: FotoHavuzu.Eklenen?
    @State private var silinecek: FotoHavuzu.Eklenen?
    @State private var bildiri: String?

    private var v: VitrinVerisi { ekipVerisi.vitrin }
    private var yetki: Bool { ekip.yapabilir("havuz.manage") }

    private func ulkeAdi(_ id: String) -> String { id.isEmpty ? "Genel" : (depo.akis.tumUlkeler.first { $0.slug == id }?.ad ?? id) }

    struct Grup: Identifiable {
        let ulke: String
        let fotolar: [FotoHavuzu.Foto]
        var id: String { ulke }
    }

    /// Ülkeler ada göre, en sonda genel.
    private var gruplar: [Grup] {
        let otomatik = v.havuz.filter(\.oto)
        let ulkeler = Set(otomatik.map(\.ulke)).sorted { a, b in
            if a.isEmpty != b.isEmpty { return !a.isEmpty }
            return ulkeAdi(a).compare(ulkeAdi(b), locale: Tr.yerel) == .orderedAscending
        }
        return ulkeler.map { u in Grup(ulke: u, fotolar: otomatik.filter { $0.ulke == u }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Görsel yüklenmemiş slaytların arka planı buradan gelir: ülke seçiliyse o ülkenin fotoğrafı, değilse genel bir fotoğraf.")
                    .font(.caption).foregroundStyle(Tema.govde)
                if let h = v.hata { AlanHatasi(metin: h) }
                if let b = bildiri { Label(b, systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Tema.olumluKoyu) }
                ForEach(gruplar) { g in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(ulkeAdi(g.ulke)) (\(g.fotolar.count))").font(.headline).foregroundStyle(Tema.lacivert)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(g.fotolar) { f in kare(f) }
                        }
                    }
                    .kart()
                }
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("Fotoğraf havuzu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if yetki {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ekleAcik = true } label: { Image(systemName: "plus") }.accessibilityLabel("Fotoğraf ekle")
                }
            }
        }
        .task { await v.yukle(ekip) }
        .refreshable { await v.yukle(ekip, zorla: true) }
        .sheet(isPresented: $ekleAcik) { HavuzaEkleSayfasi { m in bildiri = m } }
        .sheet(item: $duzenlenen) { e in OdakDuzenleSayfasi(e: e) { m in bildiri = m } }
        .confirmationDialog("Bu fotoğraf havuzdan silinecek. Onu kullanan slaytlar başka bir havuz fotoğrafı alır.",
                            isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }), titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                guard let e = silinecek, let c = ekip.calisan else { return }
                Task { bildiri = await v.isle(FotoHavuzu.sil(e, calisan: c), ekip: ekip).mesaj }
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private func kare(_ f: FotoHavuzu.Foto) -> some View {
        let e = f.hazir ? nil : v.eklenenler.first { "u-\($0.id)" == f.id }
        return VStack(alignment: .leading, spacing: 4) {
            OdakliGorsel(yol: f.yol, odak: f.odak)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 4) {
                Text(e?.ad.isEmpty == false ? e!.ad : (f.hazir ? "Hazır fotoğraf" : "Eklenen")).font(.caption2).foregroundStyle(Tema.govde).lineLimit(1)
                Spacer(minLength: 0)
                if let e, yetki {
                    Menu {
                        Button { duzenlenen = e } label: { Label("Görünen alan", systemImage: "scope") }
                        Button(role: .destructive) { silinecek = e } label: { Label("Sil", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Tema.lacivert) }
                }
            }
        }
    }
}

struct HavuzaEkleSayfasi: View {
    let bitti: (String) -> Void
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @Environment(IcerikDeposu.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State private var foto: PhotosPickerItem?
    @State private var gorsel = ""
    @State private var odak = FotoHavuzu.orta
    @State private var ulke = ""
    @State private var ad = ""
    @State private var ulkeSeciliyor = false
    @State private var hata: String?
    @State private var kaydediliyor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        PhotosPicker(selection: $foto, matching: .images) { Label(gorsel.isEmpty ? "Fotoğraf seç" : "Başka fotoğraf seç", systemImage: "photo") }
                            .buttonStyle(KucukDugme())
                        Text("Yatay bir fotoğraf en iyi sonucu verir (ör. 1600×900).").font(.caption2).foregroundStyle(Tema.silik)
                        if !gorsel.isEmpty { OdakSecici(yol: gorsel, odak: $odak) }
                    }
                    .kart()
                    VStack(alignment: .leading, spacing: 12) {
                        Alan(etiket: "Ülke") {
                            Button { ulkeSeciliyor = true } label: {
                                HStack {
                                    Text(depo.akis.tumUlkeler.first { $0.slug == ulke }?.ad ?? "Genel (ülkeye özel değil)").foregroundStyle(Tema.lacivert)
                                    Spacer()
                                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
                                }
                                .kutu()
                            }
                            .buttonStyle(.plain)
                        }
                        Alan(etiket: "Açıklama", istegeBagli: true) { TextField("Ör. Münih Marienplatz", text: $ad).kutu() }
                    }
                    .kart()
                    if let h = hata { AlanHatasi(metin: h) }
                    Button {
                        Task { await kaydet() }
                    } label: {
                        if kaydediliyor { HStack(spacing: 8) { ProgressView().tint(.white); Text("Ekleniyor…") } } else { Text("Havuza ekle") }
                    }
                    .buttonStyle(AnaDugme())
                    .disabled(gorsel.isEmpty || kaydediliyor)
                }
                .padding(Tema.bosluk)
            }
            .formKlavyesi()
            .ekranZemini()
            .navigationTitle("Fotoğraf ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
            .sheet(isPresented: $ulkeSeciliyor) { UlkeSecici(kitalar: depo.akis.kitalar, secili: ulke) { u in ulke = u.slug } }
            .onChange(of: foto) { _, yeni in
                guard let yeni else { return }
                Task {
                    let veri: Data? = try? await yeni.loadTransferable(type: Data.self)
                    foto = nil
                    guard let d = veri, let r = UIImage(data: d) else { hata = "Görsel açılamadı."; return }
                    guard let a = Gorsel.kucult(r) else { hata = "Görsel çok büyük; daha küçük bir görsel seçin."; return }
                    gorsel = a
                    odak = FotoHavuzu.orta
                    hata = nil
                }
            }
        }
    }

    private func kaydet() async {
        guard let c = ekip.calisan, !gorsel.isEmpty else { return }
        kaydediliyor = true
        let r = await ekipVerisi.vitrin.isle(FotoHavuzu.ekle(gorsel: gorsel, ulke: ulke, odak: odak, ad: ad, calisan: c), ekip: ekip)
        kaydediliyor = false
        if r.tamam { bitti("Fotoğraf havuza eklendi."); kapat() } else { hata = r.mesaj }
    }
}

struct OdakDuzenleSayfasi: View {
    let e: FotoHavuzu.Eklenen
    let bitti: (String) -> Void
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @Environment(\.dismiss) private var kapat
    @State private var odak = FotoHavuzu.orta
    @State private var hata: String?
    @State private var kaydediliyor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    OdakSecici(yol: e.gorsel, odak: $odak).kart()
                    if let h = hata { AlanHatasi(metin: h) }
                    Button {
                        Task {
                            guard let c = ekip.calisan else { return }
                            kaydediliyor = true
                            let r = await ekipVerisi.vitrin.isle(FotoHavuzu.odakGuncelle(e, odak: odak, calisan: c), ekip: ekip)
                            kaydediliyor = false
                            if r.tamam { bitti("Kaydedildi."); kapat() } else { hata = r.mesaj }
                        }
                    } label: {
                        if kaydediliyor { HStack(spacing: 8) { ProgressView().tint(.white); Text("Kaydediliyor…") } } else { Text("Kaydet") }
                    }
                    .buttonStyle(AnaDugme())
                    .disabled(kaydediliyor)
                }
                .padding(Tema.bosluk)
            }
            .ekranZemini()
            .navigationTitle("Görünen alan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
            .onAppear { odak = FotoHavuzu.odakGecerli(e.odak) ? e.odak : FotoHavuzu.orta }
        }
    }
}
