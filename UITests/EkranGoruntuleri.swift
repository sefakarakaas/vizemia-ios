import XCTest

/// Uygulamayı simülatörde açar, sekmeleri gezer, birkaç akışı dener ve ekran
/// görüntüsü alır. Mac olmadan ekranların nasıl göründüğünü görmek için:
/// Actions → "Ekran görüntüleri" işi bunları indirilebilir dosya olarak verir.
///
/// CANLI VERİYE YAZMAZ: başvuru formu bilerek eksik bırakılır (vize türü ve
/// onay seçilmez), gönderim doğrulamada durur. Takip sorgusu yalnız okur.
final class EkranGoruntuleri: XCTestCase {
    private var app: XCUIApplication!
    /// Görüntü sırası bütün testlerde ortak: dosya adları çakışmasın.
    private static var sira = 0

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    /// "Beni unutma" demiş müşteri: açılışta adıyla karşılanır, Takip sekmesi
    /// doğrudan animasyonlu süreci gösterir. Örnek kayıtla açılır (ağa ve
    /// Anahtar Zinciri'ne dokunmaz).
    func testHatirlananMusteri() {
        app.launchArguments = ["-ornek-takip"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Ana Sayfa"].waitForExistence(timeout: 60))
        XCTAssertTrue(metin(", Ahmet").waitForExistence(timeout: 10), "Açılışta karşılama yok")
        bekle(2)
        cek("karsilama")

        sekme("Takip")
        XCTAssertTrue(metin("Başvurunuzun yolculuğu").waitForExistence(timeout: 10), "Takip sekmesi süreci doğrudan göstermedi")
        XCTAssertFalse(app.textFields["takip-kod"].exists, "Hatırlanan müşteriye sorgu formu gösterildi")
        cek("takip-hatirlanan-animasyon")   // pasaport yolda
        bekle(2)
        cek("takip-hatirlanan")
        surukle(0.80, 0.25)
        cek("takip-hatirlanan-2")
        surukle(0.80, 0.25)
        cek("takip-hatirlanan-3")

        // "Beni unut" → onay → sorgu formu geri gelir.
        let unut = app.buttons["beni-unut"]
        if unut.waitForExistence(timeout: 5) {
            unut.tap()
            bekle(1)
            cek("takip-unut-onayi")
            // Onay penceresi açıkken sayfadaki aynı adlı düğmeye dokunulamaz;
            // dokunulabilen "Beni unut" penceredeki onaydır.
            let adaylar = app.buttons.matching(NSPredicate(format: "label == %@", "Beni unut"))
            var onaylandi = false
            for i in 0..<adaylar.count {
                let aday = adaylar.element(boundBy: i)
                if aday.identifier != "beni-unut", aday.isHittable {
                    aday.tap()
                    onaylandi = true
                    break
                }
            }
            XCTAssertTrue(onaylandi, "Onay penceresindeki düğme bulunamadı")
            XCTAssertTrue(app.textFields["takip-kod"].waitForExistence(timeout: 8), "Beni unut sonrası sorgu formu gelmedi")
            cek("takip-unutuldu")
        } else {
            XCTFail("Beni unut düğmesi yok")
        }
    }

    /// Çalışan girişi yapmış danışman: sol üstte "…, Sefa", özet, talepler, takvim.
    /// Örnek veriyle açılır (ağa bağlanmaz).
    func testEkip() {
        app.launchArguments = ["-ornek-ekip"]
        app.launch()
        XCTAssertTrue(metin(", Sefa").waitForExistence(timeout: 60), "Danışman karşılaması yok")
        bekle(2)
        cek("ekip-ana")
        surukle(0.80, 0.25)
        cek("ekip-ana-2")

        sekme("Talepler")
        XCTAssertTrue(metin("AYSE OZTURK").waitForExistence(timeout: 10), "Talep listesi boş")
        bekle(1)
        cek("ekip-talepler")
        metin("AYSE OZTURK").tap()
        XCTAssertTrue(metin("Görüşme sonucu").waitForExistence(timeout: 8), "Talep ayrıntısı açılmadı")
        bekle(1)
        cek("ekip-talep")
        surukle(0.80, 0.30)
        cek("ekip-talep-2")

        sekme("Takvim")
        bekle(1)
        cek("ekip-takvim")
        let ay = app.buttons["Ay"].firstMatch
        if ay.waitForExistence(timeout: 4) { ay.tap(); bekle(1); cek("ekip-takvim-ay") }

        sekme("Hesabım")
        bekle(1)
        cek("ekip-hesap")

        // Başvurular: ana sayfa → Müşteriler → Başvurular → ayrıntı.
        sekme("Ana Sayfa")
        let musteriler = dugme("Müşteriler")
        if !gorunur(musteriler) { surukle(0.80, 0.30) }
        musteriler.tap()
        let basvurular = dugme("Başvurular")
        XCTAssertTrue(basvurular.waitForExistence(timeout: 8), "Müşteriler bölümü açılmadı")
        basvurular.tap()
        XCTAssertTrue(metin("ZEYNEP ARSLAN").waitForExistence(timeout: 10), "Başvuru listesi boş")
        bekle(1)
        cek("ekip-basvurular")
        dugme("Aktaş ailesi").tap()
        bekle(1)
        cek("ekip-basvurular-grup")
        metin("ZEYNEP ARSLAN").tap()
        XCTAssertTrue(metin("Evrak kontrol listesi").waitForExistence(timeout: 8), "Başvuru ayrıntısı açılmadı")
        bekle(1)
        cek("ekip-basvuru")
        for i in 2...10 {
            surukle(0.85, 0.25)
            bekle(0.6)
            cek("ekip-basvuru-\(i)")
        }

        // Yeni başvuru formu (listeye dön → "+").
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let yeni = app.buttons["Yeni başvuru"].firstMatch
        XCTAssertTrue(yeni.waitForExistence(timeout: 8), "Yeni başvuru düğmesi yok")
        yeni.tap()
        XCTAssertTrue(metin("Başvurulan ülke").waitForExistence(timeout: 8), "Form açılmadı")
        bekle(1)
        cek("ekip-yeni-basvuru")
        for i in 2...4 {
            surukle(0.85, 0.25)
            bekle(0.6)
            cek("ekip-yeni-basvuru-\(i)")
        }
    }

    func testEkranlar() {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Ana Sayfa"].waitForExistence(timeout: 60))
        bekle(3)   // vitrin görseli insin
        cek("ana-sayfa")

        // --- Ana sayfa kayıyor mu? Önce parmak vitrinin altındayken, sonra üstündeyken.
        let ulkelerBasligi = app.staticTexts["Nereye gidiyorsunuz?"]
        surukle(0.80, 0.30)
        XCTAssertTrue(gorunur(ulkelerBasligi), "Ana sayfa kaymadı (parmak hızlı işlemlerin üstünde)")
        cek("ana-sayfa-2")
        surukle(0.30, 0.85)   // başa dön
        XCTAssertFalse(gorunur(ulkelerBasligi), "Ana sayfa başa dönmedi")
        surukle(0.45, 0.05)   // parmak vitrinin üstünde
        XCTAssertTrue(gorunur(ulkelerBasligi), "Ana sayfa kaymadı (parmak vitrinin üstünde)")
        cek("ana-sayfa-3")

        // --- Takip: olmayan kayıt sorgulanır; uygulama Firestore'dan cevap alıp "bulunamadı" demeli.
        sekme("Takip")
        yaz("takip-kod", "091234")
        // Klavyedeki "ara" tuşuyla gönderilir (klavye açıkken düğmenin yarısı kapanıyor).
        yaz("takip-pasaport", "u12345678\n")
        XCTAssertTrue(metin("bulunamadı").waitForExistence(timeout: 25), "Takip sorgusu cevap vermedi")
        XCTAssertEqual(app.textFields["takip-pasaport"].value as? String, "U12345678", "Pasaport numarası büyük harfe çevrilmedi")
        cek("takip-bulunamadi")

        // --- Başvur: harf kuralı, klavyeyi kapatma, ülke arama, saat seçici, doğrulama hatası.
        sekme("Başvur")
        // Klavyedeki "sonraki" tuşu sıradaki kutuya geçirir: ad → soyad → telefon.
        yaz("basvuru-ad", "ayşe\n")
        bekle(1)   // odak sıradaki kutuya geçsin
        app.typeText("öztürk\n")
        bekle(1)
        app.typeText("05499072523")
        XCTAssertEqual(app.textFields["basvuru-ad"].value as? String, "AYSE", "Ad Latin büyük harfe çevrilmedi")
        XCTAssertEqual(app.textFields["basvuru-soyad"].value as? String, "OZTURK", "Soyad Latin büyük harfe çevrilmedi")
        XCTAssertEqual(app.textFields["basvuru-telefon"].value as? String, "05499072523", "Sonraki tuşu telefona geçirmedi")
        cek("basvuru-klavye")
        // Rakam klavyesinde kapatma tuşu yok; üstündeki "Bitti" düğmesi kapatmalı.
        let bitti = app.buttons["Bitti"]
        XCTAssertTrue(bitti.waitForExistence(timeout: 5), "Klavyenin üstünde Bitti düğmesi yok")
        if bitti.exists { bitti.tap() }
        bekle(1)
        if app.keyboards.firstMatch.exists {
            // "Bitti" çalışmadıysa ikinci yol: kaydırınca klavye kapanmalı.
            XCTFail("Bitti düğmesi klavyeyi kapatmadı")
            surukle(0.45, 0.30)
            bekle(1)
        }
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Klavye kapanmadı")

        surukle(0.70, 0.40)   // ülke alanı ekranın ortasına gelsin
        let ulke = app.buttons["basvuru-ulke"]
        XCTAssertTrue(ulke.waitForExistence(timeout: 8), "Ülke düğmesi yok")
        ulke.tap()
        // Türkçe'ye duyarlı arama: "isvi" yazan "İsviçre"yi bulmalı.
        let ara = app.searchFields.firstMatch
        if ara.waitForExistence(timeout: 6) {
            ara.tap()
            ara.typeText("isvi")
        } else {
            XCTFail("Ülke listesinde arama kutusu yok")
        }
        cek("ulke-secici")
        let isvicre = dugme("İsviçre")
        if isvicre.waitForExistence(timeout: 5) {
            isvicre.tap()
        } else {
            XCTFail("Aramada İsviçre çıkmadı")
            let vazgec = app.buttons["Vazgeç"]
            if vazgec.exists { vazgec.tap() }
        }
        bekle(1)

        let saat = dugme("Saat seçeyim")
        if saat.waitForExistence(timeout: 5) {
            saat.tap()   // mesai içindeyse iki seçenek çıkar; dışındaysa seçici zaten açıktır
        }
        bekle(1)
        cek("basvuru-saat")
        surukle(0.75, 0.30)
        let ogleden = dugme("Öğleden sonra")
        if ogleden.waitForExistence(timeout: 4) { ogleden.tap() }   // gruptaki bütün aralıklar seçilir
        bekle(1)   // basılı görünüm geçsin, grup kutusu işaretli hâliyle çıksın
        cek("basvuru-saat-2")
        surukle(0.80, 0.15); surukle(0.80, 0.15)
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
            surukle(0.80, 0.20); cek("rehber-schengen-2")
            surukle(0.80, 0.20); cek("rehber-schengen-3")
        } else {
            XCTFail("Schengen rehberi yok")
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

    /// Ekranda yavaşça sürükler (fırlatmadan): y1 → y2, ekran yüksekliğinin oranı olarak.
    private func surukle(_ y1: CGFloat, _ y2: CGFloat) {
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y1))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y2))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .default, thenHoldForDuration: 0.15)
    }

    /// Öge ekranda ve dokunulabilir mi?
    private func gorunur(_ e: XCUIElement) -> Bool {
        e.exists && e.isHittable
    }

    private func bekle(_ saniye: TimeInterval) {
        Thread.sleep(forTimeInterval: saniye)
    }

    private func cek(_ ad: String) {
        EkranGoruntuleri.sira += 1
        let sira = EkranGoruntuleri.sira
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
