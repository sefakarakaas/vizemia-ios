import SwiftUI
import VizeMiaCekirdek

// MARK: - Başvuru ayrıntısı: Müşteriye mesaj

/// Panelin "Müşteriye mesaj"ı (panel/js/pages/mesaj.js), başvurunun içinde:
/// kanal seç (e-posta, WhatsApp, SMS), hazır metin seç ya da yeni yaz, gönder.
/// Geçmiş üç kaynaktan: eposta/, sms/, mesajKaydi/. Panel müşteriyi 1000
/// başvuru içinden arıyor; burada açık olan başvuru kullanılır, liste okunmaz.
struct MusteriyeMesajKarti: View {
    let veri: BasvuruDetayVerisi
    let b: Basvuru
    let baglam: EkBaglami
    @Environment(EkipOturumu.self) private var ekip
    @State private var yaziyor = false
    @State private var kanal: MesajKanali = .eposta
    @State private var sablon = ""
    @State private var waSablon = ""
    @State private var konu = ""
    @State private var metin = ""
    @State private var hata: String?
    @State private var gonderiliyor = false
    @State private var iptalEdilecek: EpostaKaydi?
    @State private var duzenleniyor = false
    @State private var tumu = false

    private var adres: String { veri.iletisim?.eposta.trimmingCharacters(in: .whitespaces).lowercased() ?? "" }
    private var telefon: String { veri.iletisim?.telefon ?? "" }
    private var degerler: [String: String] {
        MusteriMesaji.degerler(b, statu: b.statuAdi, benimAdim: ekip.calisan?.gorunenAd ?? "")
    }
    /// Panel: eposta.send (WhatsApp kaydı ve tek müşteri maili bu izinle yazılır).
    private var yazabilir: Bool { ekip.yapabilir("eposta.send") }

    private func durum(_ k: MesajKanali) -> (olur: Bool, neden: String) {
        MusteriMesaji.kanalDurumu(k, eposta: adres, telefon: telefon, smsHazir: ekip.smsAyari.acik, smsIzni: ekip.yapabilir("app.status"))
    }

    private enum Oge: Identifiable {
        case eposta(EpostaKaydi)
        case diger(MesajSatiri)
        var id: String {
            switch self {
            case .eposta(let m): return "e-\(m.id)"
            case .diger(let s): return s.id
            }
        }
        var zaman: Date? {
            switch self {
            case .eposta(let m): return m.zaman
            case .diger(let s): return s.zaman
            }
        }
    }

    private var gecmis: [Oge] {
        (veri.epostalar.map { Oge.eposta($0) } + veri.mesajlar.map { Oge.diger($0) })
            .sorted { ($0.zaman ?? .distantPast) > ($1.zaman ?? .distantPast) }
    }

