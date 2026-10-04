import NexoCore
import SwiftUI

/// El delegado arranca el puente con el reloj aunque iOS lance la app en segundo plano.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @MainActor in PhoneModel.shared.start() }
        return true
    }
}

@main
struct NexoPhoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = PhoneModel.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if model.code == nil { PairingView(model: model) } else { ControlView(model: model, client: model.client) }
            }
            .task { model.start() }
        }
    }
}
