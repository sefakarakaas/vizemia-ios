import SwiftUI
import VizeMiaCekirdek

/// Ayarlar (yönetici; panel: #/ayarlar). Telefondan sık değişenler burada;
/// statüler, evrak listesi, ülke formları ve şablonlar panelden.
struct AyarlarEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @State private var belgeler: [String: [String: FSDeger]] = [:]
    @State private var yuklendi = false
    @State private var hata: String?

    var body: some View {
        List {
            if let h = hata { Section { Text(h).foregroundStyle(Tema.olumsuz) } }
            if yuklendi {
                Section {
                    NavigationLink { MesaiAyarEkrani(baslangic: Ayarlar.mesai(belge: belgeler["mesai"])) { belgeler["mesai"] = nil; Task { await yukle() } } } label: {
                        ayarSatiri("Mesai saatleri ve tatil günleri", Ayarlar.mesaiTekSatir(Ayarlar.mesai(belge: belgeler["mesai"])), "clock.fill")
                    }
                    NavigationLink { GenelAyarEkrani(baslangic: Ayarlar.Genel(belge: belgeler["general"])) { Task { await yukle() } } } label: {
                        ayarSatiri("Genel", "Şirket bilgileri, saklama süresi, otomatik çıkış", "building.2.fill")
                    }
                    NavigationLink { IzinAyarEkrani(baslangic: Ayarlar.rolIzinleri(belge: belgeler["permissions"])) { Task { await yukle() } } } label: {
                        ayarSatiri("Rol izinleri", "Operasyon, izleyici ve stajyerin yetkileri", "lock.shield.fill")
                    }
                    NavigationLink { KasaAyarEkrani(baslangic: KasaAyari(alanlar: belgeler["kasa"])) { Task { await yukle() } } } label: {
                        ayarSatiri("Kasa listeleri", "Gider kategorileri, döviz büroları, rapor saati", "turkishlirasign.circle.fill")
                    }
                    NavigationLink {
                        BildirimAyarEkrani(bildirim: BildirimAyari(belge: belgeler["bildirim"]), smsAcik: SmsAyari(belge: belgeler["sms"]).acik) { Task { await yukle() } }
                    } label: {
                        ayarSatiri("Bildirimler ve SMS", "Otomatik müşteri bildirimleri, gönderim saatleri", "bell.badge.fill")
                    }
                } footer: {
                    Text("Statüler, evrak listesi, ülke formları, mail / SMS / WhatsApp şablonları, randevu konumları ve site yayını anahtarı panelden (vizemia.com/panel) değiştirilir.")
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Ayarlar")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !yuklendi { await yukle() } }
        .refreshable { await yukle() }
    }

    private func ayarSatiri(_ ad: String, _ alt: String, _ simge: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: simge).foregroundStyle(Tema.turkuaz).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(ad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                Text(alt).font(.caption).foregroundStyle(Tema.govde).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func yukle() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { yuklendi = true; return }
        #endif
        do {
            let f = try await ekip.istemci()
            var b: [String: [String: FSDeger]] = [:]
            for ad in ["mesai", "general", "permissions", "kasa", "bildirim", "sms"] {
                if let x = try await f.belge("settings/\(ad)") { b[ad] = x }
            }
            belgeler = b
            yuklendi = true
            hata = nil
        } catch {
            hata = KasaVerisi.mesaj(error, "Ayarlar yüklenemedi.")
        }
    }
}

/// Ortak: yazar, sonucu gösterir.
@MainActor
private func ayarKaydet(_ ekip: EkipOturumu, _ y: [FirestoreIstemci.Yazim], yayin: Bool = false) async -> (tamam: Bool, mesaj: String) {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return (true, "Kaydedildi.") }
    #endif
    do {
        try await ekip.istemci().isle(y)
        if yayin { return (true, SiteYayini.mesaj(basladi: await ekip.siteyiGuncelle())) }
        return (true, "Kaydedildi.")
    } catch {
        return (false, KasaVerisi.mesaj(error, "Kaydedilemedi."))
    }
}

struct MesaiAyarEkrani: View {
    let baslangic: Mesai
    let bitti: () -> Void
    @Environment(EkipOturumu.self) private var ekip
    @State private var m = Mesai.varsayilan
    @State private var tatil = Date()
    @State private var mesaj: (Bool, String)?
    @State private var calisiyor = false
    @State private var hazir = false

    private static let saatler: [Int] = Array(stride(from: Ayarlar.enErken, through: Ayarlar.enGec, by: 30))
    /// Pazartesi'den başlayarak.
    private static let gunSirasi = [1, 2, 3, 4, 5, 6, 0]

    var body: some View {
        Form {
            Section {
                ForEach(Self.gunSirasi, id: \.self) { g in gunSatiri(g) }
            } footer: {
                Text("Sitedeki \"Ara\" düğmesi, geri arama saat seçicisi ve iletişim sayfası bu saatleri kullanır. Türkiye saati. Özet: \(Ayarlar.mesaiTekSatir(m))")
            }
            Section("Tatil günleri") {
                HStack {
                    DatePicker("Gün", selection: $tatil, displayedComponents: .date).environment(\.locale, Tr.yerel)
                    Button("Ekle") {
                        let iso = Tr.isoGun(tatil, takvim: Tr.takvim)
                        m.tatiller.insert(iso)
                    }
                }
                ForEach(m.tatiller.sorted(), id: \.self) { t in
                    Text(BildirimMetni.trTarih(t))
                }
                .onDelete { i in
                    let l = m.tatiller.sorted()
                    for x in i { m.tatiller.remove(l[x]) }
                }
            }
            if let m = mesaj { Section { Text(m.1).foregroundStyle(m.0 ? Tema.olumluKoyu : Tema.olumsuz) } }
            Section {
                Button { Task { await kaydet() } } label: { if calisiyor { ProgressView() } else { Text("Kaydet ve sitede yayınla") } }.disabled(calisiyor)
            }
        }
        .navigationTitle("Mesai saatleri")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !hazir { m = baslangic; hazir = true } }
    }

    private func gunSatiri(_ g: Int) -> some View {
        let acik = Binding<Bool>(get: { m.calisma[g] != nil }, set: { m.calisma[g] = $0 ? [540, 1080] : nil })
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(Mesai.gunAdi[g], isOn: acik)
            if let a = m.calisma[g], a.count == 2 {
                HStack {
                    Picker("Açılış", selection: Binding(get: { a[0] }, set: { m.calisma[g] = [$0, a[1]] })) {
                        ForEach(Self.saatler, id: \.self) { Text(Mesai.hhmm($0)).tag($0) }
                    }
                    Picker("Kapanış", selection: Binding(get: { a[1] }, set: { m.calisma[g] = [a[0], $0] })) {
                        ForEach(Self.saatler, id: \.self) { Text(Mesai.hhmm($0)).tag($0) }
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
            }
        }
    }

    private func kaydet() async {
        let h = Ayarlar.mesaiHatalari(m)
        guard h.isEmpty else { mesaj = (false, h[0]); return }
        guard let c = ekip.calisan else { return }
        calisiyor = true
        defer { calisiyor = false }
        let r = await ayarKaydet(ekip, Ayarlar.mesaiYaz(m, calisan: c), yayin: true)
        mesaj = (r.tamam, r.mesaj)
        if r.tamam { bitti() }
    }
}

struct GenelAyarEkrani: View {
    let baslangic: Ayarlar.Genel
    let bitti: () -> Void
    @Environment(EkipOturumu.self) private var ekip
    @State private var g = Ayarlar.Genel()
    @State private var hazir = false
    @State private var mesaj: (Bool, String)?
    @State private var calisiyor = false

    var body: some View {
        Form {
            Section {
                TextField("Firma adı (form 33)", text: $g.firmaAdi)
                TextField("Adres", text: $g.firmaAdres, axis: .vertical).lineLimit(1...3)
                TextField("E-posta", text: $g.firmaEposta).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                TextField("Telefon", text: $g.firmaTelefon).keyboardType(.phonePad)
                TextField("Web sitesi", text: $g.firmaWeb).textInputAutocapitalization(.never)
                TextField("İmza yeri (şehir)", text: $g.firmaSehir)
            } header: { Text("Şirket bilgileri") } footer: {
                Text("Konsolosluk formunda (33. soru), sosyal medya paylaşımlarında ve firma maili altbilgisinde kullanılır. Sosyal medya hesapları ve şifreleri panelden.")
            }
            Section {
                Stepper("Saklama süresi: \(g.saklamaGun) gün", value: $g.saklamaGun, in: 1...3650, step: 5)
                Stepper("Silme uyarısı: \(g.uyariGun) gün önce", value: $g.uyariGun, in: 1...60)
                Stepper("Otomatik çıkış: \(g.bosDakika) dakika", value: $g.bosDakika, in: 5...240, step: 5)
            } header: { Text("Sistem") } footer: {
                Text("Saklama: son adım statüsünden sonra kişisel veriler bu kadar gün sonra silinir (yeni sonuçlananlara uygulanır).")
            }
            if let m = mesaj { Section { Text(m.1).foregroundStyle(m.0 ? Tema.olumluKoyu : Tema.olumsuz) } }
            Section {
                Button { Task { await kaydet() } } label: { if calisiyor { ProgressView() } else { Text("Kaydet") } }.disabled(calisiyor)
            }
        }
        .navigationTitle("Genel")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !hazir { g = baslangic; hazir = true } }
    }

    private func kaydet() async {
        let h = g.hatalar
        guard h.isEmpty else { mesaj = (false, h[0]); return }
        guard let c = ekip.calisan else { return }
        calisiyor = true
        defer { calisiyor = false }
        let r = await ayarKaydet(ekip, Ayarlar.genelYaz(g, calisan: c))
        mesaj = (r.tamam, r.mesaj)
        if r.tamam { bitti() }
    }
}

