import SwiftUI
import VizeMiaCekirdek

/// Armut (panel: #/armut): Chrome eklentisinin Armut.com'dan aktardığı işler.
/// Danışman inceler ("İncelendi" / "İlgisiz"), iç not yazar, müşteriyle
/// görüşülecekse Talepler'e aktarır.
struct ArmutEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @AppStorage("armut.sira") private var sira = "armut"
    @State private var isler: [ArmutIsi] = []
    @State private var filtre = "acik"
    @State private var telefon = ""
    @State private var ara = ""
    @State private var hata: String?
    @State private var bildiri: String?
    @State private var yukleniyor = false
    @State private var aktarilacak: ArmutIsi?

    /// Ekranda gösterilen kadar okunur (panel 300).
    static let sinir = 100

    private var gorunen: [ArmutIsi] {
        let q = ara.trimmingCharacters(in: .whitespaces).lowercased(with: Tr.yerel)
        return ArmutIsi.sirala(isler, sira).filter { k in
            if filtre == "acik" ? !["yeni", "incelendi"].contains(k.incelemeDurum) : (!filtre.isEmpty && k.incelemeDurum != filtre) { return false }
            if telefon == "var" && k.telefon.isEmpty { return false }
            if telefon == "yok" && !k.telefon.isEmpty { return false }
            if q.isEmpty { return true }
            return [k.ad, k.telefon, k.isId, k.baslik, k.kategori, k.konum].contains { $0.lowercased(with: Tr.yerel).contains(q) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                TextField("Ad, telefon, iş başlığı ya da konum", text: $ara).autocorrectionDisabled().kutu()
                HStack(spacing: 8) {
                    Menu {
                        Picker("Durum", selection: $filtre) {
                            Text("Bekleyenler (yeni + incelendi)").tag("acik")
                            ForEach(0..<ArmutIsi.incelemeDurumlari.count, id: \.self) { i in
                                Text(ArmutIsi.incelemeDurumlari[i].ad).tag(ArmutIsi.incelemeDurumlari[i].id)
                            }
                            Text("Tümü").tag("")
                        }
                        Picker("Telefon", selection: $telefon) {
                            Text("Telefon: tümü").tag("")
                            Text("Telefonu olanlar").tag("var")
                            Text("Telefonu olmayanlar").tag("yok")
                        }
                        Picker("Sıralama", selection: $sira) {
                            Text("Armut sırası").tag("armut")
                            Text("Teklif tarihi (yeni → eski)").tag("teklif")
                            Text("Panele geliş (yeni → eski)").tag("gelis")
                        }
                    } label: { Label("Süzgeç ve sıralama", systemImage: "line.3.horizontal.decrease.circle") }
                    .buttonStyle(KucukDugme())
                    Spacer()
                    Text("\(gorunen.count) iş · \(isler.filter { $0.incelemeDurum == "yeni" }.count) yeni").font(.caption).foregroundStyle(Tema.silik)
                }
                if let h = hata { AlanHatasi(metin: h) }
                if let b = bildiri { Label(b, systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Tema.olumluKoyu) }
                if yukleniyor && isler.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if gorunen.isEmpty {
                    ContentUnavailableView(isler.isEmpty ? "Henüz Armut'tan iş gelmedi" : "Bu süzgece uyan iş yok", systemImage: "leaf")
                }
                ForEach(gorunen) { k in
                    ArmutKarti(k: k, ayniMusteri: isler.filter { $0.id != k.id && !k.telefon.isEmpty && $0.telefon == k.telefon },
                               durum: { d in Task { await durumYap(k, d) } },
                               notKaydet: { n in Task { await notKaydet(k, n) } },
                               aktar: { aktarilacak = k })
                }
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("Armut")
        .navigationBarTitleDisplayMode(.inline)
        .task { if isler.isEmpty { await yukle() } }
        .refreshable { await yukle() }
        .sheet(item: $aktarilacak) { k in
            ArmutAktarSayfasi(k: k) { m in bildiri = m; Task { await tekKayit(k.id) } }
        }
    }

    private func yukle() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") {
            isler = [ArmutIsi(kimlik: "armut_1", alanlar: [
                "isId": .metin("12345"), "ad": .metin("Mehmet Demir"), "telefon": .metin("+905321112233"), "baslik": .metin("Schengen vizesi"),
                "kategori": .metin("Vize danışmanlığı"), "konum": .metin("Ankara, Çankaya"), "teklifTutari": .tam(2500), "armutDurum": .metin("quoted"),
                "aciklama": .metin("Almanya, aile ziyareti; 2 kişi"), "incelemeDurum": .metin("yeni"), "armutSira": .tam(0),
                "soruCevap": .dizi([.harita(["soru": .metin("Kaç kişi?"), "cevap": .metin("2")])]),
            ])]
            return
        }
        #endif
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let l = try await ekip.istemci().sorgu(koleksiyon: "armutTalepleri", sirala: ("createdAt", .azalan), sinir: Self.sinir)
            isler = l.map { ArmutIsi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            hata = nil
        } catch {
            hata = KasaVerisi.mesaj(error, "Armut işleri yüklenemedi.")
        }
    }

    /// İşlemden sonra yalnız o kayıt yeniden okunur.
    private func tekKayit(_ id: String) async {
        guard let a = try? await ekip.istemci().belge("armutTalepleri/\(id)"), let i = isler.firstIndex(where: { $0.id == id }) else { return }
        isler[i] = ArmutIsi(kimlik: id, alanlar: a)
    }

    private func isle(_ y: [FirestoreIstemci.Yazim], _ id: String, _ mesaj: String) async {
        guard let _ = ekip.calisan else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { bildiri = mesaj; return }
        #endif
        do {
            try await ekip.istemci().isle(y)
            await tekKayit(id)
            bildiri = mesaj
            hata = nil
        } catch {
            hata = KasaVerisi.mesaj(error, "Kaydedilemedi.")
        }
    }

    private func durumYap(_ k: ArmutIsi, _ d: String) async {
        guard let c = ekip.calisan else { return }
        await isle(ArmutIsi.durumYazimlari(k, d, calisan: c), k.id, "\(k.gorunenAd): \(ArmutIsi.incelemeDurumlari.first { $0.id == d }?.ad ?? d).")
    }

    private func notKaydet(_ k: ArmutIsi, _ n: String) async {
        guard let c = ekip.calisan else { return }
        await isle([ArmutIsi.guncelle(k, icNot: n, calisan: c)], k.id, "Not kaydedildi.")
    }
}

