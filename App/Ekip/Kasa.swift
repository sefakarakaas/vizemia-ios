import SwiftUI
import QuickLook
import VizeMiaCekirdek

/// Kasa ve raporlar (panel: #/kasa). Müşteri ödemeleri (başvurudaki Ödemeler),
/// harcamalar ve döviz çevrimleri tek defterde; TL, EUR, USD, GBP ayrı toplanır.
struct KasaEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @State private var form: KasaKaydiSayfasi.Kip?
    @State private var bildiri: String?
    @State private var bildiriHata = false
    @State private var basari = 0
    @State private var onizleme: URL?
    @State private var aciliyor: String?
    @State private var iptalEdilecek: KasaHareketi?
    @State private var iptalNedeni = ""
    @State private var csv: URL?

    private var kasa: KasaVerisi { ekipVerisi.kasa }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Müşteriden alınan ödemeler (başvurudaki Ödemeler bölümünden), harcamalar ve döviz çevrimleri tek defterde. TL, EUR, USD ve GBP ayrı toplanır; birbirine çevrilmez. Gün sonu raporu her gün \(ekip.kasaAyari.raporSaati)'de gider.")
                    .font(.caption)
                    .foregroundStyle(Tema.govde)
                if ekip.yapabilir("kasa.view") { RutinBekleyenlerKarti(odendi: { form = .rutin($0) }).belirme(0) }
                if ekip.yapabilir("kasa.gider") { girisKarti.belirme(1) }
                if ekip.yapabilir("kasa.view") {
                    KasaRaporKarti(fisAc: fisAc(_:), aciliyor: aciliyor, iptal: { iptalNedeni = ""; iptalEdilecek = $0 }).belirme(2)
                }
                if ekip.yapabilir("kasa.rutin") {
                    NavigationLink(value: EkipRota.kasaRutinler) {
                        HStack {
                            Label("Rutin ödemeler", systemImage: "repeat.circle.fill").font(.headline).foregroundStyle(Tema.lacivert)
                            Spacer()
                            Text("\(kasa.rutinler.count)").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.silik)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
                        }
                        .kart()
                    }
                    .buttonStyle(.plain)
                    .belirme(3)
                }
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("Kasa ve raporlar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if ekip.yapabilir("kasa.view"), !kasa.hareketler.isEmpty, let url = csv {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) { Label("Excel (CSV)", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .task {
            await kasa.rutinleriYukle(ekip, zorla: false)
            await kasa.raporYukle(ekip, zorla: false)
        }
        .refreshable {
            await kasa.rutinleriYukle(ekip)
            await kasa.raporYukle(ekip)
        }
        .sheet(item: $form) { k in
            KasaKaydiSayfasi(kip: k) { g, fis, kimlik in
                let h = await kasa.kaydet(g, fis: fis, kimlik: kimlik, ekip: ekip)
                if h == nil { goster(k.basariMetni(g), hata: false) }
                return h
            }
        }
        .alert("Kayıt iptal edilsin mi?", isPresented: Binding(get: { iptalEdilecek != nil }, set: { if !$0 { iptalEdilecek = nil } })) {
            TextField("İptal nedeni (ör. iki kez girildi)", text: $iptalNedeni)
            Button("İptal et", role: .destructive) {
                guard let x = iptalEdilecek else { return }
                let n = iptalNedeni
                Task {
                    let h = await kasa.iptal(x, neden: n, ekip: ekip)
                    goster(h ?? "Kayıt iptal edildi; raporlarda sayılmaz.", hata: h != nil)
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Kayıt silinmez; iptal edildi olarak kalır ve raporlarda sayılmaz.")
        }
        .quickLookPreview($onizleme)
        // CSV, hareketler değişince bir kez yazılır (her çizimde değil).
        .onChange(of: kasa.hareketler, initial: true) { _, _ in csv = kasa.hareketler.isEmpty ? nil : kasa.csvDosyasi() }
        .overlay(alignment: .top) {
            if let b = bildiri {
                Label(b, systemImage: bildiriHata ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(bildiriHata ? Tema.olumsuz : Tema.olumluKoyu, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { bildiri = nil }
            }
        }
        .animation(Hareket.yay, value: bildiri)
        .sensoryFeedback(.success, trigger: basari)
    }

    private var girisKarti: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kayıt ekle").font(.headline).foregroundStyle(Tema.lacivert)
            HStack(spacing: 10) {
                Button { form = .harcama(nil) } label: { Label("Harcama", systemImage: "minus.circle.fill") }
                    .buttonStyle(AnaDugme())
                Button { form = .cevrim } label: { Label("Döviz çevrimi", systemImage: "arrow.left.arrow.right.circle.fill") }
                    .buttonStyle(IkincilDugme())
            }
            Text("Müşteri ödemeleri başvurunun Ödemeler bölümünden girilir ve buraya kendiliğinden gelir.")
                .font(.caption2)
                .foregroundStyle(Tema.silik)
        }
        .kart()
    }

    private func goster(_ m: String, hata: Bool) {
        bildiriHata = hata
        bildiri = m
        if !hata { basari += 1 }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if bildiri == m { bildiri = nil }
        }
    }

    private func fisAc(_ x: KasaHareketi) {
        guard aciliyor == nil else { return }
        aciliyor = x.id
        Task {
            do { onizleme = try await KasaVerisi.fisDosyasi(x, ekip: ekip) } catch { goster("Fiş açılamadı.", hata: true) }
            aciliyor = nil
        }
    }
}

// MARK: - Ödenecek rutin ödemeler

struct RutinBekleyenlerKarti: View {
    let odendi: (RutinOdeme.Vade) -> Void
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi

