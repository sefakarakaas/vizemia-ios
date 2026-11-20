import SwiftUI
import VizeMiaCekirdek

/// Panelin bölümleri (panel/js/ana-menu.js ile aynı sıra ve izinler).
struct EkipBolumu: Identifiable {
    struct Oge: Identifiable {
        let id: String
        let ad: String
        let simge: String
        /// İzinlerden biri yeter ("a|b"); boşsa herkes.
        let izin: String
        let yonetici: Bool
        /// Uygulamadaki ekranı; yoksa "yakında".
        let rota: EkipRota?
    }

    let id: String
    let ad: String
    let simge: String
    let ogeler: [Oge]

    static let hepsi: [EkipBolumu] = [
        EkipBolumu(id: "musteriler", ad: "Müşteriler", simge: "person.2.fill", ogeler: [
            Oge(id: "basvurular", ad: "Başvurular", simge: "folder.fill", izin: "app.view", yonetici: false, rota: .basvurular),
            Oge(id: "talepler", ad: "Talepler", simge: "phone.fill", izin: "lead.view", yonetici: false, rota: .talepler),
            Oge(id: "armut", ad: "Armut", simge: "leaf.fill", izin: "armut.view|armut.manage", yonetici: false, rota: .armut),
            Oge(id: "arsiv", ad: "Müşteri arşivi", simge: "archivebox.fill", izin: "arsiv.view", yonetici: false, rota: .arsiv),
            Oge(id: "destek", ad: "Destek talepleri", simge: "lifepreserver.fill", izin: "support.view", yonetici: false, rota: .destekler),
            Oge(id: "rehber", ad: "Görüşme rehberi", simge: "book.fill", izin: "", yonetici: false, rota: .rehber),
        ]),
        EkipBolumu(id: "kasa", ad: "Kasa", simge: "turkishlirasign.circle.fill", ogeler: [
            Oge(id: "kasa", ad: "Kasa ve raporlar", simge: "turkishlirasign.circle.fill", izin: "kasa.view|kasa.gider|kasa.rutin", yonetici: false, rota: .kasa),
        ]),
        EkipBolumu(id: "iletiler", ad: "İletiler", simge: "envelope.fill", ogeler: [
            Oge(id: "bildirimler", ad: "Bildirimler (WhatsApp)", simge: "message.fill", izin: "app.sensitive", yonetici: false, rota: .bildirimler),
            Oge(id: "bildirimGonder", ad: "Bildirim gönder", simge: "paperplane.fill", izin: "", yonetici: false, rota: .bildirimGonder(nil)),
            Oge(id: "eposta", ad: "E-posta", simge: "envelope.fill", izin: "eposta.send|eposta.kampanya", yonetici: false, rota: .eposta),
            Oge(id: "firma", ad: "Firmalara mail", simge: "building.2.fill", izin: "firma.view|firma.send", yonetici: false, rota: .firma),
        ]),
        EkipBolumu(id: "sosyal", ad: "Sosyal medya", simge: "megaphone.fill", ogeler: [
            Oge(id: "icerik", ad: "Blog ve SSS", simge: "doc.text.fill", izin: "content.draft|content.publish", yonetici: false, rota: .icerikler),
            Oge(id: "sosyal", ad: "Sosyal medya", simge: "camera.fill", izin: "social.view", yonetici: false, rota: .sosyal),
            Oge(id: "vitrin", ad: "Vitrin (ana sayfa)", simge: "photo.on.rectangle.angled", izin: "vitrin.edit|vitrin.publish", yonetici: false, rota: .vitrin),
            Oge(id: "havuz", ad: "Fotoğraf havuzu", simge: "photo.stack.fill", izin: "havuz.manage|vitrin.edit|vitrin.publish", yonetici: false, rota: .havuz),
        ]),
        EkipBolumu(id: "takvim", ad: "Takvim", simge: "calendar", ogeler: [
            Oge(id: "takvim", ad: "Takvim", simge: "calendar", izin: "app.view|lead.view", yonetici: false, rota: .takvim),
        ]),
        EkipBolumu(id: "ayarlar", ad: "Ayarlar", simge: "gearshape.fill", ogeler: [
            Oge(id: "surec", ad: "Süreç adımları", simge: "list.number", izin: "surec.edit|vitrin.edit|vitrin.publish", yonetici: false, rota: .surec),
            Oge(id: "ayarlar", ad: "Ayarlar", simge: "gearshape.fill", izin: "", yonetici: true, rota: .ayarlar),
            Oge(id: "kullanicilar", ad: "Kullanıcılar", simge: "person.3.fill", izin: "", yonetici: true, rota: .kullanicilar),
            Oge(id: "kayitlar", ad: "İşlem kayıtları", simge: "list.bullet.rectangle.fill", izin: "", yonetici: true, rota: .islemKayitlari),
        ]),
    ]

