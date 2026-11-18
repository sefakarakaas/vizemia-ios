import SwiftUI
import VizeMiaCekirdek

/// Başvuru ayrıntısındaki "Müşteri formu" (panel: form-panel.js): formu müşteriye
/// gönderir (bağlantı, istenirse SMS), ne kadarını doldurduğunu gösterir, sorularını
/// cevaplatır ve cevapları başvuru formuna aktarır. Belge kart açılınca bir kez okunur.
struct MusteriFormuKarti: View {
    let veri: BasvuruDetayVerisi
    let b: Basvuru
    let baglam: EkBaglami
    @Environment(EkipOturumu.self) private var ekip
    @Environment(IcerikDeposu.self) private var icerik
    @State private var calisiyor = false
    @State private var kapatSor = false
    @State private var aktarSor = false
    @State private var cevaplar: [Int: String] = [:]
    @State private var kuralAcik = false

    private var hollanda: Bool { b.ulke == "hollanda" }
    private var telefon: String { veri.form?["phone"]?.metinDegeri ?? "" }
    private var pasaportVar: Bool { !(veri.form?["passportNo"]?.metinDegeri ?? "").isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Müşteri formu").font(.headline).foregroundStyle(Tema.lacivert)
            if veri.takipId == nil || (veri.form != nil && !pasaportVar) {
                Text("Bu başvurunun takip anahtarı yok; formu göndermek için önce pasaport numarasını kaydedin.")
                    .font(.caption).foregroundStyle(Tema.govde)
            } else if !veri.musteriFormuOkundu {
                ProgressView().frame(maxWidth: .infinity)
            } else if let k = veri.musteriFormu {
                durumBolumu(k)
                cevapBolumu(k)
                soruBolumu(k)
                gonderBolumu(k)
                kuralBolumu
                if k.durum != "kapandi" {
                    Button("Formu kapat", role: .destructive) { kapatSor = true }.buttonStyle(KucukDugme(renk: Tema.olumsuz))
                }
            } else {
                Text("Müşteriye, telefonda aldığınız bilgiler dolu gelen bir form gönderebilirsiniz. Müşteri takip kodu ve pasaport numarasıyla açar, kalan soruları kendi doldurur.")
                    .font(.caption).foregroundStyle(Tema.govde)
                gonderBolumu(nil)
                kuralBolumu
            }
        }
        .kart()
        .task { if !veri.musteriFormuOkundu { await veri.musteriFormuYukle(ekip) } }
        .confirmationDialog("Form kapatılacak; müşteri artık değiştiremeyecek.", isPresented: $kapatSor, titleVisibility: .visible) {
            Button("Kapat", role: .destructive) {
                Task { baglam.bildir(await veri.musteriFormuKapat(ekip: ekip), "Form kapatıldı.") }
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    // MARK: Durum

    private func durumBolumu(_ k: MusteriFormuKaydi) -> some View {
        let d = k.doluluk()
        let oran = d.toplam == 0 ? 0 : Double(d.dolu) / Double(d.toplam)
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(k.durumAdi) · \(d.dolu)/\(d.toplam) soru dolu\(k.guncelleme.map { " · son hareket \(Tr.tarihSaat($0))" } ?? "")")
                .font(.caption.weight(.semibold)).foregroundStyle(Tema.govde)
            ProgressView(value: oran).tint(oran >= 1 ? Tema.olumlu : Tema.turkuaz)
            if let a = k.aramaMetni {
                Label("Soru için geri arama: \(a)", systemImage: "phone.arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(k.aramaModu == "hemen" ? Tema.olumsuz : Tema.govde)
            }
            if let r = k.rizaZamani {
                Text("KVKK açık rızası verildi: \(Tr.tarihSaat(r))").font(.caption2).foregroundStyle(Tema.silik)
            } else {
                Text("KVKK açık rızası henüz verilmedi (müşteri formu göndermemiş).").font(.caption2).foregroundStyle(Tema.olumsuz)
            }
        }
    }

    // MARK: Cevaplar

    private func cevapBolumu(_ k: MusteriFormuKaydi) -> some View {
        let satirlar = k.satirlar
        let aktarilacak = icerik.formSemasi.map { k.aktarilacaklar(alanlar: alanlar($0), form: veri.form ?? [:]) } ?? []
        return VStack(alignment: .leading, spacing: 8) {
            Text("Cevaplar").font(.subheadline.weight(.bold)).foregroundStyle(Tema.lacivert)
            if satirlar.isEmpty {
                Text("Müşteri henüz bir şey yazmadı.").font(.caption).foregroundStyle(Tema.govde)
            }
            ForEach(Array(satirlar.enumerated()), id: \.offset) { _, s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.soru).font(.caption).foregroundStyle(Tema.govde)
                        Text(s.cevap).font(.subheadline).foregroundStyle(Tema.lacivert).textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    Etiket(metin: s.musteriden ? "müşteri" : "telefonda", renk: s.musteriden ? Tema.olumlu : Tema.silik)
                }
                .padding(.vertical, 2)
            }
            if aktarilacak.isEmpty {
                if !k.cevaplar.isEmpty { Text("Başvuru formuyla arada fark yok.").font(.caption2).foregroundStyle(Tema.silik) }
            } else {
                Button("\(aktarilacak.count) bilgiyi başvuruya aktar") { aktarSor = true }
                    .buttonStyle(AnaDugme())
                    .disabled(calisiyor)
                    .confirmationDialog("Şu bilgiler başvuru formuna yazılacak: \(aktarilacak.map(\.etiket).joined(separator: ", ")).",
                                        isPresented: $aktarSor, titleVisibility: .visible) {
                        Button("Aktar") {
                            Task {
                                calisiyor = true
                                baglam.bildir(await veri.musteriCevaplariniAktar(aktarilacak, ekip: ekip), "Bilgiler başvuruya aktarıldı.")
                                calisiyor = false
                            }
                        }
                        Button("Vazgeç", role: .cancel) {}
                    }
            }
        }
    }

