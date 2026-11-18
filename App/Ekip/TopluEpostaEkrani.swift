import SwiftUI
import VizeMiaCekirdek

/// Toplu gönder (panel: E-posta → Toplu gönder). Grup seçilir, alıcılar listelenir,
/// istenmeyenlerin işareti kaldırılır, hazır metin ya da yeni metin, gönder.
/// Okuma: seçilen kaynaklardan kayıt tarihine göre en çok 1000 kayıt; başvurularda
/// e-posta gizli bilgide durduğu için her başvuru ayrıca bir okuma.
struct TopluEpostaEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(IcerikDeposu.self) private var icerik
    @State private var kampanya = false
    @State private var basvuru = true
    @State private var talep = false
    @State private var arsiv = false
    @State private var ulke = ""
    @State private var statu = ""
    @State private var bas = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
    @State private var bit = Date()
    @State private var secim: [TopluAday] = []
    @State private var ozet = ""
    @State private var sablon = ""
    @State private var konu = ""
    @State private var metin = ""
    @State private var calisiyor = false
    @State private var mesaj: (Bool, String)?
    @State private var onay = false

    private var kampanyaOlur: Bool { ekip.yapabilir("eposta.kampanya") }
    private var bilgiOlur: Bool { ekip.yapabilir("eposta.send") }
    private var iysEksik: Bool { kampanya && !ekip.epostaAyari.iysTamam }
    private var seciliSayi: Int { secim.filter(\.sec).count }

    var body: some View {
        Form {
            Section {
                Picker("Tür", selection: $kampanya) {
                    if bilgiOlur { Text("Bilgilendirme (süreç, duyuru)").tag(false) }
                    if kampanyaOlur { Text("Kampanya (yalnız izin verenlere)").tag(true) }
                }
                if iysEksik {
                    Text("Kampanya maili İYS kaydı tamamlanmadan gönderilemez. Kayıt bitince yönetici panelde E-posta ayarlarında \"İYS kaydı tamam\" kutusunu işaretlemeli.")
                        .font(.caption).foregroundStyle(Tema.olumsuz)
                }
            } footer: {
                Text("Kampanya mailleri yalnız kampanya izni veren ve abonelikten çıkmamış kişilere gider; her maile \"abonelikten çık\" bağlantısı eklenir.")
            }
            Section("Grup") {
                if ekip.yapabilir("app.sensitive") { Toggle("Başvurular (müşteriler)", isOn: $basvuru) }
                if ekip.yapabilir("lead.view") { Toggle("Talepler (potansiyel müşteriler)", isOn: $talep) }
                if ekip.yapabilir("arsiv.view") { Toggle("Müşteri arşivi (silinmiş başvurular)", isOn: $arsiv) }
                Picker("Ülke", selection: $ulke) {
                    Text("Tüm ülkeler").tag("")
                    ForEach(icerik.akis.tumUlkeler, id: \.slug) { u in Text(u.ad).tag(u.slug) }
                }
                Picker("Statü (başvurular)", selection: $statu) {
                    Text("Tüm statüler").tag("")
                    ForEach(ekip.statuler) { s in Text(s.ad).tag(s.id) }
                }
                DatePicker("Kayıt tarihi: başlangıç", selection: $bas, displayedComponents: .date).environment(\.locale, Tr.yerel)
                DatePicker("Kayıt tarihi: bitiş", selection: $bit, displayedComponents: .date).environment(\.locale, Tr.yerel)
                Button { Task { await listele() } } label: { if calisiyor { ProgressView() } else { Text("Alıcıları listele") } }
                    .disabled(calisiyor)
            }
            if !ozet.isEmpty || !secim.isEmpty {
                Section {
                    ForEach($secim) { $a in
                        Toggle(isOn: $a.sec) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(a.ad) \(a.soyad)".trimmingCharacters(in: .whitespaces).isEmpty ? "—" : "\(a.ad) \(a.soyad)")
                                    .font(.subheadline.weight(.semibold))
                                Text([a.eposta, TopluAday.kaynakAdlari[a.kaynak] ?? a.kaynak, a.ulke].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(Tema.silik)
                            }
                        }
                    }
                } header: { Text(ozet) }
            }
            Section("Metin") {
                let liste = ekip.epostaAyari.sablonlar.filter { $0.tur == (kampanya ? "kampanya" : "bilgi") }
                Picker("Hazır metin", selection: $sablon) {
                    Text("Şablon seçin (isteğe bağlı)").tag("")
                    ForEach(liste) { s in Text(s.ad).tag(s.id) }
                }
                .onChange(of: sablon) { _, yeni in
                    if let s = liste.first(where: { $0.id == yeni }) { konu = s.konu; metin = s.metin }
                }
                TextField("Konu", text: $konu)
                TextField("Metin", text: $metin, axis: .vertical).lineLimit(5...14)
                Text("Yer tutucular: {ad} {soyad} {adSoyad} {ulke} {statu} {takipKodu} {takipLinki}").font(.caption2).foregroundStyle(Tema.silik)
            }
            if let m = mesaj { Section { Text(m.1).foregroundStyle(m.0 ? Tema.olumluKoyu : Tema.olumsuz) } }
            Section {
                Button("\(seciliSayi) kişiye gönder") { onay = true }
                    .disabled(calisiyor || seciliSayi == 0 || iysEksik || konu.trimmingCharacters(in: .whitespaces).isEmpty
                              || metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Toplu gönder")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !bilgiOlur && kampanyaOlur { kampanya = true } }
        .onChange(of: kampanya) { _, _ in secim = []; ozet = ""; sablon = "" }
        .alert("Sıraya alınsın mı?", isPresented: $onay) {
            Button("Sıraya al") { Task { await gonder() } }
            Button("Vazgeç", role: .cancel) {}
        } message: { Text(onayMetni) }
    }

    private var onayMetni: String {
        let kisiler = secim.filter(\.sec)
        guard let ilk = kisiler.first else { return "" }
        let d = TopluEposta.degerler(ilk)
        let ornek = MusteriBildirimi.doldur(metin, d)
        let kalan = EpostaIslemi.bosYerTutucular("\(konu) \(ornek)")
        return "\(kisiler.count) kişiye \(kampanya ? "kampanya" : "bilgilendirme") maili sıraya alınacak. Günde en çok \(ekip.epostaAyari.gunlukSinir) mail gider; fazlası ertesi güne kalır."
            + (kalan.isEmpty ? "" : "\n\nDİKKAT: doldurulamayan yer tutucu var: {\(kalan.joined(separator: "} {"))}")
            + "\n\nİlk alıcıya gidecek metin:\n\n\(MusteriBildirimi.doldur(konu, d))\n\n\(ornek.prefix(400))"
    }

    private func listele() async {
        guard basvuru || talep || arsiv else { mesaj = (false, "En az bir grup seçin."); return }
        let b0 = Tr.takvim.startOfDay(for: bas)
        let b1 = Tr.takvim.date(byAdding: DateComponents(day: 1, second: -1), to: Tr.takvim.startOfDay(for: bit)) ?? bit
        guard b0 <= b1 else { mesaj = (false, "Tarih aralığı hatalı."); return }
        calisiyor = true
        defer { calisiyor = false }
        mesaj = nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") {
            secim = [TopluAday(eposta: "ayse@ornek.com", ad: "Ayşe", soyad: "Kaya", ulke: "İtalya", kampanyaIzni: true, kaynak: "basvuru")]
            ozet = "1 alıcı"
            return
        }
        #endif
        do {
            let f = try await ekip.istemci()
            var l: [TopluAday] = []
            let araliktaMi: (Date?) -> Bool = { d in d.map { $0 >= b0 && $0 <= b1 } ?? false }
            if basvuru && ekip.yapabilir("app.sensitive") {
                let appler = try await f.sorgu(koleksiyon: "applications", kosullar: [.enAz("createdAt", .zaman(b0))],
                                               sirala: ("createdAt", .azalan), sinir: TopluEposta.enCok)
                    .map { Basvuru(kimlik: $0.kimlik, alanlar: $0.alanlar) }
                    .filter { araliktaMi($0.olusturma) && (ulke.isEmpty || $0.ulke == ulke) && (statu.isEmpty || $0.statuId == statu) }
                // E-posta gizli bilgide: 20'şerli paralel okunur.
                for parca in stride(from: 0, to: appler.count, by: 20).map({ Array(appler[$0..<min($0 + 20, appler.count)]) }) {
                    let formlar = await withTaskGroup(of: (Int, [String: FSDeger]).self) { g -> [Int: [String: FSDeger]] in
                        for (i, a) in parca.enumerated() {
                            g.addTask {
                                let d: [String: FSDeger]? = (try? await f.belge("applications/\(a.kimlik)/private/data")) ?? nil
                                return (i, d?["form"]?.haritaDegeri ?? [:])
                            }
                        }
                        var o: [Int: [String: FSDeger]] = [:]
                        for await (i, fm) in g { o[i] = fm }
                        return o
                    }
                    for (i, a) in parca.enumerated() {
                        let fm = formlar[i] ?? [:]
                        l.append(TopluAday(eposta: fm["email"]?.metinDegeri ?? "", ad: a.ad, soyad: a.soyad, ulke: a.ulkeAdi,
                                           kampanyaIzni: fm["kampanyaIzni"]?.mantikDegeri == true, kaynak: "basvuru", basvuru: a))
                    }
                }
            }
            if talep && ekip.yapabilir("lead.view") {
                for kol in ["applicationRequests", "callback"] {
                    let d = try await f.sorgu(koleksiyon: kol, kosullar: [.enAz("createdAt", .zaman(b0))], sirala: ("createdAt", .azalan), sinir: TopluEposta.enCok)
                    for x in d {
                        let a = x.alanlar
                        guard a["silindi"]?.mantikDegeri != true, araliktaMi(a["createdAt"]?.zamanDegeri),
                              ulke.isEmpty || a["country"]?.metinDegeri == ulke else { continue }
                        let ad: (ad: String, soyad: String) = kol == "callback" ? TopluEposta.adBol(a["name"]?.metinDegeri ?? "")
                            : (a["firstName"]?.metinDegeri ?? "", a["lastName"]?.metinDegeri ?? "")
                        l.append(TopluAday(eposta: a["email"]?.metinDegeri ?? "", ad: ad.ad, soyad: ad.soyad, ulke: a["countryName"]?.metinDegeri ?? "",
                                           kampanyaIzni: a["kampanyaIzni"]?.mantikDegeri == true, kaynak: "talep"))
                    }
                }
            }
            if arsiv && ekip.yapabilir("arsiv.view") {
                let d = try await f.sorgu(koleksiyon: "musteriArsivi", kosullar: [.enAz("silinme", .zaman(b0))], sirala: ("silinme", .azalan), sinir: TopluEposta.enCok)
                for x in d {
                    let a = x.alanlar
                    guard ulke.isEmpty || a["ulke"]?.metinDegeri == ulke else { continue }
                    l.append(TopluAday(eposta: a["eposta"]?.metinDegeri ?? "", ad: a["ad"]?.metinDegeri ?? "", soyad: a["soyad"]?.metinDegeri ?? "",
                                       ulke: a["ulkeAdi"]?.metinDegeri ?? "", kampanyaIzni: a["kampanyaIzni"]?.mantikDegeri == true, kaynak: "arsiv"))
                }
            }
            var ayrilan = Set<String>()
            if kampanya {
                let d = try await f.sorgu(koleksiyon: "epostaAbonelik", kosullar: [.esit("iptal", .mantik(true))], sinir: 5000)
                ayrilan = Set(d.compactMap { $0.alanlar["eposta"]?.metinDegeri?.lowercased() })
            }
            let r = TopluEposta.aliciSec(l, kampanya: kampanya, ayrilanlar: ayrilan)
            secim = r.alicilar
            ozet = TopluEposta.ozet(r.alicilar.count, r.atlanan)
        } catch {
            mesaj = (false, HataAciklamasi.metin(error, "Alıcılar listelenemedi."))
        }
    }

    private func gonder() async {
        guard let c = ekip.calisan else { return }
        let kisiler = secim.filter(\.sec)
        guard let k = TopluEposta.kuyruk(kisiler, konu: konu, metin: metin, kampanya: kampanya, kampanyaId: TopluEposta.kampanyaId(), calisan: c) else {
            mesaj = (false, "Konu ve metin boş olamaz."); return
        }
        calisiyor = true
        defer { calisiyor = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { mesaj = (true, "\(k.adet) mail sıraya alındı."); secim = []; return }
        #endif
        do {
            let f = try await ekip.istemci()
            for g in k.gruplar { try await f.isle(g) }
            secim = []; ozet = ""
            let gitti = await ekip.epostaHemen()
            mesaj = (true, gitti ? "\(k.adet) mail gönderime verildi. Günlük sınırı aşan kısım ertesi güne kalır."
                     : "\(k.adet) mail sıraya alındı; 15 dakika içinde gider.")
        } catch {
            mesaj = (false, HataAciklamasi.metin(error, "Sıraya alınamadı."))
        }
    }
}