    var body: some View {
        let kasa = ekipVerisi.kasa
        let b = kasa.bekleyenler
        let bugun = Tr.bugun()
        VStack(alignment: .leading, spacing: 10) {
            Text("Ödenecek rutin ödemeler").font(.headline).foregroundStyle(Tema.lacivert)
            if let h = kasa.rutinHata {
                AlanHatasi(metin: h)
            } else if kasa.rutinler.isEmpty {
                Text("Tanımlı rutin ödeme yok. Fatura, kira, haftalık ücret gibi ödemeler \"Rutin ödemeler\"den eklenir.")
                    .font(.caption).foregroundStyle(Tema.govde)
            } else if b.geciken.isEmpty && b.bugun.isEmpty && b.yaklasan.isEmpty {
                Text("Önümüzdeki 7 günde ödenecek ya da geciken rutin ödeme yok.").font(.caption).foregroundStyle(Tema.govde)
            } else {
                ForEach(b.geciken) { satir($0, "Gecikti", Tema.olumsuz, bugun) }
                ForEach(b.bugun) { satir($0, "Bugün", Tema.altin, bugun) }
                ForEach(b.yaklasan) { satir($0, "Yaklaşıyor", Tema.mavi, bugun) }
            }
        }
        .kart()
    }

    private func satir(_ v: RutinOdeme.Vade, _ durum: String, _ renk: Color, _ bugun: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Etiket(metin: durum, renk: renk)
                    if v.rutin.otomatik && v.vade >= v.rutin.otomatikBas { Etiket(metin: "otomatik", renk: Tema.turkuaz) }
                }
                Text(v.rutin.ad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                Text([Tr.uzunTarih(v.vade),
                      v.rutin.tutar.map { "≈ " + KasaKurali.paraYazi([v.rutin.paraBirimi: $0]) } ?? "tutar her seferinde girilir",
                      v.rutin.kategori].joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Tema.govde)
            }
            Spacer(minLength: 0)
            if ekip.yapabilir("kasa.gider") && v.vade <= bugun {
                Button("Ödendi…") { odendi(v) }.buttonStyle(KucukDugme())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Rapor

struct KasaRaporKarti: View {
    let fisAc: (KasaHareketi) -> Void
    let aciliyor: String?
    let iptal: (KasaHareketi) -> Void
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @State private var tumHareketler = false

    var body: some View {
        @Bindable var kasa = ekipVerisi.kasa
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Rapor").font(.headline).foregroundStyle(Tema.lacivert)
                Spacer()
                Picker("Dönem", selection: $kasa.aralikTuru) {
                    ForEach(0..<KasaKurali.araliklar.count, id: \.self) { i in
                        Text(KasaKurali.araliklar[i].ad).tag(KasaKurali.araliklar[i].id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Tema.lacivert)
            }
            if kasa.aralikTuru == "ozel" {
                HStack {
                    DatePicker("", selection: $kasa.ozelBas, in: ...Date(), displayedComponents: .date).labelsHidden()
                    Text("–").foregroundStyle(Tema.silik)
                    DatePicker("", selection: $kasa.ozelBit, in: ...Date(), displayedComponents: .date).labelsHidden()
                    Spacer()
                    Button("Göster") { Task { await kasa.raporYukle(ekip) } }.buttonStyle(KucukDugme())
                }
                .environment(\.locale, Tr.yerel)
            }
            if kasa.raporYukleniyor && kasa.hareketler.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let h = kasa.raporHata {
                AlanHatasi(metin: h)
            } else {
                rapor(kasa)
            }
        }
        .kart()
        .onChange(of: kasa.aralikTuru) { _, yeni in
            if yeni != "ozel" { Task { await kasa.raporYukle(ekip) } }
        }
    }

    private func baslik(_ k: KasaVerisi) -> String {
        k.tekGun ? "\(Tr.uzunTarih(k.bas)) gün sonu raporu" : "\(Tr.uzunTarih(k.bas)) – \(Tr.uzunTarih(k.bit))"
    }

    @ViewBuilder
    private func rapor(_ k: KasaVerisi) -> some View {
        let o = k.ozet
        Text(baslik(k)).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.govde)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ozetKutusu("Gelir", KasaKurali.paraYazi(o.gelir), Tema.olumluKoyu)
            ozetKutusu("Gider", KasaKurali.paraYazi(o.gider), Tema.olumsuz)
            ozetKutusu("Net (gelir − gider)", KasaKurali.isaretli(o.net), Tema.lacivert)
            ozetKutusu("Kasa değişimi (çevrim dahil)", KasaKurali.isaretli(o.kasa), Tema.mavi)
        }
        Text(sayiMetni(o)).font(.caption2).foregroundStyle(Tema.silik)
        if k.sinirDoldu {
            Text("Bu dönemde \(KasaVerisi.raporSiniri)'den çok hareket var; ilk \(KasaVerisi.raporSiniri) kayıt gösteriliyor. Daha kısa bir dönem seçin.")
                .font(.caption).foregroundStyle(Tema.uyari)
        }
        if !o.birimler.isEmpty { birimTablosu(o) }
        let cevrimler = k.hareketler.filter { $0.tur == "cevrim" && !$0.iptal }
        if !cevrimler.isEmpty { cevrimListesi(cevrimler) }
        if !k.tekGun { gunluk(k) }
        kirilim("Giderler — kategoriye göre", o.giderKategori) { $0 }
        kirilim("Giderler — müşteri / genel", o.giderKapsam) { $0 == "musteri" ? "Müşteriler için" : "Genel giderler" }
        kirilim("Gelirler — yönteme göre", o.gelirYontem) { KasaKurali.yontemAdi($0) }
        hareketListesi(k)
    }

