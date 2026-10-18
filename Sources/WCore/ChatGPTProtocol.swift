import Foundation
import CryptoKit
import Security

public enum ChatGPTProtocol {
    public static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    public static func decode(_ value: String) -> Data? {
        let s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: s + String(repeating: "=", count: (4 - s.count % 4) % 4))
    }
    public static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw NotionError("Secure random generation failed.") }
        return base64URL(Data(bytes))
    }
    public static func challenge(_ verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    public static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(values.sorted { $0.key < $1.key }.map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").utf8)
    }
    public static func callback(_ url: URL, state: String, existingClient: String?) throws -> (code: String, client: String) {
        guard url.path == "/auth/callback", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw NotionError("Invalid sign-in callback.") }
        let items = parts.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count else { throw NotionError("Duplicate sign-in parameters.") }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard values["state"] == state else { throw NotionError("Sign-in state did not match. Try again.") }
        guard values["error"] == nil else { throw NotionError("ChatGPT sign-in was declined or unavailable.") }
        let client = values["client_id"] ?? existingClient ?? ""
        guard !client.isEmpty, client != "dynamic_agent_client", existingClient == nil || client == existingClient else { throw NotionError("Registration did not return the expected client ID.") }
        guard let code = values["code"], !code.isEmpty else { throw NotionError("Missing authorization code.") }
        return (code, client)
    }
    public static func validateClaims(_ claims: [String: Any], client: String, nonce: String?, subject: String?, now: Date = Date()) throws {
        let audiences = claims["aud"] as? [String] ?? [claims["aud"] as? String ?? ""]
        guard claims["iss"] as? String == "https://auth.openai.com", audiences.contains(client),
              let expiry = claims["exp"] as? Double, expiry > now.timeIntervalSince1970,
              let sub = claims["sub"] as? String, !sub.isEmpty else { throw NotionError("ChatGPT identity validation failed.") }
        if audiences.count > 1, claims["azp"] as? String != client { throw NotionError("Unexpected authorized party.") }
        if let nonce, claims["nonce"] as? String != nonce { throw NotionError("ChatGPT identity nonce did not match.") }
        if let subject, subject != sub { throw NotionError("This sign-in belongs to a different account.") }
    }
    static func der(_ tag: UInt8, _ data: Data) -> Data {
        let count = data.count
        let length: [UInt8] = count < 128 ? [UInt8(count)] : count < 256 ? [0x81, UInt8(count)] : [0x82, UInt8(count >> 8), UInt8(count & 255)]
        return Data([tag] + length) + data
    }
    public static func verifyJWT(_ token: String, keys: [[String: Any]], client: String, nonce: String?, subject: String?) throws -> [String: Any] {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3, let headerData = decode(parts[0]), let payload = decode(parts[1]), let signature = decode(parts[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any], header["alg"] as? String == "RS256",
              let kid = header["kid"] as? String,
              let key = keys.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              let n = key["n"] as? String, let e = key["e"] as? String, var modulus = decode(n), var exponent = decode(e), !modulus.isEmpty, !exponent.isEmpty else { throw NotionError("Invalid ChatGPT identity signature format.") }
        if modulus[0] >= 128 { modulus.insert(0, at: 0) }; if exponent[0] >= 128 { exponent.insert(0, at: 0) }
        let derKey = der(0x30, der(0x02, modulus) + der(0x02, exponent))
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(derKey as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, &error),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, Data((parts[0] + "." + parts[1]).utf8) as CFData, signature as CFData, &error),
              let claims = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw NotionError("ChatGPT identity signature could not be verified.") }
        try validateClaims(claims, client: client, nonce: nonce, subject: subject)
        return claims
    }
}
