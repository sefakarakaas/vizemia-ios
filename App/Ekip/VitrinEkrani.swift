import SwiftUI
import PhotosUI
import VizeMiaCekirdek

/// Vitrin (panel: #/vitrin): sitenin en üstünde kayan slaytlar.
struct VitrinListesiEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @Environment(IcerikDeposu.self) private var depo

    private var v: VitrinVerisi { ekipVerisi.vitrin }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sitenin en üstünde yavaşça kayan slaytlar. Kaydettiğiniz değişiklikler 2–3 dakika içinde sitede görünür.")
                    .font(.caption).foregroundStyle(Tema.govde)
                if let h = v.hata { AlanHatasi(metin: h) }
                if v.yukleniyor && v.slaytlar.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if v.slaytlar.isEmpty {
                    Text("Henüz slayt yok. Sitede şu an varsayılan slaytlar görünüyor. İlk slaytı kaydettiğinizde sitede yalnızca buradaki slaytlar görünür.")
                        .font(.subheadline).foregroundStyle(Tema.govde).kart()
                }
                ForEach(Array(v.slaytlar.enumerated()), id: \.element.id) { i, s in
                    NavigationLink(value: EkipRota.slayt(s.id)) { kart(s) }.buttonStyle(.plain).belirme(min(i, 6))
                }
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("Vitrin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if ekip.yapabilir("vitrin.edit") || ekip.yapabilir("vitrin.publish") {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: EkipRota.slayt(nil)) { Image(systemName: "plus") }.accessibilityLabel("Yeni slayt")
                }
            }
        }
        .task { await v.yukle(ekip) }
        .refreshable { await v.yukle(ekip, zorla: true) }
    }

    private func kart(_ s: VitrinSlayti) -> some View {
        let a = FotoHavuzu.arkaPlan(s.girdi, komsular: v.komsular(haric: s.id), v.havuz)
        let d = s.durumYazisi()
        let renk: Color = d.tur == "yayinda" ? Tema.olumlu : (d.tur == "bitti" ? Tema.olumsuz : (d.tur == "bekliyor" ? Tema.mavi : Tema.altin))
        return HStack(spacing: 12) {
            OdakliGorsel(yol: a.gorsel, odak: a.odak)
                .frame(width: 96, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(s.baslik).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert).lineLimit(2)
                if !s.ust.isEmpty { Text(s.ust).font(.caption).foregroundStyle(Tema.govde) }
                HStack(spacing: 6) {
                    Etiket(metin: d.metin, renk: renk)
                    if s.icerikten { Etiket(metin: "Blog / SSS'ten", renk: Tema.turkuaz) }
                    Text("Sıra \(s.sira)").font(.caption2).foregroundStyle(Tema.silik)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
        }
        .kart()
    }
}

/// Slaytın sitedeki görünüşü (geniş ekran oranı).
struct SlaytOnizleme: View {
    let s: VitrinSlayti
    let arka: FotoHavuzu.ArkaPlan

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            OdakliGorsel(yol: arka.gorsel, odak: arka.odak)
            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                if !s.ust.isEmpty { Text(s.ust.uppercased(with: Tr.yerel)).font(.caption2.weight(.bold)).foregroundStyle(Color.white.opacity(0.85)) }
                Text(s.baslik.isEmpty ? "Başlık" : s.baslik).font(.headline.weight(.heavy)).foregroundStyle(Color.white).lineLimit(2)
                if !s.metin.isEmpty { Text(s.metin).font(.caption).foregroundStyle(Color.white.opacity(0.9)).lineLimit(2) }
                if !s.link.isEmpty && !s.dugme.isEmpty {
                    Text(s.dugme).font(.caption.weight(.bold)).foregroundStyle(Tema.lacivert)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.white, in: Capsule())
                        .padding(.top, 4)
                }
            }
            .padding(14)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Tema.kose))
    }
}