    private func sayiMetni(_ o: KasaOzeti) -> String {
        var s = "\(o.sayi.gelir) ödeme, \(o.sayi.gider) harcama, \(o.sayi.cevrim) döviz çevrimi"
        if o.sayi.iptal > 0 { s += ", \(o.sayi.iptal) iptal (sayılmadı)" }
        s += o.sayi.tutarsizGelir > 0 ? ". \(o.sayi.tutarsizGelir) ödemede tutar girilmemiş (toplama katılmadı)." : "."
        return s
    }

    private func ozetKutusu(_ ad: String, _ deger: String, _ renk: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ad).font(.caption2.weight(.semibold)).foregroundStyle(Tema.silik)
            Text(deger).font(.subheadline.weight(.bold)).foregroundStyle(renk)
                .lineLimit(3).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .padding(10)
        .background(Tema.zeminYumusak, in: RoundedRectangle(cornerRadius: Tema.koseKucuk))
    }

    private func altBaslik(_ s: String) -> some View {
        Text(s).font(.subheadline.weight(.bold)).foregroundStyle(Tema.lacivert).padding(.top, 4)
    }

    /// Her para birimi ayrı: gelir, gider, net, çevrim, kasa değişimi, nakit farkı.
    private func birimTablosu(_ o: KasaOzeti) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            altBaslik("Para birimlerine göre")
            ForEach(o.birimler, id: \.self) { b in
                VStack(alignment: .leading, spacing: 3) {
                    Text(b).font(.caption.weight(.heavy)).foregroundStyle(Tema.lacivert)
                    Text(birimSatiri(o, b)).font(.caption).foregroundStyle(Tema.govde)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Tema.soluk.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func birimSatiri(_ o: KasaOzeti, _ b: String) -> String {
        var l: [String] = []
        if let v = o.gelir[b], v != 0 { l.append("gelir +\(KasaKurali.paraYazi([b: v]))") }
        if let v = o.gider[b], v != 0 { l.append("gider −\(KasaKurali.paraYazi([b: v]))") }
        l.append("net \(KasaKurali.isaretli([b: o.net[b] ?? 0]))")
        if let v = o.cevrimCikan[b], v != 0 { l.append("çevrimle çıkan −\(KasaKurali.paraYazi([b: v]))") }
        if let v = o.cevrimGiren[b], v != 0 { l.append("çevrimle giren +\(KasaKurali.paraYazi([b: v]))") }
        l.append("kasa \(KasaKurali.isaretli([b: o.kasa[b] ?? 0]))")
        l.append("nakit \(KasaKurali.isaretli([b: o.nakit[b] ?? 0]))")
        return l.joined(separator: " · ")
    }

    private func cevrimListesi(_ l: [KasaHareketi]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            altBaslik("Döviz çevrimleri (\(l.count))")
            ForEach(l) { c in
                let kur = KasaKurali.cevrimKuru(tutar: c.tutar, paraBirimi: c.paraBirimi, hedefTutar: c.hedefTutar, hedefParaBirimi: c.hedefParaBirimi)
                VStack(alignment: .leading, spacing: 2) {
                    Text(KasaKurali.tutarYazi(c)).font(.caption.weight(.semibold)).foregroundStyle(Tema.lacivert)
                    Text([Tr.uzunTarih(c.tarih), c.buro, kur, c.yazan].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(Tema.govde)
                }
            }
        }
    }

    /// Yalnız hareket olan günler; TL çubukları gelir / gider karşılaştırır.
    private func gunluk(_ k: KasaVerisi) -> some View {
        let gunler = KasaKurali.gunler(bas: k.bas, bit: k.bit).filter { k.ozet.gunluk[$0] != nil }.reversed()
        let enBuyuk = max(1, gunler.map { max(k.ozet.gunluk[$0]?.gelir["TRY"] ?? 0, k.ozet.gunluk[$0]?.gider["TRY"] ?? 0) }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            if !gunler.isEmpty { altBaslik("Günlere göre") }
            ForEach(Array(gunler), id: \.self) { d in
                let g = k.ozet.gunluk[d] ?? KasaOzeti.Gun()
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(Tr.uzunTarih(d)).font(.caption.weight(.semibold)).foregroundStyle(Tema.lacivert)
                        Spacer()
                        Text("+\(KasaKurali.paraYazi(g.gelir, bos: "0")) / −\(KasaKurali.paraYazi(g.gider, bos: "0"))")
                            .font(.caption2).foregroundStyle(Tema.govde)
                    }
                    cubuk(g.gelir["TRY"] ?? 0, enBuyuk, Tema.olumlu)
                    cubuk(g.gider["TRY"] ?? 0, enBuyuk, Tema.olumsuz)
                }
            }
        }
    }

    private func cubuk(_ v: Double, _ enBuyuk: Double, _ renk: Color) -> some View {
        GeometryReader { g in
            Capsule().fill(renk.opacity(0.75)).frame(width: max(v > 0 ? 3 : 0, g.size.width * CGFloat(v / enBuyuk)))
        }
        .frame(height: 5)
    }

    private func kirilim(_ ad: String, _ o: [String: ParaToplami], _ isim: @escaping (String) -> String) -> some View {
        let satirlar = KasaOzeti.kirilim(o)
        return VStack(alignment: .leading, spacing: 4) {
            if !satirlar.isEmpty {
                altBaslik(ad)
                ForEach(0..<satirlar.count, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline) {
                        Text(isim(satirlar[i].ad)).font(.caption).foregroundStyle(Tema.govde)
                        Spacer()
                        Text(KasaKurali.paraYazi(satirlar[i].toplam)).font(.caption.weight(.semibold)).foregroundStyle(Tema.lacivert)
                    }
                }
            }
        }
    }

    /// Yalnız yönetici, iptal edilmemiş kaydı iptal edebilir.
    private func iptalEylemi(_ x: KasaHareketi) -> (() -> Void)? {
        guard ekip.calisan?.yonetici == true, !x.iptal else { return nil }
        return { iptal(x) }
    }

    private func hareketListesi(_ k: KasaVerisi) -> some View {
        let l = tumHareketler ? k.hareketler : Array(k.hareketler.prefix(30))
        return VStack(alignment: .leading, spacing: 0) {
            altBaslik("Hareketler (\(k.hareketler.count))").padding(.bottom, 6)
            if k.hareketler.isEmpty {
                Text("Bu dönemde hareket yok.").font(.caption).foregroundStyle(Tema.govde)
            }
            ForEach(l) { x in
                KasaHareketSatiri(x: x, aciliyor: aciliyor == x.id, fisAc: { fisAc(x) }, iptal: iptalEylemi(x))
                Divider()
            }
            if !tumHareketler && k.hareketler.count > l.count {
                Button("Tümünü göster (\(k.hareketler.count))") { withAnimation(Hareket.yay) { tumHareketler = true } }
                    .buttonStyle(KucukDugme())
                    .padding(.top, 8)
            }
        }
    }
}

