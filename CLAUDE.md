# VizeMia iOS — çalışma notları

vizemia.com'un iPhone uygulaması. Site deposu: `sefakarakaas/VizeMia` (panel, site, güvenlik kuralları).

## Temel ilkeler

- **Site tek kaynaktır.** İçerik `https://vizemia.com/assets/uygulama.json` dosyasından gelir (site deposu → `scripts/uygulama-akisi.mjs`). Bir metni uygulamaya elle yazmadan önce bu dosyaya eklenip eklenemeyeceğine bak. Sözleşme: alan kaldırılmaz, anlamı değiştirilmez; yalnız yeni alan eklenir (`Akis.swift` ↔ site deposundaki `tests/uygulama-akisi.test.mjs`).
- **Kurallar sitedeki JavaScript'in karşılığıdır** (harf çevirme, telefon, T.C. kimlik, mesai, saat seçici, vitrin tarihi, takip anahtarı). Bir kural değişirse iki depoda birlikte değişir. Formların alan listesi `firestore.rules` içindeki `hasOnly` listesiyle aynı olmalı.
- **Dil:** kod adları, yorumlar ve kullanıcıya görünen metinler Türkçe (site deposuyla aynı üslup). Yorumlar "neden"i anlatır.
- **Okuma kotası:** Firestore ücretsiz planda günde 50.000 belge okuma (her dönen belge bir okuma); panel, site ve zamanlanmış işler aynı kotayı kullanır, dolunca hepsi 11.00'e (TR) kadar durur. Ekip ekranları listeyi en çok 5 dakikada bir okur (`EkipVerisi.tazelik`, aşağı çekince her zaman), ağır sorgular yalnız o ekran açılınca (takvim), işlemden sonra yalnız değişen parça yeniden okunur. Yeni ekran da böyle yazılır: sınır (`sinir:`) ekranda gösterilen kadar.
- **Canlı veritabanına test verisi yazılmaz.** Form kayıtları Firestore emülatöründe denenir (README → Geliştirme). Ekran testi bilerek eksik form bırakır; hiçbir şey göndermez.

## "Beni unutma"

- Durum: `App/Durum/TakipHafizasi.swift` (hatırlanan başvuru, son görülen durum), `Kasa.swift` (Anahtar Zinciri), `Bildirimler.swift` (izin, yerel bildirim, arka plan denetimi). Metinler ve değişiklik kuralı çekirdekte: `Selamlama`, `TakipKaydi.bildirim(onceki:)`.
- Bildirim sunucudan gelmiyor (arka plan denetimi + yerel bildirim). Gerçek anlık bildirim (APNs) ayrı bir iş: Apple anahtarı, site deposunda gönderici ve cihaz kaydı kuralı gerekir.
- Ekran testinde örnek kayıt: uygulama `-ornek-takip` ile açılırsa (yalnız geliştirme derlemesi) ağa ve Anahtar Zinciri'ne dokunmadan hatırlanan müşteri hâlini gösterir.

## Ekip ekranları (panelin uygulama hâli)

