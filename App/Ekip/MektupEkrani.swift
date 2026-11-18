import SwiftUI
import UIKit
import CoreText
import VizeMiaCekirdek

/// İyi niyet mektubu (panel: pages/mektup.js). Üç adım: bilgiler → not ve cümle
/// kalıpları → prompt'u kopyala, yapay zekânın cevabını yapıştır → PDF.
/// Okuma: başvuru, private/data, private/mektup ve settings/mektup (4 belge).
struct MektupEkrani: View {
    let basvuruId: String
    @Environment(EkipOturumu.self) private var ekip
    @Environment(IcerikDeposu.self) private var icerik
    @State private var yukleniyor = true
    @State private var hata: String?
    @State private var basvuru: Basvuru?
    @State private var b = MektupBilgileri()
    @State private var not = ""
    @State private var secili: Set<String> = []
    @State private var tr: [String] = []
    @State private var en: [String] = []
    @State private var cumleler: [MektupVerisi.Cumle] = []
    @State private var ayar = MektupVerisi.Ayar()
    @State private var cevap = ""
    @State private var uyarilar: [String] = []
    @State private var mesaj: (Bool, String)?
    @State private var calisiyor = false
    @State private var pdfAdresi: URL?

    private var veri: MektupVerisi? { icerik.mektup }
    private var ulkeAdi: String { basvuru?.ulkeAdi ?? "" }

    var body: some View {
        Group {
            if yukleniyor {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let h = hata {
                ContentUnavailableView("Açılamadı", systemImage: "exclamationmark.triangle", description: Text(h))
            } else {
                form
            }
        }
        .navigationTitle("İyi niyet mektubu")
        .navigationBarTitleDisplayMode(.inline)
        .task { if yukleniyor { await yukle() } }
    }

    private var form: some View {
        Form {
            if let m = mesaj { Section { Text(m.1).foregroundStyle(m.0 ? Tema.olumluKoyu : Tema.olumsuz) } }
            bilgiBolumu
            eslikBolumu
            Section("Davet, geçmiş, iş") {
                TextField("Davet eden kişi", text: $b.davetEden)
                TextField("Davet edenin yakınlığı", text: $b.davetYakinlik)
                TextField("Önceki vizeler / ziyaretler (yoksa: ilk başvuru)", text: $b.oncekiVize, axis: .vertical).lineLimit(1...4)
                TextField("Meslek / görev", text: $b.meslek)
                TextField("İşyeri", text: $b.isyeri)
                TextField("Kaç yıldır çalışıyor", text: $b.calismaSuresi)
            }
            Section("Maddi durum ve bağlar") {
                TextField("Masraflar", text: $b.masraf, axis: .vertical).lineLimit(1...3)
                TextField("Finansal durum / belgeler", text: $b.finansal, axis: .vertical).lineLimit(1...3)
                TextField("Mülkler (ev, arsa, araç)", text: $b.mulk, axis: .vertical).lineLimit(1...3)
                TextField("Eğitim", text: $b.egitim, axis: .vertical).lineLimit(1...3)
                TextField("Bakmakla yükümlü / aile", text: $b.bakmakla, axis: .vertical).lineLimit(1...3)
                TextField("Evcil hayvan", text: $b.evcil)
                TextField("Diğer bağlar (emeklilik, kendi şirketi…)", text: $b.diger, axis: .vertical).lineLimit(1...3)
            }
            let eksik = Mektup.eksikler(b)
            Section {
                if eksik.isEmpty {
                    Label("Önemli bilgilerin hepsi dolu.", systemImage: "checkmark.seal.fill").foregroundStyle(Tema.olumluKoyu)
                } else {
                    ForEach(eksik, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(Tema.olumsuz) }
                }
            } header: { Text(eksik.isEmpty ? "Kontrol" : "Eksik bilgi (ret riski)") }
            kalipBolumu
            promptBolumu
            metinBolumu
            Section {
                Button { Task { await kaydet(pdf: false) } } label: { Text("Kaydet") }.disabled(calisiyor)
            }
        }
    }

    private var bilgiBolumu: some View {
        Section {
            TextField("Ad soyad", text: $b.adSoyad)
            TextField("Pasaport no", text: $b.pasaportNo).textInputAutocapitalization(.characters)
            tarihSatiri("Dilekçe tarihi", $b.tarih)
            Picker("Temsilcilik şehri", selection: Binding(get: { b.sehir }, set: { yeni in
                b.sehir = yeni
                if let v = veri, let u = basvuru?.ulke {
                    let h = v.hitap(u, sehir: yeni)
                    b.hitapTr = h.tr; b.hitapEn = h.en
                }
            })) {
                Text("ANKARA").tag("ANKARA")
                Text("İSTANBUL").tag("İSTANBUL")
            }
            ForEach(0..<3, id: \.self) { i in
                TextField("Hitap (TR) \(i + 1). satır", text: Binding(get: { b.hitapTr[i] }, set: { b.hitapTr[i] = $0 })).font(.caption)
            }
            ForEach(0..<3, id: \.self) { i in
                TextField("Hitap (EN) \(i + 1). satır", text: Binding(get: { b.hitapEn[i] }, set: { b.hitapEn[i] = $0 })).font(.caption)
            }
            tarihSatiri("Giriş tarihi", $b.giris)
            tarihSatiri("Çıkış tarihi", $b.cikis)
            TextField("Seyahat amacı (ör. aile ziyareti)", text: $b.amac)
            Picker("İstenen vize türü", selection: $b.vizeTuru) {
                ForEach(veri?.vizeTurleri ?? [], id: \.value) { v in Text(v.label).tag(v.value) }
            }
            TextField("Amaçla ilgili ayrıntı (şehirler, plan…)", text: $b.amacDetay, axis: .vertical).lineLimit(1...4)
        } header: { Text("1. Mektup bilgileri") } footer: {
            Text("Başvurudaki bilgilerden dolduruldu; eksikleri tamamlayın. Bu bilgilerin hepsi mektupta kullanılır.")
        }
    }

    private var eslikBolumu: some View {
        Section("Eşlik edenler") {
            ForEach($b.eslikEdenler) { $e in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Ad soyad", text: $e.ad)
                    TextField("Yakınlık (ör. eşim)", text: $e.yakinlik)
                    TextField("Pasaport no", text: $e.pasaport).textInputAutocapitalization(.characters)
                }
            }
            .onDelete { b.eslikEdenler.remove(atOffsets: $0) }
            Button { b.eslikEdenler.append(.init()) } label: { Label("Eşlik eden ekle", systemImage: "plus") }
        }
    }

