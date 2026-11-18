import SwiftUI
import VizeMiaCekirdek

// MARK: - Statüler

/// Ayarlar → Statüler (panel: StatusesPanel). Sıra, ad, müşteriye görünen ad ve
/// açıklama, renk, son adım, silme süresi, tekrar arama aralığı, geçiş şartları.
struct StatuAyarEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @State private var mesaj: (Bool, String)?
    @State private var calisiyor = false
    @State private var silinecek: Statu?
    @State private var tasinacak: Statu?
    @State private var hedef = ""

    var body: some View {
        List {
            Section {
                Text("\"Son adım\" işaretli statüye geçildiğinde saklama sayacı başlar. Müşteri, \"müşteriye görünen ad\" ve açıklamayı görür.")
                    .font(.caption).foregroundStyle(Tema.govde)
            }
            if let m = mesaj { Section { Text(m.1).foregroundStyle(m.0 ? Tema.olumluKoyu : Tema.olumsuz) } }
            Section {
                ForEach(Array(ekip.statuler.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 10) {
                        VStack(spacing: 2) {
                            Button { Task { await tasiSira(i, -1) } } label: { Image(systemName: "chevron.up") }
                                .disabled(i == 0 || calisiyor)
                            Button { Task { await tasiSira(i, 1) } } label: { Image(systemName: "chevron.down") }
                                .disabled(i == ekip.statuler.count - 1 || calisiyor)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.bold))
                        NavigationLink { StatuDuzenleEkrani(statu: s) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(kod: s.renk) ?? Tema.mavi).frame(width: 10, height: 10)
                                    Text(s.ad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                                    if s.son { Etiket(metin: "Son adım", renk: Tema.olumlu) }
                                }
                                if !s.musteriAdi.isEmpty && s.musteriAdi != s.ad {
                                    Text("Müşteriye: \(s.musteriAdi)").font(.caption).foregroundStyle(Tema.govde)
                                }
                                let ozet = kuralOzeti(s)
                                if !ozet.isEmpty { Text(ozet).font(.caption2).foregroundStyle(Tema.silik) }
                            }
                        }
                    }
                    .swipeActions {
                        Button("Sil", role: .destructive) { silinecek = s }
                    }
                }
            }
            Section {
                NavigationLink { StatuDuzenleEkrani(statu: nil) } label: { Label("Yeni statü", systemImage: "plus") }
            }
        }
        .navigationTitle("Statüler")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("\"\(silinecek?.ad ?? "")\" statüsü silinsin mi?", isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }),
                            titleVisibility: .visible) {
            Button("Sil", role: .destructive) { if let s = silinecek { Task { await silBasla(s) } } }
            Button("Vazgeç", role: .cancel) {}
        }
        .sheet(item: $tasinacak) { s in
            NavigationStack {
                Form {
                    Section {
                        Text("Bu statüdeki başvurular seçeceğiniz statüye taşınacak, ardından statü silinecek. Şartlı statüye toplu taşınamaz.")
                            .font(.caption)
                        Picker("Taşınacak statü", selection: $hedef) {
                            ForEach(ekip.statuler.filter { $0.id != s.id && $0.gerekenler.isEmpty }) { x in Text(x.ad).tag(x.id) }
                        }
                    } header: { Text("\"\(s.ad)\" kullanımda") }
                    Section {
                        Button(role: .destructive) { Task { await tasiVeSil(s) } } label: {
                            if calisiyor { ProgressView() } else { Text("Taşı ve sil") }
                        }
                        .disabled(calisiyor || hedef.isEmpty)
                    }
                }
                .navigationTitle("Statüyü sil")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { tasinacak = nil } } }
            }
        }
    }

    private func kuralOzeti(_ s: Statu) -> String {
        [
            s.silmeGun.map { "\($0) günde silinir" } ?? "",
            s.aramaMin.flatMap { a in s.aramaMax.map { "\(a)–\($0) gün içinde aranır" } } ?? "",
            s.gerekenler.isEmpty ? "" : "şart: " + s.gerekenler.compactMap { GecisSarti(rawValue: $0)?.ad }.joined(separator: ", "),
        ].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func tasiSira(_ i: Int, _ yon: Int) async {
        guard let c = ekip.calisan, ekip.statuler.indices.contains(i + yon) else { return }
        calisiyor = true
        let r = await ayarKaydet(ekip, StatuAyari.yerDegistir(ekip.statuler[i], ekip.statuler[i + yon], calisan: c))
        if r.tamam { await ekip.yukle() } else { mesaj = (false, r.mesaj) }
        calisiyor = false
    }

    /// Kullanılmıyorsa hemen silinir; kullanımdaysa hedef statü sorulur.
    private func silBasla(_ s: Statu) async {
        guard let c = ekip.calisan else { return }
        calisiyor = true
        defer { calisiyor = false }
        do {
            let f = try await ekip.istemci()
            let kullanan = try await f.sorgu(koleksiyon: "applications", kosullar: [.esit("statusId", .metin(s.id))], sinir: 1)
            if kullanan.isEmpty {
                let r = await ayarKaydet(ekip, StatuAyari.sil(s, calisan: c))
                mesaj = (r.tamam, r.tamam ? "Statü silindi." : r.mesaj)
                if r.tamam { await ekip.yukle() }
            } else {
                hedef = ekip.statuler.first { $0.id != s.id && $0.gerekenler.isEmpty }?.id ?? ""
                if hedef.isEmpty { mesaj = (false, "Taşınacak uygun statü yok.") } else { tasinacak = s }
            }
        } catch {
            mesaj = (false, HataAciklamasi.metin(error, "Kontrol edilemedi."))
        }
    }

    /// Başvuruları 100'erli taşır (her biri: statü + geçmiş + müşteri sayfası), sonra statüyü siler.
    private func tasiVeSil(_ s: Statu) async {
        guard let c = ekip.calisan, let h = ekip.statuler.first(where: { $0.id == hedef }) else { return }
        calisiyor = true
        defer { calisiyor = false }
        do {
            let f = try await ekip.istemci()
            var toplam = 0
            while true {
                let l = try await f.sorgu(koleksiyon: "applications", kosullar: [.esit("statusId", .metin(s.id))], sinir: 100)
                if l.isEmpty { break }
                var y: [FirestoreIstemci.Yazim] = []
                for d in l {
                    let b = Basvuru(kimlik: d.kimlik, alanlar: d.alanlar)
                    let k: [String: FSDeger]? = (try? await f.belge("applications/\(d.kimlik)/private/keys")) ?? nil
                    let t = k?["takipId"]?.metinDegeri
                    var notlar: FSDeger?
                    if let t { notlar = ((try? await f.belge("takip/\(t)")) ?? nil)?["notes"] }
                    y += StatuAyari.tasi(b, takipId: t, notlar: notlar, hedef: h, statuler: ekip.statuler, saklamaGun: ekip.saklamaGun, calisan: c)
                }
                try await f.isle(y)
                toplam += l.count
            }
            try await f.isle(StatuAyari.sil(s, ayrinti: "\(s.ad) → \(h.ad) (\(toplam) başvuru)", calisan: c))
            tasinacak = nil
            mesaj = (true, "\(toplam) başvuru taşındı, statü silindi.")
            await ekip.yukle()
        } catch {
            mesaj = (false, HataAciklamasi.metin(error, "Taşınamadı."))
        }
    }
}

