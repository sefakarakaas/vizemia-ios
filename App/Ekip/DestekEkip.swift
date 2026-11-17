import SwiftUI
import VizeMiaCekirdek

/// Destek talepleri (panel: #/destek).
struct DestekTalepleriEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var veri

    var body: some View {
        Group {
            if !ekip.yapabilir("support.view") {
                YetkiYok(ad: "Destek talepleri")
            } else if veri.destek.isEmpty {
                ContentUnavailableView(veri.yukleniyor ? "Yükleniyor…" : "Açık destek talebi yok",
                                       systemImage: "lifepreserver",
                                       description: Text("Siteden ve uygulamadan gelen sorular burada görünür."))
            } else {
                List {
                    ForEach(Array(veri.destek.enumerated()), id: \.element.id) { i, d in
                        NavigationLink(value: EkipRota.destek(d.kimlik)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(d.konu.isEmpty ? "(konu yok)" : d.konu).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                                    Spacer()
                                    Etiket(metin: d.durumAdi, renk: d.durum == "new" ? Tema.olumsuz : Tema.mavi)
                                }
                                Text(d.ad).font(.caption).foregroundStyle(Tema.govde)
                                Text(d.mesaj).font(.caption).foregroundStyle(Tema.silik).lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                        .belirme(i)
                    }
                }
            }
        }
        .navigationTitle("Destek talepleri")
        .refreshable { await veri.yukle(ekip, zorla: true) }
        .task { await veri.yukle(ekip) }
    }
}

struct DestekDetayi: View {
    let kimlik: String
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var veri
    @State private var durum = "new"
    @State private var icNot = ""
    @State private var hazir = false
    @State private var hata: String?
    @State private var kaydediliyor = false
    @State private var kaydedildi = false

    var body: some View {
        if let d = veri.destek.first(where: { $0.kimlik == kimlik }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Etiket(metin: d.durumAdi, renk: d.durum == "new" ? Tema.olumsuz : Tema.mavi)
                        Text(d.konu).font(.title2.weight(.heavy)).foregroundStyle(Tema.lacivert)
                        Text([d.ad, d.olusturma.map { Tr.tarihSaat($0) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Tema.govde)
                    }
                    .belirme(0)
                    Text(d.mesaj).font(.body).foregroundStyle(Tema.lacivert).textSelection(.enabled).kart().belirme(1)
                    VStack(alignment: .leading, spacing: 8) {
                        if !d.eposta.isEmpty {
                            Button {
                                let konu = "Re: \(d.konu)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                if let u = URL(string: "mailto:\(d.eposta)?subject=\(konu)") { UIApplication.shared.open(u) }
                            } label: { Label("E-postayla yanıtla", systemImage: "arrowshape.turn.up.left.fill") }
                            .buttonStyle(AnaDugme())
                        }
                        if !d.telefon.isEmpty {
                            Button {
                                if let u = URL(string: "tel:\(d.telefon.filter { $0.isNumber || $0 == "+" })") { UIApplication.shared.open(u) }
                            } label: { Label(d.telefon, systemImage: "phone.fill") }
                            .buttonStyle(IkincilDugme())
                        }
                        if !d.takipKodu.isEmpty {
                            Label("Takip kodu: \(d.takipKodu)", systemImage: "number").font(.caption).foregroundStyle(Tema.govde)
                        }
                    }
                    .belirme(2)
                    if ekip.yapabilir("support.manage") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Durum").font(.headline).foregroundStyle(Tema.lacivert)
                            HStack(spacing: 8) {
                                ForEach(0..<DestekTalebi.durumlar.count, id: \.self) { i in
                                    let k = DestekTalebi.durumlar[i].0
                                    Button(DestekTalebi.durumlar[i].1) { withAnimation(Hareket.yay) { durum = k } }
                                        .buttonStyle(SecimKutusu(secili: durum == k))
                                }
                            }
                            Alan(etiket: "İç not", istegeBagli: true) {
                                TextField("", text: $icNot, axis: .vertical).lineLimit(2...5).kutu()
                            }
                            if let h = hata { HataMetni(metin: h) }
                            Button {
                                Task { await kaydet(d) }
                            } label: {
                                Label(kaydedildi ? "Kaydedildi" : "Kaydet", systemImage: kaydedildi ? "checkmark" : "tray.and.arrow.down.fill")
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(AnaDugme())
                            .disabled(kaydediliyor)
                        }
                        .kart()
                        .belirme(3)
                    }
                }
                .padding(Tema.bosluk)
            }
            .formKlavyesi()
            .ekranZemini()
            .navigationTitle("Destek")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !hazir else { return }
                hazir = true; durum = d.durum; icNot = d.icNot
            }
            .sensoryFeedback(.success, trigger: kaydedildi)
        } else {
            ContentUnavailableView("Talep bulunamadı", systemImage: "questionmark.folder")
        }
    }

    private func kaydet(_ d: DestekTalebi) async {
        hata = nil
        kaydediliyor = true
        defer { kaydediliyor = false }
        do {
            try await veri.destekGuncelle(d, durum: durum, icNot: icNot, ekip: ekip)
            kaydedildi.toggle()
        } catch {
            hata = "Kaydedilemedi. İnternet bağlantınızı kontrol edip yeniden deneyin."
        }
    }
}
