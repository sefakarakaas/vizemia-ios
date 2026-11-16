import SwiftUI
import VizeMiaCekirdek

/// "Sizi Arayalım" formu (sitedeki /basvuru): ad soyad ve iletişim → seyahat →
/// arama saati → isteğe bağlı pasaport bilgileri → gönder.
struct BasvuruEkrani: View {
    @Environment(IcerikDeposu.self) private var icerik
    @Environment(Gezinti.self) private var gezinti

    /// Takvimden seçilen tarihler. Boş bırakılabildikleri için "var mı" ile birlikte tutulur.
    private struct Tarihler: Equatable {
        var seyahatVar = false
        var seyahat = Date()
        var dogumVar = false
        var dogum = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
        var gecerlilikVar = false
        var gecerlilik = Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date()
    }

    @State private var form = BasvuruFormu()
    @State private var arama = AramaSecimi(mod: .saat)
    @State private var tarihler = Tarihler()
    @State private var acikti = false
    @State private var pasaportAcik = false
    @State private var ulkeSeciliyor = false
    @State private var hata: FormHatasi?
    @State private var gonderiliyor = false
    @State private var gonderildi: String?
    @State private var sonGonderim: Date?
    @State private var hazir = false

    var body: some View {
        ScrollViewReader { kaydir in
            ScrollView {
                VStack(spacing: 20) {
                    if let ne = gonderildi {
                        tamam(ne)
                    } else {
                        baslik
                        kisi
                        seyahat
                        aramaBolumu
                        pasaportBolumu
                        onaylar
                        if let h = hata { HataMetni(metin: h.mesaj).id("hata") }
                        Button {
                            Task { await gonder(kaydir) }
                        } label: {
                            if gonderiliyor {
                                HStack(spacing: 8) { ProgressView().tint(.white); Text("Gönderiliyor…") }
                            } else {
                                Text("Beni arayın")
                            }
                        }
                        .buttonStyle(AnaDugme())
                        .disabled(gonderiliyor)
                        Text("Pasaport bilgileriniz yalnız siz yazarsanız gönderilir; fotoğraf istenmez.")
                            .font(.caption).foregroundStyle(Tema.govde)
                    }
                }
                .padding(Tema.bosluk)
            }
            .formKlavyesi()
        }
        .ekranZemini()
        .navigationTitle("Başvur")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $ulkeSeciliyor) {
            UlkeSecici(kitalar: icerik.akis.kitalar, secili: form.ulke) { u in
                ulkeSec(u)
            }
        }
        .onAppear {
            // Sekmeye her girişte yeniden bakılır: uygulama açık kalmışken mesai
            // bittiyse "hemen arayın" artık tutamayacağımız bir söz olur.
            let acik = icerik.mesai.acikMi()
            if !hazir {
                hazir = true
                arama = AramaSecimi(mod: acik ? .hemen : .saat, gun: icerik.mesai.uygunGunler().first ?? "")
            } else if !acik && arama.mod == .hemen {
                arama.mod = .saat
            }
            acikti = acik
            ulkeyiUygula()
        }
        .onChange(of: gezinti.basvuruUlke) { _, _ in ulkeyiUygula() }
        // Müşteri bir şeyi düzeltince eski hata satırı kalmasın.
        .onChange(of: form) { _, _ in hata = nil }
        .onChange(of: arama) { _, _ in hata = nil }
        .onChange(of: tarihler) { _, _ in hata = nil }
    }

    // MARK: - Bölümler

    /// Hata bu alandaysa metni; alanın hemen altında gösterilir (ekran oraya kayar).
    private func alanHatasi(_ alan: BasvuruAlani) -> String? {
        hata?.alan == alan ? hata?.mesaj : nil
    }

    /// Ekran okuyucu için: seçim kutusunun ne olduğu ve seçili değer.
    private var ulkeEtiketi: String {
        let ad = icerik.akis.ulke(form.ulke)?.ad ?? "seçilmedi"
        return "Gidilecek ülke: " + ad
    }

    private var vizeEtiketi: String {
        let ad = VizeTuru.hepsi.first(where: { $0.id == form.vizeTuru })?.ad ?? "seçilmedi"
        return "Vize türü: " + ad
    }

    private var baslik: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ücretsiz ön değerlendirme").ustBaslik()
            Text("Sizi Arayalım").bolumBasligi()
            Text("Bilgilerinizi bırakın, uygun saatinizde sizi arayalım.").govdeMetni()
        }
    }

    private var kisi: some View {
        Bolum(baslik: "1. Siz") {
            Alan(etiket: "Adınız *", hata: alanHatasi(.ad)) {
                TextField("", text: $form.ad)
                    .accessibilityIdentifier("basvuru-ad")
                    .accessibilityLabel("Adınız")
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .kutu()
                    .onChange(of: form.ad) { _, yeni in
                        let t = Harf.adSoyad(yeni, ulke: form.ulke)
                        if t != yeni { form.ad = t }
                    }
            }
            .id(BasvuruAlani.ad)
            Alan(etiket: "Soyadınız *", yardim: "Pasaportunuzda yazdığı gibi, Latin harfleriyle.", hata: alanHatasi(.soyad)) {
                TextField("", text: $form.soyad)
                    .accessibilityIdentifier("basvuru-soyad")
                    .accessibilityLabel("Soyadınız")
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .kutu()
                    .onChange(of: form.soyad) { _, yeni in
                        let t = Harf.adSoyad(yeni, ulke: form.ulke)
                        if t != yeni { form.soyad = t }
                    }
            }
            .id(BasvuruAlani.soyad)
            Alan(etiket: "Telefon *", hata: alanHatasi(.telefon)) {
                TextField("05xx xxx xx xx", text: $form.telefon)
                    .accessibilityIdentifier("basvuru-telefon")
                    .accessibilityLabel("Telefon")
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .kutu()
            }
            .id(BasvuruAlani.telefon)
            Alan(etiket: "E-posta", istegeBagli: true, hata: alanHatasi(.eposta)) {
                TextField("", text: $form.eposta)
                    .accessibilityIdentifier("basvuru-eposta")
                    .accessibilityLabel("E-posta")
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .kutu()
            }
            .id(BasvuruAlani.eposta)
        }
    }

    private var seyahat: some View {
        Bolum(baslik: "2. Seyahatiniz") {
            Alan(etiket: "Gidilecek ülke *", hata: alanHatasi(.ulke)) {
                Button {
                    ulkeSeciliyor = true
                } label: {
                    HStack {
                        if let u = icerik.akis.ulke(form.ulke) {
                            Text("\(u.bayrak) \(u.ad)").foregroundStyle(Tema.lacivert)
                        } else {
                            Text("Seçin").foregroundStyle(Tema.silik)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(Tema.silik)
                    }
                    .kutu()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("basvuru-ulke")
                .accessibilityLabel(Text(ulkeEtiketi))
            }
            .id(BasvuruAlani.ulke)

            Alan(etiket: "Vize türü *", hata: alanHatasi(.vizeTuru)) {
                Menu {
                    ForEach(VizeTuru.hepsi) { t in
                        Button(t.ad) { form.vizeTuru = t.id }
                    }
                } label: {
                    HStack {
                        if let t = VizeTuru.hepsi.first(where: { $0.id == form.vizeTuru }) {
                            Text(t.ad).foregroundStyle(Tema.lacivert)
                        } else {
                            Text("Seçin").foregroundStyle(Tema.silik)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(Tema.silik)
                    }
                    .kutu()
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("basvuru-vize")
                .accessibilityLabel(Text(vizeEtiketi))
            }
            .id(BasvuruAlani.vizeTuru)

            Alan(etiket: "Tahmini seyahat tarihi", yardim: "Kesin olmasa da olur.", hata: alanHatasi(.seyahat)) {
                TarihSatiri(secili: $tarihler.seyahatVar, tarih: $tarihler.seyahat, aralik: Date()...Date.distantFuture, bos: "Tarih seçin")
            }
            .id(BasvuruAlani.seyahat)
        }
    }

    private var aramaBolumu: some View {
        Bolum(baslik: "3. Sizi ne zaman arayalım?") {
            if acikti {
                HStack(spacing: 10) {
                    ModKutusu(baslik: "Hemen arayın", alt: "Şu an açığız, sırası gelince sizi arayalım", secili: arama.mod == .hemen) {
                        arama.mod = .hemen
                    }
                    ModKutusu(baslik: "Saat seçeyim", alt: "Size uygun aralıkları işaretleyin", secili: arama.mod == .saat) {
                        arama.mod = .saat
                    }
                }
            } else {
                Text("Şu an kapalıyız (\(icerik.mesai.metin())). \(icerik.mesai.sonrakiAcilis().metin) açılıyoruz — size uygun aralıkları seçin, ilk fırsatta arayalım.")
                    .font(.footnote)
                    .foregroundStyle(Tema.uyari)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tema.uyariZemin, in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                if arama.mod == .saat {
                    SaatSecici(mesai: icerik.mesai, secim: $arama)
                }
                if let h = alanHatasi(.arama) { AlanHatasi(metin: h) }
            }
            .id(BasvuruAlani.arama)

            VStack(alignment: .leading, spacing: 10) {
                Text("Size nasıl haber verelim? *").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                Text("Randevunuz alındığında ve randevudan önce evraklarınız için hatırlatma yaparken bu yollardan yazacağız.")
                    .font(.caption).foregroundStyle(Tema.govde)
                IsaretKutusu(secili: $form.kanallar.wa, metin: "WhatsApp — en hızlısı")
                IsaretKutusu(secili: $form.kanallar.sms, metin: "SMS")
                // E-posta kutusu adres yazılınca açılır: adresi olmayan bir yolu seçili göstermek "seçtim ama gelmedi" demek.
                IsaretKutusu(secili: $form.kanallar.email, metin: "E-posta", etkin: Harf.epostaGecerli(Harf.eposta(form.eposta)))
                if let h = alanHatasi(.kanal) { AlanHatasi(metin: h) }
            }
            .id(BasvuruAlani.kanal)

            Alan(etiket: "Eklemek istediğiniz bir şey") {
                TextField("Seyahat amacınız, daha önce aldığınız vizeler…", text: $form.mesaj, axis: .vertical)
                    .lineLimit(3...6)
                    .kutu()
            }
        }
    }

    private var pasaportBolumu: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { pasaportAcik.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pasaport bilgilerimi şimdi gireyim").font(.headline).foregroundStyle(Tema.lacivert)
                        Text("İsteğe bağlı. Boş bırakırsanız sonra alırız.").font(.caption).foregroundStyle(Tema.govde)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Tema.turkuaz)
                        .rotationEffect(.degrees(pasaportAcik ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if pasaportAcik {
                Alan(etiket: "Pasaport numarası", hata: alanHatasi(.pasaportNo)) {
                    TextField("U12345678", text: $form.pasaportNo)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .font(.body.monospaced())
                        .kutu()
                        .onChange(of: form.pasaportNo) { _, yeni in
                            let t = String(Harf.harfRakam(yeni).prefix(9))
                            if t != yeni { form.pasaportNo = t }
                        }
                }
                .id(BasvuruAlani.pasaportNo)
                Alan(etiket: "T.C. kimlik numarası", hata: alanHatasi(.tckn)) {
                    TextField("", text: $form.tckn)
                        .accessibilityLabel("T.C. kimlik numarası")
                        .keyboardType(.numberPad)
                        .font(.body.monospacedDigit())
                        .kutu()
                        .onChange(of: form.tckn) { _, yeni in
                            let t = String(Harf.rakam(yeni).prefix(11))
                            if t != yeni { form.tckn = t }
                        }
                }
                .id(BasvuruAlani.tckn)
                Alan(etiket: "Doğum tarihi", hata: alanHatasi(.dogum)) {
                    TarihSatiri(secili: $tarihler.dogumVar, tarih: $tarihler.dogum, aralik: Date.distantPast...Date(), bos: "Tarih seçin")
                }
                .id(BasvuruAlani.dogum)
                Alan(etiket: "Pasaport geçerlilik tarihi", hata: alanHatasi(.gecerlilik)) {
                    TarihSatiri(secili: $tarihler.gecerlilikVar, tarih: $tarihler.gecerlilik, aralik: Date()...Date.distantFuture, bos: "Tarih seçin")
                }
                .id(BasvuruAlani.gecerlilik)
            }
        }
        .kart()
    }

    private var onaylar: some View {
        VStack(spacing: 14) {
            IsaretKutusu(secili: $form.kvkk, metin: "Yukarıdaki bilgilerimin vize başvurumun hazırlanması ve benimle iletişim kurulması amacıyla işlenmesini kabul ediyorum. *")
                .id(BasvuruAlani.kvkk)
            IsaretKutusu(secili: $form.kampanya, metin: "VizeMia'nın kampanya, indirim ve duyurularını e-posta ile almak istiyorum. Bu izni her e-postadaki bağlantıdan istediğim zaman geri alabilirim. (İsteğe bağlı)")
            Button {
                gezinti.ac(link: "/gizlilik", sayfaYollari: icerik.sayfaYollari)
            } label: {
                Text("Gizlilik ve KVKK aydınlatma metni").font(.footnote.weight(.semibold)).foregroundStyle(Tema.mavi).underline()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kart()
    }

    private func tamam(_ ne: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Tema.olumlu)
            Text("Talebiniz bize ulaştı.").font(.title2.weight(.heavy)).foregroundStyle(Tema.olumluKoyu)
            Text("\(ne).").font(.body).foregroundStyle(Tema.olumluKoyu)
            Text("Görüşmede size takip kodunuzu vereceğiz; o kodla Takip sekmesinden durumu izleyebilirsiniz.")
                .font(.subheadline).foregroundStyle(Tema.govde)
            Button("Başvuru takibine git") { gezinti.ac(.takip(kod: "")) }
                .buttonStyle(AnaDugme())
                .padding(.top, 6)
            Button("Yeni talep oluştur") {
                let ulke = form.ulke, ad = form.ulkeAdi
                form = BasvuruFormu()
                form.ulke = ulke; form.ulkeAdi = ad
                tarihler = Tarihler()
                pasaportAcik = false
                arama = AramaSecimi(mod: acikti ? .hemen : .saat, gun: icerik.mesai.uygunGunler().first ?? "")
                gonderildi = nil
            }
            .buttonStyle(IkincilDugme())
        }
        .padding(Tema.bosluk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.olumlu.opacity(0.12), in: RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
    }

    // MARK: - İşlemler

    private func ulkeSec(_ u: Ulke) {
        form.ulke = u.slug
        form.ulkeAdi = u.ad
        // Ülke değişince ad/soyad yeni ülkenin harf kuralına göre yeniden temizlenir
        // (Almanya'dan başka ülkeye geçilirse Ö → O, Ü → U).
        form.ad = Harf.adSoyad(form.ad, ulke: u.slug)
        form.soyad = Harf.adSoyad(form.soyad, ulke: u.slug)
    }

    /// Rehber sayfasından ya da ana sayfadan gelen ülke seçili başlar.
    private func ulkeyiUygula() {
        let istenen = gezinti.basvuruUlke
        guard !istenen.isEmpty else { return }
        gezinti.basvuruUlke = ""
        if let u = icerik.akis.ulke(istenen) { ulkeSec(u) }
    }

    private func gonder(_ kaydir: ScrollViewProxy) async {
        hata = nil
        // Gönderilecek kopya: takvimden seçilen tarihler eklenir, kapalı pasaport
        // bölümü boş gider. Ekrandaki form değişmez (değişseydi hata satırı silinirdi).
        var f = form
        f.seyahat = tarihler.seyahatVar ? Tr.isoGun(tarihler.seyahat) : ""
        f.dogum = pasaportAcik && tarihler.dogumVar ? Tr.isoGun(tarihler.dogum) : ""
        f.gecerlilik = pasaportAcik && tarihler.gecerlilikVar ? Tr.isoGun(tarihler.gecerlilik) : ""
        if !pasaportAcik { f.pasaportNo = ""; f.tckn = "" }

        if let h = f.hata(arama: arama) {
            if h.alan == .pasaportNo || h.alan == .tckn || h.alan == .dogum || h.alan == .gecerlilik { pasaportAcik = true }
            hata = h
            withAnimation { kaydir.scrollTo(h.alan ?? .ad, anchor: .center) }
            return
        }
        if let son = sonGonderim, Date().timeIntervalSince(son) < 60 {
            hata = FormHatasi(mesaj: "Az önce bir başvuru gönderdiniz. Lütfen bir dakika bekleyin.", alan: nil)
            return
        }
        gonderiliyor = true
        defer { gonderiliyor = false }
        do {
            let kimlik = try await FirestoreIstemci().ekle(koleksiyon: "applicationRequests", alanlar: f.alanlar(arama: arama))
            icerik.bildir(tur: "basvuru", kimlik: kimlik)
            sonGonderim = Date()
            withAnimation { gonderildi = arama.metin }
        } catch {
            hata = FormHatasi(mesaj: "Talebiniz gönderilemedi. Lütfen daha sonra tekrar deneyin ya da bize ulaşın.", alan: nil)
            withAnimation { kaydir.scrollTo("hata", anchor: .center) }
        }
    }
}

/// Başlıklı form bölümü.
struct Bolum<Govde: View>: View {
    var baslik: String
    @ViewBuilder var govde: () -> Govde

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(baslik).font(.headline).foregroundStyle(Tema.lacivert)
            govde()
        }
        .kart()
    }
}

/// "Hemen arayın" / "Saat seçeyim" kutusu.
struct ModKutusu: View {
    var baslik: String
    var alt: String
    var secili: Bool
    var islem: () -> Void

    var body: some View {
        Button(action: islem) {
            VStack(alignment: .leading, spacing: 4) {
                Text(baslik).font(.subheadline.weight(.bold)).foregroundStyle(secili ? Color.white : Tema.lacivert)
                Text(alt).font(.caption).foregroundStyle(secili ? Color.white.opacity(0.85) : Tema.govde)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(secili ? Tema.lacivert : Tema.zemin, in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous).stroke(secili ? Tema.lacivert : Tema.soluk, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(secili ? .isSelected : [])
    }
}

/// İsteğe bağlı tarih: boşken "Tarih seçin", seçilince takvim ve "Temizle".
struct TarihSatiri: View {
    @Binding var secili: Bool
    @Binding var tarih: Date
    var aralik: ClosedRange<Date>
    var bos: String

    var body: some View {
        if secili {
            HStack {
                DatePicker("", selection: $tarih, in: aralik, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                Spacer()
                Button("Temizle") { secili = false }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Tema.mavi)
            }
        } else {
            Button {
                secili = true
            } label: {
                HStack {
                    Text(bos).foregroundStyle(Tema.silik)
                    Spacer()
                    Image(systemName: "calendar").foregroundStyle(Tema.silik)
                }
                .kutu()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Geri arama saati seçici: gün şeridi, altında üç grupta yarım saatlik
/// aralıklar. Grup başlığı o gruptaki bütün aralıkları birden işaretler.
struct SaatSecici: View {
    var mesai: Mesai
    @Binding var secim: AramaSecimi

    var body: some View {
        let gunler = mesai.uygunGunler()
        let bugun = Mesai.trSimdi().iso
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(gunler, id: \.self) { g in
                        let p = g.split(separator: "-").compactMap { Int($0) }
                        let seciliGun = secim.gun == g
                        Button {
                            // Gün değişince saat seçimi anlamını yitirir.
                            if secim.gun != g { secim.dilimler = [] }
                            secim.gun = g
                        } label: {
                            VStack(spacing: 2) {
                                Text(g == bugun ? "Bugün" : Mesai.gunKisa[Tr.gunNo(g)]).font(.caption.weight(.semibold))
                                Text(p.count == 3 ? "\(p[2])" : "").font(.title3.weight(.heavy))
                                Text(p.count == 3 ? Mesai.ayKisa[max(0, min(11, p[1] - 1))] : "").font(.caption2)
                            }
                            .foregroundStyle(seciliGun ? Color.white : Tema.lacivert)
                            .frame(width: 58, height: 70)
                            .background(seciliGun ? Tema.lacivert : Tema.zemin, in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous).stroke(seciliGun ? Tema.lacivert : Tema.soluk, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Mesai.gunMetni(g))
                        .accessibilityAddTraits(seciliGun ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }

            ForEach(Mesai.gruplar(mesai.dilimler(secim.gun))) { grup in
                let hepsi = grup.dilimler.allSatisfy { secim.dilimler.contains($0) }
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        if hepsi {
                            secim.dilimler.subtract(grup.dilimler)
                        } else {
                            secim.dilimler.formUnion(grup.dilimler)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: hepsi ? "checkmark.square.fill" : (grup.dilimler.contains(where: { secim.dilimler.contains($0) }) ? "minus.square.fill" : "square"))
                                .foregroundStyle(hepsi ? Tema.lacivert : Tema.silik)
                            Text(grup.ad).font(.subheadline.weight(.bold)).foregroundStyle(Tema.lacivert)
                            Text(grup.aralik).font(.caption).foregroundStyle(Tema.govde)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(grup.dilimler, id: \.self) { m in
                            let acik = secim.dilimler.contains(m)
                            Button("\(Mesai.hhmm(m))–\(Mesai.hhmm(m + 30))") {
                                if acik { secim.dilimler.remove(m) } else { secim.dilimler.insert(m) }
                            }
                            .buttonStyle(SecimKutusu(secili: acik))
                            .accessibilityAddTraits(acik ? .isSelected : [])
                        }
                    }
                }
            }

            (Text("Seçtiğiniz aralıklar: ").foregroundStyle(Tema.govde)
                + Text(Mesai.aralikOzeti(Array(secim.dilimler))).fontWeight(.bold).foregroundStyle(Tema.lacivert))
                .font(.footnote)
        }
        .onAppear {
            if secim.gun.isEmpty || !gunler.contains(secim.gun) {
                secim.gun = gunler.first ?? ""
                secim.dilimler = []
            }
        }
    }
}

/// Ülke seçimi: kıtalara göre gruplu, aranabilir liste.
struct UlkeSecici: View {
    var kitalar: [Kita]
    var secili: String
    var sec: (Ulke) -> Void
    @State private var arama = ""
    @Environment(\.dismiss) private var kapat

    var body: some View {
        NavigationStack {
            List {
                ForEach(kitalar) { kita in
                    let liste = suz(kita.ulkeler)
                    if !liste.isEmpty {
                        Section(kita.ad) {
                            ForEach(liste) { u in
                                Button {
                                    sec(u)
                                    kapat()
                                } label: {
                                    HStack {
                                        Text(u.bayrak)
                                        Text(u.ad).foregroundStyle(Tema.lacivert)
                                        Spacer()
                                        if u.slug == secili {
                                            Image(systemName: "checkmark").foregroundStyle(Tema.turkuaz)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $arama, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ülke ara")
            .navigationTitle("Gidilecek ülke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
            }
        }
    }

    private func suz(_ ulkeler: [Ulke]) -> [Ulke] {
        let q = arama.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return ulkeler }
        // Türkçe'ye duyarlı arama: "isvicre" yazan da "İsviçre"yi bulsun.
        let ara = Harf.latinBuyuk(q)
        return ulkeler.filter { Harf.latinBuyuk($0.ad).contains(ara) }
    }
}
