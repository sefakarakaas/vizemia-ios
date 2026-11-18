import SwiftUI
import PhotosUI
import VizeMiaCekirdek

/// "Post yükle" (panel: Sosyal medya → Post yükle; social.upload). Kendi görselini ve
/// kanal metinlerini ekler; post "Bekleyenler"e düşer, paylaşım her zamanki gibi.
/// Büyük ya da başka biçimdeki görsel JPEG'e çevrilip 900 KB altına küçültülür.
struct PostYukleSayfasi: View {
    let yuklendi: (String) -> Void
    @Environment(EkipOturumu.self) private var ekip
    @Environment(\.dismiss) private var kapat
    @State private var gun = Date()
    @State private var tur = "haber"
    @State private var konu = ""
    @State private var kaynak = ""
    @State private var instagram = ""
    @State private var x = ""
    @State private var whatsapp = ""
    @State private var secilen: [PhotosPickerItem] = []
    @State private var gorseller: [ElleSosyalPost.Gorsel] = []
    @State private var onizleme: [UIImage] = []
    @State private var hazirlaniyor = false
    @State private var calisiyor = false
    @State private var hata: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Gün", selection: $gun, displayedComponents: .date).environment(\.locale, Tr.yerel)
                    Picker("Tür", selection: $tur) {
                        ForEach(SosyalPost.turler.sorted { $0.value < $1.value }, id: \.key) { e in Text(e.value).tag(e.key) }
                    }
                    TextField("Konu (kartın başlığı; paylaşılmaz)", text: $konu)
                    TextField("Kaynak (isteğe bağlı)", text: $kaynak)
                }
                Section {
                    PhotosPicker(selection: $secilen, maxSelectionCount: ElleSosyalPost.gorselEnCok, matching: .images) {
                        Label(gorseller.isEmpty ? "Görsel seç" : "\(gorseller.count) görsel seçildi", systemImage: "photo.on.rectangle")
                    }
                    if hazirlaniyor { ProgressView("Görseller hazırlanıyor…") }
                    if !onizleme.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(Array(onizleme.enumerated()), id: \.offset) { _, r in
                                    Image(uiImage: r).resizable().scaledToFill().frame(width: 72, height: 72).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                } header: { Text("Görseller") } footer: { Text("Sırayla; en çok \(ElleSosyalPost.gorselEnCok). Büyük görsel otomatik küçültülür.") }
                Section("Metinler") {
                    TextField("Instagram açıklaması", text: $instagram, axis: .vertical).lineLimit(3...10)
                    TextField("X metni (isteğe bağlı)", text: $x, axis: .vertical).lineLimit(2...6)
                    TextField("WhatsApp metni (isteğe bağlı)", text: $whatsapp, axis: .vertical).lineLimit(2...6)
                }
                if let h = hata { Section { Text(h).foregroundStyle(Tema.olumsuz) } }
                Section {
                    Button { Task { await yukle() } } label: { if calisiyor { ProgressView() } else { Text("Postu yükle") } }
                        .disabled(calisiyor || hazirlaniyor)
                } footer: { Text("X ve WhatsApp metni boşsa o kanal eklenmez.") }
            }
            .navigationTitle("Post yükle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
            .onChange(of: secilen) { _, yeni in Task { await hazirla(yeni) } }
        }
    }

    private func hazirla(_ l: [PhotosPickerItem]) async {
        hazirlaniyor = true
        defer { hazirlaniyor = false }
        hata = nil
        var g: [ElleSosyalPost.Gorsel] = []
        var o: [UIImage] = []
        for (i, item) in l.enumerated() {
            guard let d = try? await item.loadTransferable(type: Data.self) else { hata = "\(i + 1). görsel açılamadı."; continue }
            if let h = Self.kucult(d) { g.append(h); if let r = UIImage(data: h.bayt) { o.append(r) } } else { hata = "\(i + 1). görsel 900 KB altına küçültülemedi." }
        }
        gorseller = g
        onizleme = o
    }

    /// Panelin gorselHazirla'sı: tanınan biçim ve 900 KB altındaysa olduğu gibi; değilse
    /// en uzun kenar 2160 px, JPEG 0.9/0.8/0.7, sığmazsa %80 küçülterek (en çok 6 kez).
    static func kucult(_ d: Data) -> ElleSosyalPost.Gorsel? {
        if let t = ElleSosyalPost.gorselTuru(d), d.count <= ElleSosyalPost.gorselBaytEnCok { return .init(tur: t, bayt: d) }
        guard let r = UIImage(data: d) else { return nil }
        var olcek = min(1, 2160 / max(r.size.width, r.size.height))
        for _ in 0..<6 {
            let boyut = CGSize(width: max(1, (r.size.width * olcek).rounded()), height: max(1, (r.size.height * olcek).rounded()))
            let bicim = UIGraphicsImageRendererFormat()
            bicim.scale = 1
            bicim.opaque = true
            let kucuk = UIGraphicsImageRenderer(size: boyut, format: bicim).image { c in
                UIColor.white.setFill()
                c.fill(CGRect(origin: .zero, size: boyut))
                r.draw(in: CGRect(origin: .zero, size: boyut))
            }
            for kalite in [0.9, 0.8, 0.7] {
                if let j = kucuk.jpegData(compressionQuality: kalite), j.count <= ElleSosyalPost.gorselBaytEnCok { return .init(tur: "image/jpeg", bayt: j) }
            }
            olcek *= 0.8
        }
        return nil
    }

    private func yukle() async {
        guard let c = ekip.calisan else { return }
        hata = nil
        calisiyor = true
        defer { calisiyor = false }
        let tarih = Tr.isoGun(gun, takvim: Tr.takvim)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { yuklendi("ornek"); kapat(); return }
        #endif
        do {
            let f = try await ekip.istemci()
            async let gunun = f.sorgu(koleksiyon: "posts", kosullar: [.esit("tarih", .metin(tarih))], sinir: 100)
            async let son = f.sorgu(koleksiyon: "posts", sirala: ("no", .azalan), sinir: 1)
            let dolu = try await gunun.compactMap { $0.alanlar["sira"]?.tamDegeri }
            let no = ((try await son).first?.alanlar["no"]?.tamDegeri ?? 0) + 1
            switch ElleSosyalPost.olustur(tarih: tarih, sira: ElleSosyalPost.bosSira(dolu), no: no, tur: tur, konu: konu, kaynak: kaynak,
                                          instagram: instagram, x: x, whatsapp: whatsapp, gorseller: gorseller, calisan: c) {
            case .failure(let h): hata = h.mesaj
            case .success(let r):
                do {
                    try await f.isle(r.yazimlar)
                    yuklendi(r.id)
                    kapat()
                } catch FirestoreHatasi.izinYok {
                    hata = "Kaydedilemedi: aynı anda başka bir post eklenmiş olabilir. Tekrar deneyin."
                }
            }
        } catch {
            hata = HataAciklamasi.metin(error, "Yüklenemedi. İnternet bağlantınızı kontrol edin.")
        }
    }
}
