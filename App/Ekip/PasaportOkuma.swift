import SwiftUI
import PhotosUI
import Vision
import VizeMiaCekirdek

// Pasaport fotoğrafından MRZ (alttaki iki satır) okuma. Panel: passport-scan.js.
// Fotoğraf telefondan çıkmaz: yazı tanıma cihazda (Vision) yapılır, görsel
// bellekte kalır ve hiçbir yere yüklenmez. Kaydedilen yalnız sonuçtur.

/// Cihazda yazı tanıma ve en iyi MRZ okumasının seçimi.
enum MrzOkuyucu {
    struct Okuma {
        var sonuc: Mrz.Sonuc
        var puan: Int
        /// Fotoğraf yan / ters çekildiyse kaç derece çevrilerek okundu.
        var dondurme: Int
        var kusursuz: Bool { puan >= Mrz.enYuksekPuan }
    }

    /// Fotoğrafı dört yönde dener; kontrol haneleri tutan ilk okumada durur.
    static func oku(_ resim: UIImage) async -> Okuma? {
        guard let cg = resim.cgImage else { return nil }
        let kendi = yon(resim.imageOrientation)
        let yonler: [(CGImagePropertyOrientation, Int)] = [(kendi, 0), (dondur(kendi, 1), 90), (dondur(kendi, 3), 270), (dondur(kendi, 2), 180)]
        var en: Okuma?
        for (y, derece) in yonler {
            let satirlar = await metin(cg, yon: y)
            guard !satirlar.isEmpty else { continue }
            // Vision MRZ'deki "<<<" dizilerine bazen boşluk koyar: hem boşluksuz hem
            // ham metin denenir, puanı yüksek olan seçilir.
            let adaylar = [satirlar.map { $0.filter { !$0.isWhitespace } }.joined(separator: "\n"), satirlar.joined(separator: "\n")]
            for a in adaylar {
                guard let s = Mrz.oku(a), s.satirlar.count == 2 else { continue }
                let p = Mrz.puan(s.satirlar[0], s.satirlar[1])
                if en == nil || p > en!.puan { en = Okuma(sonuc: s, puan: p, dondurme: derece) }
            }
            if let e = en, e.sonuc.tamam && e.kusursuz { return e }
        }
        return en
    }

    /// Satırlar yukarıdan aşağıya; aynı yükseklikteki parçalar soldan sağa birleştirilir.
    private static func metin(_ cg: CGImage, yon: CGImagePropertyOrientation) async -> [String] {
        await withCheckedContinuation { (devam: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let istek = VNRecognizeTextRequest()
                istek.recognitionLevel = .accurate
                istek.usesLanguageCorrection = false
                istek.recognitionLanguages = ["en-US"]
                let isleyici = VNImageRequestHandler(cgImage: cg, orientation: yon, options: [:])
                do { try isleyici.perform([istek]) } catch { devam.resume(returning: []); return }
                let gozlemler: [VNRecognizedTextObservation] = istek.results ?? []
                var parcalar: [(y: CGFloat, x: CGFloat, h: CGFloat, metin: String)] = []
                for g in gozlemler {
                    guard let aday = g.topCandidates(1).first else { continue }
                    let k = g.boundingBox
                    parcalar.append((k.midY, k.minX, k.height, aday.string))
                }
                parcalar.sort { $0.y > $1.y }
                var satirlar: [[(x: CGFloat, metin: String)]] = []
                var sonY: CGFloat = -1, sonH: CGFloat = 0
                for p in parcalar {
                    if !satirlar.isEmpty && abs(sonY - p.y) < max(sonH, p.h) * 0.5 {
                        satirlar[satirlar.count - 1].append((p.x, p.metin))
                    } else {
                        satirlar.append([(p.x, p.metin)])
                        sonY = p.y
                        sonH = p.h
                    }
                }
                let sonuc: [String] = satirlar.map { s in s.sorted { $0.x < $1.x }.map(\.metin).joined() }
                devam.resume(returning: sonuc)
            }
        }
    }