struct ArmutKarti: View {
    let k: ArmutIsi
    let ayniMusteri: [ArmutIsi]
    let durum: (String) -> Void
    let notKaydet: (String) -> Void
    let aktar: () -> Void
    @Environment(EkipOturumu.self) private var ekip
    @State private var acik = false
    @State private var not = ""

    private var renk: Color {
        switch k.incelemeDurum {
        case "incelendi": return Tema.mavi
        case "aktarildi": return Tema.olumlu
        case "ilgisiz": return Tema.silik
        default: return Tema.turkuaz
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(Hareket.yay) { acik.toggle() } } label: { ozet }.buttonStyle(.plain)
            if acik { govde.transition(.opacity) }
        }
        .kart()
        .overlay(RoundedRectangle(cornerRadius: Tema.kose).stroke(k.incelemeDurum == "yeni" ? Tema.turkuaz : Color.clear, lineWidth: 1.5))
        .onAppear { not = k.icNot }
    }

    private var ozet: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Etiket(metin: "Armut", renk: Tema.olumlu)
                    Text(k.gorunenAd).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert).lineLimit(1)
                }
                if !k.kategori.isEmpty { Text(k.kategori).font(.caption).foregroundStyle(Tema.govde) }
                HStack(spacing: 6) {
                    Etiket(metin: k.armutDurumAdi, renk: Tema.mavi)
                    Etiket(metin: k.incelemeAdi, renk: renk)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: acik ? "chevron.up" : "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var govde: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !k.telefon.isEmpty {
                HStack(spacing: 8) {
                    if let u = URL(string: "tel:\(k.telefon)") { Link(k.telefon, destination: u).font(.subheadline.monospaced()) }
                    if let u = URL(string: "https://wa.me/\(k.telefon.filter(\.isNumber))") {
                        Link(destination: u) { Label("WhatsApp", systemImage: "message.fill").font(.caption.weight(.semibold)) }
                    }
                }
            } else {
                bilgi("Telefon", "Henüz açılmadı")
            }
            if !k.eposta.isEmpty { bilgi("E-posta", k.eposta) }
            bilgi("Verdiğimiz teklif", ArmutIsi.tutarYaz(k.teklifTutari, k.paraBirimi))
            bilgi("Konum", k.konum.isEmpty ? "—" : k.konum)
            bilgi("İş tarihi", k.isTarihi.isEmpty ? "—" : k.isTarihi)
            if let d = k.digerTeklifSayisi { bilgi("Diğer firmaların teklifi", "\(d)") }
            bilgi("Teklif verildi", k.armutTeklifTarihi.map { Tr.tarihSaat($0) } ?? "—")
            bilgi("Panele geldi", k.paneleGelis.map { Tr.tarihSaat($0) } ?? "—")
            if !k.aktaranKisi.isEmpty { bilgi("Talepler'e aktaran", "\(k.aktaranKisi)\(k.aktarilmaTarihi.map { " · " + Tr.tarihSaat($0) } ?? "")") }
            bilgi("İş no", k.isId.isEmpty ? "—" : k.isId)
        }
        if !k.aciklama.isEmpty { blok("Müşterinin notu", k.aciklama) }
        if !k.sonMesaj.isEmpty { blok("Armut'taki son mesaj\(k.sonMesajSaat.isEmpty ? "" : " · \(k.sonMesajSaat)")", k.sonMesaj) }
        if !k.soruCevap.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Soru-cevaplar").font(.caption.weight(.bold)).foregroundStyle(Tema.lacivert)
                ForEach(0..<k.soruCevap.count, id: \.self) { i in
                    Text("\(k.soruCevap[i].soru): \(k.soruCevap[i].cevap.isEmpty ? "—" : k.soruCevap[i].cevap)").font(.caption).foregroundStyle(Tema.govde)
                }
            }
        }
        if !k.mesajlar.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Armut mesajları (\(k.mesajlar.count))").font(.caption.weight(.bold)).foregroundStyle(Tema.lacivert)
                ForEach(0..<k.mesajlar.count, id: \.self) { i in
                    let m = k.mesajlar[i]
                    VStack(alignment: m.bizden ? .trailing : .leading, spacing: 2) {
                        Text("\(m.bizden ? "Biz" : "Müşteri")\(m.saat.isEmpty ? "" : " · \(m.saat)")").font(.caption2).foregroundStyle(Tema.silik)
                        Text(m.metin).font(.caption).foregroundStyle(Tema.govde)
                            .padding(8)
                            .background(m.bizden ? Tema.soluk : Tema.zeminYumusak, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .frame(maxWidth: .infinity, alignment: m.bizden ? .trailing : .leading)
                }
            }
        }
        if !ayniMusteri.isEmpty {
            Text("Aynı müşterinin diğer Armut işleri: \(ayniMusteri.map { $0.kategori.isEmpty ? ($0.baslik.isEmpty ? $0.isId : $0.baslik) : $0.kategori }.joined(separator: ", "))")
                .font(.caption).foregroundStyle(Tema.mavi)
        }
        if !k.talepId.isEmpty {
            Label("Talepler'e aktarıldı", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Tema.olumluKoyu)
        }
        eylemler
    }

    private var eylemler: some View {
        let yonetir = ekip.yapabilir("armut.manage")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let u = URL(string: k.url), k.url.hasPrefix("https://") {
                    Link(destination: u) { Text("Armut'ta aç") }.buttonStyle(KucukDugme())
                }
                if yonetir && k.incelemeDurum != "aktarildi" {
                    if k.incelemeDurum != "incelendi" { Button("İncelendi") { durum("incelendi") }.buttonStyle(KucukDugme()) }
                    if k.incelemeDurum != "ilgisiz" { Button("İlgisiz") { durum("ilgisiz") }.buttonStyle(KucukDugme()) }
                    if k.incelemeDurum != "yeni" { Button("Yeniye al") { durum("yeni") }.buttonStyle(KucukDugme()) }
                }
            }
            if yonetir && k.incelemeDurum != "aktarildi" && ekip.yapabilir("lead.manage") {
                Button { aktar() } label: { Label("Talepler'e aktar", systemImage: "arrow.right.circle.fill") }
                    .buttonStyle(AnaDugme())
            }
            if yonetir {
                TextField("İç not (yalnız ekip görür)", text: $not, axis: .vertical).lineLimit(2...5).kutu()
                if not != k.icNot { Button("Notu kaydet") { notKaydet(not) }.buttonStyle(KucukDugme()) }
            } else if !k.icNot.isEmpty {
                Text("İç not: \(k.icNot)").font(.caption).foregroundStyle(Tema.govde)
            }
        }
    }

    private func bilgi(_ ad: String, _ deger: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ad).font(.caption2.weight(.semibold)).foregroundStyle(Tema.silik).frame(width: 110, alignment: .leading)
            Text(deger).font(.caption).foregroundStyle(Tema.lacivert)
        }
    }

    private func blok(_ baslik: String, _ metin: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(baslik).font(.caption.weight(.bold)).foregroundStyle(Tema.lacivert)
            Text(metin).font(.caption).foregroundStyle(Tema.govde)
        }
    }
}

