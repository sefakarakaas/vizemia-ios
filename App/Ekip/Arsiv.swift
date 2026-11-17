import SwiftUI
import VizeMiaCekirdek

/// Müşteri arşivi (panel: #/arsiv): KVKK ile silinen başvurulardan kalan kayıtlar.
@MainActor
@Observable
final class ArsivVerisi {
    private(set) var kayitlar: [ArsivKaydi] = []
    private(set) var bulunanlar: [ArsivKaydi] = []
    private(set) var yukleniyor = false
    private(set) var hata: String?
    private var yuklendi = false

    /// Son silinen 100 kayıt (panel 1000 okuyor; okuma kotası için 100 + sunucuda arama).
    func yukle(_ ekip: EkipOturumu) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") { ornek(); return }
        #endif
        guard !yuklendi, !yukleniyor else { return }
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let f = try await ekip.istemci()
            kayitlar = try await f.sorgu(koleksiyon: "musteriArsivi", sirala: ("silinme", .azalan), sinir: 100)
                .map { ArsivKaydi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            yuklendi = true
            hata = nil
        } catch FirestoreHatasi.izinYok {
            hata = "Müşteri arşivini görme yetkiniz yok."
        } catch {
            hata = "Arşiv yüklenemedi. İnternet bağlantınızı kontrol edin."
        }
    }

    /// Klavyede "Ara": kayıtlardaki arama anahtarlarıyla sunucuda (eski kayıtlar da bulunur).
    func ara(_ terim: String, ekip: EkipOturumu) async {
        let anahtar = MusteriArsivi.aramaAnahtari(terim)
        guard !anahtar.isEmpty, let f = try? await ekip.istemci() else { bulunanlar = []; return }
        let l = (try? await f.sorgu(koleksiyon: "musteriArsivi", kosullar: [FirestoreIstemci.Kosul("anahtarlar", "ARRAY_CONTAINS", .metin(anahtar))],
                                    sinir: 50)) ?? []
        bulunanlar = l.map { ArsivKaydi(kimlik: $0.kimlik, alanlar: $0.alanlar) }
    }

    func gruplar(_ terim: String) -> [[ArsivKaydi]] {
        var l = kayitlar.filter { MusteriArsivi.eslesir($0, terim) }
        let var_ = Set(l.map(\.id))
        l += bulunanlar.filter { !var_.contains($0.id) && MusteriArsivi.eslesir($0, terim) }
        return MusteriArsivi.gruplar(terim.isEmpty ? l : l)
    }

    func sil(_ k: ArsivKaydi, ekip: EkipOturumu) async -> String? {
        guard let c = ekip.calisan else { return "Oturum bulunamadı." }
        do {
            try await ekip.istemci().isle([
                .sil(yol: "musteriArsivi/\(k.id)"),
                .olustur(yol: "audit/\(FirestoreIstemci.yeniKimlik())",
                         alanlar: IslemKaydi.alanlar(eylem: "arsiv.delete", hedef: k.id,
                                                    ayrinti: k.adSoyad + (k.takipKodu.isEmpty ? "" : " · \(k.takipKodu)"), calisan: c),
                         zaman: ["at"]),
            ])
            kayitlar.removeAll { $0.id == k.id }
            bulunanlar.removeAll { $0.id == k.id }
            return nil
        } catch {
            return "Silinemedi (yalnız yönetici silebilir)."
        }
    }

    #if DEBUG
    private func ornek() {
        guard kayitlar.isEmpty else { return }
        let gun = 86_400.0, simdi = Date()
        func k(_ id: String, _ ad: String, _ soyad: String, _ ulke: String, _ statu: String, _ once: Double) -> ArsivKaydi {
            var a: [String: FSDeger] = [:]
            a["ad"] = .metin(ad); a["soyad"] = .metin(soyad); a["telefon"] = .metin("+905000000099"); a["eposta"] = .metin("")
            a["ulkeAdi"] = .metin(ulke); a["sonStatu"] = .metin(statu); a["takipKodu"] = .metin("2025-0\(id)123")
            a["silinme"] = .zaman(simdi.addingTimeInterval(-once * gun)); a["silmeTuru"] = .metin("otomatik")
            a["fiyat"] = .harita(["tutar": .tam(4000), "paraBirimi": .metin("TRY")])
            a["odemeler"] = .dizi([.harita(["tarih": .metin("2025-06-02"), "tutar": .tam(4000), "paraBirimi": .metin("TRY"),
                                            "yontem": .metin("havale"), "kim": .metin("Sefa Karakaş")])])
            a["islemler"] = .dizi([.harita(["metin": .metin("Evrak Bekleniyor → Pasaport Teslim Edildi"), "kim": .metin("Ezgi"),
                                            "at": .zaman(simdi.addingTimeInterval(-(once + 60) * gun))])])
            return ArsivKaydi(kimlik: id, alanlar: a)
        }
        kayitlar = [k("1", "KEMAL", "YILDIZ", "İspanya", "Pasaport Teslim Edildi", 3), k("2", "KEMAL", "YILDIZ", "Almanya", "Pasaport Teslim Edildi", 400)]
    }
    #endif
}