    private static func yon(_ y: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch y {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// Saat yönünde 90° adımlarla çevirme (aynalı yönler düz kabul edilir).
    private static func dondur(_ y: CGImagePropertyOrientation, _ adim: Int) -> CGImagePropertyOrientation {
        let sira: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        let i = sira.firstIndex(of: y) ?? 0
        return sira[(i + adim) % 4]
    }
}

/// Fotoğraf kaynağı düğmeleri (kamera / fotoğraflar) ve okuma.
struct MrzFotoDugmeleri: View {
    /// Okunan satırlar ve okumanın özeti.
    let okundu: (_ satirlar: [String], _ ozet: String) -> Void
    let okunamadi: (String) -> Void
    @State private var fotoSecimi: PhotosPickerItem?
    @State private var kameraAcik = false
    @State private var okunuyor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { kameraAcik = true } label: { Label("Fotoğraf çek", systemImage: "camera.fill") }
                        .buttonStyle(KucukDugme())
                }
                PhotosPicker(selection: $fotoSecimi, matching: .images) {
                    Label("Fotoğraflar", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(KucukDugme())
            }
            .disabled(okunuyor)
            if okunuyor {
                HStack(spacing: 6) { ProgressView(); Text("Okunuyor…").font(.caption).foregroundStyle(Tema.govde) }
            }
            Text("Fotoğraf yüklenmez, sunucuya gönderilmez; yalnız bu telefonda okunur. Veri sayfasını düz, parlamasız ve alttaki iki satır net görünecek şekilde çekin.")
                .font(.caption2)
                .foregroundStyle(Tema.silik)
        }
        .onChange(of: fotoSecimi) { _, yeni in
            guard let yeni else { return }
            Task {
                let veri: Data? = try? await yeni.loadTransferable(type: Data.self)
                fotoSecimi = nil
                if let v = veri, let r = UIImage(data: v) { await oku(r) } else { okunamadi("Fotoğraf açılamadı.") }
            }
        }
        .fullScreenCover(isPresented: $kameraAcik) {
            KameraGorunumu { resim in
                kameraAcik = false
                guard let resim else { return }
                Task { await oku(resim) }
            }
            .ignoresSafeArea()
        }
    }

    private func oku(_ r: UIImage) async {
        okunuyor = true
        defer { okunuyor = false }
        guard let o = await MrzOkuyucu.oku(r) else {
            okunamadi("MRZ satırları bulunamadı. Pasaportun alttaki iki satırı görünecek şekilde yeniden çekin ya da satırları elle yazın.")
            return
        }
        let donus = o.dondurme == 0 ? "" : "fotoğraf \(o.dondurme)° çevrildi, "
        let ozet = o.kusursuz && o.sonuc.tamam
            ? "Okundu (\(donus)kontrol haneleri tuttu). Satırları bir kez göz ucuyla kontrol edin."
            : "Okundu ama temiz çıkmadı (\(donus)puan \(o.puan)/\(Mrz.enYuksekPuan)). Satırları pasaportla karşılaştırıp düzeltin."
        okundu(o.sonuc.satirlar, ozet)
    }
}

/// İki MRZ satırı: okunan buraya gelir, elle düzeltilebilir.
struct MrzSatirlari: View {
    @Binding var metin: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("P<TURYILMAZ<<AHMET<<<…\nU01234567TUR9001011M3001012…", text: $metin, axis: .vertical)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(2...4)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .kutu()
            Text("Her satır tam 44 karakterdir. Okuma hatalıysa buradan düzeltebilirsiniz.")
                .font(.caption2)
                .foregroundStyle(Tema.silik)
        }
    }
}

// MARK: - Başvuru ayrıntısı: Pasaport kontrolü

