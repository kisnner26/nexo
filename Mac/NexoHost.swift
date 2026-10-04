import AppKit
import Network
import NexoCore

@MainActor
final class NexoHost: ObservableObject {
    struct Peer: Identifiable { let id: UUID; var name: String }

    @Published private(set) var code: String
    @Published private(set) var peers: [Peer] = []
    @Published private(set) var listening = false
    @Published var accessibility = MacActions.accessibilityGranted

    private var listener: NWListener?
    private var channels: [UUID: NexoChannel] = [:]
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var ignoreChange = false
    private var lowBatteryAlerted = false
    private var fullAlerted = false
    private let hostName = Host.current().localizedName ?? "Mac"

    init() {
        if let c = NexoStore.code, Pairing.isValid(c) { code = c } else {
            code = Pairing.newCode()
            NexoStore.code = code
        }
        start()
    }

    private func start() {
        guard listener == nil else { return }
        if !MacActions.accessibilityGranted { MacActions.requestAccessibility() }
        startListener()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func regenerateCode() {
        code = Pairing.newCode()
        NexoStore.code = code
        channels.values.forEach { $0.cancel() }
        channels.removeAll()
        peers.removeAll()
        listener?.cancel()
        startListener()
    }

    private func startListener() {
        do {
            let l = try NWListener(using: .tcp)
            l.service = NWListener.Service(name: hostName, type: nexoServiceType)
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            l.stateUpdateHandler = { [weak self] s in
                Task { @MainActor in
                    if case .ready = s { self?.listening = true }
                    if case .failed = s { self?.listening = false }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            listening = false
        }
    }

    private func accept(_ conn: NWConnection) {
        let ch = NexoChannel(connection: conn, key: Pairing.key(for: code))
        let id = ch.id
        ch.onMessage = { [weak self, weak ch] m in
            Task { @MainActor in
                guard let self, let ch else { return }
                self.handle(m, from: ch)
            }
        }
        ch.onReady = { [weak self] in Task { @MainActor in self?.sendStatus(to: id) } }
        ch.onClosed = { [weak self] in
            Task { @MainActor in
                self?.channels[id] = nil
                self?.peers.removeAll { $0.id == id }
            }
        }
        channels[id] = ch
        ch.start()
    }

    private func handle(_ m: NexoMessage, from ch: NexoChannel) {
        switch m {
        case .hello(let name):
            ch.send(.hello(device: hostName))
            if !peers.contains(where: { $0.id == ch.id }) { peers.append(Peer(id: ch.id, name: name)) }
        case .command(let c):
            switch c {
            case .typeText(let t): typeText(t)
            case .toggleKeepAwake: toggleKeepAwake()
            default: MacActions.queue.async { MacActions.run(c) }
            }
            ch.send(.ack(ok: true))
            switch c {
            case .mouseMove, .scroll: break
            default: DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.broadcastStatus() }
            }
        case .requestCatalog:
            sendCatalog(to: ch.id)
        case .requestIcons(let names):
            let id = ch.id
            MacActions.queue.async {
                var out: [String: Data] = [:]
                for n in names.prefix(8) { if let d = MacActions.iconPNG(for: n) { out[n] = d } }
                Task { @MainActor [weak self] in self?.channels[id]?.send(.icons(out)) }
            }
        case .clipboard(let text):
            ignoreChange = true
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            lastChange = NSPasteboard.general.changeCount
            ch.send(.ack(ok: true))
            relay(.clipboard(text), except: ch.id)
        default: break
        }
    }

    private func relay(_ m: NexoMessage, except id: UUID? = nil) {
        for (cid, ch) in channels where cid != id { ch.send(m) }
    }

    private var caffeinate: Process?
    private var gathering = false
    private var waiters: [@MainActor (MacStatus) -> Void] = []

    private func typeText(_ text: String) {
        let pb = NSPasteboard.general
        let old = pb.string(forType: .string)
        ignoreChange = true
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChange = pb.changeCount
        Task.detached {
            MacActions.pasteShortcut()
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run { [weak self] in
                guard let self, let old else { return }
                self.ignoreChange = true
                pb.clearContents()
                pb.setString(old, forType: .string)
                self.lastChange = pb.changeCount
            }
        }
    }

    private func toggleKeepAwake() {
        if let c = caffeinate, c.isRunning { c.terminate(); caffeinate = nil; return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-di"]
        try? p.run()
        caffeinate = p
    }

    private func sendCatalog(to id: UUID) {
        Task.detached {
            let apps = MacActions.installedApps()
            await MainActor.run { [weak self] in self?.channels[id]?.send(.catalog(shortcuts: [], apps: apps)) }
        }
    }

    /// Lo lento (AppleScript, procesos) se reúne fuera del hilo principal.
    private func gatherStatus(_ done: @escaping @MainActor (MacStatus) -> Void) {
        waiters.append(done)
        guard !gathering else { return }
        gathering = true
        let name = hostName
        let awake = caffeinate?.isRunning == true
        Task.detached {
            let p = PowerInfo.read()
            let v = MacActions.volume()
            let s = MacStatus(hostName: name, battery: p.percent, charging: p.charging, volume: v.level, muted: v.muted,
                              cpu: SystemStats.cpuPercent(), memory: SystemStats.memoryPercent(),
                              nowPlaying: MacActions.nowPlaying(), keepAwake: awake, darkMode: MacActions.darkMode(),
                              accessibility: MacActions.accessibilityGranted,
                              brightness: Int(((MacActions.brightness() ?? 0.5) * 100).rounded()))
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.gathering = false
                let w = self.waiters
                self.waiters.removeAll()
                w.forEach { $0(s) }
            }
        }
    }

    private func sendStatus(to id: UUID) {
        gatherStatus { [weak self] s in self?.channels[id]?.send(.status(s)) }
        sendCatalog(to: id)
    }

    private func broadcastStatus() {
        guard !channels.isEmpty else { return }
        gatherStatus { [weak self] s in self?.relay(.status(s)) }
    }

    private var ticks = 0
    private func tick() {
        ticks += 1
        let pb = NSPasteboard.general
        if pb.changeCount != lastChange {
            lastChange = pb.changeCount
            if ignoreChange { ignoreChange = false }
            else if let s = pb.string(forType: .string), s.utf8.count < 200_000 { relay(.clipboard(s)) }
        }
        if ticks % 3 == 0 { broadcastStatus() }
        if ticks % 30 == 0 { checkBattery() }
        if accessibility != MacActions.accessibilityGranted { accessibility = MacActions.accessibilityGranted }
    }

    private func checkBattery() {
        let p = PowerInfo.read()
        guard let pct = p.percent else { return }
        if pct <= 15, !p.charging, !lowBatteryAlerted {
            lowBatteryAlerted = true
            relay(.alert(title: "Mac con poca batería", body: "\(hostName) está al \(pct)% y no está cargando."))
        } else if pct > 20 || p.charging { lowBatteryAlerted = false }
        if pct >= 100, p.charging, !fullAlerted {
            fullAlerted = true
            relay(.alert(title: "Mac cargado", body: "\(hostName) llegó al 100%."))
        } else if pct < 95 { fullAlerted = false }
    }
}
