# VizeMia iOS — çalışma notları

vizemia.com'un iPhone uygulaması. Site deposu: `sefakarakaas/VizeMia` (panel, site, güvenlik kuralları).

## Temel ilkeler

- **Site tek kaynaktır.** İçerik `https://vizemia.com/assets/uygulama.json` dosyasından gelir (site deposu → `scripts/uygulama-akisi.mjs`). Bir metni uygulamaya elle yazmadan önce bu dosyaya eklenip eklenemeyeceğine bak. Sözleşme: alan kaldırılmaz, anlamı değiştirilmez; yalnız yeni alan eklenir (`Akis.swift` ↔ site deposundaki `tests/uygulama-akisi.test.mjs`).
- **Kurallar sitedeki JavaScript'in karşılığıdır** (harf çevirme, telefon, T.C. kimlik, mesai, saat seçici, vitrin tarihi, takip anahtarı). Bir kural değişirse iki depoda birlikte değişir. Formların alan listesi `firestore.rules` içindeki `hasOnly` listesiyle aynı olmalı.
- **Dil:** kod adları, yorumlar ve kullanıcıya görünen metinler Türkçe (site deposuyla aynı üslup). Yorumlar "neden"i anlatır.
- **Canlı veritabanına test verisi yazılmaz.** Form kayıtları Firestore emülatöründe denenir (README → Geliştirme). Ekran testi bilerek eksik form bırakır; hiçbir şey göndermez.

## Yapı

- `Cekirdek/` — ekran içermeyen bütün mantık (Swift paketi). Linux'ta derlenir: `cd Cekirdek && swift test`. Yeni mantık buraya, testiyle birlikte yazılır.
- `App/` — SwiftUI ekranları. Yalnız Mac'te derlenir.
- `project.yml` — Xcode projesi XcodeGen ile üretilir; `.xcodeproj` depoda yok.

## Mac yok: derleme GitHub'da

- `main`'e gönderilen her kod değişikliği **Derle ve test et** işini çalıştırır (çekirdek testleri + simülatör derlemesi, ~2 dk Mac).
- Ekranların nasıl göründüğünü görmek için **Ekran görüntüleri** işi elle çalıştırılır (~8 dk Mac); görüntüler işin dosyalarında (`ekran-goruntuleri`).
- Özel depoda Mac dakikaları 10 kat sayılır. Değişiklikleri toplu gönder; yalnız `.md` değişikliği derleme başlatmaz.
- Ekran kodu burada derlenemediği için dikkatli yazılır: bilinen, yerleşik SwiftUI arayüzleri (iOS 17+), belirsiz tür çıkarımlarından kaçınma (`Color.white`, `Text.LineStyle.single` gibi açık yazım).
- TestFlight: **TestFlight'a gönder** işi (README → TestFlight kurulumu). Anahtarlar yalnız GitHub gizli ayarlarında durur.
