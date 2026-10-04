import NexoCore
import SwiftUI

struct ControlView: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject var client: NexoClient
    @State private var tab = 0

    var body: some View {
        ZStack {
            NXBackdrop()
            Group {
                switch tab {
                case 0: MacScreen(model: model, client: client)
                case 1: TrackpadScreen(client: client)
                default: AppsScreen(client: client)
                }
            }
            .transition(.opacity)
        }
        .safeAreaInset(edge: .bottom) { NXTabBar(selection: $tab, icons: ["laptopcomputer", "hand.point.up.left.fill", "square.grid.2x2.fill"]).padding(.bottom, 4) }
        .preferredColorScheme(.dark)
    }
}
