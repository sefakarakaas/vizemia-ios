import SwiftUI
import VizeMiaCekirdek

/// Kullanıcılar (panel: #/kullanicilar; yalnız yönetici).
struct KullanicilarEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @State private var kullanicilar: [CalisanKaydi] = []
    @State private var hata: String?
    @State private var bildiri: String?
    @State private var duzenlenen: CalisanKaydi?
    @State private var ekleAcik = false

    var body: some View {
        List {
            if let h = hata { Section { Text(h).foregroundStyle(Tema.olumsuz) } }
            if let b = bildiri { Section { Label(b, systemImage: "checkmark.circle.fill").foregroundStyle(Tema.olumluKoyu) } }
            Section {
                ForEach(kullanicilar) { k in
                    Button { duzenlenen = k } label: { satir(k) }.buttonStyle(.plain)
                }
            } header: {
                Text("\(kullanicilar.count) kullanıcı")
            } footer: {
                Text("Pasif yapılan kullanıcı anında hiçbir veriye erişemez; erişimi kesmek için genelde bu yeterli. İzleyicilere talep bildirimi gitmez. Kendi rolünüzü değiştiremez, kendinizi silemezsiniz.")
            }
        }
        .navigationTitle("Kullanıcılar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { ekleAcik = true } label: { Image(systemName: "person.badge.plus") }.accessibilityLabel("Kullanıcı ekle")
            }
        }
        .task { if kullanicilar.isEmpty { await yukle() } }
        .refreshable { await yukle() }
        .sheet(item: $duzenlenen) { k in
            KullaniciDuzenleSayfasi(kayit: k) { m in bildiri = m; Task { await yukle() } }
        }
        .sheet(isPresented: $ekleAcik) {
            KullaniciEkleSayfasi(mevcut: kullanicilar) { m in bildiri = m; Task { await yukle() } }
        }
    }

    private func satir(_ k: CalisanKaydi) -> some View {
        HStack(spacing: 12) {
            Text(String((k.ad.isEmpty ? k.kullaniciAdi : k.ad).prefix(1)).uppercased(with: Tr.yerel))
                .font(.headline.weight(.heavy)).foregroundStyle(Color.white)
                .frame(width: 38, height: 38)
                .background(k.aktif ? Tema.lacivert : Tema.silik, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(k.ad.isEmpty ? k.kullaniciAdi : k.ad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                Text("@\(k.kullaniciAdi) · \(CalisanKaydi.rolAdi(k.rol))").font(.caption).foregroundStyle(Tema.govde)
            }
            Spacer()
            if !k.aktif { Etiket(metin: "Pasif", renk: Tema.silik) }
            if k.talepBildirimi { Image(systemName: "bell.fill").font(.caption).foregroundStyle(Tema.altin) }
        }
        .contentShape(Rectangle())
    }

    private func yukle() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") {
            kullanicilar = [CalisanKaydi(kimlik: "ornek", alanlar: ["username": .metin("sefa"), "displayName": .metin("Sefa Karakaş"),
                                                                    "role": .metin("admin"), "active": .mantik(true), "notifyLeads": .mantik(true)]),
                            CalisanKaydi(kimlik: "u2", alanlar: ["username": .metin("ezgi"), "displayName": .metin("Ezgi"),
                                                                 "role": .metin("writer"), "active": .mantik(true)])]
            return
        }
        #endif
        do {
            let l = try await ekip.istemci().sorgu(koleksiyon: "employees", sinir: 200)
            kullanicilar = l.map { CalisanKaydi(kimlik: $0.kimlik, alanlar: $0.alanlar) }.sorted { $0.kullaniciAdi < $1.kullaniciAdi }
            hata = nil
        } catch {
            hata = KasaVerisi.mesaj(error, "Kullanıcılar yüklenemedi.")
        }
    }
}

struct KullaniciDuzenleSayfasi: View {
    let kayit: CalisanKaydi
    let bitti: (String) -> Void
    @Environment(EkipOturumu.self) private var ekip
    @Environment(\.dismiss) private var kapat
    @State private var k: CalisanKaydi?
    @State private var hata: String?
    @State private var calisiyor = false
    @State private var silOnay = false

    private var kendisi: Bool { kayit.id == ekip.calisan?.uid }

