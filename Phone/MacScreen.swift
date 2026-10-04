import NexoCore
import SwiftUI

struct MacScreen: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject var client: NexoClient
    @State private var volume: Double = 40
    @State private var brightness: Double = 50
    @State private var showMore = false
    @State private var showStatus = false

    private var s: MacStatus? { client.status }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if client.isConnected {
                    if s?.accessibility == false { AccessibilityBanner() }
                    statusCard
                    mediaCard
                    quickCard
                } else {
                    disconnected
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $showStatus) { StatusSheet(client: client).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showMore) { MoreSheet(model: model, client: client).presentationDetents([.medium, .large]) }
        .onChange(of: client.status) { _, st in
            guard let st else { return }
            volume = Double(st.volume); brightness = Double(st.brightness)
        }
    }

    private var menuButton: some View {
        Menu {
            Button("Reintentar conexión") { model.retry() }
            Button("Desemparejar", role: .destructive) { model.unpair() }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).frame(width: 40, height: 40)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: tarjeta de estado (como "Listening Time")

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { showStatus = true } label: {
                    HStack(spacing: 6) {
                        Text("Batería").font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(NX.mute)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                menuButton
            }
            HStack(alignment: .center) {
                (Text("\(s?.battery ?? 0)").font(.system(size: 56, weight: .light)).monospacedDigit()
                 + Text(" %").font(.system(size: 20, weight: .regular)).foregroundColor(NX.mute))
                if s?.charging == true { Image(systemName: "bolt.fill").foregroundStyle(NX.green).font(.title3) }
                Spacer()
                appStack
            }
            HStack {
                (Text("CPU  ").foregroundColor(NX.mute) + Text("\(s?.cpu ?? 0)%").fontWeight(.semibold))
                Spacer()
                (Text("Memoria  ").foregroundColor(NX.mute) + Text("\(s?.memory ?? 0)%").fontWeight(.semibold))
            }
            .font(.footnote)
        }
        .darkCard()
        .onTapGesture { showStatus = true }
    }

    /// Círculos solapados con las primeras apps (como los avatares de la referencia).
    private var appStack: some View {
        HStack(spacing: -14) {
            ForEach(Array(client.apps.prefix(3).enumerated()), id: \.element) { i, name in
                Group {
                    if let d = client.icons[name], let img = UIImage(data: d) { Image(uiImage: img).resizable().scaledToFill() }
                    else { Color.white.opacity(0.12) }
                }
                .frame(width: 46, height: 46).clipShape(Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 2))
                .zIndex(Double(-i))
                .onAppear { client.loadIcon(for: name) }
            }
            if client.apps.count > 3 {
                Text("+\(client.apps.count - 3)").font(.caption.weight(.semibold))
                    .frame(width: 46, height: 46).background(Color.white.opacity(0.14), in: Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 2))
            }
        }
    }

    // MARK: reproducción + volumen + brillo

    private var mediaCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ahora suena").font(.subheadline.weight(.medium))
            VStack(alignment: .leading, spacing: 2) {
                Text(s?.nowPlaying ?? "Nada en reproducción").font(.system(size: 23, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.75)
                Text(s?.nowPlaying == nil ? "Abre Música o Spotify en la Mac" : "En tu Mac").font(.footnote).foregroundStyle(NX.mute)
            }
            HStack(spacing: 20) {
                Spacer()
                transport("backward.fill") { client.send(.previousTrack) }
                Button { client.send(.playPause) } label: {
                    Image(systemName: "playpause.fill").font(.system(size: 22)).foregroundStyle(.black)
                        .frame(width: 62, height: 62).background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                transport("forward.fill") { client.send(.nextTrack) }
                Spacer()
            }
            VStack(spacing: 8) {
                CapsuleSlider(value: $volume, icon: s?.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill") { client.send(.setVolume(Int($0))) }
                CapsuleSlider(value: $brightness, icon: "sun.max.fill") { client.send(.setBrightness(Int($0))) }
            }
        }
        .darkCard()
    }

    private func transport(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 20)).frame(width: 48, height: 48) }.buttonStyle(.plain)
    }

    // MARK: control rápido (tarjeta cálida, como "AI Discovery")

    private var quickCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { showMore = true } label: { cardTitle("Control rápido") }.buttonStyle(.plain)
            HStack(spacing: 4) {
                DotButton(icon: "lock.fill", label: "Bloquear") { client.send(.lockScreen) }
                DotButton(icon: "moon.fill", label: "Pantalla") { client.send(.sleepDisplay) }
                DotButton(icon: "camera.viewfinder", label: "Captura") { client.send(.screenshot) }
                DotButton(icon: "ellipsis", label: "Más") { showMore = true }
            }
        }
        .darkCard(tint: NX.salmon)
    }

    private func cardTitle(_ t: String) -> some View {
        HStack { Text(t).font(.subheadline.weight(.medium)); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(NX.mute) }
    }

    // MARK: sin conexión

    private var disconnected: some View {
        VStack(spacing: 16) {
            HStack { Spacer(); menuButton }
            Image(systemName: "wifi.exclamationmark").font(.system(size: 42, weight: .light))
            Text("No encuentro tu Mac").font(.system(size: 22, weight: .semibold))
            Text(client.detail.isEmpty ? "Buscando en la red" : client.detail).font(.subheadline).foregroundStyle(NX.mute).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                check("Nexo abierto en la Mac"); check("Misma red Wi-Fi en ambos"); check("Red local activada para Nexo")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Button { model.retry() } label: { Text("Reintentar").frame(maxWidth: .infinity, minHeight: 24) }
                    .buttonStyle(.glassProminent).tint(NX.blue).buttonBorderShape(.capsule).controlSize(.large)
                Button { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } } label: {
                    Text("Ajustes").frame(maxWidth: .infinity, minHeight: 24)
                }
                .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
            }
        }
        .darkCard(36, padding: 24)
        .padding(.top, 8)
    }

    private func check(_ t: String) -> some View { Label(t, systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(NX.mute) }

}

