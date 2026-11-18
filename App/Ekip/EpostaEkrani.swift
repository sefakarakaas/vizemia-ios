import SwiftUI
import VizeMiaCekirdek

/// E-posta (panel: #/eposta). Müşterilere iletisim@vizemia.com adresinden.
/// Elle gönderilen mail hemen gider; statü mailleri 30 dakika bekler.
struct EpostaEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @State private var kayitlar: [EpostaKaydi] = []
    @State private var filtre = ""
    @State private var yukleniyor = false
    @State private var hata: String?
    @State private var iptalEdilecek: EpostaKaydi?
    @State private var bildiri: String?
    @State private var basari = 0

    /// Ekranda gösterilen kadar okunur (panel 300).
    static let sinir = 100

    /// "Gönderiliyor" iki kodla yazılıyor; filtrede bir kez görünsün.
    static let filtreler: [Int] = EpostaKaydi.durumAdlari.indices.filter { EpostaKaydi.durumAdlari[$0].id != "hazir" }

    private var gorunen: [EpostaKaydi] { filtre.isEmpty ? kayitlar : kayitlar.filter { $0.durum == filtre } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Elle gönderilen mailler (tek müşteri, serbest) Gönder'e basınca hemen gider. Statü değişince giden otomatik mailler 30 dakika bekler ve yalnız gönderim saatlerinde gider. Günlük sınır: \(ekip.epostaAyari.gunlukSinir) mail.")
                    .font(.caption).foregroundStyle(Tema.govde)
                if ekip.yapabilir("eposta.send") || ekip.yapabilir("eposta.kampanya") {
                    NavigationLink(value: EkipRota.topluEposta) {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.badge.person.crop").font(.title3).foregroundStyle(Tema.turkuaz)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Toplu gönder").font(.headline).foregroundStyle(Tema.lacivert)
                                Text("Bilgilendirme ya da kampanya: başvurular, talepler, müşteri arşivi")
                                    .font(.caption).foregroundStyle(Tema.govde)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
                        }
                        .kart()
                    }
                    .buttonStyle(.plain)
                }
                if ekip.yapabilir("eposta.send") {
                    SerbestEpostaKarti { m in
                        goster(m)
                        Task { await yukle() }
                    }
                    .belirme(0)
                }
                gonderimler.belirme(1)
            }
            .padding(Tema.bosluk)
        }
        .formKlavyesi()
        .ekranZemini()
        .navigationTitle("E-posta")
        .navigationBarTitleDisplayMode(.inline)
        .task { if kayitlar.isEmpty { await yukle() } }
        .refreshable { await yukle() }
        .confirmationDialog("\(iptalEdilecek?.alici ?? "") adresine gidecek \"\(iptalEdilecek?.konu ?? "")\" maili iptal edilsin mi?",
                            isPresented: Binding(get: { iptalEdilecek != nil }, set: { if !$0 { iptalEdilecek = nil } }),
                            titleVisibility: .visible) {
            Button("İptal et", role: .destructive) {
                guard let m = iptalEdilecek else { return }
                Task { await iptal(m) }
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .overlay(alignment: .top) {
            if let m = bildiri {
                Label(m, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Tema.olumluKoyu, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Hareket.yay, value: bildiri)
        .sensoryFeedback(.success, trigger: basari)
    }

    private var gonderimler: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gönderimler").font(.headline).foregroundStyle(Tema.lacivert)
                Spacer()
                Picker("Durum", selection: $filtre) {
                    Text("Tümü").tag("")
                    ForEach(Self.filtreler, id: \.self) { i in
                        Text(EpostaKaydi.durumAdlari[i].ad).tag(EpostaKaydi.durumAdlari[i].id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Tema.lacivert)
            }
            if let h = hata { AlanHatasi(metin: h) }
            if yukleniyor && kayitlar.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if gorunen.isEmpty {
                Text("Kayıt yok.").font(.caption).foregroundStyle(Tema.govde)
            }
            ForEach(gorunen) { m in
                EpostaSatiri(m: m, iptal: iptalEylemi(m))
                if m.id != gorunen.last?.id { Divider() }
            }
        }
        .kart()
    }

    private func iptalEylemi(_ m: EpostaKaydi) -> (() -> Void)? {
        guard m.iptalEdilebilir, ekip.yapabilir("eposta.send") || ekip.yapabilir("eposta.kampanya") || ekip.yapabilir("app.status")
        else { return nil }
        return { iptalEdilecek = m }
    }

    private func yukle() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { kayitlar = Self.ornek(); return }
        #endif
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let l = try await ekip.istemci().sorgu(koleksiyon: "eposta", sirala: ("createdAt", .azalan), sinir: Self.sinir)
            kayitlar = l.map { EpostaKaydi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            hata = nil
        } catch {
            hata = KasaVerisi.mesaj(error, "Gönderimler yüklenemedi.")
        }
    }

    private func iptal(_ m: EpostaKaydi) async {
        guard let c = ekip.calisan else { return }
        do {
            let f = try await ekip.istemci()
            try await f.isle(EpostaIslemi.iptal(m, calisan: c))
            if let a = try? await f.belge("eposta/\(m.id)"), let i = kayitlar.firstIndex(where: { $0.id == m.id }) {
                kayitlar[i] = EpostaKaydi(kimlik: m.id, alanlar: a)
            }
            goster("Mail iptal edildi.")
        } catch {
            hata = KasaVerisi.mesaj(error, "İptal edilemedi; mail gönderilmiş olabilir.")
        }
    }

    private func goster(_ m: String) {
        bildiri = m
        basari += 1
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if bildiri == m { bildiri = nil }
        }
    }

    #if DEBUG
    static func ornek() -> [EpostaKaydi] {
        [
            EpostaKaydi(kimlik: "e1", alanlar: ["to": .metin("zeynep@example.com"), "ad": .metin("Zeynep Arslan"),
                                               "subject": .metin("Almanya vize başvurunuz için evraklarınız"), "text": .metin("…"),
                                               "tur": .metin("tekli"), "appId": .metin("a1"), "status": .metin("sent"),
                                               "createdAt": .zaman(Date().addingTimeInterval(-7200)), "byName": .metin("Sefa Karakaş")]),
            EpostaKaydi(kimlik: "e2", alanlar: ["to": .metin("mehmet@example.com"), "ad": .metin("Mehmet Yılmaz"),
                                               "subject": .metin("İtalya vize başvurunuz olumlu sonuçlandı"), "text": .metin("…"),
                                               "tur": .metin("statu"), "appId": .metin("a2"), "status": .metin("queued"),
                                               "createdAt": .zaman(Date().addingTimeInterval(-600)), "byName": .metin("Ezgi")]),
        ]
    }
    #endif
}

