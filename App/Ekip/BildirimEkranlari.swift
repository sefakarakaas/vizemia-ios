import SwiftUI
import VizeMiaCekirdek

/// Hesabım → Bildirimler: bu telefona hangi konularda anlık bildirim gelsin.
/// Yalnız izni olunan konular gösterilir (ör. kasa bildirimi kasa raporu iznine bağlı).
struct BildirimTercihleriEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @State private var secili: Set<String> = Set(AnlikBildirimMerkezi.seciliKonular)
    @State private var izin: Bool?
    @State private var kaydediliyor = false

    private var merkez: AnlikBildirimMerkezi { AnlikBildirimMerkezi.ortak }

    var body: some View {
        List {
            Section {
                if !merkez.hazir {
                    Label("Anlık bildirim bu sürümde henüz açık değil (kurulum bekliyor).", systemImage: "hourglass")
                        .font(.footnote).foregroundStyle(Tema.govde)
                } else if izin == false {
                    Button { Bildirimler.ayarlariAc() } label: {
                        Label("Bildirim izni kapalı — Ayarlar'dan açın", systemImage: "bell.slash.fill")
                    }
                } else if merkez.jeton == nil {
                    Label("Telefon bildirim için kaydediliyor…", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.footnote).foregroundStyle(Tema.govde)
                } else {
                    Label("Bu telefon bildirim alıyor.", systemImage: "checkmark.seal.fill").foregroundStyle(Tema.olumluKoyu)
                }
            }
            if let c = ekip.calisan {
                Section {
                    ForEach(BildirimKonusu.uygun(c)) { k in
                        Toggle(isOn: Binding(get: { secili.contains(k.id) }, set: { acik in
                            if acik { secili.insert(k.id) } else { secili.remove(k.id) }
                            Task { await kaydet() }
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(k.ad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                                Text(k.aciklama).font(.caption).foregroundStyle(Tema.govde)
                            }
                        }
                        .tint(Tema.turkuaz)
                        .disabled(kaydediliyor)
                    }
                } header: { Text("Hangi durumlarda") } footer: {
                    Text("Seçim bu telefona özel. Statü bildirimleri müşterinin telefonuna gider; size gelmez.")
                }
            }
        }
        .navigationTitle("Bildirimler")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            izin = await AnlikBildirimMerkezi.ortak.izinIsteVeKaydol()
        }
    }

    private func kaydet() async {
        kaydediliyor = true
        await AnlikBildirimMerkezi.ortak.konulariKaydet(BildirimKonusu.hepsi.map(\.id).filter { secili.contains($0) })
        kaydediliyor = false
    }
}

/// Elle bildirim: bir müşteriye (başvurusu üzerinden, uygulamada başvurusunu
/// hatırlattıysa) ya da bir çalışana kişiye özel. Apps Script hemen gönderir.
struct BildirimGonderEkrani: View {
    let basvuruId: String?
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var veri
    @State private var hedefTur: AnlikBildirim.HedefTur = .ekip
    @State private var calisanlar: [CalisanKaydi] = []
    @State private var calisan = ""
    @State private var arama = ""
    @State private var musteri: Basvuru?
    @State private var baslik = ""
    @State private var metin = ""
    @State private var calisiyor = false
    @State private var mesaj: (Bool, String)?
    @State private var hazir = false

    private var musteriOlur: Bool { ekip.yapabilir("eposta.send") }

    private var adaylar: [Basvuru] {
        let q = arama.trimmingCharacters(in: .whitespaces).lowercased(with: Tr.yerel)
        guard q.count >= 2 else { return [] }
        return veri.basvurular.satirlar.filter {
            $0.adSoyad.lowercased(with: Tr.yerel).contains(q) || $0.takipKodu.contains(q)
        }.prefix(8).map { $0 }
    }