struct AccessibilityBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Falta un permiso en la Mac").font(.subheadline.weight(.semibold))
                Text("Activa Nexo en Ajustes del Sistema > Privacidad y seguridad > Accesibilidad para usar trackpad y teclado.")
                    .font(.footnote).foregroundStyle(NX.mute)
            }
        }
        .darkCard(26, padding: 16)
    }
}

struct MoreSheet: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject var client: NexoClient
    private var s: MacStatus? { client.status }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    BigTile(icon: "circle.lefthalf.filled", title: "Modo oscuro", subtitle: s?.darkMode == true ? "Activado" : "Desactivado",
                            active: s?.darkMode == true) { client.send(.toggleDarkMode) }
                    BigTile(icon: "cup.and.saucer.fill", title: "Mantener activa", subtitle: s?.keepAwake == true ? "Activado" : "Desactivado",
                            active: s?.keepAwake == true) { client.send(.toggleKeepAwake) }
                    BigTile(icon: "speaker.slash.fill", title: "Silenciar", subtitle: s?.muted == true ? "Silenciada" : "Con sonido",
                            active: s?.muted == true) { client.send(.toggleMute) }
                    BigTile(icon: "speaker.wave.3.fill", title: "Encontrar Mac", subtitle: "Hace sonar la Mac") { client.send(.findMac) }
                    BigTile(icon: "powersleep", title: "Dormir", subtitle: "Suspende la Mac") { client.send(.sleepMac) }
                    BigTile(icon: "doc.on.clipboard", title: "Portapapeles", subtitle: "Enviar a la Mac") { model.pushClipboard() }
                }
                if let c = client.clipboard {
                    HStack {
                        Text(c).lineLimit(2).font(.subheadline).foregroundStyle(NX.mute)
                        Spacer()
                        Button("Copiar") { UIPasteboard.general.string = c }.buttonStyle(.glass)
                    }
                    .darkCard(26, padding: 16)
                }
                HStack {
                    Label("Presentación", systemImage: "play.rectangle.fill").font(.headline)
                    Spacer()
                    Button { client.send(.slidePrevious) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                    Button { client.send(.slideNext) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28) }
                        .buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(NX.blue)
                }
                .darkCard(28, padding: 18)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 24)
        }
        .background { NXBackdrop() }
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
    }
}

/// Detalle al tocar "Batería": anillos grandes y estado completo de la Mac.
struct StatusSheet: View {
    @ObservedObject var client: NexoClient
    private var s: MacStatus? { client.status }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text(client.status?.hostName ?? "Mac").font(.title2.weight(.semibold))
                    Text(s?.charging == true ? "Conectado a la corriente" : "Usando batería").font(.subheadline).foregroundStyle(NX.mute)
                }
                .padding(.top, 14)
                HStack(spacing: 10) {
                    ring("Batería", s?.battery ?? 0, s?.charging == true ? NX.green : .white)
                    ring("CPU", s?.cpu ?? 0, NX.periwinkle)
                    ring("Memoria", s?.memory ?? 0, NX.gold)
                }
                .darkCard(30, padding: 16)
                VStack(spacing: 0) {
                    row("speaker.wave.2.fill", "Volumen", s?.muted == true ? "Silenciado" : "\(s?.volume ?? 0)%")
                    row("sun.max.fill", "Brillo", "\(s?.brightness ?? 0)%")
                    row("circle.lefthalf.filled", "Modo oscuro", s?.darkMode == true ? "Activado" : "Desactivado")
                    row("cup.and.saucer.fill", "Mantener activa", s?.keepAwake == true ? "Activado" : "Desactivado")
                    row("hand.raised.fill", "Accesibilidad", s?.accessibility == false ? "Falta permiso" : "Concedida")
                }
                .darkCard(30, padding: 6)
            }
            .padding(.horizontal, 16).padding(.bottom, 20)
        }
        .background { NXBackdrop() }
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
    }

    private func ring(_ label: String, _ v: Int, _ tint: Color) -> some View {
        VStack(spacing: 8) {
            Gauge(value: Double(v), in: 0...100) { Text(label) } currentValueLabel: { Text("\(v)").font(.system(size: 17, weight: .semibold)) }
                .gaugeStyle(.accessoryCircularCapacity).tint(tint).scaleEffect(1.5).frame(height: 76)
            Text(label).font(.caption).foregroundStyle(NX.mute)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 28).foregroundStyle(NX.mute)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(NX.mute)
        }
        .font(.subheadline).padding(.horizontal, 14).padding(.vertical, 13)
    }
}
