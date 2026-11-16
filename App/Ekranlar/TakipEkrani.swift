import SwiftUI
import VizeMiaCekirdek

/// Başvuru takibi (sitedeki /takip sayfasının karşılığı).
///
/// İki hâli var: "Beni unutma" diyen müşteri sekmeye dokununca doğrudan
/// sürecini görür; diğerleri takip kodu ve pasaport numarasıyla sorgular.
struct TakipEkrani: View {
    @Environment(TakipHafizasi.self) private var hafiza

    var body: some View {
        Group {
            if hafiza.hatirlaniyor {
                HatirlananTakip()
            } else {
                TakipSorgusu()
            }
        }
        .ekranZemini()
        .navigationTitle("Takip")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sorgu

/// Takip kodu + pasaport numarasıyla durum sorgusu.
struct TakipSorgusu: View {
    @Environment(Gezinti.self) private var gezinti
    @Environment(TakipHafizasi.self) private var hafiza
    @Environment(\.scenePhase) private var sahne

    @State private var yil = String(Calendar(identifier: .gregorian).component(.year, from: Date()))
    @State private var kalan = ""
    @State private var pasaport = ""
    @State private var hata: String?
    @State private var yukleniyor = false
    @State private var kayit: TakipKaydi?
    @State private var sorgulananKod = ""
    @State private var sorgulananPasaport = ""
    /// Ekrandaki kaydın Firestore kimliği (sessiz yenileme için).
    @State private var sonKimlik: String?
    @State private var sinir = DenemeSiniri()
    @FocusState private var odak: Kutu?

    private enum Kutu { case kod, pasaport }

    private var yillar: [String] {
        let bu = Calendar(identifier: .gregorian).component(.year, from: Date())
        var liste = (0...4).map { String(bu - $0) }
        if !liste.contains(yil) { liste.append(yil) }
        return liste
    }

    private var kod: String { "\(yil)-\(kalan)" }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Başvuru takibi").ustBaslik()
                    Text("Başvurunuz ne durumda?").bolumBasligi()
                    Text("Size ilettiğimiz takip kodunu ve pasaport numaranızı yazın.").govdeMetni()
                }

                form

                if let k = kayit {
                    TakipSonucu(kayit: k, kod: sorgulananKod)
                    beniUnutma(k)
                }
            }
            .padding(Tema.bosluk)
        }
        .formKlavyesi()
        .ekranZemini()
        .navigationTitle("Takip")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { koduUygula() }
        .onChange(of: gezinti.takipKodu) { _, _ in koduUygula() }
        .onChange(of: sahne) { _, yeni in
            // Uygulama yeniden öne gelince ekrandaki durum sessizce tazelenir.
            if yeni == .active { Task { await tazele() } }
        }
    }

    private var form: some View {
        VStack(spacing: 16) {
            Alan(etiket: "Takip kodu", yardim: "Yıl ve ardından 6 rakam (ör. 2026-091234). Kodun tamamını yapıştırabilirsiniz.") {
                HStack(spacing: 8) {
                    Picker("Yıl", selection: $yil) {
                        ForEach(yillar, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Tema.lacivert)
                    .padding(.vertical, 4)
                    .background(Tema.zemin, in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous).stroke(Tema.silik.opacity(0.55), lineWidth: 1))

                    Text("–").foregroundStyle(Tema.silik)

                    TextField("091234", text: $kalan)
                        .keyboardType(.numberPad)
                        .font(.body.monospacedDigit())
                        .focused($odak, equals: .kod)
                        .accessibilityIdentifier("takip-kod")
                        .accessibilityLabel("Takip kodunun son 6 rakamı")
                        .kutu()
                        .onChange(of: kalan) { _, yeni in
                            // Tam kod yapıştırılırsa iki kutuya bölünür.
                            if let p = Takip.kodAyir(yeni) {
                                yil = p.yil; kalan = p.kalan
                                odak = .pasaport
                            } else {
                                let temiz = String(yeni.filter { $0.isASCII && $0.isNumber }.prefix(6))
                                if temiz != yeni { kalan = temiz }
                            }
                        }
                }
            }

            Alan(etiket: "Pasaport numarası") {
                TextField("U12345678", text: $pasaport)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .font(.body.monospaced())
                    .focused($odak, equals: .pasaport)
                    .submitLabel(.search)
                    .onSubmit { Task { await sorgula() } }
                    .accessibilityIdentifier("takip-pasaport")
                    .kutu()
                    .onChange(of: pasaport) { _, yeni in
                        let buyuk = yeni.uppercased()
                        if buyuk != yeni { pasaport = buyuk }
                    }
            }

            if let h = hata { HataMetni(metin: h) }

            Button {
                Task { await sorgula() }
            } label: {
                if yukleniyor {
                    HStack(spacing: 8) { ProgressView().tint(.white); Text("Sorgulanıyor…") }
                } else {
                    Text("Durumu sorgula")
                }
            }
            .buttonStyle(AnaDugme())
            .disabled(yukleniyor)
        }
        .kart()
    }

    /// Sonucun altındaki "Beni unutma" kutusu. Yalnız basan müşteri hatırlanır.
    private func beniUnutma(_ k: TakipKaydi) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Her seferinde yeniden yazmayın", systemImage: "bell.badge.fill")
                .font(.headline)
                .foregroundStyle(.white)
            Text("“Beni unutma”ya basarsanız uygulamayı her açtığınızda sizi adınızla karşılar, Takip sekmesinde sürecinizi doğrudan gösterir ve aşama değişince telefonunuza bildirim gönderir. Bilgileriniz yalnız bu telefonda saklanır.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
            if let onceki = hafiza.son {
                Text("Şu an \(Selamlama.ad(onceki.ad)) hatırlanıyor; bu başvuru onun yerini alır.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Tema.turkuaz)
            }
            Button("Beni unutma") { hatirla(k) }
                .buttonStyle(AnaDugme(renk: Tema.turkuaz))
                .padding(.top, 4)
                .accessibilityIdentifier("beni-unutma")
        }
        .padding(Tema.bosluk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.lacivert, in: RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
    }

    private func hatirla(_ k: TakipKaydi) {
        hafiza.hatirla(kod: sorgulananKod, pasaport: sorgulananPasaport, son: k)
        // Başka bir başvuruyu sorgulamak için açılan ikinci ekransa kapanır.
        gezinti.yollar[.takip] = []
        // Bildirim izni yalnız şimdi, müşteri istediği anda sorulur.
        Task {
            if await Bildirimler.izinIste() { Bildirimler.sonrakiDenetimiPlanla() }
        }
    }

    /// Bağlantıyla gelen takip kodu ("/takip?kod=2026-091234") kutulara yazılır;
    /// müşteri yalnız pasaport numarasını girer.
    private func koduUygula() {
        let k = gezinti.takipKodu
        guard !k.isEmpty else { return }
        gezinti.takipKodu = ""
        guard let p = Takip.kodAyir(k) else { return }
        if "\(p.yil)-\(p.kalan)" != kod {
            pasaport = ""
            kayit = nil
            sonKimlik = nil
        }
        yil = p.yil; kalan = p.kalan
        hata = nil
        odak = .pasaport
    }

    private func sorgula() async {
        hata = nil
        odak = nil
        if let h = Takip.hata(kod: kod, pasaport: pasaport) {
            hata = h
            return
        }
        if sinir.asildi() {
            hata = "Çok fazla deneme yaptınız. Lütfen birkaç dakika sonra tekrar deneyin."
            return
        }
        yukleniyor = true
        defer { yukleniyor = false }
        let sorguKodu = kod
        let temiz = Takip.pasaportTemizle(pasaport)
        let kimlik = Takip.kimlik(kod: sorguKodu, pasaport: temiz)
        do {
            guard let belge = try await FirestoreIstemci().belge("takip/\(kimlik)") else {
                kayit = nil
                sonKimlik = nil
                hata = "Bu bilgilerle eşleşen bir başvuru bulunamadı. Takip kodunu ve pasaport numaranızı kontrol edin."
                return
            }
            withAnimation { kayit = TakipKaydi(belge: belge) }
            sorgulananKod = sorguKodu
            sorgulananPasaport = temiz
            sonKimlik = kimlik
        } catch {
            hata = "Şu anda sorgulama yapılamıyor. Lütfen daha sonra tekrar deneyin."
        }
    }

    /// Ekrandaki kaydı sessizce yeniler (uygulama yeniden öne gelince). Kutulara
    /// o sırada başka bir şey yazılıyor olabilir; son başarılı sorgu yinelenir.
    private func tazele() async {
        guard let kimlik = sonKimlik, kayit != nil, !yukleniyor else { return }
        do {
            if let belge = try await FirestoreIstemci().belge("takip/\(kimlik)") {
                withAnimation { kayit = TakipKaydi(belge: belge) }
            } else {
                // Kayıt artık yok (saklama süresi dolunca silinir).
                kayit = nil
                sonKimlik = nil
            }
        } catch {
            // Bağlantı yok: ekrandaki bilgi kalır.
        }
    }
}

