import AppKit
import NexoCore
import SwiftUI

@main
struct NexoMacApp: App {
    @StateObject private var host = NexoHost()

    var body: some Scene {
        MenuBarExtra("Nexo", systemImage: host.peers.isEmpty ? "antenna.radiowaves.left.and.right" : "link") {
            MenuView(host: host)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var host: NexoHost

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Nexo").font(.title2.bold())
                Spacer()
                Label(host.peers.isEmpty ? "Esperando" : "\(host.peers.count) conectado\(host.peers.count == 1 ? "" : "s")",
                      systemImage: host.peers.isEmpty ? "wifi" : "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(host.peers.isEmpty ? NX.mute : NX.green)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Código de emparejamiento").font(.caption).foregroundStyle(NX.mute)
                Text(Pairing.display(host.code)).font(.system(size: 22, weight: .semibold, design: .monospaced)).textSelection(.enabled)
            }
            .glassCard(18, padding: 14)
            ForEach(host.peers) { Label($0.name, systemImage: "iphone.and.apple.watch").font(.subheadline) }
            if !host.accessibility {
                Button("Permitir trackpad y teclado") { MacActions.requestAccessibility() }
                    .buttonStyle(.glassProminent).tint(NX.blue)
            }
            HStack {
                Button("Nuevo código") { host.regenerateCode() }.buttonStyle(.glass)
                Spacer()
                Button("Salir") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain).foregroundStyle(NX.mute)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
