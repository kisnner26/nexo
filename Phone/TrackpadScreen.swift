import NexoCore
import SwiftUI
import UIKit

/// Superficie táctil real: un dedo mueve, dos dedos hacen scroll, un toque es clic, dos dedos tocando es clic derecho.
struct TrackpadSurface: UIViewRepresentable {
    var onMove: (Int, Int) -> Void
    var onScroll: (Int) -> Void
    var onTap: () -> Void
    var onRightClick: () -> Void
    var onTouch: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let c = context.coordinator
        let pan1 = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan1(_:)))
        pan1.minimumNumberOfTouches = 1; pan1.maximumNumberOfTouches = 1
        let pan2 = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan2(_:)))
        pan2.minimumNumberOfTouches = 2; pan2.maximumNumberOfTouches = 2
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap))
        let two = UITapGestureRecognizer(target: c, action: #selector(Coordinator.twoTap))
        two.numberOfTouchesRequired = 2
        [pan1, pan2, tap, two].forEach { v.addGestureRecognizer($0) }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject {
        var parent: TrackpadSurface
        private var rx: CGFloat = 0, ry: CGFloat = 0
        private let light = UIImpactFeedbackGenerator(style: .light)
        init(_ p: TrackpadSurface) { parent = p }

        @objc func pan1(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view); g.setTranslation(.zero, in: g.view)
            rx += t.x; ry += t.y
            let dx = Int(rx.rounded(.towardZero)), dy = Int(ry.rounded(.towardZero))
            rx -= CGFloat(dx); ry -= CGFloat(dy)
            if g.state == .began { parent.onTouch() }
            if dx != 0 || dy != 0 { parent.onMove(dx, dy) }
        }
        @objc func pan2(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view); g.setTranslation(.zero, in: g.view)
            if Int(t.y) != 0 { parent.onScroll(Int(t.y)) }
        }
        @objc func tap() { light.impactOccurred(); parent.onTouch(); parent.onTap() }
        @objc func twoTap() { light.impactOccurred(intensity: 0.8); parent.onRightClick() }
    }
}

struct TrackpadScreen: View {
    @ObservedObject var client: NexoClient
    @State private var text = ""
    @State private var touched = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 14) {
            if client.status?.accessibility == false { AccessibilityBanner() }
            ZStack {
                Color.clear.darkCard(40, padding: 0)
                DotGrid().opacity(0.30).clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                Dial().frame(maxHeight: .infinity, alignment: .bottom).clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .allowsHitTesting(false)
                if !touched {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.point.up.left").font(.system(size: 34, weight: .light))
                        Text(client.isConnected ? "Un dedo mueve · toca para hacer clic\nDos dedos: scroll · toca con dos: clic derecho" : "Sin conexión con la Mac")
                            .font(.footnote).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(NX.mute).allowsHitTesting(false)
                }
                TrackpadSurface(
                    onMove: { client.pointer(dx: $0, dy: $1) },
                    onScroll: { client.pointer(scroll: $0) },
                    onTap: { client.send(.click) },
                    onRightClick: { client.send(.rightClick) },
                    onTouch: { if !touched { withAnimation { touched = true } } }
                )
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 8) {
                keyButton("delete.left") { client.send(.pressKey("delete")) }
                keyButton("return") { client.send(.pressKey("return")) }
                TextField("Escribir en la Mac", text: $text)
                    .focused($typing).submitLabel(.send).onSubmit(send)
                    .padding(.horizontal, 18).frame(height: 50)
                    .glassEffect(.regular, in: .capsule)
                Button(action: send) { Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)).frame(width: 50, height: 50) }
                    .buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(NX.blue).disabled(text.isEmpty)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
    }

    private func send() {
        guard !text.isEmpty else { return }
        client.send(.typeText(text)); text = ""
    }

    private func keyButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 17, weight: .medium)).frame(width: 46, height: 46) }
            .buttonStyle(.plain).background(Color.white.opacity(0.12), in: Circle())
    }
}

/// Rejilla de puntos tenue para dar textura a la superficie.
/// Arco de marcas en la parte baja, como el dial de la referencia.
struct Dial: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height + size.width * 0.28)
            let r = size.width * 0.78
            for i in -40...40 {
                let a = Double(i) * 0.0105 - .pi / 2
                let long = i % 5 == 0
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                p.addLine(to: CGPoint(x: c.x + cos(a) * (r - (long ? 18 : 9)), y: c.y + sin(a) * (r - (long ? 18 : 9))))
                ctx.stroke(p, with: .color(.white.opacity(i == 0 ? 0.9 : (long ? 0.4 : 0.2))), lineWidth: i == 0 ? 2 : 1)
            }
        }
        .frame(height: 140)
    }
}

struct DotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 26
            for x in stride(from: step / 2, to: size.width, by: step) {
                for y in stride(from: step / 2, to: size.height, by: step) {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(.white.opacity(0.5)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