    var body: some View {
        NavigationStack {
            Form {
                if let x = k {
                    let bag = Binding<CalisanKaydi>(get: { k ?? x }, set: { k = $0 })
                    Section("@\(x.kullaniciAdi)") {
                        TextField("Ad soyad", text: bag.ad)
                        TextField("E-posta", text: bag.eposta).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Picker("Rol", selection: bag.rol) {
                            ForEach(0..<CalisanKaydi.roller.count, id: \.self) { i in Text(CalisanKaydi.roller[i].ad).tag(CalisanKaydi.roller[i].id) }
                        }
                        .disabled(kendisi)
                        Toggle("Talep bildirimi", isOn: bag.talepBildirimi).disabled(bag.wrappedValue.rol == "reader")
                        Toggle("Aktif", isOn: bag.aktif).disabled(kendisi)
                    }
                    if let h = hata { Section { Text(h).foregroundStyle(Tema.olumsuz) } }
                    Section {
                        Button { Task { await kaydet() } } label: { if calisiyor { ProgressView() } else { Text("Kaydet") } }
                            .disabled(calisiyor)
                    }
                    if !kendisi {
                        Section {
                            Button("Kalıcı olarak sil", role: .destructive) { silOnay = true }
                        } footer: {
                            Text("Erişimi kesmek için silmek yerine \"Aktif\"i kapatmanız yeterli. Silinirse işlem kayıtlarında adı görünmez; giriş hesabını Firebase konsolundan da kaldırın.")
                        }
                    }
                }
            }
            .navigationTitle(kayit.ad.isEmpty ? kayit.kullaniciAdi : kayit.ad)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } } }
            .onAppear { if k == nil { k = kayit } }
            .confirmationDialog("\(kayit.kullaniciAdi) panelden silinecek. Bu geri alınamaz.", isPresented: $silOnay, titleVisibility: .visible) {
                Button("Kalıcı olarak sil", role: .destructive) { Task { await sil() } }
                Button("Vazgeç", role: .cancel) {}
            }
        }
    }

    private func kaydet() async {
        guard let x = k, let c = ekip.calisan else { return }
        if let h = CalisanKaydi.epostaHatasiAcik(x.eposta) { hata = h; return }
        calisiyor = true
        defer { calisiyor = false }
        do {
            try await ekip.istemci().isle(CalisanKaydi.guncelle(x, calisan: c))
            bitti("Kullanıcı güncellendi.")
            kapat()
        } catch {
            hata = KasaVerisi.mesaj(error, "Kaydedilemedi.")
        }
    }

    private func sil() async {
        guard let c = ekip.calisan else { return }
        do {
            try await ekip.istemci().isle(CalisanKaydi.sil(kayit, calisan: c))
            bitti("\(kayit.kullaniciAdi) silindi. Giriş hesabını Firebase konsolundan da kaldırın.")
            kapat()
        } catch {
            hata = KasaVerisi.mesaj(error, "Silinemedi.")
        }
    }
}

struct KullaniciEkleSayfasi: View {
    let mevcut: [CalisanKaydi]
    let bitti: (String) -> Void
    @Environment(EkipOturumu.self) private var ekip
    @Environment(\.dismiss) private var kapat
    @State private var kullaniciAdi = ""
    @State private var ad = ""
    @State private var eposta = ""
    @State private var rol = "writer"
    @State private var uid = ""
    @State private var hata: String?
    @State private var calisiyor = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("1. Firebase konsolu → Authentication → Users → \"Add user\" ile e-posta olarak \(kullaniciAdi.isEmpty ? "kullaniciadi" : kullaniciAdi)@\(CalisanKaydi.alanAdi) yazın ve güçlü bir geçici şifre belirleyin.")
                    Text("2. Oluşan satırdaki \"User UID\" değerini aşağıya yapıştırın.")
                    Text("3. Kullanıcı adı ve geçici şifreyi çalışana güvenli bir yoldan iletin; ilk girişte şifresini değiştirmesini isteyin.")
                }
                .font(.footnote)
                Section {
                    TextField("Kullanıcı adı (ör. ayse.k)", text: $kullaniciAdi)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: kullaniciAdi) { _, y in
                            let t = String(y.lowercased().filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || "._-".contains($0) })
                            if t != y { kullaniciAdi = t }
                        }
                    TextField("Ad soyad", text: $ad)
                    TextField("E-posta", text: $eposta).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Rol", selection: $rol) {
                        ForEach(0..<CalisanKaydi.roller.count, id: \.self) { i in Text(CalisanKaydi.roller[i].ad).tag(CalisanKaydi.roller[i].id) }
                    }
                    TextField("User UID", text: $uid).textInputAutocapitalization(.never).autocorrectionDisabled().font(.footnote.monospaced())
                }
                if let h = hata { Section { Text(h).foregroundStyle(Tema.olumsuz) } }
                Section {
                    Button { Task { await ekle() } } label: { if calisiyor { ProgressView() } else { Text("Kullanıcıyı ekle") } }
                        .disabled(calisiyor)
                }
            }
            .navigationTitle("Yeni kullanıcı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
        }
    }

    private func ekle() async {
        guard let c = ekip.calisan else { return }
        let r = CalisanKaydi.ekle(uid: uid, kullaniciAdi: kullaniciAdi, ad: ad, eposta: eposta, rol: rol, mevcut: mevcut, calisan: c)
        if let h = r.hata { hata = h; return }
        calisiyor = true
        defer { calisiyor = false }
        do {
            try await ekip.istemci().isle(r.yazimlar)
            bitti("Kullanıcı eklendi.")
            kapat()
        } catch {
            hata = KasaVerisi.mesaj(error, "Eklenemedi. UID doğru mu?")
        }
    }
}

