import SwiftUI
import QuickLook
import VizeMiaCekirdek

/// Başvuru ayrıntısı (panel: #/basvuru/<id>). Kutular panelle aynı işleri
/// yapar, aynı kurallardan geçer; her işlem geçmişe ve işlem kayıtlarına yazılır.
struct BasvuruDetayi: View {
    let kimlik: String
    @Environment(EkipOturumu.self) private var ekip
    @Environment(IcerikDeposu.self) private var icerik
    @Environment(EkipVerisi.self) private var ekipVerisi
    @State private var veri: BasvuruDetayVerisi

    // Statü
    @State private var hedef = ""
    @State private var musteriNotu = ""
    @State private var smsGonder = false
    @State private var statuKaydediliyor = false
    // Notlar
    @State private var notMetni = ""
    @State private var notMusteriye = false
    @State private var notSms = false
    @State private var notKaydediliyor = false
    // Üst not
    @State private var ustNotMetni = ""
    @State private var ustNotKaydediliyor = false
    @State private var silinecekUstNot: UstNot?
    // Tekrar arama
    @State private var aramaNotu = ""
    @State private var aramaKaydediliyor = false

    @State private var bildiri: Bildiri?
    @State private var basari = 0
    // Belge önizleme
    @State private var onizleme: URL?
    @State private var aciliyor: String?

    struct Bildiri: Equatable {
        var metin: String
        var olumlu: Bool
    }

    init(kimlik: String) {
        self.kimlik = kimlik
        _veri = State(initialValue: BasvuruDetayVerisi(kimlik: kimlik))
    }

    var body: some View {
        Group {
            if let b = veri.basvuru {
                govde(b)
            } else if veri.bulunamadi {
                ContentUnavailableView("Başvuru bulunamadı", systemImage: "questionmark.folder",
                                       description: Text("Silinmiş olabilir."))
            } else if let h = veri.hata {
                ContentUnavailableView {
                    Label("Açılamadı", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(h)
                } actions: {
                    Button("Yeniden dene") { Task { await veri.yukle(ekip) } }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ekranZemini()
        .navigationTitle(veri.basvuru?.adSoyad ?? "Başvuru")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let m = ekipVerisi.sonMesaj { ekipVerisi.sonMesaj = nil; goster(nil, tamam: m) }
            if veri.basvuru == nil { await veri.yukle(ekip) }
            if hedef.isEmpty { hedef = veri.basvuru?.statuId ?? "" }
        }
        .toolbar {
            if ekip.yapabilir("app.edit") && ekip.yapabilir("app.sensitive"), veri.basvuru != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: EkipRota.basvuruDuzenle(kimlik)) { Text("Düzenle") }
                }
            }
        }
        .overlay(alignment: .top) { bildiriGorunumu }
        .animation(Hareket.yay, value: bildiri)
        .sensoryFeedback(.success, trigger: basari)
        .onChange(of: veri.basvuru) { _, yeni in
            if let yeni { ekipVerisi.basvurular.guncelle(yeni) }
        }
    }