    static func bul(_ id: String) -> EkipBolumu? { hepsi.first { $0.id == id } }
}

extension EkipOturumu {
    func acabilir(_ o: EkipBolumu.Oge) -> Bool {
        if o.yonetici { return calisan?.yonetici ?? false }
        return o.izin.isEmpty || o.izin.split(separator: "|").contains { yapabilir(String($0)) }
    }

    /// Kutunun açılacağı yer: tek ekranlı bölümde doğrudan ekranı.
    func hedef(_ b: EkipBolumu) -> EkipRota {
        if b.ogeler.count == 1, let o = b.ogeler.first { return o.rota ?? .yakinda(o.ad) }
        return .bolum(b.id)
    }
}

/// Ekibin ana sayfası: "Günaydın, Sefa", bugünün özeti, panelin 6 kutusu.
struct EkipAnaSayfa: View {
    @Binding var sekme: EkipSekme
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var veri

    private static let tarihBicimi: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = TimeZone(identifier: "Europe/Istanbul")
        f.dateFormat = "d MMMM yyyy, EEEE"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ozet.belirme(1)
                if !siradakiler.isEmpty { siradaki.belirme(2) }
                kutular
                if let h = veri.hata { HataMetni(metin: h) }
            }
            .padding(Tema.bosluk)
        }
        .ekranZemini()
        .refreshable { await veri.yukle(ekip, zorla: true) }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { ustSerit }
    }

    /// Sol üstte kişiye özel karşılama.
    private var ustSerit: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.everyMinute) { z in
                    Text(Selamlama.cumle(saat: Calendar.current.component(.hour, from: z.date), ad: ekip.calisan?.ilkAd ?? ""))
                        .font(.vitrin(24))
                        .foregroundStyle(Tema.lacivert)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(EkipAnaSayfa.tarihBicimi.string(from: Date()))
                    .font(.caption)
                    .foregroundStyle(Tema.govde)
            }
            .belirme(0)
            Spacer()
            if veri.yukleniyor {
                ProgressView().controlSize(.small).transition(.opacity)
            }
            Image("Logo").resizable().scaledToFit().frame(height: 26).opacity(0.9)
        }
        .padding(.horizontal, Tema.bosluk)
        .padding(.vertical, 10)
        .background { Tema.zemin.ignoresSafeArea(edges: .top) }
        .overlay(alignment: .bottom) { Rectangle().fill(Tema.soluk).frame(height: 1) }
        .animation(Hareket.hizli, value: veri.yukleniyor)
    }

    // MARK: Özet

    private var ozet: some View {
        let o = veri.ozet
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            OzetKutusu(sayi: o.acil, ad: "Hemen aranmak isteyen", simge: "bolt.fill", vurgu: o.acil > 0 ? Tema.olumsuz : Tema.silik) { sekme = .talepler }
            OzetKutusu(sayi: o.bugun, ad: "Bugün aranacak", simge: "phone.fill", vurgu: Tema.turkuaz) { sekme = .talepler }
            OzetKutusu(sayi: o.geciken, ad: "Gecikmiş arama", simge: "exclamationmark.triangle.fill", vurgu: o.geciken > 0 ? Color(hex: 0xd98a00) : Tema.silik) { sekme = .talepler }
            NavigationLink(value: EkipRota.destekler) {
                OzetIcerik(sayi: veri.acikDestek, ad: "Yeni destek talebi", simge: "lifepreserver.fill", vurgu: Tema.mavi)
            }
            .buttonStyle(KartDugmesi())
        }
    }

    private var siradakiler: [Talep] { Array(veri.talepler.filter { $0.durum == "new" }.prefix(4)) }

    private var siradaki: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sıradaki aramalar").font(.headline).foregroundStyle(Tema.lacivert)
                Spacer()
                Button("Tümü") { sekme = .talepler }.font(.subheadline.weight(.semibold)).foregroundStyle(Tema.mavi)
            }
            VStack(spacing: 0) {
                ForEach(Array(siradakiler.enumerated()), id: \.element.id) { i, t in
                    NavigationLink(value: EkipRota.talep(t.yol)) {
                        TalepSatiri(talep: t, bugun: veri.bugun)
                    }
                    .buttonStyle(.plain)
                    if i < siradakiler.count - 1 { Divider().padding(.leading, 52) }
                }
            }
            .kart(dolgu: 0)
        }
    }

    // MARK: Kutular

    private var kutular: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Panel").font(.headline).foregroundStyle(Tema.lacivert)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(EkipBolumu.hepsi.enumerated()), id: \.element.id) { i, b in
                    NavigationLink(value: ekip.hedef(b)) {
                        BolumKutusu(bolum: b, rozet: rozet(b))
                    }
                    .buttonStyle(KartDugmesi())
                    .belirme(3 + i)
                }
            }
        }
    }

    private func rozet(_ b: EkipBolumu) -> Int {
        switch b.id {
        case "musteriler": return veri.talepler.filter { $0.durum == "new" }.count + veri.acikDestek
        case "takvim": return veri.takvim.filter { $0.gun == veri.bugun }.count
        default: return 0
        }
    }
}