- Durum: `EkipOturumu` (giriş, izinler, statüler, ayarlar), `EkipVerisi` (talepler, destek, takvim, başvurular listesi), `BasvuruVerisi.swift` (liste ve ayrıntı). Yazımlar çekirdekte: `BasvuruIslemi` (statü + takip sayfası + mail/SMS kuyruğu tek yazımda), emülatörde `BasvuruEmulatorTests` gerçek kurallarla dener.
- Kasa: `KasaVerisi` (rapor yalnız seçilen dönemi okur, en çok 1000; kayıttan sonra yalnız o belge), çekirdekte `Kasa.swift` (panel/js/kasa.js karşılığı: rapor toplamları, döviz çevrimi, rutin ödeme vadeleri, CSV) ve `KasaIslemi` (fiş aynı yazımda; emülatörde `testKasa`).
- Pasaport kontrolü: fotoğraf telefonda Vision ile okunur (`MrzOkuyucu`), çekirdekte `Mrz` (mrz.js karşılığı) ve `PasaportKontrolu`; yalnız sonuç yazılır.
- İletiler: `BildirimGorevi` / `BildirimMetni` (WhatsApp görevleri, şablon doldurma), `Eposta.swift`, `FirmaMaili.swift` (cevap mailinin HTML'i sitenin JS çıktısıyla testte karşılaştırılır: `Tests/…/Ornekler`).
- Site içeriği: `SiteIcerigi.swift` (süreç adımları, vitrin slaytı, `SiteYayini` — kayıttan sonra yayın işini başlatır), `Icerik.swift` (blog/SSS), `FotoHavuzu.swift` (otomatik arka plan seçimi sitenin foto-havuzu.js'iyle bire bir), `Sosyal.swift`.
- Yönetim: `Kullanicilar.swift` (çalışanlar, işlem kayıtları), `Ayarlar.swift`, `StatuEvrakAyari.swift` (statüler, evrak listesi), `Armut.swift` (Armut ve elle talep).
- Başvuru ayrıntısındaki kartlar: `MusteriMesaji.swift` (WhatsApp/SMS/e-posta; WhatsApp teyidi `EkipOturumu.bekleyenWa`, kapatılamayan soru kökte), `MusteriFormu.swift` (müşteri formu, `FormKosulu` = form-kosul.js, `FormGonderimKurali`), `Grup.swift`, `BasvuruSilme.swift` (saklama, silme + müşteri arşivi tek yazımda), `BildirimTercihi.swift`, `Mektup.swift` (iyi niyet mektubu; PDF uygulamada `MektupPdf`, yazı tipi `App/Kaynaklar/Fontlar/Carlito-Bold.ttf`, OFL).
- Toplu e-posta: `TopluEposta.swift`. Görüşme rehberi: `GorusmeRehberi.swift`.
- uygulama.json'a ekip için eklenen alanlar: `rehber` (görüşme rehberi varsayılanı), `mektup` (hitaplar, cümle kalıpları); Firestore'daki ayar (settings/rehber, settings/mektup) üstüne yazar. Gömülü kopya (`Cekirdek/.../Kaynaklar/uygulama.json`) yeni alan eklenince elle güncellenir.
- Düzenlemede oluşturma alanları (createdAt…) okunup geri yazılmaz: zaman hassasiyeti kaybolur, kural "değişmedi" denetiminde reddeder. Yalnız değişen alanlar (`.guncelle`, `.derin`, `.birlestir`).
- Ekran testinde örnek veri: `-ornek-ekip` (yalnız geliştirme derlemesi; ağa dokunmaz).

## Yapı

- `Cekirdek/` — ekran içermeyen bütün mantık (Swift paketi). Linux'ta derlenir: `cd Cekirdek && swift test`. Yeni mantık buraya, testiyle birlikte yazılır.
- `App/` — SwiftUI ekranları. Yalnız Mac'te derlenir.
- `project.yml` — Xcode projesi XcodeGen ile üretilir; `.xcodeproj` depoda yok.

## Mac yok: derleme GitHub'da

- `main`'e gönderilen her kod değişikliği **Derle ve test et** işini çalıştırır (çekirdek testleri + simülatör derlemesi, ~2 dk Mac).
- Ekranların nasıl göründüğünü görmek için **Ekran görüntüleri** işi elle çalıştırılır (~8 dk Mac); görüntüler işin dosyalarında (`ekran-goruntuleri`).
- Depo herkese açık: GitHub Actions dakikaları ücretsiz (özel olsaydı Mac dakikası 10 kat sayılırdı). Yine de değişiklikleri toplu gönder; yalnız `.md` değişikliği derleme başlatmaz.
- Ekran kodu burada derlenemediği için dikkatli yazılır: bilinen, yerleşik SwiftUI arayüzleri (iOS 17+), belirsiz tür çıkarımlarından kaçınma (`Color.white`, `Text.LineStyle.single` gibi açık yazım).
- TestFlight: **TestFlight'a gönder** işi (README → TestFlight kurulumu). Anahtarlar yalnız GitHub gizli ayarlarında durur.