struct ArsivEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @State private var veri = ArsivVerisi()
    @State private var arama = ""
    @State private var silinecek: ArsivKaydi?
    @State private var bildiri: String?

    var body: some View {
        Group {
            if !ekip.yapabilir("arsiv.view") {
                YetkiYok(ad: "Müşteri arşivi")
            } else {
                let gruplar = veri.gruplar(arama)
                List {
                    Section {
                        Text("KVKK ile silinen başvurulardan kalan kayıtlar: ad soyad, telefon, e-posta, vize sonucu, işlemler, fiyat ve ödemeler. TCKN, pasaport, adres ve belgeler saklanmaz.")
                            .font(.caption).foregroundStyle(Tema.govde)
                    }
                    if let h = veri.hata { HataMetni(metin: h) }
                    if let b = bildiri { Text(b).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.olumluKoyu) }
                    if gruplar.isEmpty && veri.hata == nil {
                        Text(veri.yukleniyor ? "Yükleniyor…" : "Kayıt yok.").foregroundStyle(Tema.govde)
                    }
                    ForEach(gruplar, id: \.first?.id) { g in
                        Section { musteri(g) }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $arama, prompt: "Ad, telefon, e-posta ya da takip kodu")
                .onSubmit(of: .search) { Task { await veri.ara(arama, ekip: ekip) } }
            }
        }
        .navigationTitle("Müşteri arşivi")
        .task { await veri.yukle(ekip) }
        .confirmationDialog("Arşiv kaydı kalıcı olarak silinsin mi?", isPresented: Binding(
            get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }), titleVisibility: .visible) {
            Button("Kalıcı olarak sil", role: .destructive) {
                guard let k = silinecek else { return }
                Task { bildiri = await veri.sil(k, ekip: ekip) ?? "Arşiv kaydı silindi." }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Ör. müşterinin silme talebi. Geri alınamaz.")
        }
    }

    @ViewBuilder
    private func musteri(_ g: [ArsivKaydi]) -> some View {
        if let son = g.first {
            VStack(alignment: .leading, spacing: 6) {
                Text(son.adSoyad.isEmpty ? "—" : son.adSoyad).font(.headline).foregroundStyle(Tema.lacivert)
                Text([son.telefon, son.eposta].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(Tema.govde).textSelection(.enabled)
                Text("En son: \(son.ulkeAdi.isEmpty ? son.ulke : son.ulkeAdi) · \(son.sonStatu.isEmpty ? "—" : son.sonStatu)")
                    .font(.caption).foregroundStyle(Tema.govde)
                let odeme = MusteriArsivi.toplam(g.flatMap { $0.odemeler.map { ($0.tutar, $0.paraBirimi) } })
                Text("\(g.count) başvuru · ödeme: \(toplamYazi(odeme))").font(.caption.weight(.semibold)).foregroundStyle(Tema.mavi)
            }
            .padding(.vertical, 4)
            ForEach(g) { k in kayit(k, enSon: k.id == son.id) }
        }
    }

    private func kayit(_ k: ArsivKaydi, enSon: Bool) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                satir("Verilen fiyat", k.fiyat.map { "\(Para.yazi($0.tutar)) \($0.paraBirimi)" + ($0.aciklama.isEmpty ? "" : " — \($0.aciklama)") } ?? "—")
                satir("Alınan ödeme", toplamYazi(MusteriArsivi.toplam(k.odemeler.map { ($0.tutar, $0.paraBirimi) })))
                if !k.giderler.isEmpty { satir("Müşteri için harcanan", toplamYazi(MusteriArsivi.toplam(k.giderler.map { ($0.tutar, $0.paraBirimi) }))) }
                if let r = k.randevu { satir("Randevu", Tr.kisaTarih(r)) }
                if !k.konsTakipKodu.isEmpty { satir("Konsolosluk takip kodu", k.konsTakipKodu) }
                satir("Silinme", (k.silinme.map { Tr.tarihSaat($0) } ?? "—") + (k.silmeTuru == "manuel" ? " (elle, \(k.silenAd))" : " (otomatik)"))
                if !k.silmeSebebi.isEmpty { satir("Silme sebebi", k.silmeSebebi) }
                if !k.odemeler.isEmpty {
                    Text("Ödemeler").font(.caption.weight(.bold)).foregroundStyle(Tema.lacivert).padding(.top, 4)
                    ForEach(Array(k.odemeler.enumerated()), id: \.offset) { _, o in
                        Text([Tr.tarih(o.tarih).map { Tr.kisaTarih($0) } ?? o.tarih,
                              o.tutar.map { "\(Para.yazi($0)) \(o.paraBirimi)" } ?? "", OdemeKurali.yontemAdi(o.yontem),
                              o.onayKodu.isEmpty ? "" : "Onay: \(o.onayKodu)", o.kim].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Tema.govde)
                    }
                }
                if !k.islemler.isEmpty {
                    Text("Yapılan işlemler (\(k.islemler.count))").font(.caption.weight(.bold)).foregroundStyle(Tema.lacivert).padding(.top, 4)
                    ForEach(Array(k.islemler.prefix(30).enumerated()), id: \.offset) { _, l in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.metin).font(.caption).foregroundStyle(Tema.lacivert)
                            Text([l.zaman.map { Tr.tarihSaat($0) } ?? "", l.kim].filter { !$0.isEmpty }.joined(separator: " — "))
                                .font(.caption2).foregroundStyle(Tema.silik)
                        }
                    }
                }
                HStack(spacing: 8) {
                    if ekip.yapabilir("app.create") {
                        NavigationLink(value: EkipRota.arsivdenBasvuru(k.id)) {
                            Label("Yeniden başvuru aç", systemImage: "arrow.uturn.left")
                        }
                        .buttonStyle(KucukDugme())
                    }
                    if ekip.calisan?.yonetici ?? false {
                        Button(role: .destructive) { silinecek = k } label: { Label("Arşivden sil", systemImage: "trash") }
                            .buttonStyle(KucukDugme(renk: Tema.olumsuz))
                    }
                }
                .padding(.top, 6)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(k.ulkeAdi.isEmpty ? k.ulke : k.ulkeAdi) — \(k.sonStatu.isEmpty ? "—" : k.sonStatu)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                    if enSon { Etiket(metin: "En son", renk: Tema.turkuaz) }
                }
                Text([k.kaynak == "talep" ? "talep" : k.takipKodu, (k.acilis ?? k.silinme).map { Tr.kisaTarih($0) } ?? ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Tema.govde)
            }
        }
    }

    private func satir(_ ad: String, _ deger: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(ad).font(.caption).foregroundStyle(Tema.govde).frame(width: 130, alignment: .leading)
            Text(deger).font(.caption.weight(.semibold)).foregroundStyle(Tema.lacivert)
            Spacer(minLength: 0)
        }
    }

    private func toplamYazi(_ t: [(String, Double)]) -> String {
        t.isEmpty ? "—" : t.map { "\(Para.yazi($0.1)) \($0.0)" }.joined(separator: " + ")
    }
}
