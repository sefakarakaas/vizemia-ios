import SwiftUI
import VizeMiaCekirdek

/// Yeni başvuru / düzenle (panel: #/basvuru/yeni, #/basvuru/<id>/duzenle).
/// Alanlar sitenin şemasından (uygulama.json → form) ve Ayarlar → Ülke
/// formlarından gelir; kapatılmış alanlar kutucuk arkasında durur.
struct BasvuruFormuEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @Environment(IcerikDeposu.self) private var icerik
    @Environment(\.ekipYerDegistir) private var yerDegistir
    @State private var veri: BasvuruFormuVerisi
    @State private var ulkeSeciliyor = false
    @State private var sorun: String?
    @State private var basari = 0

    init(kimlik: String?, talepYolu: String?, arsivId: String? = nil) {
        _veri = State(initialValue: BasvuruFormuVerisi(kimlik: kimlik, talepYolu: talepYolu, arsivId: arsivId))
    }

    private var ulkeAdi: String { icerik.akis.tumUlkeler.first { $0.slug == veri.ulke }?.ad ?? "" }

    var body: some View {
        Group {
            if let sema = icerik.formSemasi {
                if let h = veri.hata {
                    ContentUnavailableView("Açılamadı", systemImage: "exclamationmark.triangle", description: Text(h))
                } else if !veri.hazir {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form(sema)
                }
            } else {
                ContentUnavailableView("Form şeması yok", systemImage: "doc.questionmark",
                                       description: Text("Uygulamayı güncelleyip yeniden deneyin."))
            }
        }
        .ekranZemini()
        .navigationTitle(veri.duzenleme ? "Başvuruyu düzenle" : "Yeni başvuru")
        .navigationBarTitleDisplayMode(.inline)
        .task { await veri.yukle(ekip, veri: ekipVerisi, ulkeler: Set(icerik.akis.tumUlkeler.map(\.slug))) }
        .sensoryFeedback(.success, trigger: basari)
    }

    private func form(_ sema: FormSemasi) -> some View {
        let alanlar = sema.panelAlanlari(veri.ulke, kayitli: ekip.ulkeFormlari)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let t = veri.talep {
                    Label("\(t.ad) talebinden dolduruldu. Kaydedince talep \"onaylandı\" olur.", systemImage: "phone.arrow.down.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tema.mavi)
                        .kartSoluk()
                }
                if veri.arsivId != nil {
                    Label("Arşivden: ad, soyad, telefon, e-posta ve ülke dolduruldu. TCKN, pasaport ve evraklar silindiği için yeniden girilmeli.",
                          systemImage: "archivebox")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tema.mavi)
                        .kartSoluk()
                }
                basvuruKarti.belirme(0)
                ForEach(Array(sema.gruplar.enumerated()), id: \.element.id) { i, g in
                    let grup = alanlar.filter { $0.group == g.id }
                    if !grup.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(g.label).font(.headline).foregroundStyle(Tema.lacivert)
                            ForEach(grup) { alanSatiri($0, sema: sema) }
                        }
                        .kart()
                        .belirme(min(i + 1, 6))
                    }
                }
                if let s = sorun { HataMetni(metin: s) }
                Button {
                    Task { await kaydet(sema) }
                } label: {
                    if veri.kaydediliyor {
                        HStack(spacing: 8) { ProgressView().tint(.white); Text("Kaydediliyor…") }
                    } else {
                        Label(veri.duzenleme ? "Değişiklikleri kaydet" : "Başvuruyu oluştur", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(AnaDugme())
                .disabled(veri.kaydediliyor)
            }
            .padding(Tema.bosluk)
        }
        .formKlavyesi()
        .sheet(isPresented: $ulkeSeciliyor) {
            UlkeSecici(kitalar: icerik.akis.kitalar, secili: veri.ulke) { u in
                veri.ulke = u.slug
                // "İlk giriş ülkesi" boşsa başvurulan ülke önerilir (panel: suggest).
                if (veri.degerler["firstEntryCountry"] ?? "").isEmpty { veri.degerler["firstEntryCountry"] = u.ad }
            }
        }
    }

    // MARK: Başvuru bilgileri

    private var basvuruKarti: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Başvuru").font(.headline).foregroundStyle(Tema.lacivert)
            if veri.duzenleme, let b = veri.basvuru {
                Text("Takip kodu: \(b.takipKodu)").font(.subheadline.monospacedDigit()).foregroundStyle(Tema.govde)
            } else {
                Text("Takip kodu kaydedince otomatik oluşturulur.").font(.caption).foregroundStyle(Tema.govde)
            }
            Alan(etiket: "Başvurulan ülke") {
                Button { ulkeSeciliyor = true } label: {
                    HStack {
                        Text(ulkeAdi.isEmpty ? "Ülke seçin" : ulkeAdi)
                            .foregroundStyle(ulkeAdi.isEmpty ? Tema.silik : Tema.lacivert)
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
                    }
                    .kutu()
                }
                .buttonStyle(.plain)
            }
            DatePicker("Oluşturma tarihi", selection: $veri.acilis, in: ...Date(), displayedComponents: .date)
                .environment(\.locale, Tr.yerel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tema.lacivert)
            SecmeliTarih(etiket: "Randevu tarihi", tarih: $veri.randevu)
            IsaretKutusu(secili: $veri.kampanyaIzni,
                         metin: "Müşteri kampanya ve duyuru e-postası almayı kabul etti (yalnız açık onay verdiyse işaretleyin).")
        }
        .kart()
    }

    // MARK: Alanlar

    @ViewBuilder
    private func alanSatiri(_ f: FormAlani, sema: FormSemasi) -> some View {
        if f.kapali {
            VStack(alignment: .leading, spacing: 8) {
                Text(f.label).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.silik)
                IsaretKutusu(secili: Binding(
                    get: { veri.acikKapalilar.contains(f.key) },
                    set: { acik in
                        withAnimation(Hareket.yay) {
                            if acik { veri.acikKapalilar.insert(f.key) } else { veri.acikKapalilar.remove(f.key); veri.degerler[f.key] = nil }
                        }
                    }), metin: "Bu başvuruda da sorulsun")
                if veri.acikKapalilar.contains(f.key) {
                    FormAlaniGorunumu(alan: f, deger: deger(f), sema: sema, degerler: $veri.degerler, ulkeler: icerik.akis.kitalar)
                }
            }
        } else {
            FormAlaniGorunumu(alan: f, deger: deger(f), sema: sema, degerler: $veri.degerler, ulkeler: icerik.akis.kitalar)
        }
    }

    private func deger(_ f: FormAlani) -> Binding<String> {
        Binding(get: { veri.degerler[f.key] ?? f.varsayilan }, set: { yeni in
            veri.degerler[f.key] = yeni
            // Pasaport tarihleri: biri girilince öteki (boşsa) aynı gün ve ayla ±10 yıl.
            if !f.mirror.isEmpty, !yeni.isEmpty, (veri.degerler[f.mirror] ?? "").isEmpty {
                let tahmin = EkipFormu.yilKaydir(yeni, f.mirrorYears)
                if !tahmin.isEmpty { veri.degerler[f.mirror] = tahmin }
            }
        })
    }

    private func kaydet(_ sema: FormSemasi) async {
        sorun = nil
        let r = await veri.kaydet(ekip, sema: sema, ulkeListesi: icerik.akis.tumUlkeler, ekipVerisi: ekipVerisi)
        guard let id = r.kimlik else { withAnimation(Hareket.yay) { sorun = r.mesaj }; return }
        basari += 1
        ekipVerisi.sonMesaj = r.mesaj
        yerDegistir(.basvuru(id))
    }
}

