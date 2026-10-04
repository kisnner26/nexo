import Foundation
import Network

/// Cliente que busca la Mac por Bonjour, se conecta, se reconecta solo y encola
/// órdenes mientras no hay conexión. Lo usan el iPhone, el Watch y los widgets.
@MainActor
public final class NexoClient: ObservableObject {
    public enum State: Equatable {
        case idle, searching, connecting
        case connected(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var status: MacStatus?
    @Published public private(set) var clipboard: String?
    @Published public private(set) var ackCount = 0
    /// Texto legible de lo que está pasando (permiso de red local, búsqueda, fallo).
    @Published public private(set) var detail = ""
    @Published public private(set) var shortcuts: [String] = []
    @Published public private(set) var apps: [String] = []
    /// Iconos de las apps de la Mac (PNG), pedidos por lotes y guardados en disco.
    @Published public private(set) var icons: [String: Data] = [:]
    private var requestedIcons = Set<String>()
    private var iconBatch = Set<String>()
    private var iconTimer: Task<Void, Never>?

    public var onAlert: ((String, String) -> Void)?
    public var onStatus: ((MacStatus) -> Void)?

    public var isConnected: Bool { if case .connected = state { return true } else { return false } }

    private var code: String?
    private var deviceName = "Dispositivo"
    private var running = false
    private var browser: NWBrowser?
    private var channel: NexoChannel?
    private var pending: [(NexoMessage, Date)] = []
    private var retry: Task<Void, Never>?
    private var connectingSince = Date()

    public init() {
        let c = NexoStore.catalog
        shortcuts = c.shortcuts
        apps = c.apps
    }

    /// Catálogo recibido por otra vía (el iPhone se lo pasa al reloj).
    public func applyCatalog(shortcuts: [String], apps: [String]) {
        self.shortcuts = shortcuts
        self.apps = apps
        NexoStore.catalog = (shortcuts, apps)
    }

    public func configure(code: String?, deviceName: String) {
        let changed = Pairing.normalize(code ?? "") != Pairing.normalize(self.code ?? "")
        self.code = code.flatMap { Pairing.isValid($0) ? Pairing.normalize($0) : nil }
        self.deviceName = deviceName
        if changed && running { restart() }
    }

    public func start() {
        guard !running else { return }
        running = true
        restart()
    }

    public func stop() {
        running = false
        teardown()
        state = .idle
    }

    public func send(_ command: NexoCommand) { enqueue(.command(command)) }
    public func sendClipboard(_ text: String) { enqueue(.clipboard(text)) }
    public func requestCatalog() { enqueue(.requestCatalog) }

    /// Pide el icono de una app si aún no lo tiene (agrupa las peticiones en lotes de 16).
    public func loadIcon(for name: String) {
        if icons[name] != nil || requestedIcons.contains(name) { return }
        if let d = IconCache.read(name) { icons[name] = d; return }
        requestedIcons.insert(name)
        iconBatch.insert(name)
        iconTimer?.cancel()
        iconTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }
            let names = Array(self.iconBatch)
            self.iconBatch.removeAll()
            for chunk in stride(from: 0, to: names.count, by: 8) {
                self.enqueue(.requestIcons(Array(names[chunk..<min(chunk + 8, names.count)])))
            }
        }
    }

    private var pointerDX = 0, pointerDY = 0, pointerScroll = 0
    private var pointerTimer: Task<Void, Never>?