/// Gönderim satırı: konu, alıcı, tür, zaman, durum, (sıradaysa) iptal.
struct EpostaSatiri: View {
    let m: EpostaKaydi
    let iptal: (() -> Void)?
    @Environment(EkipOturumu.self) private var ekip

    private var renk: Color {
        switch m.durum {
        case "sent": return Tema.olumluKoyu
        case "failed": return Tema.olumsuz
        case "cancelled": return Tema.silik
        default: return Tema.mavi
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(m.konu).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                if !m.appId.isEmpty && ekip.yapabilir("app.view") {
                    NavigationLink(value: EkipRota.basvuru(m.appId)) {
                        Text(m.ad.isEmpty ? m.alici : "\(m.ad) · \(m.alici)").font(.caption).foregroundStyle(Tema.turkuaz)
                    }
                } else {
                    Text(m.ad.isEmpty ? m.alici : "\(m.ad) · \(m.alici)").font(.caption).foregroundStyle(Tema.govde)
                }
                Text([m.turAdi, m.zaman.map { Tr.tarihSaat($0) } ?? "", m.yazan].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Tema.silik)
                Text(m.durumYazisi).font(.caption.weight(.semibold)).foregroundStyle(renk)
            }
            Spacer(minLength: 0)
            if let iptal { Button("İptal", action: iptal).buttonStyle(KucukDugme(renk: Tema.olumsuz)) }
        }
        .padding(.vertical, 6)
    }
}

