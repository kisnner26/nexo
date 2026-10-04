import XCTest
@testable import NexoCore

final class PairingTests: XCTestCase {
    func testCodeShapeAndNormalize() {
        let c = Pairing.newCode()
        XCTAssertEqual(c.count, 12)
        XCTAssertTrue(Pairing.isValid(Pairing.display(c).lowercased()))
    }

    func testMessageRoundTrip() throws {
        let m = NexoMessage.command(.setVolume(42))
        let d = try JSONEncoder().encode(Envelope(seq: 1, message: m))
        XCTAssertEqual(try JSONDecoder().decode(Envelope.self, from: d).message, m)
    }
}