/// Bir form alanının girişi (tür: metin, seçmeli, tarih, il, ilçe, ülke, çoklu seçim, uzun metin).
struct FormAlaniGorunumu: View {
    let alan: FormAlani
    @Binding var deger: String
    let sema: FormSemasi
    @Binding var degerler: [String: String]
    let ulkeler: [Kita]
    @State private var seciciAcik = false

    var body: some View {
        Alan(etiket: alan.label + (alan.required ? " *" : ""), yardim: alan.help.isEmpty ? nil : alan.help) {
            giris
        }
    }

    @ViewBuilder private var giris: some View {
        switch alan.type {
        case "date":
            SecmeliIsoTarih(deger: $deger)
        case "textarea":
            TextField("", text: $deger, axis: .vertical).lineLimit(2...6).kutu()
        case "multi":
            CokluSecim(secenekler: alan.options, deger: $deger)
        case "province", "district", "country":
            Button { seciciAcik = true } label: {
                HStack {
                    Text(deger.isEmpty ? "Seçiniz" : deger).foregroundStyle(deger.isEmpty ? Tema.silik : Tema.lacivert)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
                }
                .kutu()
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $seciciAcik) { secici }
        default:
            if !alan.options.isEmpty {
                Menu {
                    ForEach(alan.options, id: \.self) { o in Button(o.label) { deger = o.value } }
                } label: {
                    HStack {
                        Text(alan.options.first { $0.value == deger }?.label ?? (deger.isEmpty ? "Seçiniz" : deger))
                            .foregroundStyle(deger.isEmpty ? Tema.silik : Tema.lacivert)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
                    }
                    .kutu()
                }
            } else {
                TextField("", text: $deger)
                    .keyboardType(alan.type == "email" ? .emailAddress : (alan.type == "tel" ? .phonePad : .default))
                    .textInputAutocapitalization(alan.type == "email" ? .never : (alan.upper ? .characters : .sentences))
                    .autocorrectionDisabled(alan.upper || alan.type == "email")
                    .kutu()
            }
        }
    }