struct PasaportKontrolKarti: View {
    let veri: BasvuruDetayVerisi
    let baglam: EkBaglami
    @Environment(EkipOturumu.self) private var ekip
    @State private var acik = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pasaport kontrolü").font(.headline).foregroundStyle(Tema.lacivert)
                Spacer()
                if veri.form != nil {
                    Button { acik = true } label: {
                        Label(veri.pasaport == nil ? "Pasaportu okut" : "Yeniden okut", systemImage: "person.text.rectangle")
                    }
                    .buttonStyle(KucukDugme())
                }
            }
            if let k = veri.pasaport {
                ozet(k)
            } else {
                Text("Bu başvuru için henüz pasaport kontrolü yapılmadı.").font(.caption).foregroundStyle(Tema.govde)
            }
            if veri.form == nil {
                Text("Karşılaştırma için başvuru formu verisi gerekli.").font(.caption).foregroundStyle(Tema.silik)
            }
        }
        .kart()
        .sheet(isPresented: $acik) {
            PasaportKarsilastirmaSayfasi(form: veri.formMetinleri) { durum, d in
                let h = await veri.pasaportKaydet(durum, d, ekip: ekip)
                if h == nil { acik = false }
                baglam.bildir(h, "Pasaport kontrolü kaydedildi.")
                return h
            }
        }
    }

    private func ozet(_ k: PasaportKontrolu) -> some View {
        let renk: Color = k.durum == .otomatik ? Tema.olumlu : (k.durum == .danisman ? Tema.altin : Tema.olumsuz)
        return VStack(alignment: .leading, spacing: 6) {
            Etiket(metin: k.durumAdi, renk: renk)
            Text([k.zaman.map { Tr.tarihSaat($0) } ?? "", k.yapan].filter { !$0.isEmpty }.joined(separator: " — "))
                .font(.caption2)
                .foregroundStyle(Tema.silik)
            Text(k.uyusmayanlar.isEmpty ? "Tüm alanlar pasaportla eşleşti." : "Uyuşmayan alanlar: \(k.uyusmayanlar.joined(separator: ", "))")
                .font(.subheadline)
                .foregroundStyle(Tema.govde)
            if !k.onaylayan.isEmpty {
                Text("Danışman onayı: \(k.onaylayan)\(k.onayZamani.map { " — " + Tr.tarihSaat($0) } ?? "")")
                    .font(.caption2)
                    .foregroundStyle(Tema.silik)
            }
        }
    }
}