    private var kalipBolumu: some View {
        Section {
            TextField("Danışman notu (yapay zekânın bilmesi gerekenler)", text: $not, axis: .vertical).lineLimit(2...6)
            let kategoriler = (veri?.kategoriler ?? []) + Array(Set(cumleler.map(\.kategori))).filter { !(veri?.kategoriler ?? []).contains($0) }.sorted()
            ForEach(kategoriler, id: \.self) { kat in
                let liste = cumleler.filter { $0.kategori == kat }
                if !liste.isEmpty {
                    DisclosureGroup("\(kat) (\(liste.filter { secili.contains($0.id) }.count)/\(liste.count))") {
                        ForEach(liste) { c in
                            Toggle(isOn: Binding(get: { secili.contains(c.id) }, set: { if $0 { secili.insert(c.id) } else { secili.remove(c.id) } })) {
                                Text(c.metin).font(.caption)
                            }
                        }
                    }
                }
            }
        } header: { Text("2. Not ve cümle kalıpları") } footer: {
            Text("İşaretlediğiniz kalıplar mektupta mutlaka yer alır. Liste panelde Ayarlar → İyi niyet mektubu'ndan değiştirilir.")
        }
    }

    private var promptBolumu: some View {
        Section {
            Button {
                UIPasteboard.general.string = prompt
                mesaj = (true, "Prompt kopyalandı. Yapay zekâya yapıştırın, cevabın tamamını aşağıya yapıştırın.")
                Task { await kaydet(pdf: false, sessiz: true) }
            } label: { Label("Prompt'u oluştur ve kopyala", systemImage: "doc.on.doc") }
            TextField("Yapay zekânın cevabının TAMAMINI buraya yapıştırın", text: $cevap, axis: .vertical).lineLimit(3...10)
            Button("Cevabı oku") { oku() }.disabled(cevap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(uyarilar, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(Tema.olumsuz) }
        } header: { Text("3. Prompt → yapay zekâ → cevap") }
    }

    private var metinBolumu: some View {
        Section {
            if tr.isEmpty && en.isEmpty {
                Text("Henüz metin yok.").font(.caption).foregroundStyle(Tema.govde)
            }
            paragraflar("Türkçe", $tr)
            paragraflar("İngilizce", $en)
            if !tr.isEmpty || !en.isEmpty {
                Button { Task { await pdfHazirla() } } label: {
                    if calisiyor { ProgressView() } else { Label("PDF hazırla", systemImage: "doc.richtext") }
                }
                .disabled(calisiyor)
                if let u = pdfAdresi {
                    ShareLink(item: u) { Label("PDF'i paylaş / kaydet", systemImage: "square.and.arrow.up") }
                }
            }
        } header: { Text("4. Metin ve PDF") }
    }

    @ViewBuilder
    private func paragraflar(_ baslik: String, _ l: Binding<[String]>) -> some View {
        if !l.wrappedValue.isEmpty {
            Text(baslik).font(.subheadline.weight(.bold)).foregroundStyle(Tema.lacivert)
            ForEach(l.wrappedValue.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    let n = Mektup.kelimeSay(l.wrappedValue[i])
                    Text("\(i + 1). paragraf · \(n) kelime").font(.caption2)
                        .foregroundStyle(n < ayar.min || n > ayar.max ? Tema.olumsuz : Tema.silik)
                    TextField("", text: Binding(get: { l.wrappedValue.indices.contains(i) ? l.wrappedValue[i] : "" },
                                                set: { if l.wrappedValue.indices.contains(i) { l.wrappedValue[i] = $0 } }), axis: .vertical)
                        .lineLimit(2...12).font(.caption)
                }
            }
        }
    }

