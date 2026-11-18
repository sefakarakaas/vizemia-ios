import SwiftUI
import VizeMiaCekirdek

/// Bildirimler (panel: #/bildirimler). WhatsApp sunucudan gitmiyor: mesaj
/// hazır açılır, danışman kendi WhatsApp'ından gönderip "Gönderdim" der.
/// Planlanmış mesajlar "Şimdi gönder" ile öne alınır ya da iptal edilir.
struct BildirimlerEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @State private var gorunum = "gorev"
    @State private var yalnizBana = true
    @State private var kayitlar: [BildirimGorevi] = []
    @State private var yukleniyor = false
    @State private var hata: String?
    @State private var islemde: String?
    @State private var iptalEdilecek: BildirimGorevi?
    @State private var bildiri: String?
    @State private var basari = 0

    static let gorunumler: [(id: String, ad: String)] = [
        ("gorev", "WhatsApp görevleri"), ("planned", "Planlanmış"), ("sent", "Gönderilenler"), ("all", "Tümü"),
    ]
    /// Ekranda gösterilen kadar okunur (okuma kotası).
    static let sinir = 100

    private var gorunen: [BildirimGorevi] {
        var l = kayitlar
        if gorunum == "gorev" { l = l.filter(\.waGorevi) }
        if yalnizBana, let uid = ekip.calisan?.uid { l = l.filter { $0.bana(uid) } }
        return l
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Görünüm", selection: $gorunum) {
                    ForEach(0..<Self.gorunumler.count, id: \.self) { i in Text(Self.gorunumler[i].ad).tag(Self.gorunumler[i].id) }
                }
                .pickerStyle(.segmented)
                IsaretKutusu(secili: $yalnizBana, metin: "Yalnızca bana atananlar (atanmamışlar da görünür)")
                if !ekip.bildirimAyari.acik {
                    Label("Otomatik bildirimler kapalı. Ayarlar → Bildirimler'den açılır.", systemImage: "bell.slash")
                        .font(.caption.weight(.semibold)).foregroundStyle(Tema.uyari)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Tema.uyariZemin, in: RoundedRectangle(cornerRadius: Tema.koseKucuk))
                }
                if let h = hata { AlanHatasi(metin: h) }
                if yukleniyor && kayitlar.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if gorunen.isEmpty {
                    ContentUnavailableView(gorunum == "gorev" ? "Bekleyen WhatsApp görevi yok" : "Kayıt yok",
                                           systemImage: gorunum == "gorev" ? "checkmark.message" : "tray")
                } else {
                    Text("\(gorunen.count) kayıt").font(.caption).foregroundStyle(Tema.silik)
                    ForEach(Array(gorunen.enumerated()), id: \.element.id) { i, b in
                        kart(b).belirme(min(i, 6))
                    }
                }
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("Bildirimler")
        .navigationBarTitleDisplayMode(.inline)
        .task { if kayitlar.isEmpty { await yukle() } }
        .refreshable { await yukle() }
        .onChange(of: gorunum) { _, _ in Task { await yukle() } }
        .confirmationDialog("Bu mesaj müşteriye gitmeyecek. Randevu tarihi değişirse yeni plan kurulur. İptal edilsin mi?",
                            isPresented: Binding(get: { iptalEdilecek != nil }, set: { if !$0 { iptalEdilecek = nil } }),
                            titleVisibility: .visible) {
            Button("İptal et", role: .destructive) {
                guard let b = iptalEdilecek, let c = ekip.calisan else { return }
                Task { await isle(b, BasvuruIslemi.bildirimIptal(b, calisan: c), "Bildirim iptal edildi.") }
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

    // MARK: Kart

    private func kart(_ b: BildirimGorevi) -> some View {
        let metin = BildirimMetni.kur(b, ayar: ekip.bildirimAyari).metin
        let gecikmis = b.gecikmis()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.ad.isEmpty ? "(isimsiz)" : b.ad).font(.headline).foregroundStyle(Tema.lacivert)
                    Text("\(b.turAdi) · \(b.ulkeAdi.isEmpty ? "—" : b.ulkeAdi)").font(.caption).foregroundStyle(Tema.govde)
                }
                Spacer()
                Etiket(metin: b.durumAdi, renk: durumRengi(b.durum))
            }
            VStack(alignment: .leading, spacing: 4) {
                bilgi("Gönderim", (b.gonderim.map { Tr.tarihSaat($0) } ?? "—") + (gecikmis ? " (zamanı geçti)" : ""))
                if !b.randevu.isEmpty { bilgi("Randevu", BildirimMetni.trTarih(b.randevu)) }
                if !b.evrakSon.isEmpty { bilgi("Evrak son tarihi", BildirimMetni.trTarih(b.evrakSon)) }
                bilgi("Kanallar", b.kanalMetni)
                if !b.telefon.isEmpty { bilgi("Telefon", b.telefon) }
                if !b.eposta.isEmpty { bilgi("E-posta", b.eposta) }
                if !b.atananAd.isEmpty { bilgi("Danışman", b.atananAd) }
                if !b.iptalSebebi.isEmpty { bilgi("İptal sebebi", b.iptalSebebi) }
                if !b.hata.isEmpty { bilgi("Hata", b.hata) }
            }
            Text(metin)
                .font(.subheadline)
                .foregroundStyle(Tema.govde)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tema.zeminYumusak, in: RoundedRectangle(cornerRadius: Tema.koseKucuk))
                .textSelection(.enabled)
            eylemler(b, metin)
        }
        .kart()
        .overlay(RoundedRectangle(cornerRadius: Tema.kose).stroke(gecikmis ? Tema.altin : Color.clear, lineWidth: 1.5))
    }

    private func bilgi(_ ad: String, _ deger: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ad).font(.caption2.weight(.semibold)).foregroundStyle(Tema.silik).frame(width: 96, alignment: .leading)
            Text(deger).font(.caption).foregroundStyle(Tema.lacivert)
        }
    }

    private func durumRengi(_ d: String) -> Color {
        switch d {
        case "planned": return Tema.mavi
        case "sent": return Tema.olumlu
        case "failed": return Tema.olumsuz
        default: return Tema.silik
        }
    }

    @ViewBuilder
    private func eylemler(_ b: BildirimGorevi, _ metin: String) -> some View {
        let calisiyor = islemde == b.id
        VStack(alignment: .leading, spacing: 8) {
            if b.kanallar["wa"] == true, b.waGorevi, let url = BildirimMetni.waBaglantisi(telefon: b.telefon, metin: metin) {
                HStack(spacing: 8) {
                    Link(destination: url) {
                        Label("WhatsApp'ta aç", systemImage: "message.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.white)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Tema.whatsapp, in: Capsule())
                    }
                    Button {
                        guard let c = ekip.calisan else { return }
                        Task { await isle(b, BasvuruIslemi.waGonderildi(b, calisan: c), "WhatsApp görevi kapatıldı.") }
                    } label: {
                        if calisiyor { ProgressView() } else { Text("Gönderdim") }
                    }
                    .buttonStyle(IkincilDugme())
                    .disabled(calisiyor)
                }
            } else if b.waDurum == "sent" {
                Text("WhatsApp: gönderildi\(b.waZaman.map { " · " + Tr.tarihSaat($0) } ?? "")").font(.caption).foregroundStyle(Tema.olumluKoyu)
            }
            HStack(spacing: 8) {
                if !b.appId.isEmpty && ekip.yapabilir("app.view") {
                    NavigationLink(value: EkipRota.basvuru(b.appId)) { Text("Başvuruyu aç") }.buttonStyle(KucukDugme())
                }
                Spacer()
                if b.durum == "planned" && ekip.yapabilir("app.status") {
                    Button("Şimdi gönder") {
                        guard let c = ekip.calisan else { return }
                        Task { await isle(b, BasvuruIslemi.bildirimSimdi(b, calisan: c), "Bekleme atlandı; ilk turda gönderilecek.") }
                    }
                    .buttonStyle(KucukDugme())
                    .disabled(calisiyor)
                    Button("İptal et") { iptalEdilecek = b }
                        .buttonStyle(KucukDugme(renk: Tema.olumsuz))
                        .disabled(calisiyor)
                }
            }
        }
    }

    // MARK: Veri

    private func yukle() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { kayitlar = Self.ornek(); return }
        #endif
        guard ekip.yapabilir("app.sensitive") else { hata = "Bildirimleri görmek için hassas veri yetkisi gerekir."; return }
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let f = try await ekip.istemci()
            let l: [FirestoreIstemci.Belge]
            switch gorunum {
            case "gorev":
                // Görev = WhatsApp kanalı açık, henüz gönderilmemiş (panelle aynı sorgu).
                l = try await f.sorgu(koleksiyon: "bildirimler", kosullar: [.esit("waStatus", .metin("pending"))],
                                      sirala: ("sendAt", .artan), sinir: Self.sinir)
            case "all":
                l = try await f.sorgu(koleksiyon: "bildirimler", sirala: ("sendAt", .azalan), sinir: Self.sinir)
            default:
                l = try await f.sorgu(koleksiyon: "bildirimler", kosullar: [.esit("status", .metin(gorunum))],
                                      sirala: ("sendAt", .artan), sinir: Self.sinir)
            }
            kayitlar = l.map { BildirimGorevi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            hata = nil
        } catch {
            hata = KasaVerisi.mesaj(error, "Bildirimler yüklenemedi. İnternet bağlantınızı kontrol edin.")
        }
    }

    /// Yazar, sonra yalnız o kaydı yeniden okur.
    private func isle(_ b: BildirimGorevi, _ y: [FirestoreIstemci.Yazim], _ tamam: String) async {
        islemde = b.id
        defer { islemde = nil }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { goster(tamam); return }
        #endif
        do {
            let f = try await ekip.istemci()
            try await f.isle(y)
            if let a = try? await f.belge("bildirimler/\(b.id)"), let i = kayitlar.firstIndex(where: { $0.id == b.id }) {
                kayitlar[i] = BildirimGorevi(kimlik: b.id, alanlar: a)
            }
            hata = nil
            goster(tamam)
        } catch {
            hata = KasaVerisi.mesaj(error, "Kaydedilemedi. İnternet bağlantınızı kontrol edip yeniden deneyin.")
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
    static func ornek() -> [BildirimGorevi] {
        let simdi = Date()
        let bugun = Tr.bugun()
        return [
            BildirimGorevi(kimlik: "b1", alanlar: [
                "appId": .metin("a1"), "trackingCode": .metin("2026-111234"), "kind": .metin("evrak-hatirlatma"), "status": .metin("sent"),
                "channels": .harita(["wa": .mantik(true), "sms": .mantik(true), "email": .mantik(false)]),
                "name": .metin("Zeynep"), "country": .metin("almanya"), "countryName": .metin("Almanya"),
                "appointmentDate": .metin(Tr.gunEkle(bugun, 15)), "docDeadline": .metin(Tr.gunEkle(bugun, 12)), "reminderDays": .tam(15),
                "phone": .metin("+905000000011"), "waStatus": .metin("pending"), "sendAt": .zaman(simdi.addingTimeInterval(-3600)),
                "assignedName": .metin("Sefa Karakaş"),
            ]),
            BildirimGorevi(kimlik: "b2", alanlar: [
                "appId": .metin("a2"), "trackingCode": .metin("2026-115678"), "kind": .metin("randevu-alindi"), "status": .metin("planned"),
                "channels": .harita(["wa": .mantik(true), "sms": .mantik(false), "email": .mantik(true)]),
                "name": .metin("Mehmet"), "country": .metin("italya"), "countryName": .metin("İtalya"),
                "appointmentDate": .metin(Tr.gunEkle(bugun, 30)), "docDeadline": .metin(Tr.gunEkle(bugun, 27)),
                "randevuSaati": .metin("10:15"), "randevuMerkezi": .metin("iDATA"), "randevuSehri": .metin("Ankara"),
                "phone": .metin("+905000000022"), "email": .metin("mehmet@example.com"), "waStatus": .metin("pending"), "force": .mantik(true),
                "sendAt": .zaman(simdi.addingTimeInterval(1200)),
            ]),
        ]
    }
    #endif
}
