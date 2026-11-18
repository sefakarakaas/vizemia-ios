import SwiftUI
import VizeMiaCekirdek

/// Firma maili (panel: #/firma): gönderilen tanıtım mailleri ve cevaplar;
/// firmaya cevap. Toplu tanıtım gönderimi (TXT yükleme, İYS kaydı) panelden.
struct FirmaMailiEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @State private var mailler: [FirmaMaili] = []
    @State private var ara = ""
    @State private var tur = ""
    @State private var yukleniyor = false
    @State private var hata: String?
    @State private var acik: FirmaMaili?
    @State private var bildiri: String?

    /// Ekranda gösterilen kadar okunur (her koleksiyondan).
    static let sinir = 100

    private var gorunen: [FirmaMaili] {
        let t = ara.trimmingCharacters(in: .whitespaces).lowercased(with: Tr.yerel)
        return mailler.filter { m in
            (tur.isEmpty || m.tur == tur)
                && (t.isEmpty || "\(m.firma) \(m.eposta) \(m.yazan)".lowercased(with: Tr.yerel).contains(t))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tacir firmalara \(FirmaMaili.gonderen) adresinden tanıtım maili. Uygulamada gönderilenler ve firmaya cevap var; yeni firma yükleme, İYS kaydı ve toplu gönderim panelden.")
                    .font(.caption).foregroundStyle(Tema.govde)
                TextField("Firma, e-posta, gönderen", text: $ara).autocorrectionDisabled().kutu()
                Picker("Tür", selection: $tur) {
                    Text("Hepsi").tag("")
                    Text("Tanıtım").tag("tanitim")
                    Text("Cevap").tag("yanit")
                }
                .pickerStyle(.segmented)
                if let h = hata { AlanHatasi(metin: h) }
                if yukleniyor && mailler.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if gorunen.isEmpty {
                    ContentUnavailableView("Kayıt yok", systemImage: "building.2")
                } else {
                    VStack(spacing: 0) {
                        ForEach(gorunen) { m in
                            Button { acik = m } label: { satir(m) }.buttonStyle(.plain)
                            if m.id != gorunen.last?.id { Divider() }
                        }
                    }
                    .kart()
                }
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .navigationTitle("Firma maili")
        .navigationBarTitleDisplayMode(.inline)
        .task { if mailler.isEmpty { await yukle() } }
        .refreshable { await yukle() }
        .sheet(item: $acik) { m in
            FirmaMailiAyrintisi(mail: m, oncekiCevaplar: mailler.filter { $0.tur == "yanit" && $0.firmaId == m.firmaId }) { mesaj in
                acik = nil
                bildiri = mesaj
                Task { await yukle() }
            }
        }
        .overlay(alignment: .top) {
            if let m = bildiri {
                Label(m, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Tema.olumluKoyu, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        bildiri = nil
                    }
            }
        }
        .animation(Hareket.yay, value: bildiri)
    }

    private func satir(_ m: FirmaMaili) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: m.tur == "yanit" ? "arrowshape.turn.up.left.fill" : "megaphone.fill")
                .foregroundStyle(m.tur == "yanit" ? Tema.turkuaz : Tema.mavi)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.firma).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                Text(m.eposta).font(.caption).foregroundStyle(Tema.govde)
                Text([m.turAdi, (m.gonderilme ?? m.zaman).map { Tr.tarihSaat($0) } ?? "", m.yazan].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Tema.silik)
            }
            Spacer(minLength: 0)
            Etiket(metin: m.durumAdi, renk: m.durum == "gonderildi" ? Tema.olumlu : (m.durum == "kuyrukta" ? Tema.mavi : Tema.olumsuz))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func yukle() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { mailler = Self.ornek(); return }
        #endif
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let f = try await ekip.istemci()
            async let t = f.sorgu(koleksiyon: "firmaMailleri", sirala: ("at", .azalan), sinir: Self.sinir)
            async let y = f.sorgu(koleksiyon: "firmaYanitlari", sirala: ("at", .azalan), sinir: Self.sinir)
            let l = try await t.map { FirmaMaili(kimlik: $0.kimlik, tur: "tanitim", alanlar: $0.alanlar) }
                + (try await y).map { FirmaMaili(kimlik: $0.kimlik, tur: "yanit", alanlar: $0.alanlar) }
            mailler = l.sorted { ($0.zaman ?? .distantPast) > ($1.zaman ?? .distantPast) }
            hata = nil
        } catch {
            hata = KasaVerisi.mesaj(error, "Firma mailleri yüklenemedi.")
        }
    }

    #if DEBUG
    static func ornek() -> [FirmaMaili] {
        [
            FirmaMaili(kimlik: String(repeating: "b", count: 64), tur: "tanitim", alanlar: [
                "firma": .metin("Örnek Makine A.Ş."), "eposta": .metin("info@ornekmakine.com"), "konu": .metin("Yurt dışı fuar vizelerinizde yanınızdayız"),
                "govde": .metin("Sayın Yetkili,\n\nFuar ve iş seyahatleriniz için vize süreçlerinizi üstleniyoruz."), "durum": .metin("gonderildi"),
                "byName": .metin("Sefa Karakaş"), "at": .zaman(Date().addingTimeInterval(-86_400 * 3))]),
            FirmaMaili(kimlik: "y1", tur: "yanit", alanlar: [
                "firmaId": .metin(String(repeating: "b", count: 64)), "firma": .metin("Örnek Makine A.Ş."), "eposta": .metin("info@ornekmakine.com"),
                "konu": .metin("Ynt: Yurt dışı fuar vizelerinizde yanınızdayız"), "govde": .metin("Merhaba,\n\nFiyat bilgisi ektedir."),
                "durum": .metin("kuyrukta"), "byName": .metin("Sefa Karakaş"), "at": .zaman(Date().addingTimeInterval(-600))]),
        ]
    }
    #endif
}