struct IzinAyarEkrani: View {
    let baslangic: [String: Set<String>]
    let bitti: () -> Void
    @Environment(EkipOturumu.self) private var ekip
    @State private var r: [String: Set<String>] = [:]
    @State private var rol = "writer"
    @State private var hazir = false
    @State private var mesaj: (Bool, String)?
    @State private var calisiyor = false

    var body: some View {
        Form {
            Section {
                Picker("Rol", selection: $rol) {
                    Text("Operasyon").tag("writer")
                    Text("İzleyici").tag("reader")
                    Text("Stajyer").tag("intern")
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Yönetici her zaman tüm yetkilere sahiptir. Ayarlar, kullanıcılar ve işlem kayıtları yalnız yöneticidir. Değişiklik anında geçerli olur.")
            }
            ForEach(Ayarlar.izinGruplari, id: \.self) { grup in
                Section(grup) {
                    ForEach(Ayarlar.izinler.filter { $0.grup == grup }) { i in
                        Toggle(isOn: Binding(get: { r[rol]?.contains(i.id) ?? false }, set: { evet in
                            var s = r[rol] ?? []
                            if evet { s.insert(i.id) } else { s.remove(i.id) }
                            r[rol] = s
                        })) {
                            Text(i.ad).font(.subheadline)
                        }
                    }
                }
            }
            if let m = mesaj { Section { Text(m.1).foregroundStyle(m.0 ? Tema.olumluKoyu : Tema.olumsuz) } }
            Section {
                Button { Task { await kaydet() } } label: { if calisiyor { ProgressView() } else { Text("İzinleri kaydet") } }.disabled(calisiyor)
            }
        }
        .navigationTitle("Rol izinleri")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !hazir { r = baslangic; hazir = true } }
    }

