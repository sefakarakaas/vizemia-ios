# VizeMia — iPhone uygulaması

[vizemia.com](https://vizemia.com)'un iPhone uygulaması. Site ile aynı içeriği ve aynı veritabanını kullanır: sitede ya da panelde değişen, uygulamada da değişir.

| Sekme | Sitedeki karşılığı | Veri |
|---|---|---|
| **Ana Sayfa** | Ana sayfa: vitrin, ülkeler, rehberler, süreç, SSS, blog, iletişim | `vitrin.json`, `uygulama.json` |
| **Takip** | `/takip` + "Beni unutma" (aşağıda) | Firestore `takip/{kimlik}` (yalnız kod + pasaportla) |
| **Başvur** | `/basvuru` ("Sizi Arayalım") | Firestore `applicationRequests` → panelde Talepler |
| **Harç & Kur** | `/harclar` | `uygulama.json`, `kur.json`, anlık kur servisi |
| **Daha** | Ülke rehberleri, blog, SSS, destek formu, iletişim, hakkımızda | `uygulama.json`, Firestore `support` |

Sıradaki adımlar: müşteri formu (`/form`) ve pasaport okutma, bildirimler, ardından çalışan girişi (panel).

## "Beni unutma" (uygulamaya özel)

Takip sonucunun altındaki **Beni unutma** düğmesine basan müşteri için:

- Uygulama her açılışta adıyla karşılar ("Günaydın, Ahmet") ve ana sayfanın başında başvurusunun durumunu gösterir.
- **Takip** sekmesi sorgu formu yerine doğrudan sürecini gösterir; pasaport, bulunduğu aşamaya kadar animasyonla yürür.
- **Aşama değişince bildirim** gelir. Bildirimi sunucu göndermez: uygulama arka planda durumu belirli aralıklarla kendisi denetler ve son gördüğünden farklıysa bildirimi telefonda üretir. Sunucu, anahtar ya da cihaz kaydı gerekmez; karşılığında bildirim birkaç saat gecikebilir (denetimin ne zaman çalışacağına iOS karar verir) ve uygulama elle kapatıldıysa gelmeyebilir. Anında bildirim için sunucudan gönderim (APNs) gerekir — sıradaki adım.
- Takip kodu, pasaport numarası ve son görülen durum yalnız telefonun Anahtar Zinciri'nde durur; **Beni unut** ile silinir. Düğmeye basmayan müşteri için hiçbir şey saklanmaz.

## Siteyle nasıl eşleniyor?

- **İçerik:** site her yayında `https://vizemia.com/assets/uygulama.json` dosyasını yazar (VizeMia deposu → `scripts/uygulama-akisi.mjs`): ülke rehberleri, blog yazıları (panelden yayımlananlar dâhil), SSS, harçlar, süreç adımları, ülke listesi, iletişim ve mesai. Uygulama açılınca bu dosyayı, vitrini (`vitrin.json`) ve kuru (`kur.json`) indirir. Panelde bir yazı yayımlanınca 2–3 dakikada sitede, uygulamanın sonraki açılışında telefonda olur; **yeni App Store sürümü gerekmez.**
- **Çevrimdışı:** uygulamanın içinde bu dosyaların bir kopyası gelir (`Cekirdek/Sources/VizeMiaCekirdek/Kaynaklar/`). İnternet yokken ya da ilk açılışta ekran boş kalmaz; son indirilen kopya da cihazda saklanır.
- **Formlar ve takip:** siteyle aynı Firestore projesine (`vieze-941cf`), aynı güvenlik kurallarından geçerek yazar ve okur. Takip anahtarı sitedekiyle aynı: `SHA-256("vizemia-takip|" + kod + "|" + PASAPORT)`.
- **Kurallar:** harf çevirme (Almanya'da Ö/Ü kalır), telefon ve T.C. kimlik doğrulaması, mesai saatleri, arama saati seçici, vitrin tarihi — hepsi sitedeki JavaScript'in birebir karşılığı; testleri de aynı örnekleri kullanır.

**Sözleşme:** `uygulama.json`'daki alan adları `Akis.swift` ile aynıdır. Site alan kaldırmaz, yalnız ekler; uygulama bilmediği alanı ve blok türünü atlar. Böylece telefonlardaki eski sürüm bozulmaz.

## Klasörler

| Klasör | İçerik |
|---|---|
| `Cekirdek/` | Ekran içermeyen bütün mantık (Swift paketi): takip, Firestore, mesai, form kuralları, içerik modeli, Markdown. Linux'ta da derlenir ve test edilir. |
| `App/` | SwiftUI ekranları, tema, görseller. |
| `Yapi/` | `Info.plist` ekleri, App Store'a gönderim ayarı. |
| `project.yml` | Xcode projesi buradan üretilir ([XcodeGen](https://github.com/yonaskolb/XcodeGen)); `.xcodeproj` depoda tutulmaz. |
| `.github/workflows/` | `derle.yml` (her değişiklikte test + derleme), `testflight.yml` (telefona gönderim). |

## Mac olmadan nasıl çalışılıyor?

- **Derleme GitHub'ın Mac sunucularında yapılır.** `main` dalına her değişiklikte **Actions → Derle ve test et** çalışır: çekirdek testleri (Linux) ve uygulamanın derlenmesi (Mac).
- **Telefona TestFlight ile gelir.** **Actions → TestFlight'a gönder → Run workflow** uygulamayı imzalayıp App Store Connect'e yükler; birkaç dakika sonra telefondaki TestFlight uygulamasında görünür.
- Özel depoda Mac dakikaları 10 kat sayılır (ücretsiz planda ayda 2.000 dakika ≈ 200 Mac dakikası; bir derleme 5–8 dakika). Bu yüzden derleme yalnız kod değişince çalışır.

## TestFlight kurulumu (bir kez)

1. **Uygulama kaydı:** [App Store Connect](https://appstoreconnect.apple.com) → Apps → **+** → New App. Platform: iOS · Ad: VizeMia · Dil: Türkçe · Bundle ID: `com.vizemia.app` · SKU: `vizemia-ios`.
   Bundle ID listede yoksa önce [Identifiers](https://developer.apple.com/account/resources/identifiers/list) → **+** → App IDs → App → Bundle ID: `com.vizemia.app` (Explicit).
2. **API anahtarı:** App Store Connect → Users and Access → **Integrations** → App Store Connect API → **+**. Ad: `GitHub`, erişim: **Admin**. Oluşunca `.p8` dosyasını indirin (yalnız bir kez indirilebilir) ve sayfadaki **Key ID** ile **Issuer ID**'yi not edin.
3. **Ekip kimliği:** [developer.apple.com/account](https://developer.apple.com/account) → Membership details → **Team ID**.
4. **GitHub gizli ayarları:** bu depo → Settings → Secrets and variables → Actions → New repository secret:
   - `ASC_KEY_ID` — Key ID
   - `ASC_ISSUER_ID` — Issuer ID
   - `ASC_KEY_P8` — `.p8` dosyasının içeriğinin tamamı (`-----BEGIN PRIVATE KEY-----` satırı dâhil)
   - `APPLE_TEAM_ID` — Team ID
5. **Gönder:** Actions → **TestFlight'a gönder** → Run workflow. Bitince App Store Connect → TestFlight'ta derleme görünür; kendinizi "Internal Testing" grubuna ekleyin, telefonda TestFlight uygulamasından kurun.

Anahtar dosyası depoya eklenmez; yalnız GitHub gizli ayarlarında durur.

## Geliştirme

```bash
cd Cekirdek && swift test
```

Form kayıtlarını gerçek güvenlik kurallarına karşı denemek için (VizeMia deposunun klasöründen, canlı veriye dokunmadan):

```bash
npx firebase-tools emulators:exec --only firestore --project demo-vizemia "cd ../vizemia-ios/Cekirdek && swift test"
```

Mac'te projeyi açmak için:

```bash
brew install xcodegen && xcodegen generate && open VizeMia.xcodeproj
```

### Gömülü içeriği yenilemek

Uygulamayla gelen kopya, yeni bir sürüm çıkarılmadan önce siteden yenilenir:

```bash
cd Cekirdek/Sources/VizeMiaCekirdek/Kaynaklar && for d in uygulama vitrin kur; do curl -fsS "https://vizemia.com/assets/$d.json" -o "$d.json"; done
```
