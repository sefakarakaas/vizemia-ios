import SwiftUI
import AVKit
import VizeMiaCekirdek

/// Sosyal medya (panel: #/sosyal): günlük görevin hazırladığı postlar.
/// Telefondan paylaşmak için: metni kopyala, görselleri paylaşım menüsüyle
/// Instagram / X / WhatsApp'a gönder, sonra "Paylaştım" de.
struct SosyalEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @AppStorage("sosyal.kanal") private var kanal = "instagram"
    @State private var paylasilan = false
    @State private var postlar: [String: SosyalPost] = [:]
    @State private var paylasilanYuklendi = false
    @State private var yukleniyor = false
    @State private var hata: String?
    @State private var bildiri: String?
    @State private var gorseller: [String: [String: UIImage]] = [:]
    @State private var istekAcik = false
    @State private var yukleAcik = false

    /// Her kanaldan bekleyen ve son paylaşılan post sayısı sınırı (okuma kotası).
    static let sinir = 60

    private var liste: [SosyalPost] { SosyalPost.suz(Array(postlar.values), kanal: kanal, paylasilan: paylasilan) }
    private var gunler: [String] {
        var g: [String] = []
        for p in liste where g.last != p.tarih { g.append(p.tarih) }
        return g
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                kanalSecici
                Picker("Sekme", selection: $paylasilan) {
                    Text("Bekleyenler").tag(false)
                    Text("Paylaşılanlar").tag(true)
                }
                .pickerStyle(.segmented)
                if ekip.yapabilir("social.share") {
                    Button { istekAcik = true } label: { Label("Post isteği", systemImage: "text.bubble") }.buttonStyle(KucukDugme())
                }
                if let h = hata { AlanHatasi(metin: h) }
                if let b = bildiri {
                    Label(b, systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Tema.olumluKoyu)
                }
                if yukleniyor && liste.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if liste.isEmpty {
                    ContentUnavailableView(paylasilan ? "Paylaşılan post yok" : "Bekleyen post yok", systemImage: "photo.on.rectangle")
                }
                ForEach(gunler, id: \.self) { g in
                    Text(gunBasligi(g)).font(.subheadline.weight(.bold)).foregroundStyle(Tema.govde).padding(.top, 6)
                    ForEach(liste.filter { $0.tarih == g }) { p in
                        SosyalKarti(post: p, kanal: kanal, resimler: gorseller[p.id], resimleriYukle: { await resimleriYukle(p) },
                                    degisti: { yeni in postlar[yeni.id] = yeni }, silindi: { postlar[p.id] = nil },
                                    bildir: { bildiri = $0 }, hata: { hata = $0 })
                    }
                }
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("Sosyal medya")
        .navigationBarTitleDisplayMode(.inline)
        .task { if postlar.isEmpty { await yukle() } }
        .refreshable { paylasilanYuklendi = false; await yukle() }
        .onChange(of: paylasilan) { _, yeni in if yeni && !paylasilanYuklendi { Task { await paylasilanlariYukle() } } }
        .sheet(isPresented: $istekAcik) { PostIstekleriSayfasi() }
        .toolbar {
            if ekip.yapabilir("social.upload") {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { yukleAcik = true } label: { Label("Post yükle", systemImage: "square.and.arrow.up.on.square") }
                }
            }
        }
        .sheet(isPresented: $yukleAcik) {
            PostYukleSayfasi { id in
                bildiri = "Post yüklendi; Bekleyenler listesinde."
                Task { await yukle() }
                _ = id
            }
        }
    }

    private var kanalSecici: some View {
        let sayi = SosyalPost.bekleyenSayilari(Array(postlar.values))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<SosyalPost.kanallar.count, id: \.self) { i in
                    let k = SosyalPost.kanallar[i]
                    Button {
                        withAnimation(Hareket.yay) { kanal = k.id }
                    } label: {
                        HStack(spacing: 6) {
                            Text(k.ad)
                            if (sayi[k.id] ?? 0) > 0 {
                                Text("\(sayi[k.id] ?? 0)").font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(kanal == k.id ? Color.white.opacity(0.25) : Tema.altin.opacity(0.25), in: Capsule())
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(kanal == k.id ? Color.white : Tema.lacivert)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(kanal == k.id ? Tema.lacivert : Tema.soluk, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func gunBasligi(_ iso: String) -> String { BildirimMetni.trTarih(iso) }

    private func yukle() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { postlar = Self.ornek(); return }
        #endif
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let f = try await ekip.istemci()
            let durumlar = SosyalPost.bekleyenDurumlar.map { FSDeger.metin($0) }
            var yeni: [String: SosyalPost] = [:]
            for k in SosyalPost.kanallar {
                let l = try await f.sorgu(koleksiyon: "posts", kosullar: [.icinde("kanallar.\(k.id).durum", durumlar)], sinir: Self.sinir)
                for b in l { yeni[b.kimlik] = SosyalPost(kimlik: b.kimlik, alanlar: b.alanlar) }
            }
            postlar = yeni
            hata = nil
            if paylasilan { await paylasilanlariYukle() }
        } catch {
            hata = KasaVerisi.mesaj(error, "Postlar yüklenemedi.")
        }
    }

    private func paylasilanlariYukle() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return }
        #endif
        do {
            let l = try await ekip.istemci().sorgu(koleksiyon: "posts", sirala: ("tarih", .azalan), sinir: Self.sinir)
            for b in l { postlar[b.kimlik] = SosyalPost(kimlik: b.kimlik, alanlar: b.alanlar) }
            paylasilanYuklendi = true
        } catch {
            hata = KasaVerisi.mesaj(error, "Paylaşılan postlar yüklenemedi.")
        }
    }

    /// Bir postun görselleri tek sorguda (kart görününce).
    private func resimleriYukle(_ p: SosyalPost) async {
        guard gorseller[p.id] == nil else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { gorseller[p.id] = [:]; return }
        #endif
        guard let l = try? await ekip.istemci().sorgu(koleksiyon: "gorseller", sinir: 20, ust: "posts/\(p.id)") else { return }
        var m: [String: UIImage] = [:]
        for b in l { if let d = b.alanlar["veri"]?.baytDegeri, let r = UIImage(data: d) { m[b.kimlik] = r } }
        gorseller[p.id] = m
    }

    #if DEBUG
    static func ornek() -> [String: SosyalPost] {
        let bugun = Tr.bugun()
        func kanal(_ metin: String, durum: String = "bekliyor") -> FSDeger {
            .harita(["metin": .metin(metin), "gorseller": .dizi([.harita(["dosya": .metin("g1.jpg")])]), "durum": .metin(durum)])
        }
        let a = SosyalPost(kimlik: "\(bugun)-1", alanlar: [
            "tarih": .metin(bugun), "sira": .tam(1), "tur": .metin("haber"), "no": .tam(214), "konu": .metin("Almanya randevuları açıldı"),
            "kaynak": .metin("https://www.auswaertiges-amt.de"),
            "kanallar": .harita(["instagram": kanal("🇩🇪 Almanya vize randevuları açıldı! Hemen başvur. #vize #almanya"),
                                 "x": kanal("Almanya vize randevuları açıldı.", durum: "paylasildi"), "whatsapp": kanal("Almanya randevuları açıldı.")]),
        ])
        let b = SosyalPost(kimlik: "\(bugun)-2", alanlar: [
            "tarih": .metin(bugun), "sira": .tam(2), "tur": .metin("ipucu"), "no": .tam(215), "konu": .metin("Banka dökümünde dikkat"),
            "kanallar": .harita(["instagram": kanal("💡 Banka dökümü son 3 ayı göstermeli."), "x": kanal("Banka dökümü: son 3 ay.")]),
        ])
        return [a.id: a, b.id: b]
    }
    #endif
}

