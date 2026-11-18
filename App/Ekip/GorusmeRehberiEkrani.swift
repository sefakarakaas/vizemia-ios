import SwiftUI
import VizeMiaCekirdek

/// Görüşme rehberi (panel: pages/gorusme-rehberi.js): müşteriyle telefonda konuşurken
/// açılır. İlk görüşmede öğrenilecekler, en kritik soru ve cevabına göre kategori,
/// seçili ülkenin bilgisi, kategori şartları, örnek görüşme ve bölümler.
struct GorusmeRehberiEkrani: View {
    var baslangicUlke: String = ""
    @Environment(EkipOturumu.self) private var ekip
    @Environment(IcerikDeposu.self) private var icerik
    @State private var ulke = ""
    @State private var ulkeSec = false
    @State private var isaretli: Set<Int> = []
    @State private var secilenKategori: String?
    @State private var hazir = false

    private var rehber: GorusmeRehberi? { icerik.rehber?.ayarla(ekip.rehberBelgesi) }

    var body: some View {
        Group {
            if let r = rehber {
                ScrollView { icerikGorunumu(r).padding(Tema.bosluk) }
            } else {
                ContentUnavailableView("Rehber yok", systemImage: "book.closed", description: Text("Uygulamayı güncelleyip yeniden deneyin."))
            }
        }
        .ekranZemini()
        .navigationTitle("Görüşme rehberi")
        .navigationBarTitleDisplayMode(.inline)
        .task { await ekip.rehberYukle() }
        .onAppear { if !hazir { ulke = baslangicUlke; hazir = true } }
        .sheet(isPresented: $ulkeSec) {
            ListeSecici(baslik: "Ülke", secenekler: icerik.akis.tumUlkeler.map(\.ad), secili: Binding(
                get: { icerik.akis.tumUlkeler.first { $0.slug == ulke }?.ad ?? "" },
                set: { ad in ulke = icerik.akis.tumUlkeler.first { $0.ad == ad }?.slug ?? "" }))
        }
    }

