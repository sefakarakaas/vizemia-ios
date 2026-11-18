import SwiftUI
import VizeMiaCekirdek

/// Saklama süresi ve elle silme (yalnız yönetici; panel: "Saklama süresi" ve "Sil").
/// Silinen başvurudan müşteri arşivinde yalnız ad soyad, telefon, e-posta, ülke/sonuç,
/// işlem geçmişi, verilen fiyat, ödemeler ve harcamalar kalır.
struct SaklamaKarti: View {
    let veri: BasvuruDetayVerisi
    let b: Basvuru
    let baglam: EkBaglami
    let silindi: () -> Void
    @Environment(EkipOturumu.self) private var ekip
    @State private var gun = Date()
    @State private var gunVar = false
    @State private var bekletme = false
    @State private var gerekce = ""
    @State private var calisiyor = false
    @State private var silSor = false
    @State private var silOnay = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saklama süresi").font(.headline).foregroundStyle(Tema.lacivert)
            Toggle("Silinme tarihi", isOn: $gunVar).tint(Tema.turkuaz)
            if gunVar {
                DatePicker("Tarih", selection: $gun, displayedComponents: .date)
                    .environment(\.locale, Tr.yerel)
            }
            Toggle("Silmeyi beklet (itiraz, dava vb.)", isOn: $bekletme).tint(Tema.turkuaz)
            Alan(etiket: "Gerekçe", yardim: "Zorunlu; geçmişe yazılır.") {
                TextField("Gerekçe", text: $gerekce).kutu()
            }
            Button("Güncelle") {
                Task {
                    calisiyor = true
                    let g = gunVar ? Tr.isoGun(gun, takvim: Tr.takvim) : ""
                    let h = await veri.saklamaKaydet(gun: g, bekletme: bekletme, gerekce: gerekce, ekip: ekip)
                    calisiyor = false
                    baglam.bildir(h, "Saklama bilgisi güncellendi.")
                }
            }
            .buttonStyle(KucukDugme())
            .disabled(calisiyor || gerekce.trimmingCharacters(in: .whitespaces).isEmpty)

            Divider()
            Text("Başvuruyu ve bütün kişisel verilerini kalıcı olarak siler; müşteri arşivinde yalnız ad soyad, telefon, e-posta, ülke/sonuç, işlem geçmişi, verilen fiyat, ödemeler ve harcamalar kalır. Kasa defteri değişmez.")
                .font(.caption).foregroundStyle(Tema.govde)
            Button(role: .destructive) { silOnay = ""; silSor = true } label: {
                if calisiyor { ProgressView() } else { Label("Başvuruyu kalıcı olarak sil", systemImage: "trash") }
            }
            .buttonStyle(KucukDugme(renk: Tema.olumsuz))
            .disabled(calisiyor)
        }
        .kart()
        .onAppear {
            bekletme = b.bekletiliyor
            if let s = b.silinecek { gun = s; gunVar = true }
        }
        .alert("\(b.adSoyad) kalıcı olarak silinsin mi?", isPresented: $silSor) {
            TextField("Onay için SİL yazın", text: $silOnay)
            Button("Kalıcı olarak sil", role: .destructive) {
                guard silOnay.trimmingCharacters(in: .whitespaces).uppercased(with: Tr.yerel) == "SİL" else {
                    baglam.bildir("Onay yazısı yanlış; silinmedi.", "")
                    return
                }
                Task {
                    calisiyor = true
                    let h = await veri.sil(ekip: ekip)
                    calisiyor = false
                    if let h { baglam.bildir(h, "") } else { silindi() }
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bu işlem geri alınamaz. TCKN, pasaport, adres, form cevapları ve belgeler silinir.")
        }
    }
}
