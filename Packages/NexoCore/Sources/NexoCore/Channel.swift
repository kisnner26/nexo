import CryptoKit
import Foundation
import Network

/// Canal TCP con tramas `[len u32][hmac 32][json]`. Cada mensaje lleva un número de
/// secuencia creciente dentro del JSON firmado, para evitar repeticiones.
public final class NexoChannel: @unchecked Sendable {
    public let id = UUID()
    private let connection: NWConnection
    private let key: SymmetricKey
    private let queue = DispatchQueue(label: "nexo.channel")
    private var buffer = Data()
    private var sendSeq: UInt64 = 0
    private var lastRecvSeq: UInt64 = 0
    private var closed = false

    public var onMessage: (@Sendable (NexoMessage) -> Void)?
    public var onReady: (@Sendable () -> Void)?
    public var onClosed: (@Sendable () -> Void)?

    static let maxFrame = 4 << 20

    public init(connection: NWConnection, key: SymmetricKey) {
        self.connection = connection
        self.key = key
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onReady?()
                self.receive()
            case .failed, .cancelled:
                self.finish()
            case .waiting:
                // sin ruta (p. ej. permiso de red local denegado): se cierra para que el cliente lo reporte
                self.queue.asyncAfter(deadline: .now() + 6) { if case .waiting = self.connection.state { self.finish() } }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    public func send(_ message: NexoMessage) {
        queue.async { [self] in
            guard !closed else { return }
            sendSeq += 1
            guard let json = try? JSONEncoder().encode(Envelope(seq: sendSeq, message: message)) else { return }
            let mac = Data(HMAC<SHA256>.authenticationCode(for: json, using: key))
            var frame = Data()
            var len = UInt32(mac.count + json.count).bigEndian
            withUnsafeBytes(of: &len) { frame.append(contentsOf: $0) }
            frame.append(mac)
            frame.append(json)
            connection.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    public func cancel() {
        queue.async { [self] in
            connection.cancel()
            finish()
        }
    }

    private func finish() {
        queue.async { [self] in
            guard !closed else { return }
            closed = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            onClosed?()
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                if !self.drain() { self.connection.cancel(); self.finish(); return }
            }
            if isComplete || error != nil { self.finish(); return }
            self.receive()
        }
    }

    /// Devuelve false si la trama no es válida (se corta la conexión).
    private func drain() -> Bool {
        while buffer.count >= 4 {
            let len = Int(buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            guard len >= 32, len <= Self.maxFrame else { return false }
            guard buffer.count >= 4 + len else { return true }
            let body = Data(buffer.subdata(in: 4..<(4 + len)))
            buffer = Data(buffer.dropFirst(4 + len))
            let mac = body.prefix(32)
            let json = body.dropFirst(32)
            guard HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: json, using: key),
                  let env = try? JSONDecoder().decode(Envelope.self, from: json),
                  env.seq > lastRecvSeq
            else { return false }
            lastRecvSeq = env.seq
            onMessage?(env.message)
        }
        return true
    }
}