/// Yeni / düzenle (panel: editStatus). Müşteriye görünen bir şey değişirse o statüdeki
/// (en çok 100) başvurunun müşteri sayfası tazelenir.
struct StatuDuzenleEkrani: View {
    let statu: Statu?
    @Environment(EkipOturumu.self) private var ekip
    @Environment(\.dismiss) private var kapat
    @State private var g = StatuGirdisi(nil)
    @State private var renk = Color.blue
    @State private var hazir = false
    @State private var calisiyor = false
    @State private var mesaj: (Bool, String)?

    var body: some View {
        Form {
            Section {
                TextField("Panel adı", text: $g.ad)
                TextField("Müşteriye görünen ad (boşsa panel adı)", text: $g.musteriAdi)
                TextField("Müşteriye açıklama", text: $g.aciklama, axis: .vertical).lineLimit(2...6)
                ColorPicker("Renk", selection: $renk, supportsOpacity: false)
                Toggle("Son adım (saklama sayacını başlatır)", isOn: $g.son)
                Toggle("Müşteriye bildir (e-posta / SMS)", isOn: $g.bildir)
            }
            Section {
                if !g.son {
                    gunSatiri("Bu statüde kalınca silinme", $g.silmeGun, 3650)
                }
                gunSatiri("Tekrar arama: en erken", $g.aramaMin, 365)
                gunSatiri("Tekrar arama: en geç", $g.aramaMax, 365)
            } header: { Text("Süre ve kurallar") } footer: {
                Text("Silme: statü bu kadar gün değişmezse başvuru tüm kişisel verileriyle silinir (ör. potansiyel müşteri 30). Arama: statüye geçtikten (ya da son \"Arandı\"dan) sonra bu aralıkta müşteri tekrar aranmalı.")
            }
            Section {
                ForEach(GecisSarti.allCases, id: \.rawValue) { s in
                    Toggle(s.ad, isOn: Binding(get: { g.gerekenler.contains(s.rawValue) }, set: { acik in
                        g.gerekenler.removeAll { $0 == s.rawValue }
                        if acik { g.gerekenler.append(s.rawValue) }
                    }))
                }
            } header: { Text("Bu statüye geçmeden önce tamamlanmalı") } footer: {
                Text("İşaretli olanlar tamamlanmadan başvuru bu statüye alınamaz.")
            }
            if let m = mesaj { Section { Text(m.1).foregroundStyle(m.0 ? Tema.olumluKoyu : Tema.olumsuz) } }
            Section {
                Button { Task { await kaydet() } } label: { if calisiyor { ProgressView() } else { Text("Kaydet") } }
                    .disabled(calisiyor || g.ad.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle(statu == nil ? "Yeni statü" : "Statüyü düzenle")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hazir else { return }
            g = StatuGirdisi(statu)
            renk = Color(kod: g.renk) ?? Tema.lacivert
            hazir = true
        }
    }

    private func gunSatiri(_ ad: String, _ deger: Binding<Int?>, _ enCok: Int) -> some View {
        HStack {
            Text(ad).font(.subheadline)
            Spacer()
            TextField("—", text: Binding(get: { deger.wrappedValue.map(String.init) ?? "" },
                                         set: { deger.wrappedValue = Int($0.filter(\.isNumber)).flatMap { $0 >= 1 && $0 <= enCok ? $0 : nil } }))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text("gün").font(.caption).foregroundStyle(Tema.govde)
        }
    }

    private func kaydet() async {
        guard let c = ekip.calisan else { return }
        g.renk = renk.hexKodu
        guard let k = StatuAyari.kaydet(g, mevcut: statu, statuler: ekip.statuler, calisan: c) else { mesaj = (false, "Panel adı zorunlu."); return }
        calisiyor = true
        defer { calisiyor = false }
        let r = await ayarKaydet(ekip, k.yazimlar)
        guard r.tamam else { mesaj = (false, r.mesaj); return }
        var not = "Statü kaydedildi."
        if let s = statu, s.silmeGun != g.silmeGun && !g.son { not += " Yeni silme süresi bu statüye bundan sonra geçen başvurulara uygulanır." }
        await ekip.yukle()
        if let s = statu, StatuAyari.musteriyeGorunenDegisti(s, g), let yeni = ekip.statuler.first(where: { $0.id == k.id }) {
            let n = await musteriSayfalariniTazele(yeni, c)
            if n > 0 { not += " \(n) başvurunun müşteri sayfası güncellendi." }
        }
        mesaj = (true, not)
        kapat()
    }

    /// O statüdeki ilk 100 başvurunun müşteri sayfası (panel: refreshApps(move=false)).
    private func musteriSayfalariniTazele(_ s: Statu, _ c: Calisan) async -> Int {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return 0 }
        #endif
        guard let f = try? await ekip.istemci(),
              let l = try? await f.sorgu(koleksiyon: "applications", kosullar: [.esit("statusId", .metin(s.id))], sinir: 100) else { return 0 }
        var y: [FirestoreIstemci.Yazim] = []
        for d in l {
            let k: [String: FSDeger]? = (try? await f.belge("applications/\(d.kimlik)/private/keys")) ?? nil
            guard let t = k?["takipId"]?.metinDegeri else { continue }
            let notlar = ((try? await f.belge("takip/\(t)")) ?? nil)?["notes"]
            y.append(StatuAyari.takipTazele(Basvuru(kimlik: d.kimlik, alanlar: d.alanlar), takipId: t, notlar: notlar, hedef: s, statuler: ekip.statuler))
        }
        if y.isEmpty { return 0 }
        return (try? await f.isle(y)) != nil ? y.count : 0
    }
}

extension Color {
    /// "#1e2c4d" biçiminde (statü rengi panelde de böyle saklanır).
    var hexKodu: String {
        let u = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        func iki(_ x: CGFloat) -> String {
            let n = max(0, min(255, Int((x * 255).rounded())))
            let h = String(n, radix: 16)
            return h.count == 1 ? "0" + h : h
        }
        return "#" + iki(r) + iki(g) + iki(b)
    }
}

// MARK: - Evrak kontrol listesi

/// Ayarlar → Evrak kontrol listesi (panel: ChecklistPanel). Ülke seçilmezse genel liste,
/// seçilince o ülkenin listesi (yoksa hazır ya da genel listeden başlar).
struct EvrakListesiAyarEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(IcerikDeposu.self) private var icerik
    @State private var genel: [Evrak] = []
    @State private var ulkeler: [String: [Evrak]] = [:]
    @State private var ulke = ""
    @State private var liste: [Evrak] = []
    @State private var hazir = false
    @State private var ulkeSec = false
    @State private var ulkeAdi = ""
    @State private var calisiyor = false
    @State private var mesaj: (Bool, String)?