    var body: some View {
        Form {
            Section {
                Picker("Kime", selection: $hedefTur) {
                    Text("Çalışan").tag(AnlikBildirim.HedefTur.ekip)
                    if musteriOlur { Text("Müşteri").tag(AnlikBildirim.HedefTur.musteri) }
                }
                .pickerStyle(.segmented)
                if hedefTur == .ekip {
                    Picker("Çalışan", selection: $calisan) {
                        Text("Seçin").tag("")
                        ForEach(calisanlar.filter { $0.aktif && $0.id != ekip.calisan?.uid }) { k in
                            Text(k.ad.isEmpty ? k.kullaniciAdi : k.ad).tag(k.id)
                        }
                    }
                } else if let m = musteri {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.adSoyad).font(.subheadline.weight(.semibold))
                            Text([m.ulkeAdi, m.takipKodu].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(Tema.silik)
                        }
                        Spacer()
                        if basvuruId == nil { Button("Değiştir") { musteri = nil } .buttonStyle(.borderless) }
                    }
                } else {
                    TextField("Ad, soyad ya da takip kodu", text: $arama)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await tamAra() } }
                    ForEach(adaylar) { b in
                        Button { musteri = b; arama = "" } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.adSoyad).foregroundStyle(Tema.lacivert)
                                Text([b.ulkeAdi, b.takipKodu].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(Tema.silik)
                            }
                        }
                    }
                }
            } footer: {
                Text(hedefTur == .musteri
                     ? "Müşteri, uygulamada başvurusunu \"beni hatırla\" ile kaydettiyse telefonuna gider; kaydetmediyse gitmez (SMS / e-posta için Müşteriye mesaj)."
                     : "Çalışanın telefonunda uygulama açık olmasa da gider; Hesabım → Bildirimler'den \"Bana gönderilenler\" kapalıysa gitmez.")
            }
            Section("Bildirim") {
                TextField("Başlık", text: $baslik)
                TextField("Metin", text: $metin, axis: .vertical).lineLimit(2...6)
                Text("\(metin.count) / 500").font(.caption2).foregroundStyle(metin.count > 500 ? Tema.olumsuz : Tema.silik)
            }
            if let m = mesaj { Section { Text(m.1).foregroundStyle(m.0 ? Tema.olumluKoyu : Tema.olumsuz) } }
            Section {
                Button { Task { await gonder() } } label: { if calisiyor { ProgressView() } else { Text("Gönder") } }
                    .disabled(calisiyor || baslik.trimmingCharacters(in: .whitespaces).isEmpty || metin.trimmingCharacters(in: .whitespaces).isEmpty
                              || metin.count > 500 || (hedefTur == .ekip ? calisan.isEmpty : musteri == nil))
            }
        }
        .navigationTitle("Bildirim gönder")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !hazir { await yukle() } }
    }

    private func yukle() async {
        hazir = true
        if let id = basvuruId {
            hedefTur = .musteri
            if let b = veri.basvurular.satirlar.first(where: { $0.kimlik == id }) {
                musteri = b
            } else if let f = try? await ekip.istemci(), let a = ((try? await f.belge("applications/\(id)")) ?? nil) {
                musteri = Basvuru(kimlik: id, alanlar: a)
            }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return }
        #endif
        if let f = try? await ekip.istemci(), let l = try? await f.sorgu(koleksiyon: "employees", sinir: 100) {
            calisanlar = l.map { CalisanKaydi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
                .sorted { $0.ad.compare($1.ad, locale: Tr.yerel) == .orderedAscending }
        }
    }

    /// Takip koduyla tam arama (listede yoksa).
    private func tamAra() async {
        if let b = await veri.basvurular.tamAra(arama, ekip: ekip) { musteri = b; arama = "" }
    }

    private func gonder() async {
        guard let c = ekip.calisan else { return }
        let hedef: String, ad: String
        if hedefTur == .ekip {
            hedef = calisan
            let k = calisanlar.first { $0.id == calisan }
            ad = (k?.ad.isEmpty == false ? k?.ad : k?.kullaniciAdi) ?? ""
        } else {
            hedef = musteri?.kimlik ?? ""
            ad = musteri?.adSoyad ?? ""
        }
        guard let y = AnlikBildirim.istek(hedefTur: hedefTur, hedef: hedef, hedefAd: ad, baslik: baslik, metin: metin, calisan: c) else {
            mesaj = (false, "Kişi, başlık ve metin gerekli.")
            return
        }
        calisiyor = true
        defer { calisiyor = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { mesaj = (true, "Bildirim gönderildi."); return }
        #endif
        do {
            try await ekip.istemci().isle(y)
            let hemen = await ekip.bildirimHemen()
            baslik = ""; metin = ""
            mesaj = (true, hemen ? "Bildirim gönderildi." : "Bildirim sıraya alındı; en geç 10 dakika içinde gider.")
        } catch {
            mesaj = (false, HataAciklamasi.metin(error, "Gönderilemedi."))
        }
    }
}
