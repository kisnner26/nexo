import NexoCore
import SwiftUI

struct WatchView: View {
    @ObservedObject var model: WatchModel
    @ObservedObject var client: NexoClient

    var body: some View {
        if model.code == nil {
            VStack(spacing: 8) {
                Image(systemName: "iphone.and.arrow.forward").font(.title2)
                Text("Empareja Nexo en el iPhone").font(.footnote).foregroundStyle(NX.mute).multilineTextAlignment(.center)
            }
            .containerBackground(for: .navigation) { NXBackdrop() }
        } else {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 8) {
                        link("play.fill", "Reproductor", model.lastStatus?.nowPlaying ?? "Música y volumen", tint: NX.salmon) { PlayerView(model: model, client: client) }
                        link("hand.point.up.left.fill", "Trackpad", model.canControl ? "Cursor y clics" : "Sin conexión") { TrackpadView(model: model, client: client) }
                        link("square.grid.2x2.fill", "Apps", "Abrir en la Mac") {
                            CatalogView(items: client.apps) { model.send(.openApp($0), haptic: .success) }
                        }
                        link("mic.fill", "Dictar", "Escribe en la Mac") { DictateView(model: model) }
                        link("slider.horizontal.3", "Sistema", "Bloquear, captura, brillo") { SystemView(model: model, client: client) }
                        link("battery.75percent", "\(model.lastStatus?.battery ?? 0)%", "Batería · CPU · memoria") { MacView(model: model, client: client) }
                    }
                    .padding(.horizontal, 4)
                }
                .containerBackground(for: .navigation) { NXBackdrop() }
            }
        }
    }

    private func link<D: View>(_ icon: String, _ title: String, _ sub: String, tint: Color? = nil, @ViewBuilder _ dest: () -> D) -> some View {
        NavigationLink { dest() } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium)).frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(sub).font(.system(size: 11)).foregroundStyle(NX.mute).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .darkCard(24, padding: 10, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

struct PlayerView: View {
    @ObservedObject var model: WatchModel
    @ObservedObject var client: NexoClient
    @State private var volume: Double = 40

    var body: some View {
        VStack(spacing: 10) {
            Text(model.lastStatus?.nowPlaying ?? "Nada en reproducción")
                .font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2)
            HStack(spacing: 10) {
                btn("backward.fill", size: 38) { model.send(.previousTrack) }
                Button { model.send(.playPause) } label: {
                    Image(systemName: "playpause.fill").font(.system(size: 20)).foregroundStyle(.black)
                        .frame(width: 52, height: 52).background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                btn("forward.fill", size: 38) { model.send(.nextTrack) }
            }
            HStack(spacing: 6) {
                Image(systemName: model.lastStatus?.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.caption)
                ProgressView(value: volume, total: 100).tint(.white)
                Text("\(Int(volume))").font(.caption.monospacedDigit()).foregroundStyle(NX.mute)
            }
            .onTapGesture { model.send(.toggleMute) }
        }
        .focusable()
        .digitalCrownRotation($volume, from: 0, through: 100, by: 2, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: volume) { _, v in model.setVolume(Int(v)) }
        .onAppear { if let s = model.lastStatus { volume = Double(s.volume) } }
        .containerBackground(for: .navigation) { NXBackdrop() }
    }

    private func btn(_ icon: String, size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 15)).frame(width: size, height: size).background(Color.white.opacity(0.14), in: Circle()) }
            .buttonStyle(.plain)
    }
}

struct TrackpadView: View {
    @ObservedObject var model: WatchModel
    @ObservedObject var client: NexoClient
    @State private var last: CGSize?
    @State private var moved: CGFloat = 0
    @State private var began = Date()
    @State private var crown: Double = 0
    @State private var lastCrown: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            Text(model.canControl ? "Desliza · toca = clic\nCorona = scroll" : "Sin conexión con la Mac.\nAcerca el iPhone.")
                .font(.system(size: 11)).foregroundStyle(NX.mute).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .darkCard(24, padding: 0)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let t = v.translation
                        if let l = last {
                            let dx = t.width - l.width, dy = t.height - l.height
                            moved += hypot(dx, dy)
                            model.pointer(dx: Int(dx.rounded()), dy: Int(dy.rounded()))
                        } else { moved = 0; began = Date() }
                        last = t
                    }
                    .onEnded { _ in
                        if moved < 5, Date().timeIntervalSince(began) < 0.3 { model.send(.click) }
                        last = nil
                    })
            HStack(spacing: 6) {
                small("cursorarrow.click.2") { model.send(.doubleClick) }
                small("contextualmenu.and.cursorarrow") { model.send(.rightClick) }
            }
        }
        .focusable()
        .digitalCrownRotation($crown, from: -10_000, through: 10_000, by: 1, sensitivity: .high, isContinuous: true, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, v in
            model.pointer(scroll: Int(((v - lastCrown) * 6).rounded()))
            lastCrown = v
        }
        .containerBackground(for: .navigation) { NXBackdrop() }
    }

    private func small(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(maxWidth: .infinity, minHeight: 34) }
            .buttonStyle(.plain).background(Color.white.opacity(0.14), in: Capsule())
    }
}

