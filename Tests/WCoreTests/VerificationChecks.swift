import Foundation
import WCore

enum VerificationChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name); count += 1; print("PASS: \(name)")
        }
        var state = SavedState()
        let receipt = NotionVerification(settings: state.settings, tokenFingerprint: "fingerprint", verifiedAt: Date(timeIntervalSince1970: 1234))
        state.notionVerification = receipt
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        check(restored.notionVerification == receipt, "Verification and timestamp survive app restart")
        check(receipt.matches(settings: state.settings, tokenFingerprint: "fingerprint"), "Same settings and credential restore saved verification")
        check(!receipt.matches(settings: state.settings, tokenFingerprint: "new"), "Changed token cannot inherit verification")
        var changed = state.settings; changed.taskSource = "different"
        check(!receipt.matches(settings: changed, tokenFingerprint: "fingerprint"), "Changed database cannot inherit verification")
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        old.removeValue(forKey: "notionVerification")
        let legacy = try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: old))
        check(legacy.notionVerification == nil, "Existing saved sessions load without verification receipt")
        return count
    }
}