    private func tarihSatiri(_ ad: String, _ deger: Binding<String>) -> some View {
        SecmeliTarih(etiket: ad, tarih: Binding(get: { Tr.tarih(deger.wrappedValue) }, set: { deger.wrappedValue = $0.map { Tr.isoGun($0, takvim: Tr.takvim) } ?? "" }))
    }

    private var prompt: String {
        Mektup.prompt(b, ulkeAdi: ulkeAdi, not: not, cumleler: cumleler.filter { secili.contains($0.id) }.map(\.metin), ayar: ayar,
                      vizeTurleri: veri?.vizeTurleri ?? [])
    }

    private func oku() {
        let r = Mektup.cevapOku(cevap, adSoyad: b.adSoyad, paragraf: ayar.paragraf)
        guard !r.tr.isEmpty || !r.en.isEmpty else { mesaj = (false, "Cevapta metin bulunamadı."); return }
        if !r.tr.isEmpty { tr = r.tr }
        if !r.en.isEmpty { en = r.en }
        uyarilar = r.uyarilar
        mesaj = (true, r.uyarilar.isEmpty ? "\(tr.count) Türkçe ve \(en.count) İngilizce paragraf okundu." : "Cevap okundu; uyarılara bakın.")
        Task { await kaydet(pdf: false, sessiz: true) }
    }

    private func yukle() async {
        defer { yukleniyor = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") {
            basvuru = OrnekEkip.basvurular.first { $0.kimlik == basvuruId }
            cumleler = veri?.cumleler ?? []
            ayar = veri?.ayar ?? MektupVerisi.Ayar()
            b = Mektup.doldur(form: ["firstName": .metin("AYŞE"), "lastName": .metin("KAYA")], ulke: basvuru?.ulke ?? "", kayit: nil, veri: veri, bugun: Tr.bugun())
            return
        }
        #endif
        do {
            let f = try await ekip.istemci()
            let yol = "applications/\(basvuruId)"
            async let a = f.belge(yol)
            async let d = f.belge("\(yol)/private/data")
            async let m = f.belge("\(yol)/private/mektup")
            async let s = f.belge("settings/mektup")
            guard let ab = try await a else { hata = "Başvuru bulunamadı."; return }
            let bv = Basvuru(kimlik: basvuruId, alanlar: ab)
            basvuru = bv
            let form = (try await d)?["form"]?.haritaDegeri ?? [:]
            let kayit: [String: FSDeger]? = (try? await m) ?? nil
            let ayarBelgesi: [String: FSDeger]? = (try? await s) ?? nil
            let ay = veri?.ayarla(ayarBelgesi)
            cumleler = ay?.cumleler ?? []
            ayar = ay?.ayar ?? MektupVerisi.Ayar()
            var kb = kayit?["bilgiler"]?.haritaDegeri.map { MektupBilgileri(alanlar: $0) }
            if kb == nil, let sh = ay?.sehir { var y = MektupBilgileri(); y.sehir = sh; kb = y }
            b = Mektup.doldur(form: form, ulke: bv.ulke, kayit: kb, veri: veri, bugun: Tr.bugun())
            not = kayit?["not"]?.metinDegeri ?? ""
            secili = Set((kayit?["secilenler"]?.diziDegeri ?? []).compactMap { $0.metinDegeri })
            let mt = kayit?["metin"]?.haritaDegeri
            tr = (mt?["tr"]?.diziDegeri ?? []).compactMap { $0.metinDegeri }
            en = (mt?["en"]?.diziDegeri ?? []).compactMap { $0.metinDegeri }
        } catch FirestoreHatasi.izinYok {
            hata = "Mektup için hassas veri görme yetkisi gerekir."
        } catch {
            hata = HataAciklamasi.metin(error, "Açılamadı. İnternet bağlantınızı kontrol edin.")
        }
    }

