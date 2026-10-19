import Foundation

/// A record of a successful API check, never proof of current network access.
public struct NotionVerification: Codable, Equatable {
    public var settings: NotionSettings
    public var tokenFingerprint: String
    public var verifiedAt: Date
    public init(settings: NotionSettings, tokenFingerprint: String, verifiedAt: Date = Date()) {
        self.settings = settings
        self.tokenFingerprint = tokenFingerprint
        self.verifiedAt = verifiedAt
    }
    public func matches(settings: NotionSettings, tokenFingerprint: String) -> Bool {
        self.settings == settings && self.tokenFingerprint == tokenFingerprint
    }
}