    /// Acumula movimientos del trackpad y los manda cada ~30 ms para no saturar el canal.
    public func pointer(dx: Int = 0, dy: Int = 0, scroll: Int = 0) {
        guard isConnected else { return }
        pointerDX += dx; pointerDY += dy; pointerScroll += scroll
        guard pointerTimer == nil else { return }
        pointerTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000)
            guard let self else { return }
            if self.pointerDX != 0 || self.pointerDY != 0 { self.channel?.send(.command(.mouseMove(dx: self.pointerDX, dy: self.pointerDY))) }
            if self.pointerScroll != 0 { self.channel?.send(.command(.scroll(self.pointerScroll))) }
            self.pointerDX = 0; self.pointerDY = 0; self.pointerScroll = 0
            self.pointerTimer = nil
        }
    }

    private func enqueue(_ message: NexoMessage) {
        if let channel, isConnected {
            channel.send(message)
        } else {
            pending.append((message, Date()))
            if running, state == .idle { restart() }
        }
    }

    private func restart() {
        teardown()
        guard running, let code else { state = .idle; return }
        state = .searching
        detail = "Buscando la Mac en la red"
        let b = NWBrowser(for: .bonjour(type: nexoServiceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let endpoint = results.first?.endpoint else { return }
            Task { @MainActor in self?.connect(to: endpoint, code: code) }
        }
        b.stateUpdateHandler = { [weak self] s in
            Task { @MainActor in
                guard let self else { return }
                switch s {
                case .failed(let e): self.detail = "Fallo al buscar: \(e.localizedDescription)"; self.scheduleRetry()
                case .waiting(let e):
                    let denied = "\(e)".contains("65570") || "\(e)".lowercased().contains("policy")
                    self.detail = denied ? "Sin permiso de red local. Actívalo en Ajustes > Nexo > Red local." : "Esperando red: \(e.localizedDescription)"
                case .ready: if !self.isConnected { self.detail = "Buscando la Mac en la red" }
                default: break
                }
            }
        }
        b.start(queue: .main)
        browser = b
        scheduleRetry(after: 8)
    }

    private func connect(to endpoint: NWEndpoint, code: String) {
        guard channel == nil, running else { return }
        retry?.cancel()
        state = .connecting
        detail = "Mac encontrada, conectando"
        connectingSince = Date()
        let ch = NexoChannel(connection: NWConnection(to: endpoint, using: .tcp), key: Pairing.key(for: code))
        let name = deviceName
        ch.onReady = { [weak ch] in ch?.send(.hello(device: name)) }
        ch.onMessage = { [weak self] m in Task { @MainActor in self?.handle(m) } }
        ch.onClosed = { [weak self, id = ch.id] in
            Task { @MainActor in
                guard let self, self.channel?.id == id else { return }
                self.channel = nil
                self.state = .idle
                self.scheduleRetry()
            }
        }
        channel = ch
        ch.start()
        browser?.cancel()
        browser = nil
        scheduleRetry(after: 6)
    }

    private func markConnected(_ host: String) {
        guard !isConnected else { return }
        state = .connected(host)
        detail = "Conectado a \(host)"
        requestedIcons.removeAll()
        retry?.cancel()
        flush()
        channel?.send(.requestCatalog)
    }

    private func handle(_ message: NexoMessage) {
        switch message {
        case .hello(let host): markConnected(host)
        case .status(let s):
            markConnected(s.hostName)
            status = s
            onStatus?(s)
        case .alert(let t, let b): markConnected(status?.hostName ?? "Mac"); onAlert?(t, b)
        case .clipboard(let c): clipboard = c
        case .ack: ackCount += 1
        case .catalog(let sc, let ap): applyCatalog(shortcuts: sc, apps: ap)
        case .icons(let d):
            for (n, data) in d { IconCache.write(n, data) }
            icons.merge(d) { $1 }
        case .command, .requestCatalog, .requestIcons: break
        }
    }

    private func flush() {
        let now = Date()
        let items = pending.filter { now.timeIntervalSince($0.1) < 8 }
        pending.removeAll()
        for (m, _) in items { channel?.send(m) }
    }

    private func scheduleRetry(after seconds: Double = 2) {
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.running, !self.isConnected else { return }
            if self.state == .connecting, Date().timeIntervalSince(self.connectingSince) < 10 {
                self.scheduleRetry(after: 4)
                return
            }
            self.restart()
        }
    }

    private func teardown() {
        retry?.cancel()
        browser?.cancel()
        browser = nil
        let ch = channel
        channel = nil
        ch?.cancel()
    }
}

/// Envío puntual desde un widget o intent: conecta, manda y espera el acuse.
public enum NexoOneShot {
    @MainActor
    public static func run(_ command: NexoCommand, timeout: Double = 5) async -> Bool {
        guard let code = NexoStore.code, Pairing.isValid(code) else { return false }
        let client = NexoClient()
        client.configure(code: code, deviceName: "Control")
        client.start()
        client.send(command)
        let deadline = Date().addingTimeInterval(timeout)
        while client.ackCount == 0, Date() < deadline {
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        let ok = client.ackCount > 0
        client.stop()
        return ok
    }
}
