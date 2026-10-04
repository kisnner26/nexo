import CryptoKit
import Foundation

/// Código de emparejamiento de 12 caracteres (~58 bits). La clave HMAC del canal
/// se deriva de él, así que quien no conozca el código no puede enviar órdenes.
public enum Pairing {
    static let alphabet = Array("ABCDEFGHJKMNPQRSTVWXYZ23456789")

    public static func newCode() -> String {
        var g = SystemRandomNumberGenerator()
        return String((0..<12).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &g)] })
    }

    public static func normalize(_ raw: String) -> String {
        String(raw.uppercased().filter { alphabet.contains($0) })
    }

    public static func isValid(_ raw: String) -> Bool { normalize(raw).count == 12 }

    public static func display(_ code: String) -> String {
        let c = Array(normalize(code))
        guard c.count == 12 else { return code }
        return stride(from: 0, to: 12, by: 4).map { String(c[$0..<$0 + 4]) }.joined(separator: "-")
    }

    public static func key(for code: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(normalize(code).utf8)),
            salt: Data("nexo-v1".utf8),
            info: Data("channel-hmac".utf8),
            outputByteCount: 32
        )
    }
}