    var body: some View {
        let liste = gecmis
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Müşteriye mesaj").font(.headline).foregroundStyle(Tema.lacivert)
                Spacer()
                if yazabilir {
                    NavigationLink(value: EkipRota.bildirimGonder(b.kimlik)) {
                        Image(systemName: "bell.badge")
                    }
                    .buttonStyle(KucukDugme())
                    .accessibilityLabel("Uygulama bildirimi gönder")
                }
                if yazabilir && !yaziyor {
                    Button {
                        if let ilk = MesajKanali.allCases.first(where: { durum($0).olur }) { kanal = ilk }
                        withAnimation(Hareket.yay) { yaziyor = true }
                    } label: { Label("Mesaj yaz", systemImage: "square.and.pencil") }
                    .buttonStyle(KucukDugme())
                }
            }
            Text("E-posta hemen gider. WhatsApp müşterinin numarasına metin hazır açılır; gönder'e kendi WhatsApp'ınızda basarsınız. Her gönderim aşağıdaki geçmişe yazılır.")
                .font(.caption).foregroundStyle(Tema.govde)
            if yaziyor { yazmaAlani.transition(.opacity) }
            if liste.isEmpty {
                Text("Bu müşteriye henüz mesaj gönderilmedi.").font(.caption).foregroundStyle(Tema.govde)
            }
            ForEach(Array(liste.prefix(tumu ? 30 : 8))) { o in
                switch o {
                case .eposta(let m): EpostaSatiri(m: m, iptal: iptalEylemi(m))
                case .diger(let s): MesajGecmisSatiri(s: s)
                }
            }
            if liste.count > 8 && !tumu {
                Button("Tümünü göster (\(min(liste.count, 30)))") { withAnimation(Hareket.yay) { tumu = true } }
                    .buttonStyle(KucukDugme())
            }
        }
        .kart()
        .task(id: ekip.waTeyitSayaci) {
            // WhatsApp teyidi verildi: geçmiş yeniden okunur (ilk açılışta değil).
            if ekip.waTeyitSayaci > 0 { await veri.mesajlariYenile(ekip) }
        }
        .confirmationDialog("\"\(iptalEdilecek?.konu ?? "")\" maili iptal edilsin mi?",
                            isPresented: Binding(get: { iptalEdilecek != nil }, set: { if !$0 { iptalEdilecek = nil } }),
                            titleVisibility: .visible) {
            Button("İptal et", role: .destructive) {
                guard let m = iptalEdilecek else { return }
                Task { baglam.bildir(await veri.epostaIptal(m, ekip: ekip), "Mail iptal edildi.") }
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .sheet(isPresented: $duzenleniyor) {
            NavigationStack { WaSablonlariSayfasi() }
        }
    }

    private func iptalEylemi(_ m: EpostaKaydi) -> (() -> Void)? {
        guard m.iptalEdilebilir, ekip.yapabilir("eposta.send") || ekip.yapabilir("app.status") else { return nil }
        return { iptalEdilecek = m }
    }

    private var yazmaAlani: some View {
        let d = durum(kanal)
        return VStack(alignment: .leading, spacing: 12) {
            Divider()
            Picker("Kanal", selection: $kanal) {
                ForEach(MesajKanali.allCases) { k in Text(k.ad).tag(k) }
            }
            .pickerStyle(.segmented)
            .onChange(of: kanal) { _, _ in
                hata = nil
                sablon = ""
                waSablon = ""
            }
            if !d.olur {
                Label(d.neden, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Tema.olumsuz)
            } else {
                Text(kanal == .eposta ? "Alıcı: \(adres)" : "Numara: \(MusteriMesaji.telefonE164(telefon))")
                    .font(.caption.weight(.semibold)).foregroundStyle(Tema.govde)
            }
            if kanal == .eposta {
                HazirMetinSecici(secili: $sablon) { s in
                    konu = MusteriBildirimi.doldur(s.konu, degerler)
                    metin = MusteriBildirimi.doldur(s.metin, degerler)
                }
                EpostaMetniAlanlari(konu: $konu, metin: $metin)
            } else {
                waSablonSecici
                Alan(etiket: "Metin", yardim: "Yer tutucular: {ad} {adSoyad} {ulke} {statu} {takipKodu} {takipLinki} {form_link} {benim_adim} {benim_ilk_adim}") {
                    TextField("Metin", text: $metin, axis: .vertical).lineLimit(4...12).kutu()
                }
                Text("\(metin.count) / \(kanal.sinir)\(kanal == .sms ? " (Türkçe harfler sadeleşir)" : "")")
                    .font(.caption2)
                    .foregroundStyle(metin.count > kanal.sinir ? Tema.olumsuz : Tema.silik)
            }
            if let h = hata { AlanHatasi(metin: h) }
            HStack(spacing: 10) {
                Button("Vazgeç") { withAnimation(Hareket.yay) { yaziyor = false } }.buttonStyle(IkincilDugme())
                Button {
                    Task { await gonder() }
                } label: {
                    if gonderiliyor {
                        HStack(spacing: 8) { ProgressView().tint(Color.white); Text("Gönderiliyor…") }
                    } else {
                        Text(kanal == .whatsapp ? "WhatsApp’ta aç" : kanal == .sms ? "SMS gönder" : "E-posta gönder")
                    }
                }
                .buttonStyle(AnaDugme())
                .disabled(gonderiliyor || !d.olur)
            }
        }
    }

    @ViewBuilder private var waSablonSecici: some View {
        let l = ekip.waSablonlari ?? []
        Alan(etiket: "Hazır mesaj", istegeBagli: true) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Hazır mesaj", selection: $waSablon) {
                    Text("Yeni metin (şablonsuz)").tag("")
                    ForEach(l) { s in Text(s.baslik).tag(s.id) }
                }
                .pickerStyle(.menu)
                .tint(Tema.lacivert)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kutu()
                .onChange(of: waSablon) { _, yeni in
                    if let s = l.first(where: { $0.id == yeni }) {
                        metin = String(MusteriBildirimi.doldur(s.metin, degerler).prefix(kanal.sinir))
                    }
                }
                if ekip.yapabilir("lead.manage") || ekip.calisan?.yonetici == true {
                    Button("Hazır mesajları düzenle") { duzenleniyor = true }.buttonStyle(KucukDugme())
                }
            }
        }
        .task { await ekip.waSablonlariYukle() }
    }

    private func gonder() async {
        hata = nil
        let d = durum(kanal)
        guard d.olur else { hata = d.neden; return }
        let m = MusteriBildirimi.doldur(metin, degerler).trimmingCharacters(in: .whitespacesAndNewlines)
        let k = MusteriBildirimi.doldur(konu, degerler).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty, kanal != .eposta || !k.isEmpty else {
            hata = kanal == .eposta ? "Konu ve metin boş olamaz." : "Metin boş olamaz."
            return
        }
        let kalan = EpostaIslemi.bosYerTutucular(kanal == .eposta ? "\(k) \(m)" : m)
        guard kalan.isEmpty else { hata = "Doldurulamayan yer tutucu var: {\(kalan.joined(separator: "} {"))}. Metni düzeltin."; return }
        if kanal != .eposta && m.count > kanal.sinir { hata = "Metin en çok \(kanal.sinir) karakter olabilir."; return }

        switch kanal {
        case .whatsapp:
            let t = WaTeyidi(appId: b.kimlik, telefon: telefon, ad: "\(b.ad) \(b.soyad)".trimmingCharacters(in: .whitespaces),
                             metin: m, sablon: waSablon)
            guard ekip.waAc(t) else { hata = "Müşterinin telefon numarası yok ya da hatalı."; return }
            temizle()
        case .sms:
            gonderiliyor = true
            let r = await veri.smsGonder(m, ekip: ekip)
            gonderiliyor = false
            if r.tamam { temizle(); baglam.bildir(nil, r.mesaj) } else { hata = r.mesaj }
        case .eposta:
            gonderiliyor = true
            let r = await veri.epostaGonder(konu: k, metin: m, ekip: ekip)
            gonderiliyor = false
            if r.tamam { temizle(); baglam.bildir(nil, r.mesaj) } else { hata = r.mesaj }
        }
    }

    private func temizle() {
        konu = ""; metin = ""; sablon = ""; waSablon = ""
        withAnimation(Hareket.yay) { yaziyor = false }
    }
}