/// Defter satırı: tür, kategori / büro, müşteri, açıklama, yöntem, tutar, giren.
struct KasaHareketSatiri: View {
    let x: KasaHareketi
    let aciliyor: Bool
    let fisAc: () -> Void
    let iptal: (() -> Void)?
    @Environment(EkipOturumu.self) private var ekip

    private var turAdi: (String, Color) {
        switch x.tur {
        case "gelir": return ("Gelir", Tema.olumlu)
        case "cevrim": return ("Çevrim", Tema.mavi)
        default: return ("Gider", Tema.olumsuz)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Etiket(metin: turAdi.0, renk: turAdi.1)
                    if x.iptal { Etiket(metin: "İptal", renk: Tema.silik) }
                    Text(Tr.uzunTarih(x.tarih)).font(.caption2).foregroundStyle(Tema.silik)
                }
                Text(x.tur == "cevrim" ? "Döviz çevrimi · \(x.buro)" : x.kategori)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(x.iptal ? Tema.silik : Tema.lacivert)
                    .strikethrough(x.iptal)
                if !x.musteriAd.isEmpty {
                    if !x.appId.isEmpty && ekip.yapabilir("app.view") {
                        NavigationLink(value: EkipRota.basvuru(x.appId)) {
                            Text(x.musteriAd).font(.caption.weight(.semibold)).foregroundStyle(Tema.turkuaz)
                        }
                    } else {
                        Text(x.musteriAd).font(.caption).foregroundStyle(Tema.govde)
                    }
                }
                Text([x.aciklama, KasaKurali.yontemAdi(x.yontem), x.yazan].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(Tema.govde)
                if x.iptal && !x.iptalNot.isEmpty {
                    Text("İptal: \(x.iptalNot)\(x.iptalAd.isEmpty ? "" : " (\(x.iptalAd))")").font(.caption2).foregroundStyle(Tema.olumsuz)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Text(KasaKurali.tutarYazi(x))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(x.iptal ? Tema.silik : (x.tur == "gelir" ? Tema.olumluKoyu : Tema.lacivert))
                    .multilineTextAlignment(.trailing)
                if !x.fisId.isEmpty {
                    Button(action: fisAc) {
                        if aciliyor { ProgressView() } else { Label("Fiş", systemImage: "doc.text.image") }
                    }
                    .buttonStyle(KucukDugme())
                }
                if let iptal {
                    Button("İptal", action: iptal).buttonStyle(KucukDugme(renk: Tema.olumsuz))
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Harcama / çevrim / rutin ödemesi formu

struct KasaKaydiSayfasi: View {
    enum Kip: Identifiable {
        /// Başvuru verilirse müşteri harcaması o başvuruya yazılır.
        case harcama(Basvuru?)
        case cevrim
        case rutin(RutinOdeme.Vade)

        var id: String {
            switch self {
            case .harcama(let b): return "h" + (b?.kimlik ?? "")
            case .cevrim: return "c"
            case .rutin(let v): return "r" + v.id
            }
        }

        func basariMetni(_ g: KasaGirdisi) -> String {
            switch self {
            case .harcama: return "Harcama kaydedildi."
            case .cevrim:
                return "Çevrim kaydedildi: −\(KasaKurali.paraYazi([g.paraBirimi: g.tutar ?? 0])), +\(KasaKurali.paraYazi([g.hedefParaBirimi: g.hedefTutar ?? 0]))."
            case .rutin(let v): return "\(v.rutin.ad) ödendi olarak kaydedildi."
            }
        }
    }

    let kip: Kip
    /// Kaydeder; hata metni döner (nil: tamam). Üçüncü değer: defter kimliği (rutin vadesi için).
    let kaydet: (KasaGirdisi, HazirDosya?, String?) async -> String?

    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @Environment(\.dismiss) private var kapat
    @State private var g = KasaGirdisi()
    @State private var tutar = ""
    @State private var hedefTutar = ""
    @State private var tarih = Date()
    @State private var musteri: Basvuru?
    @State private var musteriArama = ""
    @State private var fis: HazirDosya?
    @State private var hatalar: [String] = []
    @State private var kaydediliyor = false
    @State private var hazir = false

    private var bugun: String { Tr.bugun() }
    private var kategoriler: [String] { g.kapsam == "musteri" ? ekip.kasaAyari.musteriGiderleri : ekip.kasaAyari.genelGiderler }
    private var basvuruSabit: Basvuru? { if case .harcama(let b) = kip { return b }; return nil }

    private var baslik: String {
        switch kip {
        case .harcama: return basvuruSabit == nil ? "Harcama ekle" : "Müşteri harcaması"
        case .cevrim: return "Döviz çevrimi"
        case .rutin: return "Ödendi olarak kaydet"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch kip {
                    case .harcama: harcamaAlanlari
                    case .cevrim: cevrimAlanlari
                    case .rutin(let v): rutinAlanlari(v)
                    }
                    ortakAlanlar
                    ForEach(hatalar, id: \.self) { AlanHatasi(metin: $0) }
                    Button {
                        Task { await gonder() }
                    } label: {
                        if kaydediliyor {
                            HStack(spacing: 8) { ProgressView().tint(.white); Text("Kaydediliyor…") }
                        } else {
                            Text(dugmeMetni)
                        }
                    }
                    .buttonStyle(AnaDugme())
                    .disabled(kaydediliyor)
                }
                .padding(Tema.bosluk)
            }
            .formKlavyesi()
            .ekranZemini()
            .navigationTitle(baslik)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
        }
        .onAppear(perform: hazirla)
    }

    private var dugmeMetni: String {
        switch kip {
        case .harcama: return "Harcamayı kaydet"
        case .cevrim: return "Çevrimi kaydet"
        case .rutin: return "Ödendi olarak kaydet"
        }
    }

    private func hazirla() {
        guard !hazir else { return }
        hazir = true
        switch kip {
        case .harcama(let b):
            if let b { g.kapsam = "musteri"; musteri = b }
            g.kategori = kategoriler.first ?? ""
        case .cevrim:
            g.tur = "cevrim"; g.kategori = "Döviz çevrimi"; g.paraBirimi = "EUR"; g.hedefParaBirimi = "TRY"
        case .rutin(let v):
            g.kategori = v.rutin.kategori; g.paraBirimi = v.rutin.paraBirimi; g.yontem = v.rutin.yontem
            g.rutinId = v.rutin.id; g.rutinVade = v.vade
            if let t = v.rutin.tutar { tutar = OdemeKurali.sayiYazi(t).replacingOccurrences(of: ".", with: ",") }
        }
    }

    // MARK: Alanlar

    private var harcamaAlanlari: some View {
        VStack(alignment: .leading, spacing: 14) {
            if basvuruSabit == nil {
                Picker("Tür", selection: $g.kapsam) {
                    Text("Genel gider").tag("genel")
                    Text("Müşteri için").tag("musteri")
                }
                .pickerStyle(.segmented)
                .onChange(of: g.kapsam) { _, _ in g.kategori = kategoriler.first ?? "" }
            }
            if g.kapsam == "musteri" { musteriAlani }
            Alan(etiket: "Kategori") {
                Picker("Kategori", selection: $g.kategori) {
                    ForEach(kategoriler, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Tema.lacivert)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kutu()
            }
            tutarAlani("Tutar", metin: $tutar, para: $g.paraBirimi)
        }
        .kart()
    }

    @ViewBuilder
    private var musteriAlani: some View {
        if let m = musteri {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.adSoyad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                    Text(m.takipKodu).font(.caption.monospacedDigit()).foregroundStyle(Tema.govde)
                }
                Spacer()
                if basvuruSabit == nil {
                    Button("Değiştir") { musteri = nil }.buttonStyle(KucukDugme())
                }
            }
            .kutu()
        } else if !ekip.yapabilir("app.view") {
            Text("Müşteriyi bulmak için başvuruları görme izni gerekir; harcamayı başvuru ekranından girin.")
                .font(.caption).foregroundStyle(Tema.uyari)
        } else {
            Alan(etiket: "Müşteri") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Ad, soyad ya da takip kodu", text: $musteriArama)
                        .autocorrectionDisabled()
                        .kutu()
                    let bulunan = BasvuruListesi.suz(ekipVerisi.basvurular.satirlar, musteriArama)
                    if !musteriArama.trimmingCharacters(in: .whitespaces).isEmpty {
                        ForEach(Array(bulunan.prefix(6))) { b in
                            Button {
                                musteri = b
                                musteriArama = ""
                            } label: {
                                HStack {
                                    Text(b.adSoyad).font(.subheadline).foregroundStyle(Tema.lacivert)
                                    Spacer()
                                    Text(b.takipKodu).font(.caption.monospacedDigit()).foregroundStyle(Tema.silik)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                        if bulunan.isEmpty {
                            Text("Son başvurularda bulunamadı; harcamayı başvurunun ekranından girin.")
                                .font(.caption).foregroundStyle(Tema.govde)
                        }
                    }
                }
            }
            .task {
                if ekipVerisi.basvurular.satirlar.isEmpty { await ekipVerisi.basvurular.yukle(ekip, suzgec: .hepsi) }
            }
        }
    }

    private var cevrimAlanlari: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Döviz bozdurulunca ya da alınınca girin: verilen tutar o para biriminden düşer, büronun verdiği tutar öteki para birimine eklenir.")
                .font(.caption).foregroundStyle(Tema.govde)
            tutarAlani("Verilen tutar", metin: $tutar, para: $g.paraBirimi)
            tutarAlani("Çevrim tutarı (alınan)", metin: $hedefTutar, para: $g.hedefParaBirimi)
            let kur = KasaKurali.cevrimKuru(tutar: OdemeKurali.tutarOku(tutar), paraBirimi: g.paraBirimi,
                                            hedefTutar: OdemeKurali.tutarOku(hedefTutar), hedefParaBirimi: g.hedefParaBirimi)
            if !kur.isEmpty {
                Text("Büronun kuru: \(kur) (yalnız bilgi; tutarlar çevrilmez).").font(.caption).foregroundStyle(Tema.mavi)
            }
            Alan(etiket: "Döviz bürosu") {
                HStack(spacing: 8) {
                    TextField("Ör. Kızılay Döviz", text: $g.buro).kutu()
                    if !ekip.kasaAyari.dovizBurolari.isEmpty {
                        Menu {
                            ForEach(ekip.kasaAyari.dovizBurolari, id: \.self) { b in Button(b) { g.buro = b } }
                        } label: {
                            Image(systemName: "list.bullet").padding(10).background(Tema.soluk, in: Circle())
                        }
                        .accessibilityLabel("Kayıtlı bürolar")
                    }
                }
            }
        }
        .kart()
    }

    private func rutinAlanlari(_ v: RutinOdeme.Vade) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(v.rutin.ad).font(.headline).foregroundStyle(Tema.lacivert)
                Text("\(Tr.uzunTarih(v.vade)) vadesi · \(v.rutin.kategori)").font(.caption).foregroundStyle(Tema.govde)
            }
            tutarAlani("Tutar", metin: $tutar, para: $g.paraBirimi)
        }
        .kart()
    }

    private var ortakAlanlar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Alan(etiket: "Yöntem") {
                Picker("Yöntem", selection: $g.yontem) {
                    ForEach(0..<KasaKurali.yontemler.count, id: \.self) { i in
                        Text(KasaKurali.yontemler[i].ad).tag(KasaKurali.yontemler[i].id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Tema.lacivert)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kutu()
            }
            DatePicker(kipRutin ? "Ödeme tarihi" : "Tarih", selection: $tarih, in: ...Date(), displayedComponents: .date)
                .environment(\.locale, Tr.yerel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tema.lacivert)
            Alan(etiket: "Açıklama") {
                TextField(kipRutin ? "Ör. fatura no" : "İsteğe bağlı", text: $g.aciklama, axis: .vertical)
                    .lineLimit(1...3)
                    .kutu()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(fisEtiketi).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                DosyaSecDugmeleri(secilen: $fis)
            }
        }
        .kart()
    }

    private var kipRutin: Bool { if case .rutin = kip { return true }; return false }
    private var fisEtiketi: String {
        switch kip {
        case .harcama: return "Fiş / makbuz (isteğe bağlı)"
        case .cevrim: return "Büro fişi (isteğe bağlı)"
        case .rutin: return "Fatura / dekont (isteğe bağlı)"
        }
    }

    private func tutarAlani(_ etiket: String, metin: Binding<String>, para: Binding<String>) -> some View {
        Alan(etiket: etiket) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("0", text: metin).keyboardType(.decimalPad).kutu()
                Picker("Para birimi", selection: para) {
                    ForEach(KasaKurali.paraBirimleri, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: Kaydet

    private func gonder() async {
        var x = g
        x.tutar = OdemeKurali.tutarOku(tutar).map { KasaKurali.yuvarla($0) }
        x.hedefTutar = OdemeKurali.tutarOku(hedefTutar).map { KasaKurali.yuvarla($0) }
        x.tarih = Tr.isoGun(tarih, takvim: Tr.takvim)
        x.aciklama = x.aciklama.trimmingCharacters(in: .whitespacesAndNewlines)
        var kimlik: String?
        switch kip {
        case .harcama:
            if x.kapsam == "musteri", let m = musteri {
                x.appId = m.kimlik; x.takipKodu = m.takipKodu; x.musteriAd = String(m.adSoyad.prefix(160))
            }
            hatalar = KasaKurali.giderHatalari(x, bugun: bugun, kategoriler: kategoriler)
        case .cevrim:
            hatalar = KasaKurali.cevrimHatalari(x, bugun: bugun)
        case .rutin(let v):
            x.aciklama = [v.rutin.ad, "\(Tr.uzunTarih(v.vade)) vadesi", x.aciklama].filter { !$0.isEmpty }.joined(separator: " · ")
            kimlik = RutinOdeme.kasaId(v.rutin.id, v.vade)
            // Rutinin kategorisi sonradan listeden kaldırılmış olabilir; listeyle denetlenmez.
            hatalar = KasaKurali.giderHatalari(x, bugun: bugun)
        }
        if let f = fis {
            let s = Dosya.sorun(mime: f.mime, boyut: f.bayt.count)
            if !s.isEmpty { hatalar.append(s) }
        }
        guard hatalar.isEmpty else { return }
        kaydediliyor = true
        let h = await kaydet(x, fis, kimlik)
        kaydediliyor = false
        if let h { hatalar = [h] } else { kapat() }
    }
}

// MARK: - Rutin ödemeler

struct RutinOdemelerEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @State private var duzenlenen: RutinOdeme?
    @State private var silinecek: RutinOdeme?
    @State private var hata: String?

    private var kasa: KasaVerisi { ekipVerisi.kasa }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fatura, kira, haftalık temizlik ücreti gibi tekrarlayan ödemeler. Günü gelince Kasa'daki \"Ödenecek rutin ödemeler\"de ve gün sonu raporunda görünür; ödendiğinde tek dokunuşla harcama olarak kaydedilir.")
                    .font(.caption).foregroundStyle(Tema.govde)
                if let h = hata ?? kasa.rutinHata { AlanHatasi(metin: h) }
                if kasa.rutinler.isEmpty {
                    Text("Henüz rutin ödeme yok.").font(.subheadline).foregroundStyle(Tema.govde).kart()
                }
                ForEach(Array(kasa.rutinler.enumerated()), id: \.element.id) { i, r in
                    satir(r).belirme(min(i, 6))
                }
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("Rutin ödemeler")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if ekip.yapabilir("kasa.rutin") {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { duzenlenen = RutinOdeme() } label: { Image(systemName: "plus") }.accessibilityLabel("Rutin ödeme ekle")
                }
            }
        }
        .task { await kasa.rutinleriYukle(ekip, zorla: false) }
        .refreshable { await kasa.rutinleriYukle(ekip) }
        .sheet(item: Binding(get: { duzenlenen.map { RutinKimligi(r: $0) } }, set: { duzenlenen = $0?.r })) { k in
            RutinFormu(rutin: k.r) { r in await kasa.rutinKaydet(r, ekip: ekip) }
        }
        .confirmationDialog("\"\(silinecek?.ad ?? "")\" rutin ödemesi silinsin mi? Daha önce kaydedilen ödemeleri silinmez.",
                            isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }), titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                guard let r = silinecek else { return }
                Task { hata = await kasa.rutinSil(r, ekip: ekip) }
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    /// `.sheet(item:)` için: yeni rutinin kimliği boş olduğundan ayrı bir kimlik.
    struct RutinKimligi: Identifiable {
        let r: RutinOdeme
        var id: String { r.id.isEmpty ? "yeni" : r.id }
    }

    private func satir(_ r: RutinOdeme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(r.ad).font(.headline).foregroundStyle(r.aktif ? Tema.lacivert : Tema.silik)
                Spacer()
                if !r.aktif { Etiket(metin: "Durduruldu", renk: Tema.silik) }
                if r.otomatik { Etiket(metin: "Otomatik kayıt", renk: Tema.turkuaz) }
            }
            Text([r.yazi, r.tutar.map { "≈ " + KasaKurali.paraYazi([r.paraBirimi: $0]) } ?? "", r.kategori]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(Tema.govde)
            Text("Başlangıç \(Tr.uzunTarih(r.baslangic))\(r.bitis.isEmpty ? "" : " · bitiş \(Tr.uzunTarih(r.bitis))")\(r.not.isEmpty ? " · \(r.not)" : "")")
                .font(.caption2).foregroundStyle(Tema.silik)
            if ekip.yapabilir("kasa.rutin") {
                HStack(spacing: 8) {
                    Button("Düzenle") { duzenlenen = r }.buttonStyle(KucukDugme())
                    Button(r.aktif ? "Durdur" : "Yeniden başlat") {
                        var y = r
                        y.aktif.toggle()
                        Task { hata = await kasa.rutinKaydet(y, kaydaYaz: false, ekip: ekip) }
                    }
                    .buttonStyle(KucukDugme())
                    Spacer()
                    Button("Sil") { silinecek = r }.buttonStyle(KucukDugme(renk: Tema.olumsuz))
                }
            }
        }
        .kart()
    }
}