/// Yeni slayt ya da düzenleme.
struct VitrinDuzenleEkrani: View {
    let kimlik: String?
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @Environment(IcerikDeposu.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State private var s = VitrinSlayti()
    @State private var hazir = false
    @State private var linkSecimi = "/basvuru"
    @State private var baslangicVar = false
    @State private var bitisVar = false
    @State private var baslangic = Date()
    @State private var bitis = Date()
    @State private var foto: PhotosPickerItem?
    @State private var yeniYuklendi = false
    @State private var havuzaEkle = false
    @State private var odakAcik = false
    @State private var ulkeSeciliyor = false
    @State private var hata: String?
    @State private var bildiri: String?
    @State private var kaydediliyor = false
    @State private var silOnay = false

    private var v: VitrinVerisi { ekipVerisi.vitrin }
    private var yayinlayabilir: Bool { ekip.yapabilir("vitrin.publish") }
    private var kilitli: Bool { s.kayitli && s.durum == "yayinda" && !yayinlayabilir }
    private var ulkeAdi: String { depo.akis.tumUlkeler.first { $0.slug == s.ulke }?.ad ?? "" }

    var body: some View {
        Group {
            if hazir { form } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .ekranZemini()
        .navigationTitle(kimlik == nil ? "Yeni slayt" : "Slaytı düzenle")
        .navigationBarTitleDisplayMode(.inline)
        .task { await hazirla() }
        .sheet(isPresented: $ulkeSeciliyor) {
            UlkeSecici(kitalar: depo.akis.kitalar, secili: s.ulke) { u in
                s.ulke = u.slug
                s.havuzFoto = ""
                if s.gorsel.isEmpty { s.odak = "" }
            }
        }
        .confirmationDialog("Bu slayt kalıcı olarak silinecek.", isPresented: $silOnay, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { Task { await sil() } }
            Button("Vazgeç", role: .cancel) {}
        }
        .onChange(of: foto) { _, yeni in
            guard let yeni else { return }
            Task {
                let veri: Data? = try? await yeni.loadTransferable(type: Data.self)
                foto = nil
                guard let d = veri, let r = UIImage(data: d) else { hata = "Görsel açılamadı."; return }
                guard let adres = Gorsel.kucult(r) else { hata = "Görsel çok büyük; daha küçük bir görsel seçin."; return }
                s.gorsel = adres
                s.odak = ""
                yeniYuklendi = true
                hata = nil
            }
        }
    }

    private var arka: FotoHavuzu.ArkaPlan { FotoHavuzu.arkaPlan(s.girdi, komsular: v.komsular(haric: s.id), v.havuz) }
    private var eksikUlkeFotosu: Bool { s.gorsel.isEmpty && !s.ulke.isEmpty && !FotoHavuzu.ulkeFotosuVar(s.ulke, v.havuz) }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if kilitli {
                    Text("Yayındaki slaytı yalnızca yayınlama yetkisi olanlar değiştirebilir.").font(.caption.weight(.semibold)).foregroundStyle(Tema.uyari)
                }
                arkaPlanKarti
                metinKarti
                zamanKarti
                if let h = hata { AlanHatasi(metin: h) }
                if let b = bildiri { Label(b, systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.olumluKoyu) }
                Button {
                    Task { await kaydet() }
                } label: {
                    if kaydediliyor { HStack(spacing: 8) { ProgressView().tint(.white); Text("Kaydediliyor…") } } else { Text("Kaydet") }
                }
                .buttonStyle(AnaDugme())
                .disabled(kaydediliyor || kilitli)
                if s.kayitli && yayinlayabilir {
                    Button("Sil", role: .destructive) { silOnay = true }.buttonStyle(KucukDugme(renk: Tema.olumsuz))
                }
            }
            .padding(Tema.bosluk)
        }
        .formKlavyesi()
    }

    private var arkaPlanKarti: some View {
        let a = arka
        return VStack(alignment: .leading, spacing: 10) {
            Text("Önizleme ve arka plan").font(.headline).foregroundStyle(Tema.lacivert)
            SlaytOnizleme(s: s, arka: a)
            Text(kaynakYazisi(a)).font(.caption).foregroundStyle(Tema.govde)
            if eksikUlkeFotosu {
                AlanHatasi(metin: "\(ulkeAdi) için havuzda fotoğraf yok. Lütfen bir fotoğraf yükleyin.")
            }
            HStack(spacing: 8) {
                PhotosPicker(selection: $foto, matching: .images) { Label(s.gorsel.isEmpty ? "Görsel yükle" : "Görseli değiştir", systemImage: "photo") }
                    .buttonStyle(KucukDugme())
                if s.gorsel.isEmpty && a.kaynak != "yok" {
                    Button {
                        s.havuzFoto = FotoHavuzu.sonrakiFoto(ulke: s.ulke, v.havuz, simdiki: a.fotoId)
                        s.odak = ""
                    } label: { Label("Başka fotoğraf", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(KucukDugme())
                }
                if !s.gorsel.isEmpty {
                    Button { s.gorsel = ""; s.odak = ""; yeniYuklendi = false; havuzaEkle = false } label: { Text("Görseli kaldır") }
                        .buttonStyle(KucukDugme(renk: Tema.olumsuz))
                }
            }
            if !a.gorsel.isEmpty {
                DisclosureGroup("Görünen alan", isExpanded: $odakAcik) {
                    OdakSecici(yol: a.gorsel, odak: Binding(get: { a.odak }, set: { s.odak = $0 }))
                        .padding(.top, 6)
                }
                .font(.subheadline.weight(.semibold))
                .tint(Tema.lacivert)
            }
            if yeniYuklendi && ekip.yapabilir("havuz.manage") {
                IsaretKutusu(secili: $havuzaEkle, metin: "Bu fotoğrafı havuza da ekle")
            }
        }
        .kart()
    }

    private func kaynakYazisi(_ a: FotoHavuzu.ArkaPlan) -> String {
        switch a.kaynak {
        case "yuklenen": return "Yüklediğiniz görsel kullanılıyor."
        case "secilen": return "Havuzdan seçilen fotoğraf."
        case "otomatik": return "Arka plan havuzdan otomatik: \(s.ulke.isEmpty ? "genel" : ulkeAdi) fotoğrafı."
        default: return "Havuzda uygun fotoğraf yok."
        }
    }

    private var metinKarti: some View {
        VStack(alignment: .leading, spacing: 12) {
            Alan(etiket: "Başlık", yardim: "En fazla 80 karakter. Kısa ve net olsun.") { TextField("Noel'i Almanya'da geçirmek ister misin?", text: $s.baslik).kutu() }
            Alan(etiket: "Üst yazı", istegeBagli: true) { TextField("Almanya · Aralık", text: $s.ust).kutu() }
            Alan(etiket: "Kısa metin", istegeBagli: true) { TextField("En fazla 200 karakter", text: $s.metin, axis: .vertical).lineLimit(1...3).kutu() }
            Alan(etiket: "Düğme yazısı", istegeBagli: true, yardim: "Boş bırakılırsa düğme gösterilmez.") { TextField("Başvur", text: $s.dugme).kutu() }
            Alan(etiket: "Düğme nereye gitsin?") {
                Picker("Bağlantı", selection: $linkSecimi) {
                    ForEach(0..<VitrinSlayti.baglantilar.count, id: \.self) { i in
                        Text(VitrinSlayti.baglantilar[i].ad).tag(VitrinSlayti.baglantilar[i].yol)
                    }
                    Text("Başka bir adres…").tag("ozel")
                    Text("Düğme yok").tag("")
                }
                .pickerStyle(.menu).tint(Tema.lacivert)
                .frame(maxWidth: .infinity, alignment: .leading).kutu()
                .onChange(of: linkSecimi) { _, yeni in if yeni != "ozel" { s.link = yeni } }
            }
            if linkSecimi == "ozel" {
                Alan(etiket: "Adres", yardim: "Site içi bir yol (/blog/almanya-vizesi) ya da https:// ile başlayan bir adres.") {
                    TextField("https://… ya da /blog/…", text: $s.link).textInputAutocapitalization(.never).autocorrectionDisabled().kutu()
                }
            }
        }
        .kart()
        .disabled(kilitli)
    }

    private var zamanKarti: some View {
        VStack(alignment: .leading, spacing: 12) {
            Alan(etiket: "Ülke", yardim: "Seçilirse arka plan o ülkenin fotoğraflarından gelir; o ülke için gelen ziyaretçiye bu slayt önce gösterilir.") {
                HStack(spacing: 8) {
                    Button { ulkeSeciliyor = true } label: {
                        HStack {
                            Text(ulkeAdi.isEmpty ? "Genel (tüm ziyaretçiler)" : ulkeAdi).foregroundStyle(Tema.lacivert)
                            Spacer()
                            Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
                        }
                        .kutu()
                    }
                    .buttonStyle(.plain)
                    if !s.ulke.isEmpty {
                        Button { s.ulke = ""; s.havuzFoto = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.silik) }
                    }
                }
            }
            IsaretKutusu(secili: $baslangicVar, metin: "Başlangıç tarihi (bu tarihe kadar sitede görünmez)")
            if baslangicVar {
                DatePicker("Başlangıç", selection: $baslangic, displayedComponents: .date).environment(\.locale, Tr.yerel)
            }
            IsaretKutusu(secili: $bitisVar, metin: "Bitiş tarihi (bu tarihten sonra kendiliğinden kalkar)")
            if bitisVar {
                DatePicker("Bitiş", selection: $bitis, displayedComponents: .date).environment(\.locale, Tr.yerel)
            }
            Stepper(value: $s.sira, in: 0...999) {
                Text("Sıra: \(s.sira) (küçük sayı önce)").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
            }
            Picker("Durum", selection: $s.durum) {
                Text("Taslak").tag("taslak")
                Text("Yayında").tag("yayinda")
            }
            .pickerStyle(.segmented)
            .disabled(!yayinlayabilir)
            if !yayinlayabilir { Text("Yayınlama yetkiniz yok; taslak olarak kaydedilir.").font(.caption2).foregroundStyle(Tema.silik) }
        }
        .kart()
        .disabled(kilitli)
    }

    private func hazirla() async {
        guard !hazir else { return }
        await v.yukle(ekip)
        if let id = kimlik, let k = v.slaytlar.first(where: { $0.id == id }) { s = k }
        let hazirLink = VitrinSlayti.baglantilar.contains { $0.yol == s.link }
        linkSecimi = s.link.isEmpty ? "" : (hazirLink ? s.link : "ozel")
        if let d = Tr.tarih(s.baslangic) { baslangicVar = true; baslangic = d }
        if let d = Tr.tarih(s.bitis) { bitisVar = true; bitis = d }
        hazir = true
    }

    private func kaydet() async {
        bildiri = nil
        var x = s
        x.baslangic = baslangicVar ? Tr.isoGun(baslangic, takvim: Tr.takvim) : ""
        x.bitis = bitisVar ? Tr.isoGun(bitis, takvim: Tr.takvim) : ""
        if linkSecimi != "ozel" { x.link = linkSecimi }
        var h = x.hatalar
        if eksikUlkeFotosu { h.append("\(ulkeAdi) için havuzda fotoğraf yok. Lütfen bir fotoğraf yükleyin.") }
        guard h.isEmpty, let c = ekip.calisan else { hata = h.joined(separator: " "); return }
        hata = nil
        kaydediliyor = true
        let r = await v.isle(VitrinIslemi.kaydet(x, yayinlayabilir: yayinlayabilir, havuzaEkle: havuzaEkle && yeniYuklendi, calisan: c), ekip: ekip)
        kaydediliyor = false
        if r.tamam { kapat() } else { hata = r.mesaj }
    }

    private func sil() async {
        guard let c = ekip.calisan else { return }
        let r = await v.isle(VitrinIslemi.sil(s, calisan: c), ekip: ekip)
        if r.tamam { kapat() } else { hata = r.mesaj }
    }
}