    private func govde(_ b: Basvuru) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                bas(b).belirme(0)
                ustNotKarti(b).belirme(1)
                if !b.kontrolNotu.isEmpty && ekip.yapabilir("app.edit") { kontrolKarti(b).belirme(2) }
                if let i = veri.iletisim, !i.telefon.isEmpty || !i.eposta.isEmpty { iletisimKarti(i).belirme(2) }
                if ekip.yapabilir("app.status") { statuKarti(b).belirme(3) }
                if let s = ekip.statuSozlugu[b.statuId], s.tekrarAranir, let d = b.aramaDurumu(s) {
                    aramaKarti(b, s, d).belirme(4)
                }
                if ekip.yapabilir("app.payment") { OdemelerKarti(veri: veri, b: b, baglam: baglam(b)).belirme(5) }
                if ekip.yapabilir("app.sensitive") { BelgelerKarti(veri: veri, b: b, baglam: baglam(b)).belirme(5) }
                evrakKarti(b).belirme(5)
                if !b.konsTakipKodu.isEmpty || ekip.yapabilir("app.edit") {
                    KonsoloslukKarti(veri: veri, b: b, baglam: baglam(b)).belirme(6)
                }
                notlarKarti(b).belirme(6)
                takipKarti(b).belirme(7)
                bilgiKarti(b).belirme(8)
                if veri.grup.count > 1 { grupKarti(b).belirme(9) }
                gecmisKarti.belirme(10)
                Text("Pasaport okutma, başvuru formu ve müşteri formu işlemleri sıradaki güncellemeyle uygulamaya gelecek; şimdilik panelden yapılır.")
                    .font(.caption)
                    .foregroundStyle(Tema.silik)
                    .padding(.horizontal, 4)
            }
            .padding(Tema.bosluk)
        }
        .formKlavyesi()
        .refreshable { await veri.yukle(ekip) }
        .quickLookPreview($onizleme)
        .confirmationDialog("Bu üst not silinsin mi?", isPresented: Binding(
            get: { silinecekUstNot != nil }, set: { if !$0 { silinecekUstNot = nil } }), titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                guard let n = silinecekUstNot else { return }
                Task { goster(await veri.ustNotSil(n, ekip: ekip), tamam: "Üst not silindi.") }
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    // MARK: Başlık

    private func bas(_ b: Basvuru) -> some View {
        let s = ekip.statuSozlugu[b.statuId]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Etiket(metin: s?.ad ?? (b.statuAdi.isEmpty ? "Belirtilmemiş" : b.statuAdi), renk: statuRengi(s))
                if b.odemeSayisi > 0 { Etiket(metin: "Ödeme alındı", renk: Tema.olumlu) }
                if !b.grupId.isEmpty { Etiket(metin: b.grupAdi.isEmpty ? "Grup" : b.grupAdi, renk: Tema.altin) }
            }
            Text(b.adSoyad).font(.vitrin(26)).foregroundStyle(Tema.lacivert).textSelection(.enabled)
            Text([b.ulkeAdi, b.takipKodu].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Tema.govde)
            if let r = b.randevu {
                Label([Tr.kisaTarih(r), b.randevuSaati, b.randevuYeri, b.randevuSehri].filter { !$0.isEmpty }.joined(separator: " · "),
                      systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tema.mavi)
            }
        }
    }

    // MARK: Üst notlar

    private func ustNotKarti(_ b: Basvuru) -> some View {
        let yazabilir = ekip.yapabilir("note.add") || ekip.yapabilir("app.edit")
        return VStack(alignment: .leading, spacing: 10) {
            Label("Üst notlar", systemImage: "pin.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Tema.uyari)
            if veri.ustNotlar.isEmpty && !yazabilir {
                Text("Üst not yok.").font(.caption).foregroundStyle(Tema.govde)
            }
            ForEach(veri.ustNotlar) { n in
                let benim = n.yazanUid == ekip.calisan?.uid
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(n.yazan.isEmpty ? "—" : n.yazan).font(.caption.weight(.bold)).foregroundStyle(Tema.lacivert)
                        Text(n.zaman.map { Tr.tarihSaat($0) } ?? "").font(.caption2).foregroundStyle(Tema.govde)
                        Spacer()
                        if benim || (ekip.calisan?.yonetici ?? false) {
                            Button { silinecekUstNot = n } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .foregroundStyle(Tema.silik)
                            .accessibilityLabel("Üst notu sil")
                        }
                    }
                    Text(n.metin).font(.subheadline).foregroundStyle(Tema.lacivert).textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(benim ? Tema.zemin : Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
            }
            if yazabilir {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ekibin hemen görmesi gereken not", text: $ustNotMetni, axis: .vertical)
                        .lineLimit(1...4)
                        .kutu()
                    Button {
                        Task {
                            ustNotKaydediliyor = true
                            let h = await veri.ustNotEkle(ustNotMetni, ekip: ekip)
                            ustNotKaydediliyor = false
                            if h == nil { ustNotMetni = "" }
                            goster(h, tamam: "Üst not kaydedildi.")
                        }
                    } label: {
                        Image(systemName: ustNotKaydediliyor ? "hourglass" : "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundStyle(ustNotMetni.kirpik.isEmpty ? Tema.silik : Tema.lacivert)
                    }
                    .disabled(ustNotMetni.kirpik.isEmpty || ustNotKaydediliyor)
                    .accessibilityLabel("Üst notu kaydet")
                }
            }
        }
        .padding(Tema.bosluk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.uyariZemin, in: RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
    }

    // MARK: Bilgileri kontrol edin

    private func kontrolKarti(_ b: Basvuru) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Bilgileri kontrol edin", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color(hex: 0xb36b00))
            Text(b.kontrolNotu).font(.subheadline).foregroundStyle(Tema.lacivert)
            if ekip.yapabilir("app.sensitive") {
                Button("Kontrol ettim") {
                    Task { goster(await veri.kontrolEdildi(ekip: ekip), tamam: "Uyarı kaldırıldı.") }
                }
                .buttonStyle(IkincilDugme(tamGenislik: false))
            }
        }
        .kart()
    }

    // MARK: İletişim

    private func iletisimKarti(_ i: MusteriIletisimi) -> some View {
        let tel = MusteriBildirimi.e164(i.telefon)
        return VStack(alignment: .leading, spacing: 10) {
            if !i.telefon.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        if let u = URL(string: "tel:\(tel.isEmpty ? i.telefon : tel)") { UIApplication.shared.open(u) }
                    } label: { Label("Ara", systemImage: "phone.fill") }
                        .buttonStyle(AnaDugme(renk: Tema.olumlu))
                    Button {
                        if let u = URL(string: "https://wa.me/\(tel.filter(\.isNumber))") { UIApplication.shared.open(u) }
                    } label: { Label("WhatsApp", systemImage: "message.fill") }
                        .buttonStyle(AnaDugme(renk: Tema.whatsapp))
                        .disabled(tel.isEmpty)
                }
                Label(i.telefon, systemImage: "phone").font(.subheadline).foregroundStyle(Tema.lacivert).textSelection(.enabled)
            }
            if !i.eposta.isEmpty {
                Button {
                    if let u = URL(string: "mailto:\(i.eposta)") { UIApplication.shared.open(u) }
                } label: {
                    Label(i.eposta, systemImage: "envelope").font(.subheadline).foregroundStyle(Tema.mavi)
                }
            }
            HStack(spacing: 6) {
                kanal("WhatsApp", i.whatsapp)
                kanal("SMS", i.sms)
                kanal("E-posta", i.epostaIzni)
            }
        }
        .kart()
    }

    private func kanal(_ ad: String, _ acik: Bool) -> some View {
        Label(ad, systemImage: acik ? "checkmark.circle.fill" : "xmark.circle")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(acik ? Tema.olumluKoyu : Tema.silik)
    }

    // MARK: Statü

    private func statuKarti(_ b: Basvuru) -> some View {
        let s = ekip.statuSozlugu[hedef]
        let evrakTamam = evrakTamamMi(b)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Statü").font(.headline).foregroundStyle(Tema.lacivert)
            Picker("Yeni statü", selection: $hedef) {
                ForEach(ekip.statuler) { st in
                    Text(st.ad + (st.son ? " (son adım)" : "") + (st.gerekenler.isEmpty ? "" : " (şartlı)")).tag(st.id)
                }
            }
            .pickerStyle(.menu)
            .tint(Tema.lacivert)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kutu()
            if let s, s.id != b.statuId, !s.gerekenler.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(s.gerekenler, id: \.self) { g in
                        let tamam = sartTamam(g, b, evrakTamam: evrakTamam)
                        Label(GecisSarti(rawValue: g)?.ad ?? g,
                              systemImage: tamam == true ? "checkmark.circle.fill" : (tamam == false ? "xmark.circle.fill" : "circle.dashed"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tamam == true ? Tema.olumluKoyu : (tamam == false ? Tema.olumsuz : Tema.govde))
                    }
                }
                .transition(.opacity)
            }
            Alan(etiket: "Müşteriye not", istegeBagli: true, yardim: "Müşterinin takip sayfasında görünür.") {
                TextField("Ör. Randevu tarihiniz netleşti.", text: $musteriNotu, axis: .vertical)
                    .lineLimit(2...5)
                    .kutu()
            }
            if ekip.smsAyari.acik {
                let i = veri.iletisim
                IsaretKutusu(secili: $smsGonder,
                             metin: i == nil || i?.telefon.isEmpty == true ? "Müşteriye SMS gönder — telefon yok"
                                : (i?.sms == true ? "Müşteriye SMS gönder (\(i?.telefon ?? ""))" : "SMS kapalı — müşteri SMS almak istemiyor"),
                             etkin: i?.smsAcik == true)
            }
            Button {
                Task { await statuKaydet(evrakTamam: evrakTamam) }
            } label: {
                if statuKaydediliyor {
                    HStack(spacing: 8) { ProgressView().tint(.white); Text("Kaydediliyor…") }
                } else {
                    Label("Statüyü kaydet", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(AnaDugme())
            .disabled(statuKaydediliyor || (hedef == b.statuId && musteriNotu.kirpik.isEmpty))
        }
        .kart()
        .animation(Hareket.yay, value: hedef)
    }

    private func sartTamam(_ g: String, _ b: Basvuru, evrakTamam: Bool) -> Bool? {
        switch GecisSarti(rawValue: g) {
        case .odeme: return b.odemeSayisi > 0
        case .takipKodu: return !b.konsTakipKodu.isEmpty
        case .evrak: return evrakTamam
        default: return nil   // randevu kağıdı ve fiş kaydederken denetlenir
        }
    }

    private func statuKaydet(evrakTamam: Bool) async {
        guard let s = ekip.statuSozlugu[hedef] else { return }
        statuKaydediliyor = true
        let r = await veri.statuKaydet(s, not: musteriNotu, sms: smsGonder, evrakTamam: evrakTamam, ekip: ekip)
        statuKaydediliyor = false
        if r.tamam { musteriNotu = ""; smsGonder = false }
        bildiri = Bildiri(metin: r.mesaj, olumlu: r.tamam)
        if r.tamam { basari += 1 }
        kapat()
    }

    // MARK: Tekrar arama

    private func aramaKarti(_ b: Basvuru, _ s: Statu, _ d: Basvuru.AramaDurumu) -> some View {
        let renk: Color = d.durum == .gecikti ? Color(hex: 0xb36b00) : (d.durum == .ara ? Tema.turkuaz : Tema.govde)
        var aciklama = "\"\(s.ad)\" statüsündeki müşteri \(s.aramaMin ?? 0)–\(s.aramaMax ?? 0) gün içinde tekrar aranmalı: "
            + "\(Tr.kisaTarih(d.enErken)) – \(Tr.kisaTarih(d.enGec))."
        if let a = b.sonArama { aciklama += " Son arama: \(Tr.tarihSaat(a))." }
        if s.silmeGun != nil, let sil = b.silinecek, !b.bekletiliyor {
            aciklama += " Statü değişmezse \(Tr.kisaTarih(sil)) tarihinde silinir."
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Tekrar arama").font(.headline).foregroundStyle(Tema.lacivert)
            Label(Basvuru.aramaEtiketi(d), systemImage: "phone.arrow.up.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(renk)
            Text(aciklama).font(.caption).foregroundStyle(Tema.govde)
            if ekip.yapabilir("app.status") {
                TextField("Görüşme notu (isteğe bağlı)", text: $aramaNotu).kutu()
                Button {
                    Task {
                        aramaKaydediliyor = true
                        let h = await veri.arandi(not: aramaNotu, ekip: ekip)
                        aramaKaydediliyor = false
                        if h == nil { aramaNotu = "" }
                        goster(h, tamam: "Arama kaydedildi; sonraki arama aralığı buna göre hesaplanır.")
                    }
                } label: {
                    Label(aramaKaydediliyor ? "Kaydediliyor…" : "Arandı", systemImage: "checkmark")
                }
                .buttonStyle(AnaDugme(renk: Tema.turkuaz))
                .disabled(aramaKaydediliyor)
            }
        }
        .kart()
    }

    // MARK: Evrak kontrol listesi

    /// Herkesten istenen evrakların hepsi geldi mi (geçiş şartı "evrak").
    private func evrakTamamMi(_ b: Basvuru) -> Bool {
        let temel = evrakListesi(b).filter { !$0.kosullu }
        return !temel.isEmpty && temel.allSatisfy { b.evraklar[$0.id] == true }
    }

    private func baglam(_ b: Basvuru) -> EkBaglami {
        EkBaglami(bildir: { h, t in goster(h, tamam: t) }, ac: { belgeAc($0) }, aciliyor: aciliyor, evrakTamam: evrakTamamMi(b))
    }

    /// Belgeyi indirir (parçalar) ve önizler.
    private func belgeAc(_ d: DosyaBilgisi) {
        guard aciliyor == nil else { return }
        aciliyor = d.id
        Task {
            do {
                onizleme = try await veri.belgeDosyasi(d, ekip: ekip)
            } catch {
                goster("Belge açılamadı (eksik ya da silinmiş olabilir).", tamam: "")
            }
            aciliyor = nil
        }
    }

    private func evrakListesi(_ b: Basvuru) -> [Evrak] {
        ekip.evrakAyari.liste(ulke: b.ulke, katalog: icerik.evrak, isaretli: b.evraklar)
    }

    private func evrakKarti(_ b: Basvuru) -> some View {
        let liste = evrakListesi(b)
        let temel = liste.filter { !$0.kosullu }
        let kosullu = liste.filter(\.kosullu)
        let gelen = temel.filter { b.evraklar[$0.id] == true }.count
        let oran = temel.isEmpty ? 0 : Double(gelen) / Double(temel.count)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Evrak kontrol listesi").font(.headline).foregroundStyle(Tema.lacivert)
                Spacer()
                Text("\(gelen)/\(temel.count)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(gelen == temel.count && !temel.isEmpty ? Tema.olumluKoyu : Tema.lacivert)
                    .contentTransition(.numericText())
            }
            ProgressView(value: oran)
                .tint(oran >= 1 ? Tema.olumlu : Tema.turkuaz)
                .animation(Hareket.yay, value: oran)
            if liste.isEmpty {
                Text("Bu ülke için evrak listesi tanımlı değil (Ayarlar → Evrak listeleri).").font(.caption).foregroundStyle(Tema.govde)
            }
            ForEach(temel) { evrakSatiri($0, b) }
            if !kosullu.isEmpty {
                Text("Duruma göre istenenler (\(kosullu.filter { b.evraklar[$0.id] == true }.count)/\(kosullu.count) işaretli)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Tema.govde)
                    .padding(.top, 6)
                ForEach(kosullu) { evrakSatiri($0, b) }
            }
        }
        .kart()
    }

    private func evrakSatiri(_ e: Evrak, _ b: Basvuru) -> some View {
        let geldi = b.evraklar[e.id] == true
        let etkin = ekip.yapabilir("app.checklist")
        return Button {
            Task {
                if let h = await veri.evrak(e, geldi: !geldi, ekip: ekip) { goster(h, tamam: "") }
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: geldi ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(geldi ? Tema.olumlu : Tema.silik)
                    .contentTransition(.symbolEffect(.replace))
                Text(e.ad)
                    .font(.subheadline)
                    .foregroundStyle(geldi ? Tema.lacivert : Tema.govde)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!etkin)
        .sensoryFeedback(.selection, trigger: geldi)
        .accessibilityAddTraits(geldi ? .isSelected : [])
    }

    // MARK: Notlar

    private func notlarKarti(_ b: Basvuru) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notlar").font(.headline).foregroundStyle(Tema.lacivert)
            if veri.notlar.isEmpty { Text("Henüz not yok.").font(.caption).foregroundStyle(Tema.govde) }
            ForEach(veri.notlar) { n in
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.metin).font(.subheadline).foregroundStyle(Tema.lacivert).textSelection(.enabled)
                    HStack(spacing: 6) {
                        Text([n.zaman.map { Tr.tarihSaat($0) } ?? "", n.yazan].filter { !$0.isEmpty }.joined(separator: " — "))
                            .font(.caption2)
                            .foregroundStyle(Tema.govde)
                        if n.musteriyeGorunur { Etiket(metin: "Müşteriye görünür", renk: Tema.olumlu) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                Divider()
            }
            if ekip.yapabilir("note.add") {
                TextField("Not ekle…", text: $notMetni, axis: .vertical).lineLimit(2...6).kutu()
                if ekip.yapabilir("app.status") {
                    IsaretKutusu(secili: Binding(get: { notMusteriye }, set: { notMusteriye = $0; if !$0 { notSms = false } }),
                                 metin: "Müşteriye göster (takip sayfasında)")
                    if ekip.smsAyari.acik {
                        let i = veri.iletisim
                        IsaretKutusu(secili: Binding(get: { notSms }, set: { notSms = $0; if $0 { notMusteriye = true } }),
                                     metin: i?.smsAcik == true ? "SMS gönder" : "SMS kapalı (telefon yok ya da müşteri istemiyor)",
                                     etkin: i?.smsAcik == true)
                    }
                }
                Button {
                    Task {
                        notKaydediliyor = true
                        let h = await veri.notEkle(notMetni, musteriye: notMusteriye, sms: notSms, ekip: ekip)
                        notKaydediliyor = false
                        if h == nil { notMetni = ""; notMusteriye = false; notSms = false }
                        goster(h, tamam: notSms ? "Not eklendi. SMS 30 dk sonra gider." : "Not eklendi.")
                    }
                } label: {
                    Label(notKaydediliyor ? "Kaydediliyor…" : "Not ekle", systemImage: "plus.bubble")
                }
                .buttonStyle(IkincilDugme())
                .disabled(notMetni.kirpik.isEmpty || notKaydediliyor)
            }
        }
        .kart()
    }

    // MARK: Müşteri takibi

    private func takipKarti(_ b: Basvuru) -> some View {
        let link = "https://vizemia.com/takip?kod=\(b.takipKodu)"
        let mesaj = "Sayın \(b.ad) \(b.soyad), VizeMia başvurunuzu aşağıdaki bağlantıdan takip edebilirsiniz:\n\(link)\n"
            + "Bağlantıda takip kodunuz hazır gelir; yalnızca pasaport numaranızı yazmanız yeterlidir.\nTakip kodunuz: \(b.takipKodu)"
        let anahtarGorur = ekip.yapabilir("app.sensitive") || ekip.yapabilir("app.status") || ekip.yapabilir("app.edit")
        return VStack(alignment: .leading, spacing: 12) {
            Text("Müşteri takibi").font(.headline).foregroundStyle(Tema.lacivert)
            Text(b.takipKodu)
                .font(.system(.title, design: .monospaced).weight(.bold))
                .foregroundStyle(Tema.lacivert)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = b.takipKodu
                    goster(nil, tamam: "Takip kodu kopyalandı.")
                } label: { Label("Kopyala", systemImage: "doc.on.doc").lineLimit(1) }
                    .buttonStyle(IkincilDugme())
                ShareLink(item: mesaj) {
                    Label("Müşteriye gönder", systemImage: "square.and.arrow.up").lineLimit(1).minimumScaleFactor(0.8)
                }
                .buttonStyle(AnaDugme(renk: Tema.turkuaz))
            }
            Text("Müşteri yalnız statüyü ve \"müşteriye görünür\" notları görür.").font(.caption).foregroundStyle(Tema.govde)
            if anahtarGorur && veri.takipId == nil {
                HataMetni(metin: "Takip anahtarı bulunamadı; müşteri sorgusu çalışmayabilir. Başvuruyu panelden düzenleyip kaydedin.")
            }
            if b.pasaportSon3.isEmpty {
                Text("Pasaport numarası girilmedi: takip sayfası pasaport numarası kaydedilince çalışır.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xb36b00))
            }
        }
        .kart()
    }

    // MARK: Bilgiler

    private func bilgiKarti(_ b: Basvuru) -> some View {
        let kalan = BasvuruListesi.kalanGun(b.silinecek)
        var satirlar: [(String, String)] = [
            ("Ülke", b.ulkeAdi),
            ("Pasaport", b.pasaportSon3.isEmpty ? "—" : "•••\(b.pasaportSon3)"),
            ("Oluşturma tarihi", (b.acilis ?? b.olusturma).map { Tr.kisaTarih($0) } ?? "—"),
        ]
        if let r = b.randevu {
            satirlar.append(("Randevu", [Tr.kisaTarih(r), b.randevuSaati, b.randevuYeri, b.randevuSehri].filter { !$0.isEmpty }.joined(separator: " · ")))
        }
        if !b.konsTakipKodu.isEmpty { satirlar.append(("Konsolosluk takip kodu", b.konsTakipKodu)) }
        if !b.sorumlu.isEmpty { satirlar.append(("Sorumlu danışman", b.sorumlu)) }
        satirlar.append(("Kayıt zamanı", b.olusturma.map { Tr.tarihSaat($0) } ?? "—"))
        satirlar.append(("Son güncelleme", b.guncelleme.map { Tr.tarihSaat($0) } ?? "—"))
        if b.bekletiliyor {
            satirlar.append(("Silinme", "Bekletiliyor"))
        } else if let s = b.silinecek {
            satirlar.append(("Silinme", Tr.kisaTarih(s) + (kalan.map { $0 <= 0 ? " (bugün)" : " (\($0) gün)" } ?? "")))
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Başvuru bilgileri").font(.headline).foregroundStyle(Tema.lacivert)
            ForEach(Array(satirlar.enumerated()), id: \.offset) { _, s in
                HStack(alignment: .firstTextBaseline) {
                    Text(s.0).font(.caption).foregroundStyle(Tema.govde).frame(width: 130, alignment: .leading)
                    Text(s.1).font(.subheadline).foregroundStyle(Tema.lacivert).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
            if veri.form == nil {
                Text("TCKN, pasaport ve iletişim bilgilerini görme yetkiniz yok.").font(.caption).foregroundStyle(Tema.silik)
            }
        }
        .kart()
    }

    // MARK: Grup

    private func grupKarti(_ b: Basvuru) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(b.grupAdi.isEmpty ? "Grup" : b.grupAdi) · \(veri.grup.count) kişi", systemImage: "person.3.fill")
                .font(.headline)
                .foregroundStyle(Tema.lacivert)
            ForEach(veri.grup.filter { $0.kimlik != b.kimlik }) { u in
                NavigationLink(value: EkipRota.basvuru(u.kimlik)) {
                    HStack {
                        Text(u.adSoyad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                        Spacer()
                        Etiket(metin: ekip.statuSozlugu[u.statuId]?.ad ?? u.statuAdi, renk: statuRengi(ekip.statuSozlugu[u.statuId]))
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Tema.silik)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .kart()
    }

    // MARK: Geçmiş

    private var gecmisKarti: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Geçmiş").font(.headline).foregroundStyle(Tema.lacivert).padding(.bottom, 10)
            if veri.gecmis.isEmpty { Text("Kayıt yok.").font(.caption).foregroundStyle(Tema.govde) }
            ForEach(Array(veri.gecmis.prefix(60).enumerated()), id: \.element.id) { i, g in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle().fill(g.tur == "status" ? Tema.turkuaz : Tema.soluk).frame(width: 10, height: 10).padding(.top, 4)
                        if i < min(veri.gecmis.count, 60) - 1 {
                            Rectangle().fill(Tema.soluk).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.metin).font(.subheadline).foregroundStyle(Tema.lacivert)
                        Text([g.zaman.map { Tr.tarihSaat($0) } ?? "", g.yazan].filter { !$0.isEmpty }.joined(separator: " — "))
                            .font(.caption2)
                            .foregroundStyle(Tema.govde)
                    }
                    .padding(.bottom, 12)
                    Spacer(minLength: 0)
                }
            }
        }
        .kart()
    }

    // MARK: Ortak

    private func statuRengi(_ s: Statu?) -> Color { s.flatMap { Color(kod: $0.renk) } ?? Tema.mavi }

    /// Hata varsa onu, yoksa başarı metnini kısa süre gösterir.
    private func goster(_ hata: String?, tamam: String) {
        if let hata {
            bildiri = Bildiri(metin: hata, olumlu: false)
        } else if !tamam.isEmpty {
            bildiri = Bildiri(metin: tamam, olumlu: true)
            basari += 1
        }
        kapat()
    }

    private func kapat() {
        let simdiki = bildiri
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if bildiri == simdiki { bildiri = nil }
        }
    }

    @ViewBuilder private var bildiriGorunumu: some View {
        if let b = bildiri {
            Label(b.metin, systemImage: b.olumlu ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(b.olumlu ? Tema.olumluKoyu : Tema.olumsuz, in: RoundedRectangle(cornerRadius: Tema.koseKucuk, style: .continuous))
                .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
                .padding(.horizontal, Tema.bosluk)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { bildiri = nil }
        }
    }
}