struct OzetKutusu: View {
    let sayi: Int
    let ad: String
    let simge: String
    let vurgu: Color
    let islem: () -> Void

    var body: some View {
        Button(action: islem) {
            OzetIcerik(sayi: sayi, ad: ad, simge: simge, vurgu: vurgu)
        }
        .buttonStyle(KartDugmesi())
    }
}

struct OzetIcerik: View {
    let sayi: Int
    let ad: String
    let simge: String
    let vurgu: Color

    var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: simge).font(.subheadline.weight(.bold)).foregroundStyle(vurgu)
                    Spacer()
                }
                Text("\(sayi)")
                    .font(.vitrin(28))
                    .foregroundStyle(Tema.lacivert)
                    .contentTransition(.numericText())
                    .animation(Hareket.yay, value: sayi)
                Text(ad).font(.caption).foregroundStyle(Tema.govde).lineLimit(2).multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(Tema.zemin, in: RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tema.kose, style: .continuous).stroke(Tema.soluk, lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}

struct BolumKutusu: View {
    let bolum: EkipBolumu
    let rozet: Int
    @Environment(EkipOturumu.self) private var ekip

    var body: some View {
        let acik = bolum.ogeler.contains { ekip.acabilir($0) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: bolum.simge)
                    .font(.title3)
                    .foregroundStyle(acik ? Tema.turkuaz : Tema.silik)
                    .frame(width: 40, height: 40)
                    .background(Tema.soluk, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
                if rozet > 0 {
                    Text("\(rozet)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Tema.olumsuz, in: Capsule())
                        .contentTransition(.numericText())
                } else if !acik {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(Tema.silik)
                }
            }
            Text(bolum.ad).font(.headline).foregroundStyle(acik ? Tema.lacivert : Tema.silik)
            Text(bolum.ogeler.map { $0.ad }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(Tema.govde)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(Tema.zemin, in: RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tema.kose, style: .continuous).stroke(Tema.soluk, lineWidth: 1))
    }
}

/// Çok ekranlı bölümün alt kutuları (panel: #/bolum/<id>).
struct BolumEkrani: View {
    let id: String
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var veri

    var body: some View {
        let b = EkipBolumu.bul(id)
        List {
            ForEach(Array((b?.ogeler ?? []).enumerated()), id: \.element.id) { i, o in
                let acik = ekip.acabilir(o)
                NavigationLink(value: o.rota ?? .yakinda(o.ad)) {
                    HStack(spacing: 14) {
                        Image(systemName: o.simge)
                            .foregroundStyle(acik ? Tema.turkuaz : Tema.silik)
                            .frame(width: 28)
                        Text(o.ad).foregroundStyle(acik ? Tema.lacivert : Tema.silik)
                        Spacer()
                        if o.id == "talepler", veri.talepler.contains(where: { $0.durum == "new" }) {
                            Text("\(veri.talepler.filter { $0.durum == "new" }.count) yeni")
                                .font(.caption.weight(.bold)).foregroundStyle(Tema.olumsuz)
                        }
                        if o.id == "destek", veri.acikDestek > 0 {
                            Text("\(veri.acikDestek) açık").font(.caption.weight(.bold)).foregroundStyle(Tema.mavi)
                        }
                        if !acik { Image(systemName: "lock.fill").font(.caption).foregroundStyle(Tema.silik) }
                    }
                    .padding(.vertical, 4)
                }
                .disabled(!acik)
                .belirme(i)
            }
        }
        .navigationTitle(b?.ad ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}
