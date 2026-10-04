import SwiftUI

/// Estilo "mate oscuro con cristal": tarjetas casi negras con borde de luz, títulos a dos tonos,
/// una tarjeta cálida protagonista y barra flotante mínima.
enum NX {
    static let blue = Color(red: 0.16, green: 0.40, blue: 0.93)
    static let red = Color(red: 0.90, green: 0.13, blue: 0.27)
    static let green = Color(red: 0.20, green: 0.80, blue: 0.36)
    static let salmon = Color(red: 0.86, green: 0.46, blue: 0.38)
    static let periwinkle = Color(red: 0.45, green: 0.48, blue: 1.0)
    static let gold = Color(red: 0.86, green: 0.68, blue: 0.38)
    static let sage = Color(red: 0.50, green: 0.78, blue: 0.62)
    static let mute = Color.white.opacity(0.55)
    static let dim = Color.white.opacity(0.4)
}

struct NXBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.035, blue: 0.045)
            Circle().fill(NX.salmon.opacity(0.22)).frame(width: 360).blur(radius: 120).offset(x: -150, y: -330)
            Circle().fill(NX.periwinkle.opacity(0.20)).frame(width: 340).blur(radius: 130).offset(x: 170, y: 300)
        }
        .ignoresSafeArea()
    }
}

/// Tarjeta mate: degradado casi negro, borde de luz que se apaga hacia abajo.
struct DarkCard: ViewModifier {
    var radius: CGFloat = 34
    var padding: CGFloat = 20
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial.opacity(0.35), in: shape)
            .background(
                shape.fill(LinearGradient(
                    colors: tint.map { [$0.opacity(0.55), $0.opacity(0.18)] } ?? [.white.opacity(0.10), .white.opacity(0.025)],
                    startPoint: .top, endPoint: .bottom))
            )
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

extension View {
    func darkCard(_ radius: CGFloat = 34, padding: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(DarkCard(radius: radius, padding: padding, tint: tint))
    }
    func glassCard(_ radius: CGFloat = 30, padding: CGFloat = 18) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}

/// Título a dos tonos: primera línea blanca, segunda gris.
struct TwoTone: View {
    let top: String
    let bottom: String
    var size: CGFloat = 32
    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(top).foregroundStyle(.white)
            Text(bottom).foregroundStyle(.white.opacity(0.42)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .font(.system(size: size, weight: .semibold)).tracking(-0.5)
    }
}

/// Botón circular de cristal (buscar, menú...).
struct CircleGlass: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 17, weight: .medium)).frame(width: 50, height: 50) }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}
