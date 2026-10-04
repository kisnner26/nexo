import Foundation
import NexoCore
import UserNotifications
import WatchConnectivity
import WatchKit

/// Intenta hablar directo con la Mac por Wi-Fi; si no puede, retransmite por el iPhone.
@MainActor
final class WatchModel: NSObject, ObservableObject {
    let client = NexoClient()
    @Published var code: String? = NexoStore.code
    @Published var viaPhone = false
    @Published var lastStatus: MacStatus? = NexoStore.lastStatus
    private var session: WCSession?
    private var volumeTask: Task<Void, Never>?
    @Published var reachable = false
    private var pAcc = (dx: 0, dy: 0, sc: 0)
    private var pTask: Task<Void, Never>?
    private var polling = false

    /// Hay forma de llegar a la Mac: directo por Wi-Fi o a través del iPhone.
    var canControl: Bool { client.isConnected || reachable }

    func start() {
        client.onStatus = { [weak self] s in
            NexoStore.lastStatus = s
            self?.lastStatus = s
        }
        client.onAlert = { [weak self] t, b in self?.notify(t, b) }
        client.configure(code: code, deviceName: "Apple Watch")
        client.start()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        session = s
        startPolling()
    }

    var direct: Bool { client.isConnected }

    func send(_ command: NexoCommand, haptic: WKHapticType = .click) {
        WKInterfaceDevice.current().play(haptic)
        deliver(command)
    }

    private func deliver(_ command: NexoCommand) {
        if client.isConnected {
            viaPhone = false
            client.send(command)
        } else if let session, session.isReachable, let data = try? JSONEncoder().encode(command) {
            viaPhone = true
            session.sendMessage(["cmd": data], replyHandler: { [weak self] r in Task { @MainActor in self?.apply(context: r) } },
                                errorHandler: { [weak self] _ in Task { @MainActor in self?.client.send(command) } })
        } else {
            client.send(command)
        }
    }

    /// Movimiento del trackpad: directo, o agrupado cada 50 ms por el iPhone.
    func pointer(dx: Int = 0, dy: Int = 0, scroll: Int = 0) {
        if client.isConnected { client.pointer(dx: dx, dy: dy, scroll: scroll); return }
        guard session?.isReachable == true else { return }
        pAcc.dx += dx; pAcc.dy += dy; pAcc.sc += scroll
        guard pTask == nil else { return }
        pTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self else { return }
            let a = self.pAcc
            self.pAcc = (0, 0, 0)
            self.pTask = nil
            if a.dx != 0 || a.dy != 0 { self.deliver(.mouseMove(dx: a.dx, dy: a.dy)) }
            if a.sc != 0 { self.deliver(.scroll(a.sc)) }
        }
    }

    /// Pregunta al iPhone por el estado de la Mac mientras no haya conexión directa.
    private func startPolling() {
        guard !polling else { return }
        polling = true
        Task { [weak self] in
            while let self {
                if let s = self.session, s.isReachable, !self.client.isConnected {
                    s.sendMessage(["needStatus": 1], replyHandler: { r in Task { @MainActor in self.apply(context: r) } }, errorHandler: nil)
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    /// La corona genera muchos eventos: se manda solo el último valor.
    func setVolume(_ v: Int) {
        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            self?.send(.setVolume(v), haptic: .directionUp)
        }
    }

    private func apply(context: [String: Any]) {
        if let c = context["code"] as? String {
            let value = c.isEmpty ? nil : c
            NexoStore.code = value
            code = value
            client.configure(code: value, deviceName: "Apple Watch")
            if value == nil { client.stop() } else { client.start() }
        }
        if let d = context["status"] as? Data, let s = try? JSONDecoder().decode(MacStatus.self, from: d), !client.isConnected {
            lastStatus = s
        }
        if let c = context["connected"] as? Bool, c == false, !client.isConnected { /* el iPhone aún no ve la Mac */ }
        if let d = context["catalog"] as? Data, let l = try? JSONDecoder().decode([[String]].self, from: d), l.count == 2 {
            client.applyCatalog(shortcuts: l[0], apps: l[1])
        }
    }

    private func notify(_ title: String, _ body: String) {
        WKInterfaceDevice.current().play(.notification)
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        let r = session.isReachable
        Task { @MainActor in self.reachable = r; self.apply(context: ctx) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.apply(context: context) }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let r = session.isReachable
        Task { @MainActor in self.reachable = r }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["status"] != nil { Task { @MainActor in self.apply(context: message) } }
        if let a = message["alert"] as? [String], a.count == 2 {
            Task { @MainActor in
                if !self.client.isConnected { self.notify(a[0], a[1]) }
            }
        }
    }
}