/// Okuma, karşılaştırma tablosu ve karar düğmeleri.
struct PasaportKarsilastirmaSayfasi: View {
    let form: [String: String]
    let kaydet: (PasaportKontrolu.Durum, PasaportDegerlendirmesi) async -> String?
    @Environment(\.dismiss) private var kapat
    @State private var satirlar = ""
    @State private var ozet: String?
    @State private var hata: String?
    @State private var sonuc: PasaportDegerlendirmesi?
    @State private var kaydediliyor = false
    @State private var elleOnay = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pasaport fotoğrafı (veri sayfası)").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                        MrzFotoDugmeleri(okundu: { l, o in
                            satirlar = l.joined(separator: "\n")
                            ozet = o
                            hata = nil
                            karsilastir()
                        }, okunamadi: { hata = $0; ozet = nil })
                        if let o = ozet { Text(o).font(.caption).foregroundStyle(Tema.govde) }
                        if let h = hata { AlanHatasi(metin: h) }
                        Text("MRZ satırları (alt iki satır)").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                        MrzSatirlari(metin: $satirlar)
                        Button("Karşılaştır") { karsilastir() }
                            .buttonStyle(IkincilDugme())
                    }
                    .kart()
                    if let d = sonuc { sonucKarti(d).transition(.opacity) }
                }
                .padding(Tema.bosluk)
            }
            .formKlavyesi()
            .ekranZemini()
            .navigationTitle("Pasaport kontrolü")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } }
            }
            .animation(Hareket.yay, value: sonuc)
            .confirmationDialog("Uyuşmayan alanlar: \(sonuc?.uyusmayanlar.joined(separator: ", ") ?? "—"). Sorumluluğu alarak onaylıyor musunuz?",
                                isPresented: $elleOnay, titleVisibility: .visible) {
                Button("Onaylıyorum") { gonder(.danisman) }
                Button("Vazgeç", role: .cancel) {}
            }
        }
    }

    private func karsilastir() {
        guard let d = PasaportDegerlendirmesi.degerlendir(metin: satirlar.uppercased(), form: form) else {
            hata = "İki MRZ satırı gerekli."
            sonuc = nil
            return
        }
        hata = nil
        sonuc = d
    }

    private func gonder(_ durum: PasaportKontrolu.Durum) {
        guard let d = sonuc, !kaydediliyor else { return }
        Task {
            kaydediliyor = true
            let h = await kaydet(durum, d)
            kaydediliyor = false
            if let h { hata = h }
        }
    }

    private func sonucKarti(_ d: PasaportDegerlendirmesi) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Karşılaştırma").font(.headline).foregroundStyle(Tema.lacivert)
            if !d.yanlisUzunluk.isEmpty {
                AlanHatasi(metin: "Okunan satırların uzunluğu yanlış (" + d.yanlisUzunluk.map { "\($0.satir). satır: \($0.uzunluk) karakter" }.joined(separator: ", ")
                           + "; olması gereken 44). Alanlar kaymış olabilir; satırları elle düzeltin.")
            }
            ForEach(d.sonuc.hatalar, id: \.self) { AlanHatasi(metin: $0) }
            ForEach(d.sonuc.notlar, id: \.self) { n in
                Label(n, systemImage: "info.circle").font(.caption).foregroundStyle(Tema.mavi)
            }
            if d.guvenilmez {
                Text("Okuma güvenilir değil. Karşılaştırmaya güvenmeden önce MRZ satırlarını pasaportla karşılaştırıp düzeltin.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Tema.uyari)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tema.uyariZemin, in: RoundedRectangle(cornerRadius: Tema.koseKucuk))
            }
            VStack(spacing: 0) {
                ForEach(d.satirlar) { s in
                    karsilastirmaSatiri(s)
                    if s.id != d.satirlar.last?.id { Divider() }
                }
            }
            Text(d.hepsiUyuyor ? "Pasaport ile form birebir uyuşuyor — otomatik onaylanabilir." : "Farklılık var. Danışman onayı gerekiyor.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(d.hepsiUyuyor ? Tema.olumluKoyu : Tema.uyari)
            if d.hepsiUyuyor {
                Button { gonder(.otomatik) } label: {
                    Text(kaydediliyor ? "Kaydediliyor…" : "Otomatik onayla ve kaydet")
                }
                .buttonStyle(AnaDugme())
                .disabled(kaydediliyor)
            } else {
                Button { elleOnay = true } label: { Text("Farklılığı gördüm, elle onaylıyorum") }
                    .buttonStyle(IkincilDugme())
                    .disabled(kaydediliyor)
                Button(role: .destructive) { gonder(.uyusmuyor) } label: {
                    Text(kaydediliyor ? "Kaydediliyor…" : "Uyuşmuyor olarak kaydet")
                }
                .buttonStyle(KucukDugme(renk: Tema.olumsuz))
                .disabled(kaydediliyor)
            }
            Text("Yalnız sonuç saklanır; MRZ satırları ve fotoğraf kaydedilmez.")
                .font(.caption2)
                .foregroundStyle(Tema.silik)
        }
        .kart()
    }

    private func karsilastirmaSatiri(_ s: Mrz.Karsilastirma) -> some View {
        let isaret: String = s.uyuyor ? "checkmark.circle.fill" : (s.mrz.isEmpty ? "minus.circle" : "xmark.circle.fill")
        let renk: Color = s.uyuyor ? Tema.olumlu : (s.mrz.isEmpty ? Tema.silik : Tema.olumsuz)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: isaret).foregroundStyle(renk).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.etiket).font(.caption.weight(.bold)).foregroundStyle(Tema.lacivert)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Pasaport").font(.caption2).foregroundStyle(Tema.silik).frame(width: 52, alignment: .leading)
                    Text(s.mrz.isEmpty ? "—" : s.mrz).font(.system(.caption, design: .monospaced)).foregroundStyle(Tema.govde)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Form").font(.caption2).foregroundStyle(Tema.silik).frame(width: 52, alignment: .leading)
                    Text(s.form.isEmpty ? "—" : s.form).font(.system(.caption, design: .monospaced)).foregroundStyle(Tema.govde)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Yeni / düzenle: Pasaporttan doldur