/// Talepler'e aktar: şimdi görüşüldü ya da tekrar aranacak (gün ve saat), KVKK onayı.
struct ArmutAktarSayfasi: View {
    let k: ArmutIsi
    let bitti: (String) -> Void
    @Environment(EkipOturumu.self) private var ekip
    @Environment(IcerikDeposu.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State private var t = ElleTalep()
    @State private var tarih = Date()
    @State private var hata: String?
    @State private var calisiyor = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(k.telefon.isEmpty
                         ? "\(k.gorunenAd) Talepler'e eklenecek. Telefonu açılmadığı için iletişim Armut mesajlarından sürer; müşteriye otomatik mesaj gitmez."
                         : "\(k.ad.isEmpty ? "Müşteri" : k.ad) (\(k.telefon)) Talepler'e eklenecek; Armut bilgileri (iş, teklif, soru-cevaplar) talebin notuna yazılır.")
                        .font(.footnote)
                }
                AramaZamaniBolumu(t: $t, tarih: $tarih, mesai: depo.mesai, armutla: k.telefon.isEmpty)
                Section { Toggle("Müşteriye kişisel verilerinin işleneceği anlatıldı ve onayı alındı (KVKK)", isOn: $t.onay) }
                if let h = hata { Section { Text(h).foregroundStyle(Tema.olumsuz) } }
                Section {
                    Button { Task { await aktar() } } label: { if calisiyor { ProgressView() } else { Text("Aktar") } }.disabled(calisiyor)
                }
            }
            .navigationTitle("Talepler'e aktar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
        }
    }

    private func aktar() async {
        guard let c = ekip.calisan else { return }
        var x = t
        x.tarih = Tr.isoGun(tarih, takvim: Tr.takvim)
        let r = ArmutIsi.aktar(k, talep: x, bugun: Tr.bugun(), mesai: depo.mesai, calisan: c)
        if !r.hatalar.isEmpty { hata = r.hatalar.joined(separator: " "); return }
        calisiyor = true
        defer { calisiyor = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { bitti("Talepler'e aktarıldı."); kapat(); return }
        #endif
        do {
            try await ekip.istemci().isle(r.yazimlar)
            bitti(x.sonra ? "Talepler'e aktarıldı: \(BildirimMetni.trTarih(x.tarih, gun: false)) \(x.saat)'de aranacak." : "Talepler'e aktarıldı.")
            kapat()
        } catch {
            hata = KasaVerisi.mesaj(error, "Aktarılamadı.")
        }
    }
}