    private func icerikGorunumu(_ r: GorusmeRehberi) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("İlk görüşmede öğrenilecekler").font(.headline).foregroundStyle(Tema.lacivert)
                ForEach(Array(r.ilkSorular.enumerated()), id: \.offset) { i, s in
                    Button {
                        if isaretli.contains(i) { isaretli.remove(i) } else { isaretli.insert(i) }
                    } label: {
                        Label(s, systemImage: isaretli.contains(i) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isaretli.contains(i) ? Tema.olumluKoyu : Tema.lacivert)
                    }
                    .buttonStyle(.plain)
                }
            }
            .kart()

            VStack(alignment: .leading, spacing: 10) {
                Text("En kritik soru: \(r.kritikSoru.soru)").font(.headline).foregroundStyle(Tema.olumsuz)
                if !r.kritikSoru.aciklama.isEmpty { Text(r.kritikSoru.aciklama).font(.caption).foregroundStyle(Tema.govde) }
                HStack(spacing: 8) {
                    Button("Gelecek → \(r.kritikSoru.evet)") { secilenKategori = r.kritikSoru.evet }
                        .buttonStyle(KucukDugme(renk: secilenKategori == r.kritikSoru.evet ? Tema.turkuaz : Tema.lacivert))
                    Button("Gelmeyecek → \(r.kritikSoru.hayir)") { secilenKategori = r.kritikSoru.hayir }
                        .buttonStyle(KucukDugme(renk: secilenKategori == r.kritikSoru.hayir ? Tema.turkuaz : Tema.lacivert))
                }
                if let ad = secilenKategori {
                    if let k = r.kategori(ad) { KartGorunumu(k: k) } else { Text("→ \(ad)").font(.subheadline.weight(.bold)) }
                }
            }
            .kart()

            ulkeBolumu(r).kart()

            VStack(alignment: .leading, spacing: 8) {
                Text("Kategori şartları").font(.headline).foregroundStyle(Tema.lacivert)
                ForEach(r.kategoriler) { k in
                    DisclosureGroup {
                        RehberMetni(metin: k.metin).padding(.top, 4)
                    } label: {
                        HStack {
                            Text(k.baslik).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                            if !k.etiket.isEmpty { Etiket(metin: k.etiket, renk: Tema.mavi) }
                        }
                    }
                    .tint(Tema.lacivert)
                }
            }
            .kart()

            if !r.ornekKonusma.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(GorusmeRehberi.konusma(r.ornekKonusma).enumerated()), id: \.offset) { _, s in
                            (Text(s.kim.isEmpty ? "" : "\(s.kim): ").bold() + RehberMetni.satir(s.metin))
                                .font(.subheadline).foregroundStyle(Tema.lacivert)
                        }
                    }
                    .padding(.top, 4)
                } label: { Text("Örnek görüşme").font(.headline).foregroundStyle(Tema.lacivert) }
                .tint(Tema.lacivert)
                .kart()
            }

            ForEach(r.bolumler) { b in
                DisclosureGroup {
                    RehberMetni(metin: b.metin).padding(.top, 4)
                } label: { Text(b.baslik).font(.headline).foregroundStyle(Tema.lacivert) }
                .tint(Tema.lacivert)
                .kart()
            }
            if !r.kaynak.isEmpty { Text("Kaynak: \(r.kaynak)").font(.caption2).foregroundStyle(Tema.silik) }
        }
    }

    private func ulkeBolumu(_ r: GorusmeRehberi) -> some View {
        let ad = icerik.akis.tumUlkeler.first { $0.slug == ulke }?.ad ?? ulke
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ülke").font(.headline).foregroundStyle(Tema.lacivert)
                Spacer()
                Button(ulke.isEmpty ? "Ülke seç" : ad) { ulkeSec = true }.buttonStyle(KucukDugme())
            }
            if ulke.isEmpty {
                Text("Ülke seçilince o ülkenin randevu, otel/uçak ve ikametgâh bilgisi burada çıkar.").font(.caption).foregroundStyle(Tema.govde)
            } else if let u = r.ulkeler[ulke] {
                ForEach(r.ulkeAlanlari.filter { !(u[$0.key] ?? "").isEmpty }, id: \.key) { a in
                    let v = u[a.key] ?? ""
                    HStack(alignment: .firstTextBaseline) {
                        Text(a.ad).font(.caption).foregroundStyle(Tema.govde).frame(width: 110, alignment: .leading)
                        Text(v).font(.subheadline.weight(GorusmeRehberi.dikkat(v) ? .bold : .regular))
                            .foregroundStyle(GorusmeRehberi.dikkat(v) ? Tema.olumsuz : Tema.lacivert)
                    }
                }
                if let n = u["notlar"], !n.isEmpty { RehberMetni(metin: n) }
            } else {
                Text("\(ad) için rehber bilgisi yok.\(ekip.calisan?.yonetici == true ? " Panelde Ayarlar → Görüşme rehberi'nden eklenebilir." : "")")
                    .font(.caption).foregroundStyle(Tema.govde)
            }
        }
    }
}

struct KartGorunumu: View {
    let k: GorusmeRehberi.Kart
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(k.baslik).font(.subheadline.weight(.bold)).foregroundStyle(Tema.lacivert)
                if !k.etiket.isEmpty { Etiket(metin: k.etiket, renk: Tema.mavi) }
            }
            RehberMetni(metin: k.metin)
        }
        .padding(12)
        .background(Tema.zeminYumusak, in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
    }
}

/// "- madde" ve **kalın** biçimli metin (HTML yorumlanmaz).
struct RehberMetni: View {
    let metin: String

    static func satir(_ s: String) -> Text { yaz(GorusmeRehberi.parcalar(s)) }

    static func yaz(_ l: [GorusmeRehberi.Parca]) -> Text {
        l.reduce(Text("")) { t, p in t + (p.kalin ? Text(p.metin).bold() : Text(p.metin)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(GorusmeRehberi.bloklar(metin).enumerated()), id: \.offset) { _, b in
                switch b {
                case .paragraf(let p):
                    Self.yaz(p).font(.subheadline).foregroundStyle(Tema.lacivert)
                case .liste(let maddeler):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(maddeler.enumerated()), id: \.offset) { _, m in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(Tema.turkuaz)
                                Self.yaz(m).font(.subheadline).foregroundStyle(Tema.lacivert)
                            }
                        }
                    }
                }
            }
        }
    }
}
