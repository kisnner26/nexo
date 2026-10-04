import SwiftUI

/// Deslizador de cápsula: pista translúcida, relleno blanco, icono que se invierte.
struct CapsuleSlider: View {
    @Binding var value: Double
    let icon: String
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.13))
                Capsule().fill(.white).frame(width: max(g.size.height, g.size.width * value / 100))
                Image(systemName: icon).font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                    .blendMode(.difference).padding(.leading, 18)
            }
            .compositingGroup()
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value = max(0, min(100, ($0.location.x / g.size.width * 100).rounded())) }
                .onEnded { _ in onCommit(value) })
        }
        .frame(height: 46)
        .sensoryFeedback(.selection, trigger: Int(value / 5))
    }
}

/// Botón redondo con etiqueta pequeña debajo.
struct DotButton: View {
    let icon: String
    let label: String
    var active = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Button(action: action) {
                Image(systemName: icon).font(.system(size: 19, weight: .medium))
                    .foregroundStyle(active ? Color.black : .white)
                    .frame(width: 54, height: 54)
                    .background(active ? Color.white : Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .light), trigger: active)
    }
}

/// Mosaico grande para la hoja "Más".
struct BigTile: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 22, weight: .medium))
                Spacer(minLength: 0)
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).opacity(0.65) }
            }
            .foregroundStyle(active ? Color.black : .white)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .padding(18)
            .background(active ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .darkCard(28, padding: 0)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: active)
    }
}

/// Barra flotante mínima de tres iconos (como la referencia): el activo va en un círculo.
struct NXTabBar: View {
    @Binding var selection: Int
    let icons: [String]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(icons.enumerated()), id: \.offset) { i, icon in
                Button { withAnimation(.snappy(duration: 0.22)) { selection = i } } label: {
                    Image(systemName: icon).font(.system(size: 19, weight: .medium))
                        .foregroundStyle(selection == i ? Color.white : Color.white.opacity(0.45))
                        .frame(width: 58, height: 52)
                        .background(selection == i ? Color.white.opacity(0.14) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .glassEffect(.regular, in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