/// SMS ya da WhatsApp geçmiş satırı.
struct MesajGecmisSatiri: View {
    let s: MesajSatiri

    private var renk: Color {
        switch s.durum {
        case "Gönderildi": return Tema.olumluKoyu
        case "Gönderilemedi", "Gönderilmedi": return Tema.olumsuz
        case "İptal": return Tema.silik
        default: return Tema.mavi
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: s.kanal == .whatsapp ? "message.fill" : "text.bubble.fill")
                .font(.subheadline)
                .foregroundStyle(s.kanal == .whatsapp ? Tema.olumluKoyu : Tema.mavi)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.metin).font(.subheadline).foregroundStyle(Tema.lacivert).lineLimit(3)
                Text([s.kanal.ad, s.zaman.map { Tr.tarihSaat($0) } ?? "", s.kim].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Tema.silik)
                Text(s.durum).font(.caption.weight(.semibold)).foregroundStyle(renk)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - WhatsApp teyidi

/// "Mesajı gönderdiniz mi?" Kapatılamaz: Gönderdim ya da Göndermedim seçilmeden
/// devam edilemez (panel: wa-teyit.js). Cevap yazılamazsa soru açık kalır.
struct WaTeyitSayfasi: View {
    @Environment(EkipOturumu.self) private var ekip
    @State private var kaydediliyor = false
    @State private var hata: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mesajı gönderdiniz mi?").font(.title3.weight(.bold)).foregroundStyle(Tema.lacivert)
            if let t = ekip.bekleyenWa {
                Text("\(t.ad.isEmpty ? "Müşteri" : t.ad) (\(MusteriMesaji.telefonE164(t.telefon))) için WhatsApp açıldı. WhatsApp'ta gönder'e bastıysanız \"Gönderdim\", vazgeçtiyseniz \"Göndermedim\" seçin.")
                    .font(.subheadline).foregroundStyle(Tema.govde)
                ScrollView {
                    Text(t.metin).font(.callout).foregroundStyle(Tema.lacivert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .kutu()
                Button {
                    if let u = MusteriMesaji.waBaglantisi(telefon: t.telefon, metin: t.metin) { UIApplication.shared.open(u) }
                } label: { Label("WhatsApp'ı yeniden aç", systemImage: "arrow.up.forward.app") }
                .buttonStyle(KucukDugme())
            }
            if let h = hata { AlanHatasi(metin: "Kaydedilemedi: \(h) Tekrar deneyin.") }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("Göndermedim") { Task { await cevap(false) } }.buttonStyle(IkincilDugme())
                Button {
                    Task { await cevap(true) }
                } label: {
                    if kaydediliyor { ProgressView().tint(Color.white) } else { Text("Gönderdim") }
                }
                .buttonStyle(AnaDugme())
            }
            .disabled(kaydediliyor)
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    private func cevap(_ gonderildi: Bool) async {
        kaydediliyor = true
        hata = await ekip.waTeyitKaydet(gonderildi: gonderildi)
        kaydediliyor = false
    }
}

// MARK: - Hazır WhatsApp/SMS mesajları

/// WhatsApp düğmesi: hazır mesaj seçilir, metin hazır açılır, uygulamaya dönünce
/// teyit sorulur. "Boş sohbet aç" teyitsiz açar (panelde de öyle).
struct WaMenusu<Etiket: View>: View {
    let telefon: String
    let degerler: [String: String]
    let teyit: (_ metin: String, _ sablon: String) -> WaTeyidi
    @ViewBuilder var etiket: () -> Etiket
    @Environment(EkipOturumu.self) private var ekip