/// Bir postun seçili kanaldaki kartı.
struct SosyalKarti: View {
    let post: SosyalPost
    let kanal: String
    let resimler: [String: UIImage]?
    let resimleriYukle: () async -> Void
    let degisti: (SosyalPost) -> Void
    let silindi: () -> Void
    let bildir: (String) -> Void
    let hata: (String) -> Void
    @Environment(EkipOturumu.self) private var ekip
    @State private var calisiyor = false
    @State private var igOnay = false
    @State private var silOnay = false
    @State private var paylasim: [Any]?
    @State private var video: URL?
    @State private var oynatici: AVPlayer?
    @State private var videoYukleniyor = false

    private var kv: SosyalPost.Kanal? { post.kanallar[kanal] }
    private var dosyalar: [String] { kanal == SosyalPost.videoKanali ? [] : post.gorseller(kanal) }
    private var hazirResimler: [UIImage] { dosyalar.compactMap { resimler?[$0] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            medya
            HStack(spacing: 6) {
                Etiket(metin: post.turAdi, renk: post.tur == "haber" ? Tema.olumsuz : Tema.mavi)
                if let n = post.no { Text("#\(String(format: "%03d", n))").font(.caption2.monospaced()).foregroundStyle(Tema.silik) }
                ForEach(post.rozetler(kanal), id: \.self) { Etiket(metin: "\($0) ✓", renk: Tema.olumlu) }
            }
            Text(post.konu).font(.headline).foregroundStyle(Tema.lacivert)
            Text(kv?.metin ?? "").font(.subheadline).foregroundStyle(Tema.govde).textSelection(.enabled)
            if !post.kaynak.isEmpty {
                if let u = URL(string: post.kaynak), post.kaynak.lowercased().hasPrefix("http") {
                    Link("Kaynak: \(post.kaynak)", destination: u).font(.caption).lineLimit(1)
                } else {
                    Text("Kaynak: \(post.kaynak)").font(.caption).foregroundStyle(Tema.silik)
                }
            }
            durumSatiri
            dugmeler
        }
        .kart()
        .task { await resimleriYukle() }
        .sheet(isPresented: Binding(get: { paylasim != nil }, set: { if !$0 { paylasim = nil } })) {
            PaylasimSayfasi(ogeler: paylasim ?? []).ignoresSafeArea()
        }
        .confirmationDialog("\"\(post.konu)\" @vizemiacom Instagram hesabında paylaşılacak (görseller ve bu metin). Paylaşılan post panelden geri alınamaz.",
                            isPresented: $igOnay, titleVisibility: .visible) {
            Button("Paylaş") { Task { await instagram() } }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog("\"\(post.konu)\" bütün kanallarıyla ve görselleriyle silinecek. Bu geri alınamaz.\(post.kanallar["instagram"]?.permalink.isEmpty == false ? " Instagram'daki gönderi silinmez." : "")",
                            isPresented: $silOnay, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { Task { await sil() } }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var medya: some View {
        if kanal == SosyalPost.videoKanali {
            if let o = oynatici {
                VideoPlayer(player: o).frame(height: 420).clipShape(RoundedRectangle(cornerRadius: Tema.koseKucuk))
            } else if (kv?.videoParca ?? 0) > 0 {
                Button { Task { await videoYukle() } } label: {
                    HStack {
                        if videoYukleniyor { ProgressView() }
                        Label("Videoyu yükle", systemImage: "play.rectangle")
                    }
                }
                .buttonStyle(KucukDugme())
            }
        } else if !dosyalar.isEmpty {
            if resimler == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else if hazirResimler.isEmpty {
                Text(post.eski(gun: SosyalPost.gorselSaklamaGun) ? "\(SosyalPost.gorselSaklamaGun) günden eski görseller silinir." : "Görsel bulunamadı.")
                    .font(.caption).foregroundStyle(Tema.silik)
            } else {
                TabView {
                    ForEach(0..<hazirResimler.count, id: \.self) { i in
                        Image(uiImage: hazirResimler[i]).resizable().scaledToFit()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: hazirResimler.count > 1 ? .always : .never))
                .frame(height: 340)
                .background(Tema.zeminYumusak, in: RoundedRectangle(cornerRadius: Tema.koseKucuk))
            }
        }
    }

    @ViewBuilder
    private var durumSatiri: some View {
        if let kv {
            if kv.durum == "paylasildi" {
                HStack(spacing: 6) {
                    Text("Paylaşan: \(kv.paylasan.isEmpty ? "—" : kv.paylasan)\(kv.paylasildiTarih.map { " · " + Tr.tarihSaat($0) } ?? "")")
                        .font(.caption).foregroundStyle(Tema.olumluKoyu)
                    if let u = URL(string: kv.permalink), !kv.permalink.isEmpty { Link("Instagram'da aç", destination: u).font(.caption.weight(.semibold)) }
                }
            } else if kanal == SosyalPost.otomatikKanal {
                switch kv.durum {
                case "paylasim-bekliyor":
                    Text("Instagram'a gönderilmeyi bekliyor · İsteyen: \(kv.isteyen.isEmpty ? "—" : kv.isteyen)\(kv.istekTarih.map { " · " + Tr.tarihSaat($0) } ?? "")")
                        .font(.caption).foregroundStyle(Tema.mavi)
                case "paylasiliyor":
                    Text("Instagram'a gönderiliyor…").font(.caption).foregroundStyle(Tema.mavi)
                case "hata":
                    Text("Instagram'a gönderilemedi: \(kv.hata.isEmpty ? "bilinmeyen hata" : kv.hata)").font(.caption).foregroundStyle(Tema.olumsuz)
                default:
                    EmptyView()
                }
            }
        }
    }

    private var paylasildi: Bool { post.durum(kanal) == "paylasildi" }

    private var dugmeler: some View {
        let adi = SosyalPost.kanallar.first { $0.id == kanal }
        let otomatikVar = kanal == SosyalPost.otomatikKanal && ekip.yapabilir("social.instagram")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = kv?.metin ?? ""
                    bildir("Metin kopyalandı.")
                } label: { Label("Metni kopyala", systemImage: "doc.on.doc") }
                .buttonStyle(KucukDugme())
                Button { paylas() } label: { Label("Paylaş…", systemImage: "square.and.arrow.up") }
                    .buttonStyle(KucukDugme())
                    .disabled(kanal == SosyalPost.videoKanali ? video == nil : (hazirResimler.isEmpty && (kv?.metin ?? "").isEmpty))
            }
            HStack(spacing: 8) {
                if otomatikVar && post.otomatikIstenebilir(kanal) {
                    Button(post.durum(kanal) == "hata" ? "Tekrar dene" : "Instagram'da paylaş") { igOnay = true }
                        .buttonStyle(KucukDugme(renk: Tema.turkuaz))
                        .disabled(calisiyor)
                }
                if ekip.yapabilir("social.share") && !post.elleKilitli(kanal) {
                    Button {
                        Task { await isaretle(!paylasildi) }
                    } label: {
                        if calisiyor { ProgressView() } else { Text(paylasildi ? "Geri al" : (otomatikVar ? "Elle paylaştım" : (adi?.paylastim ?? "Paylaştım"))) }
                    }
                    .buttonStyle(KucukDugme(renk: paylasildi ? Tema.govde : Tema.olumluKoyu))
                    .disabled(calisiyor)
                }
                Spacer()
                if ekip.yapabilir("social.delete") && !post.otomatikSuruyor(SosyalPost.otomatikKanal) {
                    Button("Sil") { silOnay = true }.buttonStyle(KucukDugme(renk: Tema.olumsuz)).disabled(calisiyor)
                }
            }
        }
    }

