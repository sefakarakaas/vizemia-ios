import SwiftUI
import VizeMiaCekirdek

/// Müşterinin bildirim tercihleri (panel: BildirimTercihPanel): otomatik mesajların
/// hangi yoldan gideceği. Değiştirmek için düzenleme ve hassas veri izni gerekir.
struct BildirimTercihKarti: View {
    let veri: BasvuruDetayVerisi
    let baglam: EkBaglami
    @Environment(EkipOturumu.self) private var ekip
    @State private var k = Kanallar()
    @State private var eposta = ""
    @State private var hazir = false
    @State private var calisiyor = false
    @State private var durum: String?

    private var degisir: Bool { ekip.yapabilir("app.edit") && ekip.yapabilir("app.sensitive") }
    private var telefonVar: Bool { !(veri.form?["phone"]?.metinDegeri ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bildirim tercihleri").font(.headline).foregroundStyle(Tema.lacivert)
            Text("Randevu, evrak hatırlatması, form bağlantısı ve statü mesajları yalnız açık yollardan gider. Elle yazılan mesajlar danışmanın seçimidir.")
                .font(.caption).foregroundStyle(Tema.govde)
            anahtar("WhatsApp", telefonVar ? "Danışman WhatsApp'tan gönderir" : "Telefon numarası yok (Düzenle'den ekleyin).", $k.wa, telefonsuz: !telefonVar)
            anahtar("SMS", telefonVar ? "Otomatik SMS" : "Telefon numarası yok (Düzenle'den ekleyin).", $k.sms, telefonsuz: !telefonVar)
            anahtar("E-posta", "Otomatik e-posta", $k.email, telefonsuz: false)
            if k.email {
                TextField("musteri@ornek.com", text: $eposta)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .kutu()
                    .disabled(!degisir)
            }
            if let d = durum { Text(d).font(.caption).foregroundStyle(Tema.govde) }
            if degisir {
                Button {
                    Task {
                        calisiyor = true
                        let r = await veri.tercihKaydet(k, eposta: eposta, ekip: ekip)
                        calisiyor = false
                        if r.tamam { durum = "Kayıtlı: \(BildirimTercihi.ozet(k))"; baglam.bildir(nil, r.mesaj) } else { baglam.bildir(r.mesaj, "") }
                    }
                } label: { if calisiyor { ProgressView() } else { Text("Kaydet") } }
                .buttonStyle(KucukDugme())
                .disabled(calisiyor || !BildirimTercihi.degisti(veri.form, k, eposta: eposta))
            }
        }
        .kart()
        .onAppear {
            guard !hazir else { return }
            k = BildirimTercihi.oku(veri.form).kanallar
            if !telefonVar { k.wa = false; k.sms = false }
            eposta = veri.form?["email"]?.metinDegeri ?? ""
            hazir = true
        }
    }

    private func anahtar(_ ad: String, _ aciklama: String, _ deger: Binding<Bool>, telefonsuz: Bool) -> some View {
        Toggle(isOn: deger) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                Text(aciklama).font(.caption2).foregroundStyle(Tema.silik)
            }
        }
        .tint(Tema.turkuaz)
        .disabled(!degisir || telefonsuz)
    }
}
