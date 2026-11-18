import SwiftUI
import VizeMiaCekirdek

/// Süreç adımları (panel: #/surec): ana sayfadaki "5 adımda başvuru" bölümü.
/// Kaydedilince site yayını başlar; 2–3 dakikada ana sayfada görünür.
struct SurecEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @State private var s: SurecAdimlari?
    @State private var hata: String?
    @State private var bildiri: String?
    @State private var kaydediliyor = false
    @State private var basari = 0

    private var yetki: Bool { ekip.yapabilir("surec.edit") }

    var body: some View {
        Group {
            if let s {
                form(s)
            } else if let h = hata {
                ContentUnavailableView("Açılamadı", systemImage: "exclamationmark.triangle", description: Text(h))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ekranZemini()
        .navigationTitle("Süreç adımları")
        .navigationBarTitleDisplayMode(.inline)
        .task { if s == nil { await yukle() } }
        .sensoryFeedback(.success, trigger: basari)
    }

    private func form(_ x: SurecAdimlari) -> some View {
        let bag = Binding<SurecAdimlari>(get: { s ?? x }, set: { s = $0 })
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Ana sayfadaki \"5 adımda başvuru\" bölümü. Değişiklikler 2–3 dakika içinde sitede görünür.")
                    .font(.caption).foregroundStyle(Tema.govde)
                if !yetki {
                    Text("Değiştirmek için yayınlama yetkisi gerekiyor.").font(.caption.weight(.semibold)).foregroundStyle(Tema.uyari)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Alan(etiket: "Bölüm başlığı", yardim: "Adım sayısını değiştirirseniz başlığı da güncelleyin (ör. \"4 adımda başvuru\").") {
                        TextField("Başlık", text: bag.baslik).kutu()
                    }
                    Alan(etiket: "Kısa açıklama", istegeBagli: true) {
                        TextField("Açıklama", text: bag.aciklama, axis: .vertical).lineLimit(1...3).kutu()
                    }
                }
                .kart()
                .disabled(!yetki)
                ForEach(Array(x.adimlar.enumerated()), id: \.element.id) { i, _ in
                    adimKarti(i, bag).belirme(min(i + 1, 6))
                }
                if yetki && x.adimlar.count < SurecAdimlari.enFazla {
                    Button {
                        withAnimation(Hareket.yay) { s?.adimlar.append(.init(baslik: "", metin: "")) }
                    } label: { Label("Adım ekle", systemImage: "plus") }
                    .buttonStyle(IkincilDugme())
                }
                if let h = hata { AlanHatasi(metin: h) }
                if let b = bildiri {
                    Label(b, systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.olumluKoyu)
                }
                if yetki {
                    Button {
                        Task { await kaydet() }
                    } label: {
                        if kaydediliyor { HStack(spacing: 8) { ProgressView().tint(.white); Text("Kaydediliyor…") } } else { Text("Kaydet") }
                    }
                    .buttonStyle(AnaDugme())
                    .disabled(kaydediliyor)
                }
            }
            .padding(Tema.bosluk)
        }
        .formKlavyesi()
    }

    private func adimKarti(_ i: Int, _ bag: Binding<SurecAdimlari>) -> some View {
        let sayi = bag.wrappedValue.adimlar.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(i + 1). adım").font(.headline).foregroundStyle(Tema.lacivert)
                Spacer()
                if yetki {
                    Button { tasi(i, -1) } label: { Image(systemName: "arrow.up") }.buttonStyle(KucukDugme()).disabled(i == 0)
                    Button { tasi(i, 1) } label: { Image(systemName: "arrow.down") }.buttonStyle(KucukDugme()).disabled(i == sayi - 1)
                    Button { withAnimation(Hareket.yay) { _ = s?.adimlar.remove(at: i) } } label: { Image(systemName: "trash") }
                        .buttonStyle(KucukDugme(renk: Tema.olumsuz))
                        .disabled(sayi <= SurecAdimlari.enAz)
                        .accessibilityLabel("Adımı kaldır")
                }
            }
            if i < sayi {
                TextField("Başlık", text: bag.adimlar[i].baslik).kutu()
                TextField("Metin", text: bag.adimlar[i].metin, axis: .vertical).lineLimit(2...5).kutu()
            }
        }
        .kart()
        .disabled(!yetki)
    }

    private func tasi(_ i: Int, _ yon: Int) {
        guard var x = s else { return }
        let j = i + yon
        guard j >= 0, j < x.adimlar.count else { return }
        x.adimlar.swapAt(i, j)
        withAnimation(Hareket.yay) { s = x }
    }

    private func yukle() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { s = .varsayilan; return }
        #endif
        do {
            let b = try await ekip.istemci().belge("siteMetin/surec")
            s = SurecAdimlari(belge: b)
        } catch {
            hata = KasaVerisi.mesaj(error, "Yüklenemedi.")
        }
    }

    private func kaydet() async {
        guard let x = s, let c = ekip.calisan else { return }
        bildiri = nil
        let h = x.hatalar
        guard h.isEmpty else { hata = h.joined(separator: " "); return }
        hata = nil
        kaydediliyor = true
        defer { kaydediliyor = false }
        do {
            try await ekip.istemci().isle(x.yazimlar(calisan: c))
            bildiri = SiteYayini.mesaj(basladi: await ekip.siteyiGuncelle())
            basari += 1
        } catch {
            hata = KasaVerisi.mesaj(error, "Kaydedilemedi.")
        }
    }
}
