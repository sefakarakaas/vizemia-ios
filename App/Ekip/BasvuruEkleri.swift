import SwiftUI
import VizeMiaCekirdek

// Başvuru ayrıntısının ek kutuları (panel: pages/basvuru-ekleri.js):
// ödemeler + verilen fiyat, belgeler, konsolosluk takibi. Belgeler Firestore'da
// parça parça durur; açılınca indirilip önizlenir.

/// Kutuların ortak bağlamı: bildirim ve belge açma üst ekranda.
struct EkBaglami {
    var bildir: (_ hata: String?, _ tamam: String) -> Void
    var ac: (DosyaBilgisi) -> Void
    var aciliyor: String?
    var evrakTamam: Bool
}

// MARK: - Ödemeler

struct OdemelerKarti: View {
    let veri: BasvuruDetayVerisi
    let b: Basvuru
    let baglam: EkBaglami
    @Environment(EkipOturumu.self) private var ekip

    // Fiyat
    @State private var fiyatTutar = ""
    @State private var fiyatPara = "TRY"
    @State private var fiyatAciklama = ""
    @State private var fiyatDuzenle = false
    // Yeni ödeme
    @State private var ekleAcik = false
    @State private var tarih = Date()
    @State private var tutar = ""
    @State private var para = "TRY"
    @State private var yontem = "havale"
    @State private var onayKodu = ""
    @State private var aciklama = ""
    @State private var dekont: HazirDosya?
    @State private var kaydediliyor = false
    @State private var dekontEklenecek: Odeme?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Ödemeler").font(.headline).foregroundStyle(Tema.lacivert)
                Spacer()
                Text("\(veri.odemeler.count)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(veri.odemeler.isEmpty ? Tema.silik : Tema.olumluKoyu)
                    .contentTransition(.numericText())
            }
            fiyatBolumu
            Divider()
            if veri.odemeler.isEmpty {
                Text("Henüz ödeme kaydı yok.").font(.caption).foregroundStyle(Tema.govde)
            }
            ForEach(veri.odemeler) { odemeSatiri($0) }
            Button {
                withAnimation(Hareket.yay) { ekleAcik.toggle() }
            } label: {
                Label(ekleAcik ? "Vazgeç" : "Ödeme ekle", systemImage: ekleAcik ? "xmark" : "plus.circle.fill")
            }
            .buttonStyle(IkincilDugme())
            if ekleAcik { ekleFormu.transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .kart()
        .sheet(item: $dekontEklenecek) { o in
            SonradanDekontSayfasi(odeme: o) { d in
                await baglam.bildir(veri.sonradanDekont(o, dekont: d, ekip: ekip), "Dekont yüklendi.")
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: Fiyat

    private var fiyatBolumu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verilen fiyat").font(.caption.weight(.semibold)).foregroundStyle(Tema.govde)
            if let f = veri.fiyat {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Para.yazi(f.tutar)) \(f.paraBirimi)").font(.title3.weight(.bold)).foregroundStyle(Tema.lacivert)
                    if !f.aciklama.isEmpty { Text(f.aciklama).font(.caption).foregroundStyle(Tema.govde) }
                }
                Text([f.zaman.map { Tr.tarihSaat($0) } ?? "", f.yazan].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Tema.silik)
            } else {
                Text("Henüz fiyat girilmedi.").font(.subheadline).foregroundStyle(Tema.govde)
            }
            if fiyatDuzenle {
                HStack(spacing: 8) {
                    TextField("Ör. 4500", text: $fiyatTutar).keyboardType(.decimalPad).kutu()
                    Picker("Para birimi", selection: $fiyatPara) {
                        ForEach(OdemeKurali.paraBirimleri, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                TextField("Açıklama (ör. hizmet bedeli, harç hariç)", text: $fiyatAciklama).kutu()
                Button("Fiyatı kaydet") {
                    Task {
                        let h = await veri.fiyatKaydet(tutar: OdemeKurali.tutarOku(fiyatTutar), paraBirimi: fiyatPara,
                                                       aciklama: fiyatAciklama, ekip: ekip)
                        if h == nil { withAnimation(Hareket.yay) { fiyatDuzenle = false } }
                        baglam.bildir(h, "Fiyat kaydedildi.")
                    }
                }
                .buttonStyle(AnaDugme())
            } else {
                Button(veri.fiyat == nil ? "Fiyat gir" : "Fiyatı değiştir") {
                    if let f = veri.fiyat {
                        fiyatTutar = Para.yazi(f.tutar); fiyatPara = f.paraBirimi; fiyatAciklama = f.aciklama
                    }
                    withAnimation(Hareket.yay) { fiyatDuzenle = true }
                }
                .buttonStyle(KucukDugme())
            }
        }
    }

    // MARK: Ödeme satırı

    private func odemeSatiri(_ o: Odeme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Tr.tarih(o.tarih).map { Tr.kisaTarih($0) } ?? o.tarih)
                    .font(.subheadline.weight(.bold)).foregroundStyle(Tema.lacivert)
                if let t = o.tutar {
                    Text("\(Para.yazi(t)) \(o.paraBirimi)").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.olumluKoyu)
                }
                Spacer(minLength: 0)
                Etiket(metin: OdemeKurali.yontemAdi(o.yontem), renk: Tema.mavi)
            }
            if !o.onayKodu.isEmpty {
                Text("Onay: \(o.onayKodu)").font(.caption.monospaced()).foregroundStyle(Tema.govde).textSelection(.enabled)
            }
            if !o.aciklama.isEmpty { Text(o.aciklama).font(.caption).foregroundStyle(Tema.govde) }
            HStack(spacing: 8) {
                if let id = o.dosyaId, let d = veri.dosyalar.first(where: { $0.id == id }) {
                    Button { baglam.ac(d) } label: {
                        Label(baglam.aciliyor == d.id ? "Açılıyor…" : "Dekontu aç", systemImage: "doc.viewfinder")
                    }
                    .buttonStyle(KucukDugme())
                    .disabled(baglam.aciliyor != nil)
                } else if o.dosyaId == nil {
                    Etiket(metin: o.dekontDurumu, renk: Color(hex: 0xb36b00))
                    Button { dekontEklenecek = o } label: { Label("Dekont ekle", systemImage: "camera") }
                        .buttonStyle(KucukDugme())
                }
                Spacer(minLength: 0)
                Text([o.zaman.map { Tr.tarihSaat($0) } ?? "", o.yazan].filter { !$0.isEmpty }.joined(separator: " — "))
                    .font(.caption2).foregroundStyle(Tema.silik).lineLimit(1)
            }
        }
        .padding(10)
        .background(Tema.zeminYumusak.opacity(0.6), in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
    }

    // MARK: Yeni ödeme

    private var ekleFormu: some View {
        let otomatik = ekip.yapabilir("app.status") && veri.takipId != nil && b.ileriStatu(ekip.statuler, hedefId: "randevu-takip") != nil
        return VStack(alignment: .leading, spacing: 12) {
            DatePicker("Ödeme tarihi", selection: $tarih, in: ...Date(), displayedComponents: .date)
                .environment(\.locale, Tr.yerel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tema.lacivert)
            HStack(spacing: 8) {
                TextField("Tutar (isteğe bağlı)", text: $tutar).keyboardType(.decimalPad).kutu()
                Picker("Para birimi", selection: $para) {
                    ForEach(OdemeKurali.paraBirimleri, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            HStack {
                Text("Yöntem").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                Spacer()
                Picker("Yöntem", selection: $yontem) {
                    ForEach(OdemeKurali.yontemler.map { $0.id }, id: \.self) { id in
                        Text(OdemeKurali.yontemAdi(id)).tag(id)
                    }
                }
                .pickerStyle(.menu)
            }
            TextField("Onay kodu (POS slip / havale)", text: $onayKodu)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .kutu()
            TextField("Açıklama (isteğe bağlı)", text: $aciklama).kutu()
            Alan(etiket: "Dekont / slip", istegeBagli: true, yardim: "Girilmezse ödemenin yanında \"Dekont girilmedi\" yazar; sonradan eklenebilir.") {
                DosyaSecDugmeleri(secilen: $dekont)
            }
            if otomatik {
                Label("Ödeme kaydedilince başvuru kendiliğinden \"Randevu Takipte\" statüsüne geçer.", systemImage: "arrow.forward.circle")
                    .font(.caption).foregroundStyle(Tema.turkuaz)
            }
            Button {
                Task { await kaydet() }
            } label: {
                if kaydediliyor {
                    HStack(spacing: 8) { ProgressView().tint(.white); Text("Kaydediliyor…") }
                } else {
                    Label("Ödemeyi kaydet", systemImage: "checkmark.circle.fill")
                }
            }
            .buttonStyle(AnaDugme(renk: Tema.olumlu))
            .disabled(kaydediliyor)
        }
        .padding(12)
        .background(Tema.zeminYumusak.opacity(0.6), in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
    }

    private func kaydet() async {
        let t = OdemeKurali.tutarOku(tutar)
        if !tutar.trimmingCharacters(in: .whitespaces).isEmpty && t == nil {
            baglam.bildir("Tutar geçersiz.", ""); return
        }
        kaydediliyor = true
        let g = BasvuruIslemi.OdemeGirdisi(tarih: Tr.isoGun(tarih, takvim: Tr.takvim), tutar: t, paraBirimi: para, yontem: yontem,
                                           onayKodu: onayKodu, aciklama: aciklama)
        let r = await veri.odemeKaydet(g, dekont: dekont, ekip: ekip)
        kaydediliyor = false
        if r.tamam {
            tutar = ""; onayKodu = ""; aciklama = ""; dekont = nil; tarih = Date()
            withAnimation(Hareket.yay) { ekleAcik = false }
            baglam.bildir(nil, r.mesaj)
        } else {
            baglam.bildir(r.mesaj, "")
        }
    }
}

/// Dekontu girilmemiş ödemeye sonradan dekont.
struct SonradanDekontSayfasi: View {
    let odeme: Odeme
    let yukle: (HazirDosya) async -> Void
    @Environment(\.dismiss) private var kapat
    @State private var dosya: HazirDosya?
    @State private var yukleniyor = false

    private var baslik: String {
        let gun = Tr.tarih(odeme.tarih).map { Tr.kisaTarih($0) } ?? odeme.tarih
        guard let t = odeme.tutar else { return gun }
        return gun + " · " + Para.yazi(t) + " " + odeme.paraBirimi
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(baslik).font(.headline).foregroundStyle(Tema.lacivert)
                Text("Dekontun fotoğrafını çekin ya da dosyasını seçin.").font(.subheadline).foregroundStyle(Tema.govde)
                DosyaSecDugmeleri(secilen: $dosya)
                Spacer()
                Button {
                    guard let d = dosya else { return }
                    Task {
                        yukleniyor = true
                        await yukle(d)
                        yukleniyor = false
                        kapat()
                    }
                } label: {
                    Text(yukleniyor ? "Yükleniyor…" : "Dekontu yükle")
                }
                .buttonStyle(AnaDugme())
                .disabled(dosya == nil || yukleniyor)
            }
            .padding(Tema.bosluk)
            .navigationTitle("Dekont ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
        }
    }
}

// MARK: - Belgeler (randevu kağıdı, diğer belgeler)

struct BelgelerKarti: View {
    let veri: BasvuruDetayVerisi
    let baglam: EkBaglami
    @Environment(EkipOturumu.self) private var ekip
    @State private var dosya: HazirDosya?
    @State private var yukleniyor = false
    @State private var silinecek: DosyaBilgisi?

    private var belgeler: [DosyaBilgisi] { veri.dosyalar.filter { $0.tur == "randevu" || $0.tur == "diger" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Belgeler").font(.headline).foregroundStyle(Tema.lacivert)
            if belgeler.isEmpty { Text("Henüz belge yok.").font(.caption).foregroundStyle(Tema.govde) }
            ForEach(belgeler) { d in
                BelgeSatiri(d: d, aciliyor: baglam.aciliyor == d.id, silinebilir: silebilir,
                            ac: { baglam.ac(d) }, sil: { silinecek = d })
            }
            if ekip.yapabilir("app.edit") {
                Divider()
                Text("Diğer belge ekle").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                DosyaSecDugmeleri(secilen: $dosya)
                Button {
                    guard let d = dosya else { return }
                    Task {
                        yukleniyor = true
                        let r = await veri.belgeYukle(tur: "diger", dosya: d, evrakTamam: baglam.evrakTamam, ekip: ekip)
                        yukleniyor = false
                        if r.tamam { dosya = nil }
                        baglam.bildir(r.tamam ? nil : r.mesaj, r.mesaj)
                    }
                } label: { Text(yukleniyor ? "Yükleniyor…" : "Yükle") }
                    .buttonStyle(IkincilDugme())
                    .disabled(dosya == nil || yukleniyor)
                Text("Randevu kağıdı (tarih, saat ve merkez bilgisiyle) sıradaki güncellemede; şimdilik panelden yüklenir.")
                    .font(.caption).foregroundStyle(Tema.silik)
            }
        }
        .kart()
        .belgeSilmeOnayi($silinecek) { d in await baglam.bildir(veri.belgeSil(d, ekip: ekip), "Belge silindi.") }
    }

    private var silebilir: Bool { (ekip.calisan?.yonetici ?? false) || (ekip.yapabilir("app.edit") && ekip.yapabilir("app.sensitive")) }
}

// MARK: - Konsolosluk takibi

struct KonsoloslukKarti: View {
    let veri: BasvuruDetayVerisi
    let b: Basvuru
    let baglam: EkBaglami
    @Environment(EkipOturumu.self) private var ekip
    @State private var kod = ""
    @State private var fis: HazirDosya?
    @State private var kaydediliyor = false
    @State private var silinecek: DosyaBilgisi?

    private var fisler: [DosyaBilgisi] { veri.dosyalar.filter { $0.tur == "takip" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Konsolosluk takibi").font(.headline).foregroundStyle(Tema.lacivert)
            if !b.konsTakipKodu.isEmpty {
                HStack {
                    Text(b.konsTakipKodu).font(.system(.title3, design: .monospaced).weight(.bold)).foregroundStyle(Tema.lacivert)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = b.konsTakipKodu
                        baglam.bildir(nil, "Kod kopyalandı.")
                    } label: { Label("Kopyala", systemImage: "doc.on.doc") }
                        .buttonStyle(KucukDugme())
                }
                if let z = b.konsTakipZamani { Text("Girildi: \(Tr.tarihSaat(z))").font(.caption2).foregroundStyle(Tema.silik) }
            }
            if ekip.yapabilir("app.sensitive") {
                if fisler.isEmpty {
                    Text("Pasaport teslim fişi henüz yüklenmedi.").font(.caption).foregroundStyle(Tema.govde)
                }
                ForEach(fisler) { d in
                    BelgeSatiri(d: d, aciliyor: baglam.aciliyor == d.id, silinebilir: ekip.yapabilir("app.edit"),
                                ac: { baglam.ac(d) }, sil: { silinecek = d })
                }
            }
            if ekip.yapabilir("app.edit") {
                Divider()
                HStack(spacing: 8) {
                    TextField(b.konsTakipKodu.isEmpty ? "Fişteki takip / referans no" : "Kodu değiştir", text: $kod)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .kutu()
                    Button(b.konsTakipKodu.isEmpty ? "Kaydet" : "Güncelle") {
                        Task {
                            kaydediliyor = true
                            let r = await veri.konsoloslukKaydet(kod, evrakTamam: baglam.evrakTamam, ekip: ekip)
                            kaydediliyor = false
                            if r.tamam { kod = "" }
                            baglam.bildir(r.tamam ? nil : r.mesaj, r.mesaj)
                        }
                    }
                    .buttonStyle(KucukDugme())
                    .disabled(kaydediliyor || kod.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if ekip.yapabilir("app.sensitive") {
                    Text("Pasaport teslim fişi").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                    DosyaSecDugmeleri(secilen: $fis)
                    Button {
                        guard let d = fis else { return }
                        Task {
                            kaydediliyor = true
                            let r = await veri.belgeYukle(tur: "takip", dosya: d, evrakTamam: baglam.evrakTamam, ekip: ekip)
                            kaydediliyor = false
                            if r.tamam { fis = nil }
                            baglam.bildir(r.tamam ? nil : r.mesaj, r.mesaj)
                        }
                    } label: { Text(kaydediliyor ? "Yükleniyor…" : "Fişi yükle") }
                        .buttonStyle(IkincilDugme())
                        .disabled(fis == nil || kaydediliyor)
                    Text("Fiş yüklenince başvuru şartları tamamsa kendiliğinden \"Konsoloslukta İşlemde\"ye geçer.")
                        .font(.caption).foregroundStyle(Tema.govde)
                }
            }
        }
        .kart()
        .belgeSilmeOnayi($silinecek) { d in await baglam.bildir(veri.belgeSil(d, ekip: ekip), "Belge silindi.") }
    }
}

// MARK: - Ortak

struct BelgeSatiri: View {
    let d: DosyaBilgisi
    let aciliyor: Bool
    let silinebilir: Bool
    let ac: () -> Void
    let sil: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: d.pdf ? "doc.richtext.fill" : "photo.fill")
                .foregroundStyle(Tema.turkuaz)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.ad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert).lineLimit(1)
                Text([d.turAdi, Dosya.boyutYazi(d.boyut), d.zaman.map { Tr.tarihSaat($0) } ?? "", d.yazan]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Tema.govde).lineLimit(2)
            }
            Spacer(minLength: 0)
            if aciliyor {
                ProgressView()
            } else {
                Button(action: ac) { Image(systemName: "eye.fill") }
                    .buttonStyle(KucukDugme())
                    .accessibilityLabel("\(d.ad) aç")
            }
            if silinebilir {
                Button(action: sil) { Image(systemName: "trash") }
                    .buttonStyle(KucukDugme(renk: Tema.olumsuz))
                    .accessibilityLabel("\(d.ad) sil")
            }
        }
        .padding(.vertical, 4)
    }
}

/// Para yazısı: 4500 → "4.500", 2250.5 → "2.250,50".
enum Para {
    static func yazi(_ t: Double) -> String {
        let f = NumberFormatter()
        f.locale = Tr.yerel
        f.numberStyle = .decimal
        f.minimumFractionDigits = t == t.rounded() ? 0 : 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: t)) ?? String(t)
    }
}

extension View {
    /// Belge silme onayı.
    func belgeSilmeOnayi(_ secili: Binding<DosyaBilgisi?>, sil: @escaping (DosyaBilgisi) async -> Void) -> some View {
        confirmationDialog("\"\(secili.wrappedValue?.ad ?? "")\" silinsin mi?",
                           isPresented: Binding(get: { secili.wrappedValue != nil }, set: { if !$0 { secili.wrappedValue = nil } }),
                           titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                guard let d = secili.wrappedValue else { return }
                Task { await sil(d) }
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}