// MARK: - Hatırlanan müşteri

/// "Beni unutma" diyen müşterinin Takip sekmesi: karşılama, animasyonlu
/// yolculuk, durum ve notlar. Form yok; sekmeye dokununca süreç doğrudan gelir.
struct HatirlananTakip: View {
    @Environment(TakipHafizasi.self) private var hafiza
    @Environment(Gezinti.self) private var gezinti
    @Environment(\.scenePhase) private var sahne

    @State private var bildirimAcik = true
    @State private var bildirimReddedildi = false
    @State private var unutSorusu = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                karsilama
                if let k = hafiza.son {
                    TakipSonucu(kayit: k, kod: hafiza.kayit?.kod ?? "", onceYolculuk: true)
                }
                if hafiza.silinmis { silinmisBilgisi }
                bildirimSatiri
                altDugmeler
            }
            .padding(Tema.bosluk)
        }
        .refreshable { await hafiza.yenile(zorla: true) }
        .task {
            hafiza.goruldu()
            baglantiKodunaBak()
            await bildirimDurumunuOku()
            await hafiza.yenile()
        }
        .onChange(of: gezinti.takipKodu) { _, _ in baglantiKodunaBak() }
        .onChange(of: sahne) { _, yeni in
            // Ayarlardan dönüldüyse bildirim izni değişmiş olabilir.
            if yeni == .active { Task { await bildirimDurumunuOku() } }
        }
    }

    private var karsilama: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Günün saatine göre: Günaydın / İyi günler / İyi akşamlar / İyi geceler.
            TimelineView(.everyMinute) { zaman in
                Text(Selamlama.cumle(saat: Calendar.current.component(.hour, from: zaman.date), ad: hafiza.son?.ad ?? ""))
                    .font(.vitrin(28))
                    .foregroundStyle(Tema.lacivert)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: 8) {
                Text("Başvurunuz şu an burada:").govdeMetni()
                if hafiza.yenileniyor { ProgressView().controlSize(.small) }
            }
        }
    }

    private var silinmisBilgisi: some View {
        Text("Bu başvuru artık takipte görünmüyor. İşlem tamamlandıktan bir süre sonra kayıtlar silinir; aşağıdaki son durumdur.")
            .font(.footnote)
            .foregroundStyle(Tema.uyari)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.uyariZemin, in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
    }

    @ViewBuilder private var bildirimSatiri: some View {
        if bildirimAcik {
            VStack(alignment: .leading, spacing: 4) {
                Label("Aşama değişince bildirim alacaksınız", systemImage: "bell.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tema.lacivert)
                Text("Uygulama durumu arka planda belirli aralıklarla denetler; bildirim birkaç saat gecikebilir. Güncel durumu görmek için bu ekranı aşağı çekip yenileyebilirsiniz.")
                    .font(.caption)
                    .foregroundStyle(Tema.govde)
            }
            .kart(dolgu: 14)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Bildirimler kapalı", systemImage: "bell.slash.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tema.lacivert)
                Text("Açarsanız aşama değişince telefonunuza haber veririz.").font(.caption).foregroundStyle(Tema.govde)
                Button("Bildirimleri aç") {
                    if bildirimReddedildi {
                        // İzin daha önce reddedildi: yalnız sistem ayarlarından açılabilir.
                        Bildirimler.ayarlariAc()
                    } else {
                        Task {
                            if await Bildirimler.izinIste() { Bildirimler.sonrakiDenetimiPlanla() }
                            await bildirimDurumunuOku()
                        }
                    }
                }
                .buttonStyle(IkincilDugme())
            }
            .kart(dolgu: 14)
        }
    }

    private var altDugmeler: some View {
        VStack(spacing: 14) {
            NavigationLink(value: Rota.takipSorgu) {
                Text("Başka bir başvuruyu sorgula")
            }
            .buttonStyle(IkincilDugme())

            Button {
                unutSorusu = true
            } label: {
                Text("Beni unut")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tema.olumsuz)
            }
            .accessibilityIdentifier("beni-unut")
            .accessibilityHint("Bu telefondaki takip bilgilerinizi siler")
            .confirmationDialog("Bu telefon sizi unutsun mu?", isPresented: $unutSorusu, titleVisibility: .visible) {
                Button("Beni unut", role: .destructive) { hafiza.unut() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Takip kodunuz ve pasaport numaranız bu telefondan silinir, bildirim gelmez. Dilediğinizde yeniden sorgulayabilirsiniz.")
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    private func bildirimDurumunuOku() async {
        bildirimAcik = await Bildirimler.izinVerildi()
        bildirimReddedildi = await Bildirimler.reddedildi()
    }

    /// Bağlantıyla başka bir takip kodu geldiyse sorgu ekranı açılır (kodu o alır);
    /// hatırlanan başvurunun koduysa yapılacak bir şey yok.
    private func baglantiKodunaBak() {
        let k = gezinti.takipKodu
        guard !k.isEmpty else { return }
        if let p = Takip.kodAyir(k), "\(p.yil)-\(p.kalan)" != hafiza.kayit?.kod {
            let acik = gezinti.yollar[.takip]?.contains(Rota.takipSorgu) ?? false
            if !acik { gezinti.yollar[.takip, default: []].append(Rota.takipSorgu) }
        } else {
            gezinti.takipKodu = ""
        }
    }
}

// MARK: - Sonuç

/// Durum kartı, aşama çubuğu, notlar.
struct TakipSonucu: View {
    var kayit: TakipKaydi
    var kod: String
    /// Hatırlanan müşteride önce animasyonlu yolculuk, sonra durum gelir.
    var onceYolculuk = false
    @Environment(Gezinti.self) private var gezinti

    var body: some View {
        VStack(spacing: 16) {
            if onceYolculuk {
                if let i = kayit.ilerleme { Yolculuk(ilerleme: i) }
                durum
            } else {
                durum
                if let i = kayit.ilerleme { Yolculuk(ilerleme: i) }
            }
            if !kayit.notlar.isEmpty { notlar }
            Button {
                gezinti.it(.destek(kod: kod))
            } label: {
                Text("Sorunuz mu var? Destek formundan bize yazın.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tema.mavi)
                    .underline()
            }
        }
    }

    private var durum: some View {
        let renk = kayit.renk.flatMap { Color(kod: $0) } ?? Tema.turkuaz
        return HStack(spacing: 0) {
            Rectangle().fill(renk).frame(width: 6)
            VStack(alignment: .leading, spacing: 8) {
                Text(kayit.ustSatir).font(.caption).foregroundStyle(Tema.govde)
                Text(kayit.durum.isEmpty ? "Durum bilgisi" : kayit.durum)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Tema.lacivert)
                if !kayit.aciklama.isEmpty {
                    Text(kayit.aciklama).font(.body).foregroundStyle(Tema.govde)
                }
                if let g = kayit.guncelleme {
                    Text("Son güncelleme: \(Tr.tarihSaat(g))").font(.caption).foregroundStyle(Tema.silik)
                }
            }
            .padding(Tema.bosluk)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tema.soluk)
        .clipShape(RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var notlar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Size iletilen notlar").font(.headline).foregroundStyle(Tema.lacivert)
            ForEach(kayit.notlar) { n in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Tema.turkuaz).frame(width: 8, height: 8).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        if let t = n.tarih {
                            Text(Tr.kisaTarih(t)).font(.caption).foregroundStyle(Tema.silik)
                        }
                        Text(n.metin).font(.subheadline).foregroundStyle(Tema.govde)
                    }
                }
            }
        }
        .kart()
    }
}

