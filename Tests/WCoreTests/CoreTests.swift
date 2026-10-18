import Foundation
import WCore
import Security

@main struct Checks {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fatalError("FAIL: \(name)") }; count += 1; print("PASS: \(name)")
        }
        func rejects(_ name: String, _ action: () throws -> Void) {
            do { try action(); fatalError("FAIL: \(name)") } catch { count += 1; print("PASS: \(name)") }
        }
        let tasks = [WorkTask(id: "1", title: "Onboarding proposal", project: "Acme"), WorkTask(id: "2", title: "Onboarding proposal", project: "Other"), WorkTask(id: "3", title: "Onboarding proposal", done: true)]
        check(Matcher.ranked("working on the onboarding proposal for Acme", tasks: tasks).first?.task.id == "1", "Project disambiguation")
        check(Matcher.ranked("onbording", tasks: tasks).count == 2, "Fuzzy typo match excludes completed tasks")
        check(Matcher.ranked("grocery shopping", tasks: tasks).isEmpty, "Unrelated query has no match")
        check(Matcher.ranked("working on the", tasks: tasks).isEmpty, "Filler-only query has no match")
        let t = Date(timeIntervalSince1970: 1000)
        var s = WorkSession(task: WorkTask(title: "Test"), now: t)
        s.pause(at: t.addingTimeInterval(61.5))
        check(s.elapsed(at: t.addingTimeInterval(400)) == 61.5, "Paused time excluded")
        s.resume(at: t.addingTimeInterval(500)); s.resume(at: t.addingTimeInterval(510)); s.stop(done: false, at: t.addingTimeInterval(520))
        check(s.accumulated == 81.5 && !s.completed, "Exact time survives resume and stop")
        s.resume(at: t.addingTimeInterval(600)); check(s.runningSince == nil, "Finished sessions cannot resume")
        var state = SavedState(); state.active = s
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        check(restored.active == s, "Session persistence roundtrip")
        check(ChatGPTProtocol.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC 7636 PKCE vector")
        let callback = URL(string: "http://127.0.0.1/auth/callback?code=abc&state=valid&client_id=oaiapp_example")!
        let result = try ChatGPTProtocol.callback(callback, state: "valid", existingClient: nil)
        check(result.client == "oaiapp_example", "Dynamic registration retains issued client")
        rejects("Wrong OAuth state") { _ = try ChatGPTProtocol.callback(callback, state: "wrong", existingClient: nil) }
        rejects("Returning account client substitution") { _ = try ChatGPTProtocol.callback(callback, state: "valid", existingClient: "oaiapp_other") }
        rejects("Duplicate callback state") { _ = try ChatGPTProtocol.callback(URL(string: callback.absoluteString + "&state=valid")!, state: "valid", existingClient: nil) }
        let claims: [String: Any] = ["iss": "https://auth.openai.com", "aud": "client", "sub": "user", "exp": Date().addingTimeInterval(600).timeIntervalSince1970, "nonce": "nonce"]
        try ChatGPTProtocol.validateClaims(claims, client: "client", nonce: "nonce", subject: "user")
        rejects("Wrong ID token audience") { try ChatGPTProtocol.validateClaims(claims, client: "other", nonce: "nonce", subject: "user") }
        rejects("Wrong ID token nonce") { try ChatGPTProtocol.validateClaims(claims, client: "client", nonce: "other", subject: "user") }
        rejects("Wrong returning identity") { try ChatGPTProtocol.validateClaims(claims, client: "client", nonce: "nonce", subject: "other") }
        rejects("Forged JWT rejected") { _ = try ChatGPTProtocol.verifyJWT("e30.e30.AA", keys: [], client: "client", nonce: nil, subject: nil) }
        var expired = claims; expired["exp"] = Date().addingTimeInterval(-1).timeIntervalSince1970
        rejects("Expired ID token") { try ChatGPTProtocol.validateClaims(expired, client: "client", nonce: "nonce", subject: "user") }
        var extended = WorkSession(task: tasks[0], now: t)
        extended.extend(minutes: 15, at: t.addingTimeInterval(1500))
        check(extended.checkInAt == 2400, "Extension starts from current elapsed time")
        state.pending = [PendingUpdate(pageID: "1", status: "In progress", start: t, settings: NotionSettings()), PendingUpdate(pageID: "1", status: "Done", settings: NotionSettings())]
        let queue = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state)).pending
        check(queue.map(\.status) == ["In progress", "Done"] && queue[0].start == t, "Pending sync order survives restart")
        let key = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil)!
        let publicKey = SecKeyCopyPublicKey(key)!
        let der = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data
        let bytes = Array(der); var offset = 0
        func readTLV(_ expected: UInt8) -> Data {
            precondition(bytes[offset] == expected); offset += 1
            var length = Int(bytes[offset]); offset += 1
            if length >= 128 { let size = length & 127; length = 0; for _ in 0..<size { length = length * 256 + Int(bytes[offset]); offset += 1 } }
            let data = Data(bytes[offset..<offset + length]); if expected != 0x30 { offset += length }; return data
        }
        _ = readTLV(0x30)
        let modulus = readTLV(0x02), exponent = readTLV(0x02)
        let header = ChatGPTProtocol.base64URL(try JSONSerialization.data(withJSONObject: ["alg": "RS256", "kid": "test-key"]))
        let payload = ChatGPTProtocol.base64URL(try JSONSerialization.data(withJSONObject: claims))
        let signed = header + "." + payload
        let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(signed.utf8) as CFData, nil)! as Data
        let jwt = signed + "." + ChatGPTProtocol.base64URL(signature)
        let keys: [[String: Any]] = [["kid": "test-key", "kty": "RSA", "n": ChatGPTProtocol.base64URL(modulus), "e": ChatGPTProtocol.base64URL(exponent)]]
        let verified = try ChatGPTProtocol.verifyJWT(jwt, keys: keys, client: "client", nonce: "nonce", subject: "user")
        check(verified["sub"] as? String == "user", "Real RSA signature verifies against JWKS")
        rejects("Tampered JWT signature") { _ = try ChatGPTProtocol.verifyJWT(signed + "." + ChatGPTProtocol.base64URL(Data(repeating: 0, count: signature.count)), keys: keys, client: "client", nonce: "nonce", subject: "user") }
        print("\(count) checks passed.")
    }
}
