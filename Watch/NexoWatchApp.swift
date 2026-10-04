import AppIntents
import NexoCore
import SwiftUI

@main
struct NexoWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchView(model: model, client: model.client)
                .task { model.start() }
        }
    }
}

// Botón de acción del Ultra: play/pausa en la Mac.
struct MacPlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pausa en la Mac"
    func perform() async throws -> some IntentResult {
        _ = await NexoOneShot.run(.playPause)
        return .result()
    }
}
