import SwiftUI
import VizeMiaCekirdek

/// Başvuru ayrıntısındaki "Grup" (panel: GrupPanel). Grup yalnız bir arada göstermek
/// içindir: başvuru, evrak, ödeme ve statü herkes için ayrı kalır.
struct GrupKarti: View {
    let veri: BasvuruDetayVerisi
    let b: Basvuru
    let baglam: EkBaglami
    @Environment(EkipOturumu.self) private var ekip
    @State private var kod = ""
    @State private var ad = ""
    @State private var calisiyor = false
    @State private var tasima: String?
    @State private var cikarSor = false

    private var grupta: Bool { GrupIsi.gecerliId(b.grupId) }
    private var digerleri: [Basvuru] { veri.grup.filter { $0.kimlik != b.kimlik } }
    private var yazabilir: Bool { ekip.yapabilir("app.edit") || ekip.yapabilir("app.create") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(grupta ? "\(b.grupAdi.isEmpty ? "Grup" : b.grupAdi) · \(max(veri.grup.count, 1)) kişi" : "Grup", systemImage: "person.3.fill")
                .font(.headline)
                .foregroundStyle(Tema.lacivert)
            if grupta {
                if digerleri.isEmpty { Text("Grupta başka kişi yok.").font(.caption).foregroundStyle(Tema.govde) }
                ForEach(digerleri) { u in
                    NavigationLink(value: EkipRota.basvuru(u.kimlik)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.adSoyad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                                Text(u.takipKodu).font(.caption.monospaced()).foregroundStyle(Tema.silik)
                            }
                            Spacer()
                            let s = ekip.statuSozlugu[u.statuId]
                            Etiket(metin: s?.ad ?? u.statuAdi, renk: s.flatMap { Color(kod: $0.renk) } ?? Tema.mavi)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Bu başvuru bir grupta değil. Aynı yolculuğa katılan kişileri gruplayın: liste ve ayrıntıda bir arada görünürler; başvuru, evrak, ödeme ve statü herkes için ayrı kalır.")
                    .font(.caption).foregroundStyle(Tema.govde)
            }
            if ekip.yapabilir("app.create") {
                NavigationLink(value: EkipRota.grubaEkle(b.kimlik)) {
                    Label("Gruba kişi ekle", systemImage: "person.badge.plus")
                }
                .buttonStyle(AnaDugme())
            }
            if yazabilir {
                HStack(spacing: 8) {
                    TextField("Takip kodu (ör. 2026-110401)", text: $kod)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .kutu()
                    Button(grupta ? "Bu gruba ekle" : "Grupla") { Task { await bagla(tasimaOnayli: false) } }
                        .buttonStyle(KucukDugme())
                        .disabled(calisiyor || kod.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if grupta {
                    HStack(spacing: 8) {
                        TextField("Grup adı", text: $ad).kutu()
                        Button("Adı kaydet") {
                            Task {
                                calisiyor = true
                                baglam.bildir(await veri.grupAdiDegistir(ad, ekip: ekip), "Grup adı değişti.")
                                calisiyor = false
                            }
                        }
                        .buttonStyle(KucukDugme())
                        .disabled(calisiyor || GrupIsi.adTemizle(ad).isEmpty || GrupIsi.adTemizle(ad) == b.grupAdi)
                    }
                    Button("Bu kişiyi gruptan çıkar", role: .destructive) { cikarSor = true }
                        .buttonStyle(KucukDugme(renk: Tema.olumsuz))
                        .disabled(calisiyor)
                }
            }
        }
        .kart()
        .onAppear { if ad.isEmpty { ad = b.grupAdi } }
        .onChange(of: b.grupAdi) { _, yeni in ad = yeni }
        .confirmationDialog("Başvuru şu an \"\(tasima ?? "")\" grubunda. Bu gruba taşınsın mı?",
                            isPresented: Binding(get: { tasima != nil }, set: { if !$0 { tasima = nil } }), titleVisibility: .visible) {
            Button("Taşı") { Task { await bagla(tasimaOnayli: true) } }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog("\(b.adSoyad) \"\(b.grupAdi)\" grubundan çıkarılsın mı? Başvurusu olduğu gibi kalır.",
                            isPresented: $cikarSor, titleVisibility: .visible) {
            Button("Çıkar", role: .destructive) {
                Task {
                    calisiyor = true
                    baglam.bildir(await veri.gruptanCikar(ekip: ekip), "Gruptan çıkarıldı.")
                    calisiyor = false
                }
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private func bagla(tasimaOnayli: Bool) async {
        calisiyor = true
        let r = await veri.grupBagla(kod: kod, tasimaOnayli: tasimaOnayli, ekip: ekip)
        calisiyor = false
        switch r {
        case .tamam(let m): kod = ""; baglam.bildir(nil, m)
        case .sor(let ad): tasima = ad
        case .hata(let m): baglam.bildir(m, "")
        }
    }
}