    private func alanlar(_ sema: FormSemasi) -> [FormAlani] {
        sema.panelAlanlari(b.ulke, kayitli: ekip.ulkeFormlari).filter { !$0.kapali }
    }

    // MARK: Müşterinin soruları

    private func soruBolumu(_ k: MusteriFormuKaydi) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Müşterinin soruları").font(.subheadline.weight(.bold)).foregroundStyle(Tema.lacivert)
            if k.musteriSorulari.isEmpty {
                Text("Müşteri soru sormadı.").font(.caption).foregroundStyle(Tema.govde)
            }
            ForEach(Array(k.musteriSorulari.enumerated()), id: \.offset) { i, s in
                VStack(alignment: .leading, spacing: 4) {
                    let hakkinda = s.alan.isEmpty ? "Genel soru" : (k.sorular.first { $0.key == s.alan }?.label ?? s.alan)
                    Text([hakkinda, zamanYazisi(s.zaman)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(Tema.silik)
                    Text(s.metin).font(.subheadline).foregroundStyle(Tema.lacivert)
                    if !s.cevap.isEmpty {
                        Text("Cevabımız: \(s.cevap)").font(.subheadline).foregroundStyle(Tema.olumluKoyu)
                        Text([zamanYazisi(s.cevapZamani), s.cevaplayan].filter { !$0.isEmpty }.joined(separator: " — "))
                            .font(.caption2).foregroundStyle(Tema.silik)
                    } else {
                        TextField("Cevabınızı yazın…", text: Binding(get: { cevaplar[i] ?? "" }, set: { cevaplar[i] = $0 }), axis: .vertical)
                            .lineLimit(2...6).kutu()
                        Button("Cevapla") {
                            let t = (cevaplar[i] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            Task {
                                calisiyor = true
                                let h = await veri.musteriSorusunuCevapla(i, metin: t, ekip: ekip)
                                calisiyor = false
                                if h == nil { cevaplar[i] = nil }
                                baglam.bildir(h, "Cevap kaydedildi; müşteri formu açtığında görecek.")
                            }
                        }
                        .buttonStyle(KucukDugme())
                        .disabled(calisiyor)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Müşteri tarafı ISO yazıyor.
    private func zamanYazisi(_ s: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return Tr.tarihSaat(d) }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s).map { Tr.tarihSaat($0) } ?? ""
    }

    // MARK: Gönderme

    @ViewBuilder
    private func gonderBolumu(_ k: MusteriFormuKaydi?) -> some View {
        let smsIster = veri.iletisim?.sms ?? true
        let smsNeden: String? = !ekip.smsAyari.acik ? "SMS kapalı"
            : telefon.isEmpty ? "Formda telefon yok"
            : !smsIster ? "Müşteri SMS almak istemiyor (Bildirim tercihleri)" : nil
        VStack(alignment: .leading, spacing: 8) {
            if hollanda {
                Text("Hollanda formu portal şablonuyla (bölümler, koşullu sorular) panelden hazırlanır; burada durumu ve cevapları görebilirsiniz.")
                    .font(.caption).foregroundStyle(Tema.silik)
            } else if let sema = icerik.formSemasi {
                HStack(spacing: 10) {
                    Button(k == nil ? "Formu hazırla" : "Formu yenile") { Task { await hazirla(sema, sms: false) } }
                        .buttonStyle(AnaDugme())
                    Button("Hazırla ve SMS gönder") { Task { await hazirla(sema, sms: true) } }
                        .buttonStyle(IkincilDugme())
                        .disabled(smsNeden != nil)
                }
                .disabled(calisiyor)
                if let n = smsNeden { Text("SMS: \(n)").font(.caption2).foregroundStyle(Tema.silik) }
            }
            if !b.takipKodu.isEmpty {
                Button {
                    UIPasteboard.general.string = BildirimMetni.formBaglantisi(b.takipKodu)
                    baglam.bildir(nil, "Bağlantı kopyalandı.")
                } label: { Label("Bağlantıyı kopyala", systemImage: "link") }
                .buttonStyle(KucukDugme())
            }
        }
    }

    private func hazirla(_ sema: FormSemasi, sms: Bool) async {
        calisiyor = true
        let r = await veri.musteriFormuHazirla(sms: sms, sema: sema, ekip: ekip)
        calisiyor = false
        baglam.bildir(r.tamam ? nil : r.mesaj, r.mesaj)
    }

    // MARK: Gönderim zamanı

    private var kuralBolumu: some View {
        DisclosureGroup(isExpanded: $kuralAcik) {
            FormKuraliDuzeni(veri: veri, b: b, baglam: baglam)
        } label: {
            Text("Form ne zaman gitsin?").font(.subheadline.weight(.bold)).foregroundStyle(Tema.lacivert)
        }
        .tint(Tema.lacivert)
    }
}

/// Bu başvuruya özel gönderim kuralı (panel: zamanBlock). Değişen kural başvuruya
/// yazılır ve form bağlantısı bildirimi yeniden planlanır.
struct FormKuraliDuzeni: View {
    let veri: BasvuruDetayVerisi
    let b: Basvuru
    let baglam: EkBaglami
    @Environment(EkipOturumu.self) private var ekip
    @State private var mod = ""
    @State private var gun = 7
    @State private var durum: String?
    @State private var kaydediliyor = false

    private var gecerli: (kural: FormGonderimKurali, kaynak: FormGonderimKurali.Kaynak) {
        FormGonderimKurali.gecerli(basvuru: b.formGonderim, ulke: ekip.ulkeFormlari[b.ulke]?.formGonderim)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Gönderim zamanı", selection: $mod) {
                ForEach(FormGonderimKurali.modlar, id: \.id) { m in Text(m.ad).tag(m.id) }
            }
            .pickerStyle(.menu)
            .tint(Tema.lacivert)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kutu()
            if FormGonderimKurali.gunIsteyen.contains(mod) {
                Stepper("Gün: \(gun)", value: $gun, in: 0...365)
                    .font(.subheadline)
            }
            Text(durum ?? "Şu anki kural: \(gecerli.kural.ozet) (\(gecerli.kaynak.ad)).")
                .font(.caption).foregroundStyle(Tema.govde)
            Button {
                Task {
                    kaydediliyor = true
                    let r = await veri.formKuraliKaydet(FormGonderimKurali(mod: mod, gun: gun), ekip: ekip)
                    kaydediliyor = false
                    if r.tamam { durum = r.mesaj; baglam.bildir(nil, "Gönderim kuralı kaydedildi.") } else { baglam.bildir(r.mesaj, "") }
                }
            } label: {
                if kaydediliyor { ProgressView() } else { Text("Kuralı kaydet ve planla") }
            }
            .buttonStyle(KucukDugme())
            .disabled(kaydediliyor || mod.isEmpty)
        }
        .padding(.top, 6)
        .onAppear {
            if mod.isEmpty {
                mod = gecerli.kural.mod
                gun = gecerli.kural.gun == 0 ? 7 : gecerli.kural.gun
            }
        }
    }
}