struct RutinFormu: View {
    let rutin: RutinOdeme
    let kaydet: (RutinOdeme) async -> String?
    @Environment(EkipOturumu.self) private var ekip
    @Environment(\.dismiss) private var kapat
    @State private var r = RutinOdeme()
    @State private var tutar = ""
    @State private var baslangic = Date()
    @State private var bitisVar = false
    @State private var bitis = Date()
    @State private var hatalar: [String] = []
    @State private var kaydediliyor = false
    @State private var hazir = false

    private var kategoriler: [String] {
        var l = ekip.kasaAyari.genelGiderler
        if !rutin.kategori.isEmpty && !l.contains(rutin.kategori) { l.insert(rutin.kategori, at: 0) }
        return l
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        Alan(etiket: "Ad") { TextField("Ör. Elektrik faturası, Ofis kirası", text: $r.ad).kutu() }
                        Alan(etiket: "Kategori") {
                            Picker("Kategori", selection: $r.kategori) { ForEach(kategoriler, id: \.self) { Text($0).tag($0) } }
                                .pickerStyle(.menu).tint(Tema.lacivert)
                                .frame(maxWidth: .infinity, alignment: .leading).kutu()
                        }
                        Alan(etiket: "Tahmini tutar") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Tutar değişkense boş bırakın", text: $tutar).keyboardType(.decimalPad).kutu()
                                Picker("Para birimi", selection: $r.paraBirimi) {
                                    ForEach(KasaKurali.paraBirimleri, id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        Alan(etiket: "Yöntem") {
                            Picker("Yöntem", selection: $r.yontem) {
                                ForEach(0..<KasaKurali.yontemler.count, id: \.self) { i in
                                    Text(KasaKurali.yontemler[i].ad).tag(KasaKurali.yontemler[i].id)
                                }
                            }
                            .pickerStyle(.menu).tint(Tema.lacivert)
                            .frame(maxWidth: .infinity, alignment: .leading).kutu()
                        }
                    }
                    .kart()
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Sıklık", selection: $r.siklik) {
                            ForEach(0..<RutinOdeme.sikliklar.count, id: \.self) { i in
                                Text(RutinOdeme.sikliklar[i].ad).tag(RutinOdeme.sikliklar[i].id)
                            }
                        }
                        .pickerStyle(.segmented)
                        if r.siklik == "haftalik" {
                            Alan(etiket: "Haftanın günü") {
                                Picker("Haftanın günü", selection: $r.gun) {
                                    ForEach(1...7, id: \.self) { g in Text(RutinOdeme.haftaGunleri[g - 1]).tag(g) }
                                }
                                .pickerStyle(.menu).tint(Tema.lacivert)
                                .frame(maxWidth: .infinity, alignment: .leading).kutu()
                            }
                        } else if r.siklik == "aylik" {
                            Stepper(value: $r.gun, in: 1...31) {
                                Text("Ayın \(r.gun). günü").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                            }
                            Text("Ay kısaysa ayın son günü sayılır.").font(.caption2).foregroundStyle(Tema.silik)
                        } else {
                            Text("Yıllık ödeme her yıl başlangıç tarihinin gün ve ayında görünür.").font(.caption).foregroundStyle(Tema.govde)
                        }
                        DatePicker("Başlangıç", selection: $baslangic, displayedComponents: .date)
                            .environment(\.locale, Tr.yerel)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                        IsaretKutusu(secili: $bitisVar, metin: "Bitiş tarihi var")
                        if bitisVar {
                            DatePicker("Bitiş", selection: $bitis, in: baslangic..., displayedComponents: .date)
                                .environment(\.locale, Tr.yerel)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                        }
                        Alan(etiket: "Not") { TextField("Ör. abone no, IBAN", text: $r.not).kutu() }
                        IsaretKutusu(secili: $r.otomatik,
                                     metin: "Günü gelince otomatik kaydet (tutar sabitse: kira, aidat, haftalık ücret). Gece 03:00 işi gider olarak yazar; tutar değişen faturalarda kapalı bırakın.")
                    }
                    .kart()
                    ForEach(hatalar, id: \.self) { AlanHatasi(metin: $0) }
                    Button {
                        Task { await gonder() }
                    } label: {
                        if kaydediliyor {
                            HStack(spacing: 8) { ProgressView().tint(.white); Text("Kaydediliyor…") }
                        } else {
                            Text(rutin.id.isEmpty ? "Rutin ödemeyi ekle" : "Değişiklikleri kaydet")
                        }
                    }
                    .buttonStyle(AnaDugme())
                    .disabled(kaydediliyor)
                }
                .padding(Tema.bosluk)
            }
            .formKlavyesi()
            .ekranZemini()
            .navigationTitle(rutin.id.isEmpty ? "Rutin ödeme ekle" : "Rutin ödemeyi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
        }
        .onAppear(perform: hazirla)
    }

    private func hazirla() {
        guard !hazir else { return }
        hazir = true
        r = rutin
        if r.kategori.isEmpty { r.kategori = kategoriler.first ?? "" }
        if let t = r.tutar { tutar = OdemeKurali.sayiYazi(t).replacingOccurrences(of: ".", with: ",") }
        if let d = Tr.tarih(r.baslangic) { baslangic = d }
        if let d = Tr.tarih(r.bitis) { bitisVar = true; bitis = d }
    }

    private func gonder() async {
        var x = r
        x.tutar = OdemeKurali.tutarOku(tutar).map { KasaKurali.yuvarla($0) }
        x.baslangic = Tr.isoGun(baslangic, takvim: Tr.takvim)
        x.bitis = bitisVar ? Tr.isoGun(bitis, takvim: Tr.takvim) : ""
        if x.siklik == "yillik" { x.gun = Int(x.baslangic.suffix(2)) ?? 1 }
        if x.siklik == "haftalik" && !(1...7).contains(x.gun) { x.gun = 1 }
        // Otomatik kayıt yalnız açıldığı günden sonraki vadelere yazar (geçmişe toplu kayıt olmasın).
        x.otomatikBas = x.otomatik ? (rutin.otomatik && !rutin.otomatikBas.isEmpty ? rutin.otomatikBas : Tr.bugun()) : ""
        x.ad = x.ad.trimmingCharacters(in: .whitespacesAndNewlines)
        x.not = x.not.trimmingCharacters(in: .whitespacesAndNewlines)
        hatalar = x.hatalar
        guard hatalar.isEmpty else { return }
        kaydediliyor = true
        let h = await kaydet(x)
        kaydediliyor = false
        if let h { hatalar = [h] } else { kapat() }
    }
}