    private func kaydet() async {
        guard let c = ekip.calisan else { return }
        calisiyor = true
        defer { calisiyor = false }
        let s = await ayarKaydet(ekip, Ayarlar.izinleriYaz(r, calisan: c))
        mesaj = (s.tamam, s.tamam ? "İzinler kaydedildi. Değişiklik anında geçerli olur." : s.mesaj)
        if s.tamam { bitti() }
    }
}

struct KasaAyarEkrani: View {
    let baslangic: KasaAyari
    let bitti: () -> Void
    @Environment(EkipOturumu.self) private var ekip
    @State private var musteri = ""
    @State private var genel = ""
    @State private var burolar = ""
    @State private var rapor = Date()
    @State private var hazir = false
    @State private var mesaj: (Bool, String)?
    @State private var calisiyor = false

    var body: some View {
        Form {
            Section { TextField("Her satıra bir kategori", text: $musteri, axis: .vertical).lineLimit(4...14) } header: {
                Text("Müşteri için giderler")
            }
            Section { TextField("Her satıra bir kategori", text: $genel, axis: .vertical).lineLimit(4...14) } header: {
                Text("Genel giderler")
            }
            Section { TextField("Her satıra bir büro", text: $burolar, axis: .vertical).lineLimit(2...8) } header: {
                Text("Döviz büroları")
            }
            Section {
                DatePicker("Gün sonu raporu", selection: $rapor, displayedComponents: .hourAndMinute).environment(\.locale, Tr.yerel)
            } footer: {
                Text("Rapor Telegram'a / e-postaya bu saatte gider. Alıcılar ve servis adresi panelden.")
            }
            if let m = mesaj { Section { Text(m.1).foregroundStyle(m.0 ? Tema.olumluKoyu : Tema.olumsuz) } }
            Section {
                Button { Task { await kaydet() } } label: { if calisiyor { ProgressView() } else { Text("Kaydet") } }.disabled(calisiyor)
            }
        }
        .navigationTitle("Kasa listeleri")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hazir else { return }
            hazir = true
            musteri = baslangic.musteriGiderleri.joined(separator: "\n")
            genel = baslangic.genelGiderler.joined(separator: "\n")
            burolar = baslangic.dovizBurolari.joined(separator: "\n")
            let p = baslangic.raporSaati.split(separator: ":").compactMap { Int($0) }
            var c = DateComponents(); c.hour = p.first ?? 20; c.minute = p.count > 1 ? p[1] : 0
            rapor = Tr.takvim.date(from: c) ?? Date()
        }
    }

    private func kaydet() async {
        guard let c = ekip.calisan else { return }
        let satirlar = { (s: String) in s.components(separatedBy: "\n") }
        let p = Tr.takvim.dateComponents([.hour, .minute], from: rapor)
        let saat = String(format: "%02d:%02d", p.hour ?? 20, p.minute ?? 0)
        let r = Ayarlar.kasaListeleriYaz(musteri: satirlar(musteri), genel: satirlar(genel), burolar: satirlar(burolar), raporSaati: saat, calisan: c)
        if let h = r.hata { mesaj = (false, h); return }
        calisiyor = true
        defer { calisiyor = false }
        let s = await ayarKaydet(ekip, r.yazimlar)
        mesaj = (s.tamam, s.mesaj)
        if s.tamam { bitti() }
    }
}

