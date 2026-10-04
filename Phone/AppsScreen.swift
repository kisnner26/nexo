import NexoCore
import SwiftUI

struct AppsScreen: View {
    @ObservedObject var client: NexoClient
    @State private var query = ""
    @State private var opened: String?

    private var filtered: [String] {
        query.isEmpty ? client.apps : client.apps.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(NX.mute)
                    TextField("Buscar en la Mac", text: $query).autocorrectionDisabled()
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(NX.mute) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 18).frame(height: 50).glassEffect(.regular, in: .capsule)
                .padding(.bottom, 4)
                if client.apps.isEmpty {
                    Text("Conecta con la Mac para ver sus apps.").foregroundStyle(NX.mute).padding(.top, 80)
                }
                ForEach(filtered, id: \.self) { row($0) }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: client.isConnected) { filtered.prefix(40).forEach { client.loadIcon(for: $0) } }
    }

    private func row(_ name: String) -> some View {
        Button { opened = name; client.send(.openApp(name)) } label: {
            HStack(spacing: 14) {
                icon(name).frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Text(opened == name ? "Abriendo en la Mac" : "Toca para abrir").font(.footnote).foregroundStyle(NX.mute)
                }
                Spacer()
                Image(systemName: opened == name ? "checkmark" : "arrow.up.right").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(opened == name ? NX.green : NX.mute)
            }
            .darkCard(26, padding: 12)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: opened)
        .onAppear { client.loadIcon(for: name) }
    }

    @ViewBuilder private func icon(_ name: String) -> some View {
        if let d = client.icons[name], let img = UIImage(data: d) {
            Image(uiImage: img).resizable().scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.1))
                .overlay(Text(String(name.prefix(1))).font(.title3.weight(.semibold)).foregroundStyle(NX.mute))
        }
    }
}
