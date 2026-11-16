import SwiftUI
import VizeMiaCekirdek

/// Vize harçları ve döviz çevirici (sitedeki /harclar).
struct HarclarEkrani: View {
    @Environment(IcerikDeposu.self) private var icerik
    @Environment(Gezinti.self) private var gezinti

    @State private var tutar = "90"
    @State private var para = "EUR"
    @FocusState private var tutarOdakta: Bool

    private struct Para: Identifiable { let id: String; let ad: String }
    private struct Hazir: Identifiable { let id: String; let tutar: String; let para: String }

    private let paralar = [
        Para(id: "EUR", ad: "€ Euro"), Para(id: "USD", ad: "$ Dolar"), Para(id: "GBP", ad: "£ Sterlin"),
        Para(id: "CAD", ad: "C$ Kanada"), Para(id: "TRY", ad: "₺ Lira"),
    ]
    private let hazirlar = [
        Hazir(id: "🇪🇺 90 € (Schengen)", tutar: "90", para: "EUR"), Hazir(id: "🇪🇺 45 € (Çocuk)", tutar: "45", para: "EUR"),
        Hazir(id: "🇺🇸 185 $ (ABD)", tutar: "185", para: "USD"), Hazir(id: "🇬🇧 135 £ (İngiltere)", tutar: "135", para: "GBP"),
        Hazir(id: "🇨🇦 100 CAD (Kanada)", tutar: "100", para: "CAD"),
    ]
    private let bayraklar = ["schengen": "🇪🇺", "ingiltere": "🇬🇧", "abd": "🇺🇸", "kanada": "🇨🇦"]
    private let basvuruUlkesi = ["ingiltere": "birlesik-krallik", "abd": "abd", "kanada": "kanada"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hesaplama ve rehber").ustBaslik()
                    Text("Vize harçları ve döviz çevirici").bolumBasligi()
                    Text("Tutarlar konsolosluk harcıdır; başvuru merkezi hizmet bedeli ayrıca alınır. Her harcın altında resmî kaynağı var.").govdeMetni()
                }

                cevirici

                ForEach(icerik.akis.harclar) { h in
                    harc(h)
                }

                Text("Bu ekran ve döviz çevirici, vize başvuru sahiplerinin resmî konsolosluk harçlarını ve seyahat bütçelerini öngörebilmelerine yardımcı olmak için hazırlanmış, ticari amaç gütmeyen bir bilgilendirme hizmetidir. Gösterilen kurlar yatırım tavsiyesi, kambiyo alım-satım teklifi ya da garanti niteliği taşımaz. Gerçek ödeme tutarları, randevu günü ilgili konsolosluk ya da yetkili başvuru merkezinin uyguladığı kura ve banka komisyonlarına göre değişebilir.")
                    .font(.caption)
                    .foregroundStyle(Tema.govde)
            }
            .padding(Tema.bosluk)
        }
        .scrollDismissesKeyboard(.interactively)
        .ekranZemini()
        .navigationTitle("Harç & Kur")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await icerik.canliKur() }
        .task {
            // Ekran açık kaldıkça kur birkaç dakikada bir yenilenir.
            while !Task.isCancelled {
                await icerik.canliKur()
                try? await Task.sleep(for: .seconds(300))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Bitti") { tutarOdakta = false }
            }
        }
    }

    private var cevirici: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Döviz çevirici").font(.headline).foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(hazirlar) { h in
                        Button(h.id) {
                            tutar = h.tutar
                            para = h.para
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.white.opacity(0.14), in: Capsule())
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Tutar", text: $tutar)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .focused($tutarOdakta)
                    .kutu()
                Picker("Para birimi", selection: $para) {
                    ForEach(paralar) { p in Text(p.ad).tag(p.id) }
                }
                .pickerStyle(.menu)
                .tint(Tema.lacivert)
                .padding(.vertical, 5)
                .background(Tema.zemin, in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tahmini karşılık").font(.caption).foregroundStyle(.white.opacity(0.75))
                Text(sonuc.tutar)
                    .font(.vitrin(28))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                if !sonuc.oran.isEmpty {
                    Text(sonuc.oran).font(.caption).foregroundStyle(.white.opacity(0.85))
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(Tema.bosluk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.lacivert, in: RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
    }

    private var sonuc: (tutar: String, oran: String) {
        guard let k = icerik.kur else { return ("Kur yükleniyor…", "") }
        guard let m = Sayi.oku(tutar), let s = k.cevir(miktar: m, kaynak: para) else {
            return ("Lütfen geçerli bir tutar girin", "")
        }
        return (s.tutar, "\(s.oran) — \(k.bilgi)")
    }

    private func harc(_ h: HarcGrubu) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(bayraklar[h.id] ?? "🌍").font(.title2)
                Text(h.ad).font(.headline).foregroundStyle(Tema.lacivert)
            }
            VStack(spacing: 0) {
                ForEach(Array(h.satirlar.enumerated()), id: \.offset) { i, satir in
                    if satir.count >= 2 {
                        HStack(alignment: .firstTextBaseline) {
                            Text(satir[0]).font(.subheadline).foregroundStyle(Tema.govde)
                            Spacer(minLength: 12)
                            Text(satir[1]).font(.subheadline.weight(.heavy)).foregroundStyle(Tema.lacivert)
                        }
                        .padding(.vertical, 10)
                        if i < h.satirlar.count - 1 { Divider() }
                    }
                }
            }
            if h.kaynak.count >= 2, let u = URL(string: h.kaynak[1]) {
                Link(destination: u) {
                    (Text("Kaynak: ").foregroundStyle(Tema.govde) + Text(h.kaynak[0]).foregroundStyle(Tema.mavi).underline()
                        + Text(h.guncelleme.isEmpty ? "" : " · Son kontrol: \(Tr.uzunTarih(h.guncelleme))").foregroundStyle(Tema.govde))
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                }
            }
            if h.id == "schengen" {
                NavigationLink(value: Rota.ulkeler) {
                    Text("Ülkeyi seçin, ücretsiz ön değerlendirme alın")
                }
                .buttonStyle(IkincilDugme())
            } else {
                Button("\(h.ad) için ücretsiz ön değerlendirme al") {
                    gezinti.ac(.basvuru(ulke: basvuruUlkesi[h.id] ?? ""))
                }
                .buttonStyle(IkincilDugme())
            }
        }
        .kart()
    }
}
