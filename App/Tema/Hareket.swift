import SwiftUI

/// Uygulamanın hareket dili: kısa, yumuşak, abartısız. Ekran açılırken
/// parçalar sırayla hafifçe yukarı kayarak belirir; sayılar yerinde değişir.
/// Cihazda "Hareketi azalt" açıksa hiçbir şey kaymaz, yalnız belirir.
enum Hareket {
    /// Ekran geçişlerinde ve seçimlerde kullanılan yay.
    static let yay = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let hizli = Animation.easeOut(duration: 0.2)
}

private struct Belirme: ViewModifier {
    let sira: Int
    @State private var gorundu = false
    @Environment(\.accessibilityReduceMotion) private var hareketAz

    func body(content: Content) -> some View {
        content
            .opacity(gorundu ? 1 : 0)
            .offset(y: gorundu || hareketAz ? 0 : 10)
            .onAppear {
                guard !gorundu else { return }
                // İlk birkaç parça sırayla; sonrakiler beklemeden.
                let gecikme = Double(min(sira, 8)) * 0.045
                withAnimation(hareketAz ? .easeOut(duration: 0.15) : Hareket.yay.delay(gecikme)) { gorundu = true }
            }
    }
}

extension View {
    /// Ekran açılırken sırayla hafifçe belirme (0, 1, 2 … sırası).
    func belirme(_ sira: Int = 0) -> some View { modifier(Belirme(sira: sira)) }
}

/// Basılınca hafifçe küçülen kart (dokunulduğu belli olsun).
struct KartDugmesi: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(Hareket.hizli, value: configuration.isPressed)
    }
}
