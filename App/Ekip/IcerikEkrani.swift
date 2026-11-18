import SwiftUI
import VizeMiaCekirdek

/// Blog ve SSS (panel: #/icerik). Kaydedilen değişiklikler 2–3 dakikada sitede.
struct IcerikListesiEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @State private var icerikler: [Icerik] = []
    @State private var ara = ""
    @State private var tur = ""
    @State private var yukleniyor = false
    @State private var hata: String?

    /// Ekranda gösterilen kadar okunur (panel 300).
    static let sinir = 100

    private var gorunen: [Icerik] {
        let t = ara.trimmingCharacters(in: .whitespaces).lowercased(with: Tr.yerel)
        return icerikler.filter { (tur.isEmpty || $0.tur == tur) && (t.isEmpty || $0.baslik.lowercased(with: Tr.yerel).contains(t)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Başlıkta ara", text: $ara).autocorrectionDisabled().kutu()
                Picker("Tür", selection: $tur) {
                    Text("Hepsi").tag("")
                    Text("Blog").tag("blog")
                    Text("SSS").tag("faq")
                }
                .pickerStyle(.segmented)
                if let h = hata { AlanHatasi(metin: h) }
                if yukleniyor && icerikler.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if gorunen.isEmpty {
                    ContentUnavailableView("İçerik yok", systemImage: "doc.text")
                } else {
                    VStack(spacing: 0) {
                        ForEach(gorunen) { i in
                            NavigationLink(value: EkipRota.icerik(i.id)) { satir(i) }.buttonStyle(.plain)
                            if i.id != gorunen.last?.id { Divider() }
                        }
                    }
                    .kart()
                }
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("Blog ve SSS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if ekip.yapabilir("content.draft") || ekip.yapabilir("content.publish") {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: EkipRota.icerik(nil)) { Image(systemName: "plus") }.accessibilityLabel("Yeni içerik")
                }
            }
        }
        // Bir kez okunur (okuma kotası); aşağı çekince yenilenir.
        .task { if icerikler.isEmpty { await yukle() } }
        .refreshable { await yukle() }
    }

    private func satir(_ i: Icerik) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(i.baslik).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert).multilineTextAlignment(.leading)
                Text([i.turAdi, i.guncelleme.map { Tr.tarihSaat($0) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Tema.silik)
            }
            Spacer(minLength: 0)
            Etiket(metin: i.yayinda ? "Yayında" : "Taslak", renk: i.yayinda ? Tema.olumlu : Tema.altin)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func yukle() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { icerikler = Self.ornek(); return }
        #endif
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let l = try await ekip.istemci().sorgu(koleksiyon: "content", sirala: ("updatedAt", .azalan), sinir: Self.sinir)
            icerikler = l.map { Icerik(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            hata = nil
        } catch {
            hata = KasaVerisi.mesaj(error, "İçerikler yüklenemedi.")
        }
    }

    #if DEBUG
    static func ornek() -> [Icerik] {
        var a = Icerik(id: "c1")
        a.baslik = "Schengen vizesi için banka dökümü nasıl olmalı?"; a.durum = "published"; a.guncelleme = Date().addingTimeInterval(-86_400)
        a.metin = "## Kısaca\n- Son 3 ay\n- **Kaşeli** ve imzalı"
        var b = Icerik(id: "c2")
        b.tur = "faq"; b.baslik = "Vize randevusu ne kadar sürede alınır?"; b.guncelleme = Date().addingTimeInterval(-3600)
        b.metin = "Ülkeye ve döneme göre değişir."
        return [b, a]
    }
    #endif
}

