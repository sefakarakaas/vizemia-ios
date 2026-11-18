// swift-tools-version: 5.9
// VizeMia çekirdeği: ekran içermeyen bütün mantık (takip anahtarı, Firestore,
// mesai, form doğrulamaları, içerik modeli). Linux'ta da derlenir; testler
// GitHub'da ve geliştirme ortamında Mac olmadan çalışır.
import PackageDescription

let package = Package(
    name: "VizeMiaCekirdek",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VizeMiaCekirdek", targets: ["VizeMiaCekirdek"]),
    ],
    targets: [
        .target(
            name: "VizeMiaCekirdek",
            resources: [.process("Kaynaklar")]
        ),
        .testTarget(
            name: "VizeMiaCekirdekTests",
            dependencies: ["VizeMiaCekirdek"],
            // Sitenin JavaScript'inden üretilmiş beklenen çıktılar (testler dosyadan okur).
            exclude: ["Ornekler"]
        ),
    ]
)