/// Serbest e-posta: sistemde kayıtlı olmayan bir adrese ("müşteri değil";
/// kişi hiçbir listeye kaydedilmez, mail Gönderimler'de görünür).
struct SerbestEpostaKarti: View {
    let gonderildi: (String) -> Void
    @Environment(EkipOturumu.self) private var ekip
    @State private var ad = ""
    @State private var adres = ""
    @State private var sablon = ""
    @State private var konu = ""
    @State private var metin = ""
    @State private var hata: String?
    @State private var gonderiliyor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Serbest e-posta").font(.headline).foregroundStyle(Tema.lacivert)
            Text("Sistemde kayıtlı olmayan bir adrese (kurum, tedarikçi…). Kişi Talepler'e, Başvurular'a ya da arşive kaydedilmez. Müşteriyse önce Talepler'e ekleyin.")
                .font(.caption).foregroundStyle(Tema.govde)
            Alan(etiket: "Alıcının adı", istegeBagli: true) { TextField("Ad soyad", text: $ad).kutu() }
            Alan(etiket: "E-posta") {
                TextField("ornek@alan.com", text: $adres)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .kutu()
            }
            HazirMetinSecici(secili: $sablon) { s in konu = s.konu; metin = s.metin }
            EpostaMetniAlanlari(konu: $konu, metin: $metin)
            if let h = hata { AlanHatasi(metin: h) }
            Button {
                Task { await gonder() }
            } label: {
                if gonderiliyor { HStack(spacing: 8) { ProgressView().tint(.white); Text("Gönderiliyor…") } } else { Text("Gönder") }
            }
            .buttonStyle(AnaDugme())
            .disabled(gonderiliyor)
        }
        .kart()
    }

    private func gonder() async {
        hata = nil
        let a = adres.trimmingCharacters(in: .whitespaces).lowercased()
        guard MusteriBildirimi.epostaGecerli(a) else { hata = "Geçerli bir e-posta adresi yazın."; return }
        let d = EpostaIslemi.serbestDegerler(ad: ad)
        let k = MusteriBildirimi.doldur(konu, d).kirpik, m = MusteriBildirimi.doldur(metin, d).kirpik
        guard !k.isEmpty, !m.isEmpty else { hata = "Konu ve metin boş olamaz."; return }
        let kalan = EpostaIslemi.bosYerTutucular("\(k) \(m)")
        guard kalan.isEmpty else { hata = "Doldurulamayan yer tutucu var: {\(kalan.joined(separator: "} {"))}. Metni düzeltin."; return }
        guard let c = ekip.calisan, let y = EpostaIslemi.serbest(alici: a, konu: k, metin: m, calisan: c) else { hata = "Mail sıraya alınamadı."; return }
        gonderiliyor = true
        defer { gonderiliyor = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { gonderildi("Mail gönderildi."); return }
        #endif
        do {
            try await ekip.istemci().isle(y)
            let gitti = await ekip.epostaHemen()
            ad = ""; adres = ""; konu = ""; metin = ""; sablon = ""
            gonderildi(gitti ? "Mail gönderildi." : "Mail sıraya alındı; 15 dakika içinde gider.")
        } catch {
            hata = KasaVerisi.mesaj(error, "Gönderilemedi. İnternet bağlantınızı kontrol edin.")
        }
    }
}

/// Ayarlardaki "bilgi" türündeki hazır metinlerden seçim.
struct HazirMetinSecici: View {
    @Binding var secili: String
    let secildi: (EpostaAyari.HazirMetin) -> Void
    @Environment(EkipOturumu.self) private var ekip

    var body: some View {
        let l = ekip.epostaAyari.sablonlar.filter { $0.tur == "bilgi" }
        if !l.isEmpty {
            Alan(etiket: "Hazır metin", istegeBagli: true) {
                Picker("Hazır metin", selection: $secili) {
                    Text("Seçin").tag("")
                    ForEach(l) { s in Text(s.ad).tag(s.id) }
                }
                .pickerStyle(.menu)
                .tint(Tema.lacivert)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kutu()
                .onChange(of: secili) { _, yeni in
                    if let s = l.first(where: { $0.id == yeni }) { secildi(s) }
                }
            }
        }
    }
}

struct EpostaMetniAlanlari: View {
    @Binding var konu: String
    @Binding var metin: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Alan(etiket: "Konu") { TextField("Konu", text: $konu).kutu() }
            Alan(etiket: "Metin", yardim: "Yer tutucular: {ad} {soyad} {adSoyad} {ulke} {statu} {takipKodu} {takipLinki}") {
                TextField("Metin", text: $metin, axis: .vertical).lineLimit(5...14).kutu()
            }
        }
    }
}

