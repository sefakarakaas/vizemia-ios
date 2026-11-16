import SwiftUI
import VizeMiaCekirdek

/// Başvuru takibi: takip kodu + pasaport numarasıyla durum sorgusu
/// (sitedeki /takip sayfasının karşılığı).
struct TakipEkrani: View {
    @Environment(Gezinti.self) private var gezinti

    @State private var yil = String(Calendar(identifier: .gregorian).component(.year, from: Date()))
    @State private var kalan = ""
    @State private var pasaport = ""
    @State private var hatirla = false
    @State private var hata: String?
    @State private var yukleniyor = false
    @State private var kayit: TakipKaydi?
    @State private var sorgulananKod = ""
    /// Ekrandaki kaydın Firestore kimliği (sessiz yenileme için).
    @State private var sonKimlik: String?
    @State private var sinir = DenemeSiniri()
    @State private var ilkAcilis = true
    @State private var baglantidanGeldi = false
    @FocusState private var odak: Kutu?
    @Environment(\.scenePhase) private var sahne

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
                }
            }
            .padding(Tema.bosluk)
        }
        .scrollDismissesKeyboard(.interactively)
        .ekranZemini()
        .navigationTitle("Takip")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { koduUygula() }
        .onChange(of: gezinti.takipKodu) { _, _ in koduUygula() }
        .task {
            // Daha önce "hatırla" denildiyse bilgiler dolu gelir ve durum kendiliğinden sorgulanır.
            // Bağlantıyla başka bir kod geldiyse o öncelikli: kayıtlı bilgi üstüne yazılmaz.
            guard ilkAcilis else { return }
            ilkAcilis = false
            if !baglantidanGeldi, let k = Kasa.oku(), let p = Takip.kodAyir(k.kod) {
                yil = p.yil; kalan = p.kalan; pasaport = k.pasaport; hatirla = true
                await sorgula(otomatik: true)
            }
        }
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

            IsaretKutusu(secili: $hatirla, metin: "Bu telefonda hatırla. Uygulamayı açınca durumunuz kendiliğinden görünür; bilgiler yalnız bu cihazda saklanır.")
                .onChange(of: hatirla) { _, acik in
                    if !acik { Kasa.sil() }
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

    /// Bağlantıyla gelen takip kodu ("/takip?kod=2026-091234") kutulara yazılır;
    /// müşteri yalnız pasaport numarasını girer.
    private func koduUygula() {
        let k = gezinti.takipKodu
        guard !k.isEmpty else { return }
        gezinti.takipKodu = ""
        guard let p = Takip.kodAyir(k) else { return }
        baglantidanGeldi = true
        if "\(p.yil)-\(p.kalan)" != kod {
            pasaport = ""
            kayit = nil
            sonKimlik = nil
            hatirla = false
        }
        yil = p.yil; kalan = p.kalan
        hata = nil
        odak = .pasaport
    }

    private func sorgula(otomatik: Bool = false) async {
        // Kendiliğinden sorguda (kayıtlı bilgiyle açılış) klavyeye ve hata satırına dokunulmaz.
        if !otomatik {
            hata = nil
            odak = nil
        }
        if let h = Takip.hata(kod: kod, pasaport: pasaport) {
            if !otomatik { hata = h }
            return
        }
        if !otomatik, sinir.asildi() {
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
                if !otomatik {
                    hata = "Bu bilgilerle eşleşen bir başvuru bulunamadı. Takip kodunu ve pasaport numaranızı kontrol edin."
                }
                return
            }
            withAnimation { kayit = TakipKaydi(belge: belge) }
            sorgulananKod = sorguKodu
            sonKimlik = kimlik
            if hatirla { Kasa.yaz(Kasa.Kayit(kod: sorguKodu, pasaport: temiz)) }
        } catch {
            if !otomatik {
                hata = "Şu anda sorgulama yapılamıyor. Lütfen daha sonra tekrar deneyin."
            }
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

/// Sorgu sonucu: durum kartı, aşama çubuğu, notlar.
struct TakipSonucu: View {
    var kayit: TakipKaydi
    var kod: String
    @Environment(Gezinti.self) private var gezinti

    var body: some View {
        VStack(spacing: 16) {
            durum
            if let i = kayit.ilerleme { Yolculuk(ilerleme: i) }
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
            // Ekran açılınca pasaport baştan bulunduğu aşamaya yürür.
            if hareketAz {
                oran = ilerleme.oran
            } else {
                withAnimation(.easeInOut(duration: 1.1).delay(0.2)) { oran = ilerleme.oran }
            }
        }
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