struct BildirimAyarEkrani: View {
    let bildirim: BildirimAyari
    let smsAcik: Bool
    let bitti: () -> Void
    @Environment(EkipOturumu.self) private var ekip
    @State private var acik = true
    @State private var bas = 9
    @State private var son = 21
    @State private var sms = false
    @State private var hazir = false
    @State private var mesaj: (Bool, String)?
    @State private var calisiyor = false

    var body: some View {
        Form {
            Section {
                Toggle("Otomatik müşteri bildirimleri", isOn: $acik)
                Stepper("Gönderim başlangıcı: \(String(format: "%02d", bas)):00", value: $bas, in: 0...23)
                Stepper("Gönderim bitişi: \(String(format: "%02d", son)):00", value: $son, in: 1...24)
            } footer: {
                Text("\"Randevunuz alındı\" ve evrak hatırlatması gibi mesajlar. Pencere dışına düşen mesaj ertesi sabaha kalır. Şablonlar ve ülke grupları panelden.")
            }
            Section {
                Toggle("SMS gönderimi", isOn: $sms)
            } footer: {
                Text("Statü ve not SMS'leri. Sağlayıcı anahtarları GitHub gizli ayarlarında; şablonlar panelden.")
            }
            if let m = mesaj { Section { Text(m.1).foregroundStyle(m.0 ? Tema.olumluKoyu : Tema.olumsuz) } }
            Section {
                Button { Task { await kaydet() } } label: { if calisiyor { ProgressView() } else { Text("Kaydet") } }.disabled(calisiyor)
            }
        }
        .navigationTitle("Bildirimler ve SMS")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hazir else { return }
            hazir = true
            acik = bildirim.acik; bas = bildirim.pencereBas; son = bildirim.pencereSon; sms = smsAcik
        }
    }

    private func kaydet() async {
        guard let c = ekip.calisan else { return }
        let b = Ayarlar.bildirimYaz(acik: acik, pencereBas: bas, pencereSon: son, calisan: c)
        if let h = b.hata { mesaj = (false, h); return }
        calisiyor = true
        defer { calisiyor = false }
        var y = b.yazimlar
        if sms != smsAcik { y += Ayarlar.smsYaz(acik: sms, calisan: c) }
        let s = await ayarKaydet(ekip, y)
        mesaj = (s.tamam, s.mesaj)
        if s.tamam { bitti() }
    }
}