    /// Paylaşım menüsü: görseller (ya da video) ve metin. Instagram metni almadığı için önce panoya kopyalanır.
    private func paylas() {
        let metin = kv?.metin ?? ""
        UIPasteboard.general.string = metin
        var l: [Any] = []
        if let v = video { l.append(v) } else { l += hazirResimler }
        if l.isEmpty || kanal != "instagram" { l.append(metin) }
        paylasim = l
        if !metin.isEmpty { bildir("Metin panoya da kopyalandı; açıklamaya yapıştırabilirsiniz.") }
    }

    private func isle(_ y: [FirestoreIstemci.Yazim]) async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return true }
        #endif
        do {
            let f = try await ekip.istemci()
            try await f.isle(y)
            if let a = try? await f.belge("posts/\(post.id)") { degisti(SosyalPost(kimlik: post.id, alanlar: a)) }
            return true
        } catch {
            hata(KasaVerisi.mesaj(error, "Kaydedilemedi."))
            return false
        }
    }

    private func isaretle(_ evet: Bool) async {
        guard let c = ekip.calisan else { return }
        calisiyor = true
        defer { calisiyor = false }
        let ad = SosyalPost.kanallar.first { $0.id == kanal }?.ad ?? kanal
        if await isle(SosyalIslemi.isaret(post, kanal: kanal, paylasildi: evet, calisan: c)) {
            bildir(evet ? "\(ad): paylaşıldı olarak işaretlendi." : "\(ad) işareti geri alındı.")
        }
    }

    private func instagram() async {
        guard let c = ekip.calisan else { return }
        calisiyor = true
        defer { calisiyor = false }
        guard await isle(SosyalIslemi.instagramIstegi(post, calisan: c)) else { return }
        // Görseller önce sitede yayınlanmalı: yayın işi bunu yapıp postu gönderir.
        let basladi = await ekip.siteyiGuncelle()
        bildir(basladi == true ? "Sıraya alındı. Görseller sitede yayınlanınca (birkaç dakika) Instagram'a gidecek."
               : "Sıraya alındı. Instagram paylaşım işi sırası gelince gönderecek.")
    }

    private func sil() async {
        guard let c = ekip.calisan else { return }
        calisiyor = true
        defer { calisiyor = false }
        do {
            let f = try await ekip.istemci()
            async let g = f.sorgu(koleksiyon: "gorseller", sinir: 20, ust: "posts/\(post.id)")
            async let v = f.sorgu(koleksiyon: "video", sinir: 10, ust: "posts/\(post.id)")
            let gl = try await g.map(\.kimlik), vl = try await v.map(\.kimlik)
            try await f.isle(SosyalIslemi.sil(post, gorseller: gl, videoParcalari: vl, calisan: c))
            if post.kanallar["instagram"]?.permalink.isEmpty == false { _ = await ekip.siteyiGuncelle() }
            silindi()
            bildir("Post silindi.")
        } catch {
            hata(KasaVerisi.mesaj(error, "Silinemedi."))
        }
    }

    /// Reels videosu: parçalar sırayla birleştirilir.
    private func videoYukle() async {
        videoYukleniyor = true
        defer { videoYukleniyor = false }
        do {
            let l = try await ekip.istemci().sorgu(koleksiyon: "video", sinir: 10, ust: "posts/\(post.id)")
            let parcalar = l.sorted { ($0.alanlar["sira"]?.tamDegeri ?? 0) < ($1.alanlar["sira"]?.tamDegeri ?? 0) }
            guard !parcalar.isEmpty, parcalar.count >= (kv?.videoParca ?? 0) else {
                hata(post.eski(gun: SosyalPost.videoSaklamaGun) ? "\(SosyalPost.videoSaklamaGun) günden eski videolar silinir." : "Video bulunamadı.")
                return
            }
            var d = Data()
            for p in parcalar { if let v = p.alanlar["veri"]?.baytDegeri { d.append(v) } }
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(post.id).mp4")
            try d.write(to: u, options: .atomic)
            video = u
            oynatici = AVPlayer(url: u)
        } catch {
            hata(KasaVerisi.mesaj(error, "Video yüklenemedi."))
        }
    }
}