    var body: some View {
        Menu {
            ForEach(ekip.waSablonlari ?? []) { s in
                Button(s.baslik) {
                    let m = WaSablonu.doldur(s.metin, degerler)
                    if !m.isEmpty { _ = ekip.waAc(teyit(m, s.id)) }
                }
            }
            Button {
                let e164 = MusteriMesaji.telefonE164(telefon)
                let rakam = e164.isEmpty ? telefon.filter { $0.isASCII && $0.isNumber } : String(e164.dropFirst())
                if let u = URL(string: "https://wa.me/\(rakam)") { UIApplication.shared.open(u) }
            } label: { Label("Boş sohbet aç", systemImage: "bubble.left") }
        } label: {
            etiket()
        }
        .task { await ekip.waSablonlariYukle() }
    }
}

/// Ekleme / düzenleme / kaldırma (panel: waSablonPenceresi; yönetici ve lead.manage).
struct WaSablonlariSayfasi: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(\.dismiss) private var kapat
    @State private var liste: [WaSablonu] = []
    @State private var yuklendi = false
    @State private var kaydediliyor = false
    @State private var hata: String?

    var body: some View {
        Form {
            Section {
                Text("Talepler ve müşteriye mesajda seçilen hazır metinler. Yer tutucular: {ad} {tam_ad} {ulke} {kod} {form_link} {takip_link} {benim_adim} {benim_ilk_adim}")
                    .font(.caption).foregroundStyle(Tema.govde)
            }
            ForEach($liste) { $s in
                Section {
                    TextField("Başlık", text: $s.baslik)
                    TextField("Metin", text: $s.metin, axis: .vertical).lineLimit(3...10)
                    Text("\(s.metin.count) / \(MusteriMesaji.waEnCok)").font(.caption2)
                        .foregroundStyle(s.metin.count > MusteriMesaji.waEnCok ? Tema.olumsuz : Tema.silik)
                    Button("Kaldır", role: .destructive) {
                        let id = s.id
                        withAnimation { liste.removeAll { $0.id == id } }
                    }
                }
            }
            if liste.count < WaSablonu.enCok {
                Section {
                    Button {
                        withAnimation { liste.append(WaSablonu(id: WaSablonu.geciciKimlik(), baslik: "", metin: "")) }
                    } label: { Label("Yeni hazır mesaj", systemImage: "plus") }
                }
            }
            if let h = hata { Section { Text(h).font(.caption).foregroundStyle(Tema.olumsuz) } }
        }
        .navigationTitle("Hazır mesajlar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
            ToolbarItem(placement: .confirmationAction) {
                if kaydediliyor { ProgressView() } else { Button("Kaydet") { Task { await kaydet() } }.disabled(!yuklendi) }
            }
        }
        .task {
            await ekip.waSablonlariYukle()
            if !yuklendi { liste = ekip.waSablonlari ?? []; yuklendi = true }
        }
    }

    private func kaydet() async {
        hata = nil
        if liste.contains(where: { $0.baslik.trimmingCharacters(in: .whitespaces).isEmpty || $0.metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            hata = "Başlığı ya da metni boş olan hazır mesaj var; doldurun ya da kaldırın."
            return
        }
        if liste.contains(where: { $0.metin.count > MusteriMesaji.waEnCok }) {
            hata = "Metin en çok \(MusteriMesaji.waEnCok) karakter olabilir."
            return
        }
        kaydediliyor = true
        hata = await ekip.waSablonlariKaydet(liste)
        kaydediliyor = false
        if hata == nil { kapat() }
    }
}