    @ViewBuilder private var secici: some View {
        switch alan.type {
        case "province":
            ListeSecici(baslik: alan.label, secenekler: sema.iller.map(\.ad), secili: $deger)
        case "district":
            let il = degerler["birthProvince"] ?? ""
            let liste = il.isEmpty ? Array(Set(sema.iller.flatMap(\.ilceler))).sorted { $0.compare($1, locale: Tr.yerel) == .orderedAscending }
                : sema.ilceler(il)
            ListeSecici(baslik: alan.label, secenekler: liste, secili: Binding(get: { deger }, set: { yeni in
                deger = Harf.latinBuyuk(yeni)
                // İlçe yazılınca il bulunur (tek ilse).
                if il.isEmpty, let tek = sema.iller(ilce: yeni).first, sema.iller(ilce: yeni).count == 1 { degerler["birthProvince"] = tek }
            }))
        default:
            UlkeSecici(kitalar: ulkeler, secili: "") { u in deger = u.ad }
        }
    }
}

/// Aranabilir liste seçimi (il, ilçe …).
struct ListeSecici: View {
    let baslik: String
    let secenekler: [String]
    @Binding var secili: String
    @Environment(\.dismiss) private var kapat
    @State private var arama = ""

    var body: some View {
        NavigationStack {
            List {
                let q = arama.lowercased(with: Tr.yerel)
                ForEach(q.isEmpty ? secenekler : secenekler.filter { $0.lowercased(with: Tr.yerel).contains(q) }, id: \.self) { s in
                    Button {
                        secili = s
                        kapat()
                    } label: {
                        HStack {
                            Text(s).foregroundStyle(Tema.lacivert)
                            Spacer()
                            if s == secili { Image(systemName: "checkmark").foregroundStyle(Tema.turkuaz) }
                        }
                    }
                }
            }
            .searchable(text: $arama, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ara")
            .navigationTitle(baslik)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .destructiveAction) {
                    if !secili.isEmpty { Button("Temizle") { secili = ""; kapat() } }
                }
            }
        }
    }
}

/// İsteğe bağlı tarih (Date?): boşken "Tarih seç", seçiliyken takvim ve temizle.
struct SecmeliTarih: View {
    let etiket: String
    @Binding var tarih: Date?

    var body: some View {
        HStack {
            Text(etiket).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
            Spacer()
            if let t = tarih {
                DatePicker("", selection: Binding(get: { t }, set: { tarih = $0 }), displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Tr.yerel)
                Button { tarih = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.silik) }
                    .accessibilityLabel("\(etiket) temizle")
            } else {
                Button("Tarih seç") { tarih = Date() }.buttonStyle(KucukDugme())
            }
        }
    }
}

/// İsteğe bağlı tarih (YYYY-AA-GG metni).
struct SecmeliIsoTarih: View {
    @Binding var deger: String

    var body: some View {
        SecmeliTarih(etiket: deger.isEmpty ? "Girilmedi" : (Tr.tarih(deger).map { Tr.kisaTarih($0) } ?? deger),
                     tarih: Binding(get: { Tr.tarih(deger) }, set: { deger = $0.map { Tr.isoGun($0, takvim: Tr.takvim) } ?? "" }))
    }
}

/// Çoklu seçim (virgülle ayrılmış değerler; panel: multiField).
struct CokluSecim: View {
    let secenekler: [FormSecenegi]
    @Binding var deger: String
    @State private var acik = false

    private var secili: Set<String> {
        Set(deger.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Hareket.yay) { acik.toggle() }
            } label: {
                HStack {
                    Text(deger.isEmpty ? "Seçiniz" : deger).foregroundStyle(deger.isEmpty ? Tema.silik : Tema.lacivert).lineLimit(2)
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(acik ? 180 : 0)).foregroundStyle(Tema.silik)
                }
                .kutu()
            }
            .buttonStyle(.plain)
            if acik {
                ForEach(secenekler, id: \.self) { o in
                    IsaretKutusu(secili: Binding(get: { secili.contains(o.value) }, set: { isaretli in
                        var s = secenekler.map(\.value).filter { secili.contains($0) }
                        if isaretli { if !s.contains(o.value) { s = secenekler.map(\.value).filter { secili.contains($0) || $0 == o.value } } }
                        else { s.removeAll { $0 == o.value } }
                        deger = s.joined(separator: ", ")
                    }), metin: o.label)
                }
            }
        }
    }
}