struct CatalogView: View {
    let items: [String]
    let action: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if items.isEmpty {
                    Text("Nada todavía. Abre Nexo en el iPhone con la Mac cerca.").font(.footnote).foregroundStyle(NX.mute)
                }
                ForEach(items, id: \.self) { name in
                    Button { action(name) } label: {
                        HStack { Text(name).font(.system(size: 14, weight: .medium)).lineLimit(1); Spacer(minLength: 0) }
                            .darkCard(20, padding: 11)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(for: .navigation) { NXBackdrop() }
    }
}

struct DictateView: View {
    @ObservedObject var model: WatchModel
    @State private var text = ""
    @State private var sent = false

    var body: some View {
        VStack(spacing: 10) {
            TextField("Dictar o escribir", text: $text)
                .onSubmit {
                    guard !text.isEmpty else { return }
                    model.send(.typeText(text), haptic: .success)
                    text = ""
                    sent = true
                }
            if sent { Label("Enviado a la Mac", systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(NX.green) }
            Text("Se escribe donde esté el cursor.").font(.system(size: 11)).foregroundStyle(NX.mute).multilineTextAlignment(.center)
        }
        .containerBackground(for: .navigation) { NXBackdrop() }
    }
}

struct SystemView: View {
    @ObservedObject var model: WatchModel
    @ObservedObject var client: NexoClient

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                item("lock.fill", "Bloquear") { model.send(.lockScreen) }
                item("moon.fill", "Apagar pantalla") { model.send(.sleepDisplay) }
                item("camera.viewfinder", "Captura") { model.send(.screenshot) }
                item("circle.lefthalf.filled", model.lastStatus?.darkMode == true ? "Modo claro" : "Modo oscuro", on: model.lastStatus?.darkMode == true) { model.send(.toggleDarkMode) }
                item("cup.and.saucer.fill", "Mantener activa", on: model.lastStatus?.keepAwake == true) { model.send(.toggleKeepAwake) }
                item("speaker.wave.3.fill", "Encontrar Mac") { model.send(.findMac, haptic: .success) }
                item("sun.max.fill", "Más brillo") { model.send(.brightness(2)) }
                item("sun.min.fill", "Menos brillo") { model.send(.brightness(-2)) }
                item("chevron.right", "Diapositiva siguiente") { model.send(.slideNext) }
                item("chevron.left", "Diapositiva anterior") { model.send(.slidePrevious) }
                item("powersleep", "Dormir Mac") { model.send(.sleepMac, haptic: .retry) }
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(for: .navigation) { NXBackdrop() }
    }

    private func item(_ icon: String, _ text: String, on: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 22)
                Text(text).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? Color.black : .white)
            .padding(11)
            .background(on ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .darkCard(20, padding: 0)
        }
        .buttonStyle(.plain)
    }
}

struct MacView: View {
    @ObservedObject var model: WatchModel
    @ObservedObject var client: NexoClient

    var body: some View {
        let s = model.lastStatus
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ring("Batería", s?.battery ?? 0, s?.charging == true ? NX.green : .white)
                    ring("CPU", s?.cpu ?? 0, NX.periwinkle)
                    ring("RAM", s?.memory ?? 0, NX.gold)
                }
                .darkCard(24, padding: 10)
                Text(client.isConnected ? "Conexión directa" : (model.reachable ? "Vía iPhone" : "Sin conexión")).font(.system(size: 11)).foregroundStyle(NX.mute)
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(for: .navigation) { NXBackdrop() }
    }

    private func ring(_ label: String, _ v: Int, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Gauge(value: Double(v), in: 0...100) { Text(label) } currentValueLabel: { Text("\(v)").font(.caption2) }
                .gaugeStyle(.accessoryCircularCapacity).tint(tint)
            Text(label).font(.system(size: 10)).foregroundStyle(NX.mute)
        }
    }
}
