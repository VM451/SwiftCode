import Crypto
import Foundation

/// HMAC-SHA256 signing and verification helper for webhooks and checkpoints (`swift-crypto`).
public enum WebhookSigner {
    /// Produces a `sha256=<lowercase hex>` signature header for `payload`.
    public static func sign(payload: Data, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        return "sha256=\(hex)"
    }

    /// Constant-time verification of `X-Hub-Signature-256` headers.
    public static func verify(payload: Data, signatureHeader: String, secret: String) -> Bool {
        let expected = sign(payload: payload, secret: secret)
        guard expected.count == signatureHeader.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(expected.utf8, signatureHeader.utf8) {
            diff |= (a ^ b)
        }
        return diff == 0
    }

    /// Computes SHA-256 hex digest for data payloads (e.g., binary file metadata).
    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
