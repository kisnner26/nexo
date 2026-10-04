import CryptoKit
import Foundation

/// Caché de iconos en disco para no volver a pedirlos a la Mac.
enum IconCache {
    private static var dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("nexo-icons")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func url(_ name: String) -> URL {
        let h = SHA256.hash(data: Data(name.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(h + ".png")
    }

    static func read(_ name: String) -> Data? { try? Data(contentsOf: url(name)) }
    static func write(_ name: String, _ data: Data) { try? data.write(to: url(name)) }
}