/// iOS paylaşım menüsü (görseller, video, metin).
struct PaylasimSayfasi: UIViewControllerRepresentable {
    let ogeler: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: ogeler, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Post istekleri: "şu konuda post olsun" — günlük görev sıradaki postlarda yapar.
struct PostIstekleriSayfasi: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(\.dismiss) private var kapat
    @State private var istekler: [PostIstegi] = []
    @State private var metin = ""
    @State private var tarihVar = false
    @State private var tarih = Date()
    @State private var hata: String?
    @State private var gonderiliyor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("İstediğiniz konuyu yazın; günlük post görevi sıradaki postlarda onu hazırlar.").font(.caption).foregroundStyle(Tema.govde)
                        TextField("Ör. İtalya randevuları açıldı, duyuru postu", text: $metin, axis: .vertical).lineLimit(2...5).kutu()
                        IsaretKutusu(secili: $tarihVar, metin: "Belirli bir gün için")
                        if tarihVar {
                            DatePicker("Gün", selection: $tarih, in: Date()..., displayedComponents: .date).environment(\.locale, Tr.yerel)
                        }
                        if let h = hata { AlanHatasi(metin: h) }
                        Button {
                            Task { await gonder() }
                        } label: {
                            if gonderiliyor { ProgressView().tint(.white) } else { Text("İsteği gönder") }
                        }
                        .buttonStyle(AnaDugme())
                        .disabled(gonderiliyor)
                    }
                    .kart()
                    if !istekler.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("İstekler").font(.headline).foregroundStyle(Tema.lacivert)
                            ForEach(istekler) { i in satir(i); if i.id != istekler.last?.id { Divider() } }
                        }
                        .kart()
                    }
                }
                .padding(Tema.bosluk)
            }
            .formKlavyesi()
            .ekranZemini()
            .navigationTitle("Post isteği")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } } }
            .task { await yukle() }
        }
    }

    private func satir(_ i: PostIstegi) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(i.metin).font(.subheadline).foregroundStyle(Tema.lacivert)
                Text([i.isteyen, i.zaman.map { Tr.tarihSaat($0) } ?? "", i.hedefTarih.isEmpty ? "" : "Gün: \(BildirimMetni.trTarih(i.hedefTarih, gun: false))"]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Tema.silik)
            }
            Spacer()
            Etiket(metin: i.durum == "bekliyor" ? "Bekliyor" : (i.durum == "yapildi" ? "Yapıldı" : "İptal"),
                   renk: i.durum == "bekliyor" ? Tema.altin : (i.durum == "yapildi" ? Tema.olumlu : Tema.silik))
            if i.durum == "bekliyor" && (i.isteyenUid == ekip.calisan?.uid || ekip.yapabilir("social.delete")) {
                Button("İptal") { Task { await iptal(i) } }.buttonStyle(KucukDugme(renk: Tema.olumsuz))
            }
        }
    }

    private func yukle() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { return }
        #endif
        guard let l = try? await ekip.istemci().sorgu(koleksiyon: "postIstekleri", sirala: ("at", .azalan), sinir: 30) else { return }
        istekler = PostIstegi.sirala(l.map { PostIstegi(kimlik: $0.kimlik, alanlar: $0.alanlar) })
    }

    private func gonder() async {
        let gun = tarihVar ? Tr.isoGun(tarih, takvim: Tr.takvim) : ""
        if let h = PostIstegi.hata(metin: metin, hedefTarih: gun, bugun: Tr.bugun()) { hata = h; return }
        guard let c = ekip.calisan else { return }
        gonderiliyor = true
        defer { gonderiliyor = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { metin = ""; return }
        #endif
        do {
            try await ekip.istemci().isle(SosyalIslemi.istek(metin: metin, hedefTarih: gun, calisan: c))
            metin = ""; tarihVar = false; hata = nil
            await yukle()
        } catch {
            hata = KasaVerisi.mesaj(error, "Gönderilemedi.")
        }
    }

    private func iptal(_ i: PostIstegi) async {
        guard let c = ekip.calisan else { return }
        do {
            try await ekip.istemci().isle(SosyalIslemi.istekIptal(i, calisan: c))
            await yukle()
        } catch {
            hata = KasaVerisi.mesaj(error, "İptal edilemedi.")
        }
    }
}