/// Mailin içeriği ve (yetki varsa) firmaya cevap.
struct FirmaMailiAyrintisi: View {
    let mail: FirmaMaili
    let oncekiCevaplar: [FirmaMaili]
    let gonderildi: (String) -> Void
    @Environment(EkipOturumu.self) private var ekip
    @Environment(\.dismiss) private var kapat
    @State private var yaziyor = false
    @State private var konu = ""
    @State private var govde = FirmaMailMetni.varsayilanGovde
    @State private var hata: String?
    @State private var gonderiliyor = false
    @State private var onay = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mail.firma).font(.headline).foregroundStyle(Tema.lacivert)
                        Text("\(mail.eposta) · \(mail.turAdi) · \(mail.durumAdi)").font(.caption).foregroundStyle(Tema.govde)
                        if !mail.hata.isEmpty { AlanHatasi(metin: mail.hata) }
                        Divider()
                        Text(mail.konu).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                        Text(mail.govde).font(.subheadline).foregroundStyle(Tema.govde).textSelection(.enabled)
                    }
                    .kart()
                    if !oncekiCevaplar.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Önceki cevaplar (\(oncekiCevaplar.count))").font(.subheadline.weight(.bold)).foregroundStyle(Tema.lacivert)
                            ForEach(oncekiCevaplar) { y in
                                Text("\(y.zaman.map { Tr.tarihSaat($0) } ?? "") · \(y.konu) · \(y.durumAdi) · \(y.yazan)")
                                    .font(.caption).foregroundStyle(Tema.govde)
                            }
                        }
                        .kart()
                    }
                    if ekip.yapabilir("firma.send") {
                        if yaziyor { cevapAlani } else {
                            Button { hazirla(); withAnimation(Hareket.yay) { yaziyor = true } } label: {
                                Label("Cevap yaz", systemImage: "arrowshape.turn.up.left")
                            }
                            .buttonStyle(AnaDugme())
                        }
                    }
                }
                .padding(Tema.bosluk)
            }
            .formKlavyesi()
            .ekranZemini()
            .navigationTitle(mail.tur == "yanit" ? "Cevap" : "Tanıtım maili")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } } }
            .confirmationDialog("\(mail.eposta) adresine cevap gönderilecek.", isPresented: $onay, titleVisibility: .visible) {
                Button("Gönder") { Task { await gonder() } }
                Button("Vazgeç", role: .cancel) {}
            }
        }
    }

    private var cevapAlani: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cevap: kime \(mail.eposta), gönderen \(FirmaMaili.gonderen). Altbilgide yalnız logo ve iletişim bilgileri olur; İYS, unvan, MERSİS ve listeden çık satırı eklenmez.")
                .font(.caption).foregroundStyle(Tema.govde)
            Alan(etiket: "Konu") { TextField("Konu", text: $konu).kutu() }
            Alan(etiket: "Mesaj", yardim: "Boş satır paragraf olur; \"•\" ile başlayan satırlar liste olur.") {
                TextField("Mesaj", text: $govde, axis: .vertical).lineLimit(8...20).kutu()
            }
            if let h = hata { AlanHatasi(metin: h) }
            Button {
                let m = FirmaMailMetni.yanit(konu: konu, govde: govde, genel: ekip.firmaIletisimi)
                if m.konu.isEmpty || m.govde.isEmpty { hata = "Konu ve mesaj boş olamaz." } else { hata = nil; onay = true }
            } label: {
                if gonderiliyor { HStack(spacing: 8) { ProgressView().tint(.white); Text("Gönderiliyor…") } } else { Text("Gönder") }
            }
            .buttonStyle(AnaDugme())
            .disabled(gonderiliyor)
        }
        .kart()
    }

    private func hazirla() {
        guard konu.isEmpty else { return }
        // Son cevabın konusu, yoksa tanıtım mailinin konusuna "Ynt:".
        let son = oncekiCevaplar.max { ($0.zaman ?? .distantPast) < ($1.zaman ?? .distantPast) }
        konu = son?.konu ?? FirmaMailMetni.yanitKonusu(mail.konu)
    }

    private func gonder() async {
        guard let c = ekip.calisan,
              let y = FirmaMaili.cevap(firmaId: mail.firmaId, firma: mail.firma, eposta: mail.eposta, konu: konu, govde: govde,
                                       genel: ekip.firmaIletisimi, calisan: c) else { hata = "Konu ve mesaj boş olamaz."; return }
        gonderiliyor = true
        defer { gonderiliyor = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { gonderildi("Cevap gönderim sırasına alındı."); return }
        #endif
        do {
            try await ekip.istemci().isle(y)
            gonderildi("Cevap gönderim sırasına alındı.")
        } catch {
            hata = KasaVerisi.mesaj(error, "Gönderilemedi. İnternet bağlantınızı kontrol edin.")
        }
    }
}
