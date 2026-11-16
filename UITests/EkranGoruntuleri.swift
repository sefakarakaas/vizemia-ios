import XCTest

/// Uygulamayı simülatörde açar, sekmeleri gezer ve ekran görüntüsü alır.
/// Mac olmadan ekranların nasıl göründüğünü görmek için: Actions →
/// "Ekran görüntüleri" işi bunları indirilebilir dosya olarak verir.
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
        app.swipeUp(); cek("ana-sayfa-3")
        app.swipeUp(); cek("ana-sayfa-4")
        app.swipeUp(); cek("ana-sayfa-5")

        sekme("Takip")
        cek("takip")

        sekme("Başvur")
        cek("basvuru")
        app.swipeUp(); cek("basvuru-2")
        app.swipeUp(); cek("basvuru-3")
        app.swipeUp(); cek("basvuru-4")

        sekme("Harç & Kur")
        cek("harclar")
        app.swipeUp(); cek("harclar-2")

        sekme("Daha")
        cek("daha")

        dokun("Ülke rehberleri")
        bekle(2)
        cek("rehberler")
        let almanya = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Almanya")).firstMatch
        if almanya.waitForExistence(timeout: 5) {
            almanya.tap()
            bekle(2)
            cek("rehber-almanya")
            app.swipeUp(); cek("rehber-almanya-2")
            app.swipeUp(); cek("rehber-almanya-3")
            geri()
        }
        geri()

        dokun("Blog")
        bekle(1)
        cek("blog")
        geri()

        dokun("Sıkça sorulan sorular")
        cek("sss")
        geri()

        dokun("Destek formu")
        cek("destek")
        geri()

        dokun("İletişim ve harita")
        bekle(3)
        cek("iletisim")
        geri()

        dokun("Vize gereken ülkeler")
        cek("ulkeler")
    }

    // MARK: - Yardımcılar

    private func sekme(_ ad: String) {
        let d = app.tabBars.buttons[ad]
        XCTAssertTrue(d.waitForExistence(timeout: 10), "\(ad) sekmesi yok")
        d.tap()
        bekle(1)
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
        bekle(1)
    }

    private func geri() {
        let d = app.navigationBars.buttons.firstMatch
        if d.exists { d.tap() }
        bekle(1)
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