    private func kaydet(pdf: Bool, sessiz: Bool = false) async {
        guard let c = ekip.calisan else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { if !sessiz { mesaj = (true, "Mektup kaydedildi.") }; return }
        #endif
        let y = Mektup.kaydet(basvuruId, bilgiler: b, not: not, secilenler: Array(secili), tr: tr, en: en, pdf: pdf, calisan: c)
        do {
            try await ekip.istemci().isle(y)
            if !sessiz { mesaj = (true, "Mektup kaydedildi.") }
        } catch {
            mesaj = (false, HataAciklamasi.metin(error, "Kaydedilemedi."))
        }
    }

    private func pdfHazirla() async {
        calisiyor = true
        defer { calisiyor = false }
        let temizTr = tr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let temizEn = en.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let veri = MektupPdf.olustur(b, tr: temizTr, en: temizEn) else { mesaj = (false, "PDF hazırlanamadı (yazı tipi yüklenemedi)."); return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Mektup.dosyaAdi(b.adSoyad))
        do {
            try veri.write(to: url, options: .atomic)
            pdfAdresi = url
            await kaydet(pdf: true, sessiz: true)
            mesaj = (true, "PDF hazır; paylaş düğmesiyle kaydedin ya da gönderin.")
        } catch {
            mesaj = (false, "PDF kaydedilemedi.")
        }
    }
}

/// Mektup → PDF (panel: mektup-pdf.js). Örnek dilekçe Calibri Bold 11; aynı ölçülerdeki
/// açık lisanslı Carlito Bold kullanılır (Kaynaklar/Fontlar, OFL). Önce Türkçe,
/// İngilizce yeni sayfadan. Her şey telefonda; metin hiçbir yere gönderilmez.
enum MektupPdf {
    static let fontAdi: String? = {
        guard let url = Bundle.main.url(forResource: "Carlito-Bold", withExtension: "ttf") else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let saglayici = CGDataProvider(url: url as CFURL), let f = CGFont(saglayici) else { return nil }
        return f.postScriptName as String?
    }()

    static func olustur(_ b: MektupBilgileri, tr: [String], en: [String]) -> Data? {
        guard let ad = fontAdi, let font = UIFont(name: ad, size: CGFloat(Mektup.Olcu.punto)) else { return nil }
        let nitelik: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let olc: (String) -> Double = { Double(($0 as NSString).size(withAttributes: nitelik).width) }
        let diller: [(hitap: [String], tarih: String, selam: String, p: [String], kapanis: String)] = [
            (b.hitapTr, Mektup.tarihNoktali(b.tarih), "Sayın Yetkili,", tr, "Saygılarımla,"),
            (b.hitapEn, Mektup.tarihEn(b.tarih), "Dear Sir/Madam,", en, "Yours faithfully,"),
        ]
        let sayfa = CGRect(x: 0, y: 0, width: Mektup.Olcu.genislik, height: Mektup.Olcu.yukseklik)
        let bicim = UIGraphicsPDFRendererFormat()
        bicim.documentInfo = [kCGPDFContextTitle as String: "\(b.adSoyad) Dilekçe".trimmingCharacters(in: .whitespaces)]
        return UIGraphicsPDFRenderer(bounds: sayfa, format: bicim).pdfData { ctx in
            for d in diller where !d.p.isEmpty {
                let sayfalar = Mektup.yerlesim(hitap: d.hitap, tarih: d.tarih, selam: d.selam, paragraflar: d.p, kapanis: d.kapanis,
                                               imza: b.adSoyad, olc: olc)
                for satirlar in sayfalar {
                    ctx.beginPage()
                    for s in satirlar {
                        // Yerleşimde y taban çizgisi, aşağıdan; UIKit yukarıdan ve kutunun üstünden çizer.
                        let ust = Mektup.Olcu.yukseklik - s.y - Double(font.ascender)
                        (s.metin as NSString).draw(at: CGPoint(x: s.x, y: ust), withAttributes: nitelik)
                    }
                }
            }
        }
    }
}