/// "Başvurunuzun yolculuğu": pasaport, bulunduğu aşamaya kadar çubukta ilerler.
struct Yolculuk: View {
    var ilerleme: TakipKaydi.Ilerleme
    @State private var oran: Double = 0
    @Environment(\.accessibilityReduceMotion) private var hareketAz

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Başvurunuzun yolculuğu").font(.headline).foregroundStyle(Tema.lacivert)

            GeometryReader { geo in
                let genislik = max(geo.size.width - 28, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Tema.soluk).frame(height: 6).padding(.horizontal, 14)
                    Capsule()
                        .fill(ilerleme.bitti ? Tema.olumlu : Tema.turkuaz)
                        .frame(width: genislik * oran, height: 6)
                        .padding(.leading, 14)
                    PasaportCizimi()
                        .frame(width: 28, height: 37)
                        .offset(x: genislik * oran)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                }
                .frame(height: 40)
            }
            .frame(height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(ilerleme.adlar.enumerated()), id: \.offset) { i, ad in
                    let gecti = ilerleme.gecti(i)
                    let simdi = i == ilerleme.simdi && !ilerleme.bitti
                    HStack(spacing: 10) {
                        Group {
                            if gecti {
                                Image(systemName: "checkmark").font(.caption.weight(.heavy))
                            } else {
                                Text("\(i + 1)").font(.caption.weight(.heavy))
                            }
                        }
                        .foregroundStyle(gecti || simdi ? Color.white : Tema.govde)
                        .frame(width: 26, height: 26)
                        .background(gecti ? Tema.olumlu : (simdi ? Tema.lacivert : Tema.soluk), in: Circle())

                        Text(ad)
                            .font(simdi ? .subheadline.weight(.bold) : .subheadline)
                            .foregroundStyle(simdi ? Tema.lacivert : Tema.govde)
                        if simdi {
                            Text("şimdi")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Tema.turkuaz, in: Capsule())
                        }
                    }
                }
            }

            Text(ilerleme.ozet).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
        }
        .kart()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ilerleme.adlar.count) aşamadan \(ilerleme.simdi + 1). aşama: \(ilerleme.adlar[ilerleme.simdi])")
        .onAppear {
            // Ekran her açıldığında pasaport baştan bulunduğu aşamaya yürür.
            if hareketAz {
                oran = ilerleme.oran
            } else {
                withAnimation(.easeInOut(duration: 1.2).delay(0.25)) { oran = ilerleme.oran }
            }
        }
        // Sekmeden çıkınca başa döner; geri gelindiğinde animasyon yeniden oynar.
        .onDisappear { oran = 0 }
        .onChange(of: ilerleme) { _, yeni in
            withAnimation(.easeInOut(duration: 0.6)) { oran = yeni.oran }
        }
    }
}

/// Pasaport çizimi: lacivert kapak, altın arma ve yazı (sitedeki SVG'nin karşılığı).
struct PasaportCizimi: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.11, style: .continuous).fill(Tema.lacivert)
                RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                    .stroke(Tema.altin.opacity(0.7), lineWidth: max(w * 0.022, 0.5))
                    .padding(w * 0.07)
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Tema.altin)
                    .frame(width: w * 0.42)
                    .offset(y: -h * 0.08)
                VStack(spacing: h * 0.045) {
                    Capsule().fill(Tema.altin).frame(width: w * 0.5, height: max(h * 0.04, 1))
                    Capsule().fill(Tema.altin.opacity(0.7)).frame(width: w * 0.34, height: max(h * 0.03, 1))
                }
                .offset(y: h * 0.3)
            }
        }
    }
}