    private var ozel: Bool { !ulke.isEmpty && ulkeler[ulke] != nil }

    var body: some View {
        let katalog = icerik.evrak
        let eksik = EvrakListesiAyari.eksikler(liste, ulke: ulke, katalog: katalog)
        Form {
            Section {
                Button { ulkeSec = true } label: {
                    HStack {
                        Text("Ülke").foregroundStyle(Tema.lacivert)
                        Spacer()
                        Text(ulke.isEmpty ? "Genel liste (tüm ülkeler)" : ulkeAdi).foregroundStyle(Tema.govde)
                    }
                }
            } footer: {
                Text(durumYazisi(katalog))
            }
            Section {
                ForEach($liste) { $e in
                    TextField("Evrak adı", text: $e.ad)
                }
                .onDelete { liste.remove(atOffsets: $0) }
                .onMove { liste.move(fromOffsets: $0, toOffset: $1) }
                Button { liste.append(Evrak(id: "yeni-\(UUID().uuidString)", ad: "")) } label: { Label("Evrak ekle", systemImage: "plus") }
                if !eksik.isEmpty {
                    Button("Eksik evrak türlerini ekle (\(eksik.count))") { liste += eksik }
                }
            }
            if ozel {
                Section {
                    Button(EvrakListesiAyari.hazirVar(ulke, katalog) ? "Hazır listeye dön" : "Genel listeye dön", role: .destructive) {
                        ulkeler[ulke] = nil
                        Task { await kaydet() }
                    }
                }
            }
            if let m = mesaj { Section { Text(m.1).foregroundStyle(m.0 ? Tema.olumluKoyu : Tema.olumsuz) } }
            Section {
                Button { Task { await kaydet() } } label: { if calisiyor { ProgressView() } else { Text("Listeyi kaydet") } }
                    .disabled(calisiyor)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Evrak listesi")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hazir else { return }
            genel = EvrakListesiAyari.genel(ekip.evrakAyari, katalog)
            ulkeler = ekip.evrakAyari.ulkeler
            liste = genel
            hazir = true
        }
        .sheet(isPresented: $ulkeSec) {
            ListeSecici(baslik: "Ülke", secenekler: icerik.akis.tumUlkeler.map(\.ad), secili: Binding(get: { ulkeAdi }, set: { ad in
                sakla()
                ulkeAdi = ad
                ulke = icerik.akis.tumUlkeler.first { $0.ad == ad }?.slug ?? ""
                yukle(katalog)
            }))
        }
    }

    private func durumYazisi(_ k: EvrakKatalogu) -> String {
        if ulke.isEmpty { return "Bu liste, kendi listesi tanımlanmamış tüm ülkelerde kullanılır." }
        if ozel { return "Bu ülkenin kendine ait listesi var." }
        return EvrakListesiAyari.hazirVar(ulke, k)
            ? "Bu ülke VizeMia'nın hazır listesini kullanıyor. Değişiklik yapıp kaydederseniz ülkeye özel liste oluşur."
            : "Bu ülke şu an genel listeyi kullanıyor. Değişiklik yapıp kaydederseniz ülkeye özel liste oluşur."
    }

    /// Ekrandaki listeyi kendi yerine koyar (ülke değişmeden önce).
    private func sakla() {
        if ulke.isEmpty { genel = liste } else if ulkeler[ulke] != nil || liste != EvrakListesiAyari.baslangic(ulke: ulke, ayar: ayar, katalog: icerik.evrak) {
            ulkeler[ulke] = liste
        }
    }

    private var ayar: EvrakAyari {
        var a = EvrakAyari(belge: nil)
        a.genel = genel
        a.ulkeler = ulkeler
        return a
    }

    private func yukle(_ k: EvrakKatalogu) {
        liste = ulke.isEmpty ? genel : EvrakListesiAyari.baslangic(ulke: ulke, ayar: ayar, katalog: k)
    }

    private func kaydet() async {
        guard let c = ekip.calisan else { return }
        if ulke.isEmpty { genel = liste } else if ulkeler[ulke] != nil || liste != EvrakListesiAyari.baslangic(ulke: ulke, ayar: ayar, katalog: icerik.evrak) {
            ulkeler[ulke] = liste
        }
        calisiyor = true
        defer { calisiyor = false }
        let r = await ayarKaydet(ekip, EvrakListesiAyari.kaydet(genel: genel, ulkeler: ulkeler, kapsam: ulke, calisan: c))
        mesaj = (r.tamam, r.tamam ? "Evrak listesi kaydedildi." : r.mesaj)
        if r.tamam {
            await ekip.yukle()
            genel = EvrakListesiAyari.genel(ekip.evrakAyari, icerik.evrak)
            ulkeler = ekip.evrakAyari.ulkeler
            yukle(icerik.evrak)
        }
    }
}
