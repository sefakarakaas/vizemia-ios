import XCTest

/// Uygulamayı simülatörde açar, sekmeleri gezer, birkaç akışı dener ve ekran
/// görüntüsü alır. Mac olmadan ekranların nasıl göründüğünü görmek için:
/// Actions → "Ekran görüntüleri" işi bunları indirilebilir dosya olarak verir.
///
/// CANLI VERİYE YAZMAZ: başvuru formu bilerek eksik bırakılır (vize türü ve
/// onay seçilmez), gönderim doğrulamada durur. Takip sorgusu yalnız okur.
final class EkranGoruntuleri: XCTestCase {
    private var app: XCUIApplication!
    private var sira = 0

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    func testEkranlar() {
        XCTAssertTrue(app.tabBars.buttons["Ana Sayfa"].waitForExistence(timeout: 30))
        bekle(3)   // vitrin görseli insin
        cek("ana-sayfa")
        app.swipeUp(); cek("ana-sayfa-2")

        // --- Takip: olmayan kayıt sorgulanır; uygulama Firestore'dan cevap alıp "bulunamadı" demeli.
        sekme("Takip")
        yaz("takip-kod", "091234")
        yaz("takip-pasaport", "u12345678")
        app.buttons["Durumu sorgula"].tap()
        XCTAssertTrue(metin("bulunamadı").waitForExistence(timeout: 25), "Takip sorgusu cevap vermedi")
        XCTAssertEqual(app.textFields["takip-pasaport"].value as? String, "U12345678", "Pasaport numarası büyük harfe çevrilmedi")
        cek("takip-bulunamadi")

        // --- Başvur: harf kuralı, ülke seçici, saat seçici, doğrulama hatası.
        sekme("Başvur")
        yaz("basvuru-ad", "ayşe")
        yaz("basvuru-soyad", "öztürk")
        XCTAssertEqual(app.textFields["basvuru-ad"].value as? String, "AYSE", "Ad Latin büyük harfe çevrilmedi")
        XCTAssertEqual(app.textFields["basvuru-soyad"].value as? String, "OZTURK", "Soyad Latin büyük harfe çevrilmedi")
        yaz("basvuru-telefon", "05499072523")
        cek("basvuru-dolu")

        app.swipeUp()   // klavye kapanır, ülke alanı görünür
        let ulke = app.buttons["basvuru-ulke"]
        if ulke.waitForExistence(timeout: 8) {
            ulke.tap()
            bekle(1)
            cek("ulke-secici")
            let fransa = dugme("Fransa")
            if fransa.waitForExistence(timeout: 5) { fransa.tap() } else { XCTFail("Ülke listesinde Fransa yok") }
            bekle(1)
        } else {
            XCTFail("Ülke düğmesi yok")
        }

        let saat = dugme("Saat seçeyim")
        if saat.waitForExistence(timeout: 5) {
            saat.tap()   // mesai içindeyse iki seçenek çıkar; dışındaysa seçici zaten açıktır
        }
        bekle(1)
        cek("basvuru-saat")
        app.swipeUp(); cek("basvuru-saat-2")
        app.swipeUp(); app.swipeUp()
        let gonder = app.buttons["Beni arayın"]
        if gonder.waitForExistence(timeout: 5) {
            gonder.tap()   // vize türü seçilmedi: doğrulama durdurur, hiçbir şey gönderilmez
            XCTAssertTrue(metin("Vize türünü seçin").waitForExistence(timeout: 5), "Doğrulama hatası görünmedi")
            bekle(1)
            cek("basvuru-hata")
        } else {
            XCTFail("Gönder düğmesi yok")
        }

        sekme("Harç & Kur")
        cek("harclar")

        sekme("Daha")
        dokun("Vize gereken ülkeler")
        cek("ulkeler")
        geri()

        dokun("Ülke rehberleri")
        bekle(2)
        let schengen = dugme("Schengen")
        if schengen.waitForExistence(timeout: 5) {
            schengen.tap()
            bekle(2)
            cek("rehber-schengen")
            app.swipeUp(); cek("rehber-schengen-2")
            app.swipeUp(); cek("rehber-schengen-3")
        }
    }

    // MARK: - Yardımcılar

    private func sekme(_ ad: String) {
        let d = app.tabBars.buttons[ad]
        XCTAssertTrue(d.waitForExistence(timeout: 10), "\(ad) sekmesi yok")
        d.tap()
    }

    private func yaz(_ kimlik: String, _ metin: String) {
        let kutu = app.textFields[kimlik]
        XCTAssertTrue(kutu.waitForExistence(timeout: 10), "\(kimlik) kutusu yok")
        kutu.tap()
        kutu.typeText(metin)
    }

    /// Etiketinde bu metin geçen herhangi bir öge (hata satırı, bilgi metni).
    private func metin(_ parca: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", parca)).firstMatch
    }

    /// Etiketinde (ya da içindeki yazıda) bu metin geçen düğme.
    private func dugme(_ parca: String) -> XCUIElement {
        let p = NSPredicate(format: "label CONTAINS[c] %@", parca)
        let kendisi = app.buttons.matching(p).firstMatch
        if kendisi.waitForExistence(timeout: 4) { return kendisi }
        return app.buttons.containing(p).firstMatch
    }

    private func dokun(_ ad: String) {
        let d = app.buttons[ad].firstMatch
        if d.waitForExistence(timeout: 8) {
            d.tap()
        } else {
            let m = app.staticTexts[ad].firstMatch
            XCTAssertTrue(m.waitForExistence(timeout: 3), "\(ad) bulunamadı")
            m.tap()
        }
    }

    private func geri() {
        let d = app.navigationBars.buttons.firstMatch
        if d.waitForExistence(timeout: 5) { d.tap() }
    }

    private func bekle(_ saniye: TimeInterval) {
        Thread.sleep(forTimeInterval: saniye)
    }

    private func cek(_ ad: String) {
        sira += 1
        let goruntu = XCUIScreen.main.screenshot()
        let ek = XCTAttachment(screenshot: goruntu)
        ek.name = String(format: "%02d-%@", sira, ad)
        ek.lifetime = .keepAlways
        add(ek)
        // Simülatör ana makinenin diskine yazabilir; iş akışı klasörü dosya olarak yükler.
        let klasor = ProcessInfo.processInfo.environment["EKRAN_KLASORU"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: klasor, withIntermediateDirectories: true)
        let yol = (klasor as NSString).appendingPathComponent(String(format: "%02d-%@.png", sira, ad))
        try? goruntu.pngRepresentation.write(to: URL(fileURLWithPath: yol))
    }
}
