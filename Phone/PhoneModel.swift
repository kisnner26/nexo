import Combine
import Foundation
import NexoCore
import UIKit
import UserNotifications
import WatchConnectivity
import WidgetKit

/// Cliente de la Mac + puente hacia el Watch (código, estado, órdenes retransmitidas).
@MainActor
final class PhoneModel: NSObject, ObservableObject {
    static let shared = PhoneModel()
    private var started = false
    let client = NexoClient()
    @Published var code: String? = NexoStore.code
    @Published var watchPaired = false
    private var session: WCSession?
    private var catalogObserver: AnyCancellable?

    func start() {
        guard !started else { return }
        started = true
        client.onStatus = { [weak self] s in self?.statusChanged(s) }
        catalogObserver = client.$shortcuts.combineLatest(client.$apps).sink { [weak self] _, _ in self?.pushCatalog() }
        client.onAlert = { [weak self] t, b in self?.alert(t, b) }
        client.configure(code: code, deviceName: UIDevice.current.name)
        client.start()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        if WCSession.isSupported() {
            let s = WCSession.default
            s.delegate = self
            s.activate()
            session = s
        }
    }

    func pair(_ raw: String) -> Bool {
        guard Pairing.isValid(raw) else { return false }
        let c = Pairing.normalize(raw)
        NexoStore.code = c
        code = c
        client.configure(code: c, deviceName: UIDevice.current.name)
        client.start()
        pushCodeToWatch()
        return true
    }

    func unpair() {
        NexoStore.code = nil
        NexoStore.lastStatus = nil
        code = nil
        client.configure(code: nil, deviceName: UIDevice.current.name)
        client.stop()
        pushCodeToWatch()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func retry() {
        client.configure(code: code, deviceName: UIDevice.current.name)
        client.stop()
        client.start()
    }

    func pushClipboard() {
        if let s = UIPasteboard.general.string, !s.isEmpty { client.sendClipboard(s) }
    }

    private func statusChanged(_ s: MacStatus) {
        NexoStore.lastStatus = s
        WidgetCenter.shared.reloadAllTimelines()
        guard let session, session.activationState == .activated, session.isPaired,
              let data = try? JSONEncoder().encode(s) else { return }
        var ctx = session.applicationContext
        ctx["status"] = data
        try? session.updateApplicationContext(ctx)
        if session.isReachable { session.sendMessage(["status": data], replyHandler: nil, errorHandler: nil) }
    }

    private func alert(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        if let session, session.isReachable {
            session.sendMessage(["alert": [title, body]], replyHandler: nil)
        }
    }

    private func pushCatalog() {
        guard let session, session.activationState == .activated, session.isPaired,
              !client.shortcuts.isEmpty || !client.apps.isEmpty,
              let data = try? JSONEncoder().encode([client.shortcuts, client.apps]) else { return }
        var ctx = session.applicationContext
        ctx["catalog"] = data
        try? session.updateApplicationContext(ctx)
    }

    private func pushCodeToWatch() {
        guard let session, session.activationState == .activated else { return }
        var ctx = session.applicationContext
        ctx["code"] = code ?? ""
        try? session.updateApplicationContext(ctx)
    }
}

extension PhoneModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.watchPaired = session.isPaired
            self.pushCodeToWatch()
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.watchPaired = session.isPaired; self.pushCodeToWatch() }
    }

    /// El reloj retransmite órdenes por aquí cuando no ve la Mac directamente.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in _ = self.handleWatch(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in replyHandler(self.handleWatch(message)) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {}
}

extension PhoneModel {
    /// Ejecuta lo que pide el reloj y devuelve estado, catálogo y código para que se sincronice.
    @MainActor func handleWatch(_ message: [String: Any]) -> [String: Any] {
        start()
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(bg) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { UIApplication.shared.endBackgroundTask(bg) }
        if let d = message["cmd"] as? Data, let cmd = try? JSONDecoder().decode(NexoCommand.self, from: d) {
            switch cmd {
            case .mouseMove(let dx, let dy): client.pointer(dx: dx, dy: dy)
            case .scroll(let dy): client.pointer(scroll: dy)
            default: client.send(cmd)
            }
        }
        var reply: [String: Any] = ["ok": true, "connected": client.isConnected, "code": code ?? ""]
        if let st = client.status, let d = try? JSONEncoder().encode(st) { reply["status"] = d }
        if !client.shortcuts.isEmpty || !client.apps.isEmpty, let d = try? JSONEncoder().encode([client.shortcuts, client.apps]) { reply["catalog"] = d }
        return reply
    }
}