struct PasaporttanDoldurKutusu: View {
    /// Alanları forma yazar (zorla: çelişenlerin üzerine) ve sonucu döner.
    let uygula: (_ gelen: [String: String], _ zorla: Bool) -> PasaporttanDoldurma.Sonuc
    @State private var acik = false
    @State private var satirlar = ""
    @State private var ozet: String?
    @State private var hata: String?
    @State private var okuma: Mrz.Sonuc?
    @State private var sonuc: PasaporttanDoldurma.Sonuc?
    @State private var yanlisUzunluk = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Hareket.yay) { acik.toggle() }
            } label: {
                HStack {
                    Label("Pasaporttan doldur", systemImage: "person.text.rectangle").font(.headline).foregroundStyle(Tema.lacivert)
                    Spacer()
                    Image(systemName: acik ? "chevron.up" : "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
                }
            }
            .buttonStyle(.plain)
            if acik {
                Text("Pasaportun fotoğrafını seçin; isim, soyisim, pasaport no, TCKN, doğum ve geçerlilik tarihi ile cinsiyet otomatik dolsun.")
                    .font(.caption)
                    .foregroundStyle(Tema.govde)
                MrzFotoDugmeleri(okundu: { l, o in
                    satirlar = l.joined(separator: "\n")
                    ozet = o
                    hata = nil
                    doldur(zorla: false)
                }, okunamadi: { hata = $0; ozet = nil })
                if let o = ozet { Text(o).font(.caption).foregroundStyle(Tema.govde) }
                if let h = hata { AlanHatasi(metin: h) }
                DisclosureGroup("MRZ satırlarını elle yaz") {
                    VStack(alignment: .leading, spacing: 8) {
                        MrzSatirlari(metin: $satirlar)
                        Button("Satırlardan doldur") { doldur(zorla: false) }.buttonStyle(KucukDugme())
                    }
                    .padding(.top, 6)
                }
                .font(.subheadline.weight(.semibold))
                .tint(Tema.lacivert)
                if let s = sonuc { sonucGorunumu(s) }
            }
        }
        .kartSoluk()
    }

    private func doldur(zorla: Bool) {
        let l = satirlar.uppercased().split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard l.count >= 2 else { hata = "İki MRZ satırı gerekli."; return }
        let o = Mrz.coz(l[0], l[1])
        yanlisUzunluk = l[0].count != 44 || l[1].count != 44
        okuma = o
        let gelen = Mrz.formDegerleri(o.alanlar)
        if zorla {
            // Yalnız çelişen alanlar pasaporttakiyle değiştirilir.
            var c: [String: String] = [:]
            for x in sonuc?.celiskiler ?? [] { c[x.key] = x.yeni }
            _ = uygula(c, true)
        }
        withAnimation(Hareket.yay) { sonuc = uygula(gelen, false) }
    }

    private func sonucGorunumu(_ s: PasaporttanDoldurma.Sonuc) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if yanlisUzunluk {
                AlanHatasi(metin: "Okunan satırların uzunluğu yanlış (olması gereken 44). Alanlar kaymış olabilir, lütfen kontrol edin.")
            }
            ForEach(okuma?.hatalar ?? [], id: \.self) { AlanHatasi(metin: $0) }
            ForEach(okuma?.notlar ?? [], id: \.self) { n in
                Label(n, systemImage: "info.circle").font(.caption).foregroundStyle(Tema.mavi)
            }
            if s.dolan.isEmpty {
                Text("Doldurulacak boş alan kalmadı.").font(.caption).foregroundStyle(Tema.govde)
            } else {
                Label("Dolduruldu: \(s.dolan.joined(separator: ", ")).", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Tema.olumluKoyu)
            }
            if !(okuma?.alanlar.gecerlilik.isEmpty ?? true) {
                Text("Veriliş (düzenleme) tarihi pasaportun makine okunur alanında yok, bu yüzden doldurulmadı. Pasaportun ön yüzündeki \"Veriliş tarihi / Date of issue\" satırından okuyup elle yazın. (Tahmin etmiyoruz: pasaport 6 ay ile 10 yıl arasında değişen sürelerle düzenlenebiliyor.)")
                    .font(.caption)
                    .foregroundStyle(Tema.uyari)
            }
            if !s.celiskiler.isEmpty {
                Text("Şu alanlarda farklı bir değer zaten yazılı: " + s.celiskiler.map { "\($0.etiket) (formda \"\($0.simdiki)\", pasaportta \"\($0.yeni)\")" }.joined(separator: "; ") + ".")
                    .font(.caption)
                    .foregroundStyle(Tema.uyari)
                Button("Pasaporttakiyle değiştir") { doldur(zorla: true) }.buttonStyle(KucukDugme())
            }
        }
    }
}
