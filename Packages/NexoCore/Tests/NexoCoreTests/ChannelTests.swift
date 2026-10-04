import Network
import XCTest
@testable import NexoCore

final class ChannelTests: XCTestCase {
    private func makeServer(code: String, got: XCTestExpectation?) throws -> (NWListener, NexoChannel?, UInt16) {
        let l = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "listener")
        l.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        var keep: [NexoChannel] = []
        l.newConnectionHandler = { c in
            let ch = NexoChannel(connection: c, key: Pairing.key(for: code))
            ch.onMessage = { m in if m == .command(.setVolume(33)) { got?.fulfill() } }
            keep.append(ch)
            ch.start()
        }
        l.start(queue: .main)
        wait(for: [ready], timeout: 3)
        return (l, nil, l.port!.rawValue)
    }

    func testAuthenticatedDelivery() throws {
        let code = Pairing.newCode()
        let got = expectation(description: "msg")
        let (l, _, port) = try makeServer(code: code, got: got)
        let c = NexoChannel(connection: NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp),
                            key: Pairing.key(for: code))
        c.onReady = { c.send(.command(.setVolume(33))) }
        c.start()
        wait(for: [got], timeout: 4)
        l.cancel(); c.cancel()
    }

    func testWrongCodeRejected() throws {
        let got = expectation(description: "msg"); got.isInverted = true
        let (l, _, port) = try makeServer(code: Pairing.newCode(), got: got)
        let c = NexoChannel(connection: NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp),
                            key: Pairing.key(for: Pairing.newCode()))
        c.onReady = { c.send(.command(.setVolume(33))) }
        c.start()
        wait(for: [got], timeout: 2)
        l.cancel(); c.cancel()
    }
}