/// İşlem kayıtları (panel: #/kayitlar; yalnız yönetici). Değiştirilemez, silinemez.
struct IslemKayitlariEkrani: View {
    @Environment(EkipOturumu.self) private var ekip
    @Environment(EkipVerisi.self) private var ekipVerisi
    @State private var kayitlar: [IslemSatiri] = []
    @State private var ara = ""
    @State private var hata: String?
    @State private var dahaVar = true
    @State private var yukleniyor = false

    /// Ekranda gösterilen kadar okunur; "Daha eski" ile 100'er.
    static let sayfa = 100

    /// Hedefin adı: önbellekteki başvurulardan (ek okuma yapılmaz).
    private func hedefAdi(_ s: IslemSatiri) -> String {
        ekipVerisi.basvurular.satirlar.first { $0.kimlik == s.hedef }?.adSoyad ?? ""
    }

    private var gorunen: [IslemSatiri] { kayitlar.filter { $0.eslesir(ara, hedefAdi: hedefAdi($0)) } }

    var body: some View {
        List {
            if let h = hata { Text(h).foregroundStyle(Tema.olumsuz) }
            ForEach(gorunen) { s in satir(s) }
            if dahaVar && ara.isEmpty && !kayitlar.isEmpty {
                Button { Task { await yukle(devam: true) } } label: {
                    HStack {
                        if yukleniyor { ProgressView() }
                        Text("Daha eski kayıtlar")
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $ara, prompt: "Kişi, işlem, müşteri ya da ayrıntı")
        .navigationTitle("İşlem kayıtları")
        .navigationBarTitleDisplayMode(.inline)
        .task { if kayitlar.isEmpty { await yukle(devam: false) } }
        .refreshable { await yukle(devam: false) }
    }

    private func satir(_ s: IslemSatiri) -> some View {
        let ad = hedefAdi(s)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(s.eylemAdi).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.lacivert)
                Spacer()
                Text(s.zaman.map { Tr.tarihSaat($0) } ?? "").font(.caption2).foregroundStyle(Tema.silik)
            }
            Text(s.yapan).font(.caption).foregroundStyle(Tema.govde)
            if !ad.isEmpty {
                NavigationLink(value: EkipRota.basvuru(s.hedef)) { Text(ad).font(.caption.weight(.semibold)).foregroundStyle(Tema.turkuaz) }
            } else if !s.hedef.isEmpty {
                Text(s.hedef).font(.caption2.monospaced()).foregroundStyle(Tema.silik).lineLimit(1)
            }
            if !s.ayrinti.isEmpty { Text(s.ayrinti).font(.caption).foregroundStyle(Tema.govde) }
        }
        .padding(.vertical, 2)
    }

    private func yukle(devam: Bool) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ornek-ekip") {
            kayitlar = [IslemSatiri(kimlik: "a1", alanlar: ["action": .metin("app.status"), "target": .metin("x"), "detail": .metin("Randevu Takipte → Evrak Bekleniyor"),
                                                           "byName": .metin("Sefa Karakaş"), "at": .zaman(Date().addingTimeInterval(-600))])]
            dahaVar = false
            return
        }
        #endif
        yukleniyor = true
        defer { yukleniyor = false }
        do {
            let son = devam ? kayitlar.last?.zaman.map { FSDeger.zaman($0) } : nil
            let l = try await ekip.istemci().sorgu(koleksiyon: "audit", sirala: ("at", .azalan), sinir: Self.sayfa, sonra: son)
            let yeni = l.map { IslemSatiri(kimlik: $0.kimlik, alanlar: $0.alanlar) }
            if devam { kayitlar += yeni.filter { y in !kayitlar.contains { $0.id == y.id } } } else { kayitlar = yeni }
            dahaVar = l.count == Self.sayfa
            hata = nil
        } catch {
            hata = KasaVerisi.mesaj(error, "İşlem kayıtları yüklenemedi.")
        }
    }
}