// MARK: - Başvuru ayrıntısı: müşteri için yapılan harcamalar

struct MusteriGiderleriKarti: View {
    let veri: BasvuruDetayVerisi
    let b: Basvuru
    let baglam: EkBaglami
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @State private var form: KasaKaydiSayfasi.Kip?
    @State private var onizleme: URL?
    @State private var aciliyor: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Müşteri için yapılan harcamalar").font(.headline).foregroundStyle(Tema.lacivert)
                Spacer()
                if ekip.yapabilir("kasa.gider") {
                    Button { form = .harcama(b) } label: { Label("Ekle", systemImage: "plus") }.buttonStyle(KucukDugme())
                }
            }
            if ekip.yapabilir("kasa.view") || ekip.yapabilir("app.payment") {
                if veri.giderler.isEmpty {
                    Text("Henüz harcama yok.").font(.caption).foregroundStyle(Tema.govde)
                } else {
                    Text("Toplam: \(KasaKurali.paraYazi(KasaOzeti(veri.giderler).gider))")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Tema.lacivert)
                    ForEach(veri.giderler) { g in
                        KasaHareketSatiri(x: g, aciliyor: aciliyor == g.id, fisAc: { fisAc(g) }, iptal: nil)
                        if g.id != veri.giderler.last?.id { Divider() }
                    }
                }
            }
            if ekip.yapabilir("kasa.gider") {
                Text("Fotokopi, fotoğraf, kargo, harç gibi bu müşteri için yapılan harcamalar. Kategoriler Ayarlar → Kasa ve raporlar'dan değişir.")
                    .font(.caption2).foregroundStyle(Tema.silik)
            }
        }
        .kart()
        .quickLookPreview($onizleme)
        .sheet(item: $form) { k in
            KasaKaydiSayfasi(kip: k) { g, fis, _ in
                let h = await veri.giderEkle(g, fis: fis, ekip: ekip)
                if h == nil {
                    ekipVerisi.kasa.eskit()
                    baglam.bildir(nil, "Harcama kaydedildi.")
                }
                return h
            }
        }
    }

    private func fisAc(_ x: KasaHareketi) {
        guard aciliyor == nil else { return }
        aciliyor = x.id
        Task {
            do { onizleme = try await KasaVerisi.fisDosyasi(x, ekip: ekip) } catch { baglam.bildir("Fiş açılamadı.", "") }
            aciliyor = nil
        }
    }
}