/// Yeni içerik ya da düzenleme.
struct IcerikDuzenleEkrani: View {
    let kimlik: String?
    @Environment(EkipOturumu.self) private var ekip
    @Environment(IcerikDeposu.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State private var i = Icerik()
    @State private var slayt: [String: FSDeger]?
    @State private var yuklendi = false
    @State private var bulunamadi = false
    @State private var slugElle = false
    @State private var onizleme = false
    @State private var ulkeSeciliyor = false
    @State private var hata: String?
    @State private var bildiri: String?
    @State private var kaydediliyor = false
    @State private var silOnay = false
    @State private var basari = 0

    private var yayinlayabilir: Bool { ekip.yapabilir("content.publish") }
    /// Yayındaki içeriği yalnız yayınlama yetkisi olan değiştirebilir.
    private var kilitli: Bool { kimlik != nil && i.yayinda && !yayinlayabilir }
    private var ulkeAdi: String { depo.akis.tumUlkeler.first { $0.slug == i.ulke }?.ad ?? "" }

    var body: some View {
        Group {
            if bulunamadi {
                ContentUnavailableView("İçerik bulunamadı", systemImage: "doc.questionmark")
            } else if !yuklendi {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                form
            }
        }
        .ekranZemini()
        .navigationTitle(kimlik == nil ? "Yeni içerik" : "İçeriği düzenle")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !yuklendi { await yukle() } }
        .sensoryFeedback(.success, trigger: basari)
        .sheet(isPresented: $ulkeSeciliyor) {
            UlkeSecici(kitalar: depo.akis.kitalar, secili: i.ulke) { u in i.ulke = u.slug }
        }
        .confirmationDialog("Bu içerik kalıcı olarak silinecek.", isPresented: $silOnay, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { Task { await sil() } }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if kilitli {
                    Text("Yayındaki içeriği yalnızca yayınlama yetkisi olanlar değiştirebilir.")
                        .font(.caption.weight(.semibold)).foregroundStyle(Tema.uyari)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Tür", selection: $i.tur) {
                        ForEach(0..<Icerik.turler.count, id: \.self) { k in Text(Icerik.turler[k].ad).tag(Icerik.turler[k].id) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Durum", selection: $i.durum) {
                        Text("Taslak").tag("draft")
                        Text("Yayında").tag("published")
                    }
                    .pickerStyle(.segmented)
                    .disabled(!yayinlayabilir)
                    if !yayinlayabilir {
                        Text("Yayınlama yetkiniz yok; taslak olarak kaydedilir.").font(.caption2).foregroundStyle(Tema.silik)
                    }
                    Alan(etiket: "Başlık") {
                        TextField("Başlık", text: $i.baslik, axis: .vertical).lineLimit(1...3).kutu()
                            .onChange(of: i.baslik) { _, yeni in if !slugElle { i.slug = Icerik.slug(yeni) } }
                    }
                    Alan(etiket: "Adres (slug)", yardim: "Sayfa adresi: /blog/\(i.slug.isEmpty ? "…" : i.slug)") {
                        TextField("adres", text: Binding(get: { i.slug }, set: { i.slug = $0; slugElle = true }))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.subheadline.monospaced())
                            .kutu()
                    }
                    Alan(etiket: "Ülke") {
                        HStack(spacing: 8) {
                            Button { ulkeSeciliyor = true } label: {
                                HStack {
                                    Text(ulkeAdi.isEmpty ? "Genel (ülkeye özel değil)" : ulkeAdi).foregroundStyle(Tema.lacivert)
                                    Spacer()
                                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
                                }
                                .kutu()
                            }
                            .buttonStyle(.plain)
                            if !i.ulke.isEmpty {
                                Button { i.ulke = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.silik) }
                                    .accessibilityLabel("Ülkeyi kaldır")
                            }
                        }
                    }
                    Alan(etiket: "Özet", istegeBagli: true, yardim: "Arama sonuçlarında görünür.") {
                        TextField("Özet", text: $i.ozet, axis: .vertical).lineLimit(2...4).kutu()
                    }
                }
                .kart()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(i.tur == "faq" ? "Cevap" : "Metin").font(.headline).foregroundStyle(Tema.lacivert)
                        Spacer()
                        Picker("Görünüm", selection: $onizleme) {
                            Text("Yaz").tag(false)
                            Text("Önizleme").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    if onizleme {
                        MarkdownMetin(md: i.metin)
                    } else {
                        TextField("Markdown: ## başlık, - madde, **kalın**, [bağlantı](https://…)", text: $i.metin, axis: .vertical)
                            .font(.callout.monospaced())
                            .lineLimit(10...40)
                            .kutu()
                    }
                }
                .kart()
                if slayt != nil {
                    Label("Bu içerik ana sayfadaki kayan slaytlarda da var; başlığı, adresi ve durumu slayta da işlenir. Slaytın görselini ve metnini Vitrin'den değiştirin.",
                          systemImage: "rectangle.stack")
                        .font(.caption).foregroundStyle(Tema.mavi)
                }
                if let h = hata { AlanHatasi(metin: h) }
                if let b = bildiri {
                    Label(b, systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.olumluKoyu)
                }
                Button {
                    Task { await kaydet() }
                } label: {
                    if kaydediliyor { HStack(spacing: 8) { ProgressView().tint(.white); Text("Kaydediliyor…") } } else { Text("Kaydet") }
                }
                .buttonStyle(AnaDugme())
                .disabled(kaydediliyor || kilitli)
                if kimlik != nil && yayinlayabilir {
                    Button("Sil", role: .destructive) { silOnay = true }.buttonStyle(KucukDugme(renk: Tema.olumsuz))
                }
            }
            .padding(Tema.bosluk)
        }
        .formKlavyesi()
    }

    private func yukle() async {
        defer { yuklendi = true }
        guard let id = kimlik else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") {
            i = IcerikListesiEkrani.ornek().first { $0.id == id } ?? Icerik(id: id); slugElle = true; return
        }
        #endif
        do {
            let f = try await ekip.istemci()
            guard let a = try await f.belge("content/\(id)") else { bulunamadi = true; return }
            i = Icerik(kimlik: id, alanlar: a)
            slugElle = true
            // Slaytı okuma yetkisi yoksa (vitrin izni) boş kalır.
            if ekip.yapabilir("vitrin.edit") || ekip.yapabilir("vitrin.publish") {
                slayt = (try? await f.belge("vitrin/icerik-\(id)")) ?? nil
            }
        } catch {
            hata = KasaVerisi.mesaj(error, "Yüklenemedi.")
        }
    }

    /// Slayt yalnız yazılabiliyorsa güncellenir (yoksa içerik kaydı yine olur).
    private var slaytYazilir: Bool {
        guard let s = slayt else { return false }
        if ekip.yapabilir("vitrin.publish") { return true }
        let hedef = (yayinlayabilir ? i.durum : "draft") == "published" ? "yayinda" : "taslak"
        return ekip.yapabilir("vitrin.edit") && s["durum"]?.metinDegeri == "taslak" && hedef == "taslak"
    }

    private func kaydet() async {
        bildiri = nil
        let h = i.hatalar
        guard h.isEmpty else { hata = h.joined(separator: " "); return }
        guard let c = ekip.calisan else { return }
        hata = nil
        kaydediliyor = true
        defer { kaydediliyor = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { bildiri = SiteYayini.mesaj(basladi: true); basari += 1; return }
        #endif
        do {
            let f = try await ekip.istemci()
            // Aynı adres aynı türde başka içerikte var mı?
            let s = Icerik.slug(i.slug).isEmpty ? Icerik.slug(i.baslik) : Icerik.slug(i.slug)
            let ayni = try await f.sorgu(koleksiyon: "content", kosullar: [.esit("slug", .metin(s))], sinir: 5)
            if ayni.contains(where: { $0.kimlik != i.id && $0.alanlar["type"]?.metinDegeri == i.tur }) {
                hata = "Bu adres (slug) başka bir içerikte kullanılıyor."
                return
            }
            let yeni = kimlik == nil && i.olusma == nil
            try await f.isle(IcerikIslemi.kaydet(i, yeni: yeni, yayinlayabilir: yayinlayabilir, slayt: slaytYazilir ? slayt : nil, calisan: c))
            if let a = try? await f.belge("content/\(i.id)") { i = Icerik(kimlik: i.id, alanlar: a) }
            bildiri = SiteYayini.mesaj(basladi: await ekip.siteyiGuncelle())
            basari += 1
        } catch {
            hata = KasaVerisi.mesaj(error, "Kaydedilemedi.")
        }
    }

    private func sil() async {
        guard let c = ekip.calisan else { return }
        do {
            try await ekip.istemci().isle(IcerikIslemi.sil(i, slaytVar: slayt != nil, calisan: c))
            _ = await ekip.siteyiGuncelle()
            kapat()
        } catch {
            hata = KasaVerisi.mesaj(error, "Silinemedi.")
        }
    }
}