/// "Şimdi görüşüldü" ya da "Tekrar aranacak" (gün ve mesai içinden saat).
struct AramaZamaniBolumu: View {
    @Binding var t: ElleTalep
    @Binding var tarih: Date
    let mesai: Mesai
    var armutla = false

    var body: some View {
        Section("Durum") {
            Picker("Durum", selection: $t.sonra) {
                Text("Görüşüldü (şimdi konuşuldu)").tag(false)
                Text(armutla ? "Tekrar dönülecek" : "Tekrar aranacak").tag(true)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if t.sonra {
                DatePicker("Arama günü", selection: $tarih, in: Date()..., displayedComponents: .date).environment(\.locale, Tr.yerel)
                Picker("Arama saati", selection: $t.saat) {
                    ForEach(mesai.aramaDilimleri, id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .onAppear { if t.saat.isEmpty { t.saat = mesai.simdikiSaat() } }
    }
}

/// Talepler → "Telefonla gelen müşteri": arayan müşteriyi Talepler'e ekler.
struct ElleTalepSayfasi: View {
    let bitti: (String) -> Void
    @Environment(EkipOturumu.self) private var ekip
    @Environment(IcerikDeposu.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State private var t = ElleTalep()
    @State private var tarih = Date()
    @State private var ulkeSeciliyor = false
    @State private var hata: String?
    @State private var calisiyor = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Müşteri") {
                    TextField("Ad soyad", text: $t.ad).textContentType(.name)
                    TextField("Telefon (0532 123 45 67)", text: $t.telefon).keyboardType(.phonePad)
                    TextField("E-posta (isteğe bağlı)", text: $t.eposta).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { ulkeSeciliyor = true } label: {
                        HStack {
                            Text("Ülke").foregroundStyle(Tema.lacivert)
                            Spacer()
                            Text(t.ulkeAdi.isEmpty ? "Seçin (isteğe bağlı)" : t.ulkeAdi).foregroundStyle(Tema.govde)
                        }
                    }
                    TextField("Not (görüşmede konuşulanlar)", text: $t.not, axis: .vertical).lineLimit(2...6)
                }
                AramaZamaniBolumu(t: $t, tarih: $tarih, mesai: depo.mesai)
                Section("Müşteriye haber verme yolu") {
                    Toggle("WhatsApp", isOn: $t.wa)
                    Toggle("SMS", isOn: $t.sms)
                    Toggle("E-posta", isOn: $t.email)
                }
                Section { Toggle("Müşteriye kişisel verilerinin işleneceği anlatıldı ve onayı alındı (KVKK)", isOn: $t.onay) }
                if let h = hata { Section { Text(h).foregroundStyle(Tema.olumsuz) } }
                Section {
                    Button { Task { await kaydet() } } label: { if calisiyor { ProgressView() } else { Text("Talepler'e ekle") } }.disabled(calisiyor)
                }
            }
            .navigationTitle("Telefonla gelen müşteri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
            .sheet(isPresented: $ulkeSeciliyor) {
                UlkeSecici(kitalar: depo.akis.kitalar, secili: t.ulke) { u in t.ulke = u.slug; t.ulkeAdi = u.ad }
            }
        }
    }

    private func kaydet() async {
        guard let c = ekip.calisan else { return }
        var x = t
        x.tarih = Tr.isoGun(tarih, takvim: Tr.takvim)
        let r = x.kayit(bugun: Tr.bugun(), mesai: depo.mesai)
        guard let alanlar = r.alanlar else { hata = r.hatalar.joined(separator: " "); return }
        calisiyor = true
        defer { calisiyor = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { bitti("Talep eklendi."); kapat(); return }
        #endif
        do {
            try await ekip.istemci().isle(ElleTalep.yazimlar(alanlar, calisan: c))
            bitti(x.sonra ? "Talep eklendi: \(BildirimMetni.trTarih(x.tarih, gun: false)) \(x.saat)'de aranacak." : "Talep eklendi (görüşüldü).")
            kapat()
        } catch {
            hata = KasaVerisi.mesaj(error, "Eklenemedi.")
        }
    }
}
