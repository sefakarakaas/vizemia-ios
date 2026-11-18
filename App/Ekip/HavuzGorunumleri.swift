import SwiftUI
import VizeMiaCekirdek

/// Görseli kutuyu dolduracak biçimde, "görünen alan" (x% y%) ekranda kalacak şekilde
/// gösterir (CSS object-fit: cover + object-position).
struct OdakliGorsel: View {
    let yol: String
    let odak: String
    @State private var resim: UIImage?

    var body: some View {
        GeometryReader { g in
            ZStack {
                Tema.soluk
                if let r = resim {
                    let o = FotoHavuzu.odakOku(odak)
                    let olcek = max(g.size.width / max(r.size.width, 1), g.size.height / max(r.size.height, 1))
                    let w = r.size.width * olcek, h = r.size.height * olcek
                    Image(uiImage: r)
                        .resizable()
                        .frame(width: w, height: h)
                        .offset(x: (g.size.width - w) * (CGFloat(o.x) - 0.5), y: (g.size.height - h) * (CGFloat(o.y) - 0.5))
                        .frame(width: g.size.width, height: g.size.height)
                } else if !yol.isEmpty {
                    ProgressView()
                } else {
                    Image(systemName: "photo").foregroundStyle(Tema.silik)
                }
            }
            .clipped()
        }
        .task(id: yol) { resim = yol.isEmpty ? nil : await Gorsel.resim(yol) }
    }
}

/// Görünen alan seçici: fotoğrafın tamamı; dokunulan yerde işaret.
struct OdakSecici: View {
    let yol: String
    @Binding var odak: String
    @State private var resim: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ekranda görünmesini istediğiniz yere dokunun.").font(.caption).foregroundStyle(Tema.govde)
            if let r = resim {
                Image(uiImage: r)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        GeometryReader { g in
                            let o = FotoHavuzu.odakOku(odak)
                            ZStack {
                                Color.clear.contentShape(Rectangle())
                                    .onTapGesture(coordinateSpace: .local) { p in
                                        odak = FotoHavuzu.odakYaz(Double(p.x / max(g.size.width, 1)) * 100, Double(p.y / max(g.size.height, 1)) * 100)
                                    }
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                                    .background(Circle().fill(Tema.turkuaz.opacity(0.6)))
                                    .frame(width: 26, height: 26)
                                    .shadow(radius: 3)
                                    .position(x: g.size.width * CGFloat(o.x), y: g.size.height * CGFloat(o.y))
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Tema.koseKucuk))
                    .animation(Hareket.yay, value: odak)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task(id: yol) { resim = await Gorsel.resim(yol) }
    }
}
