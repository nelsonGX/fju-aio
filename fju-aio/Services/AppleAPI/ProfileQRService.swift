import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - ProfileQRService
// Generates and parses QR codes for profile sharing and group rollcall credential sharing.
// All data stays on-device and peer-to-peer — nothing transits a server.

nonisolated enum ProfileQRService {
    private static let stableDeviceTokenKey = "com.nelsongx.apps.fju-aio.stableDeviceToken"
    private static let scheduleShareTokenKey = "com.nelsongx.apps.fju-aio.scheduleShareToken"
    private static let legacyScheduleShareTokensKey = "com.nelsongx.apps.fju-aio.legacyScheduleShareTokens"

    // MARK: - Stable Device Token
    // Generated once per install and stored in Keychain.
    // Used only for device-local identity/diagnostics, not as the public profile ID.

    static func stableDeviceToken() -> String {
        if let existing = existingStableDeviceToken() {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try? KeychainManager.shared.save(token, for: stableDeviceTokenKey)
        return token
    }

    static func scheduleShareToken() -> String {
        if let existing = existingScheduleShareToken() {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try? KeychainManager.shared.save(token, for: scheduleShareTokenKey)
        return token
    }

    static func existingStableDeviceToken() -> String? {
        try? KeychainManager.shared.retrieveString(for: stableDeviceTokenKey)
    }

    static func existingScheduleShareToken() -> String? {
        try? KeychainManager.shared.retrieveString(for: scheduleShareTokenKey)
    }

    static func storeScheduleShareToken(_ token: String) {
        guard !token.isEmpty else { return }
        if let existing = existingScheduleShareToken(), existing != token {
            storeLegacyScheduleShareToken(existing)
        } else if existingScheduleShareToken() == token {
            return
        }
        try? KeychainManager.shared.save(token, for: scheduleShareTokenKey)
    }

    static func scheduleShareTokensForPublishing() -> [String] {
        var seen = Set<String>()
        return ([scheduleShareToken()] + legacyScheduleShareTokens()).filter { token in
            guard !token.isEmpty, !seen.contains(token) else { return false }
            seen.insert(token)
            return true
        }
    }

    static func legacyScheduleShareTokens() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: legacyScheduleShareTokensKey),
              let tokens = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return tokens
    }

    static func clearStoredTokens() {
        try? KeychainManager.shared.delete(for: stableDeviceTokenKey)
        try? KeychainManager.shared.delete(for: scheduleShareTokenKey)
        UserDefaults.standard.removeObject(forKey: legacyScheduleShareTokensKey)
    }

    private static func storeLegacyScheduleShareToken(_ token: String) {
        var tokens = legacyScheduleShareTokens()
        guard !tokens.contains(token) else { return }
        tokens.append(token)
        if let data = try? JSONEncoder().encode(tokens) {
            UserDefaults.standard.set(data, forKey: legacyScheduleShareTokensKey)
        }
    }

    // MARK: - Generate Profile QR Payload

    static func makeProfilePayload(
        userId: Int,
        empNo: String,
        displayName: String
    ) -> ProfileQRPayload {
        ProfileQRPayload(
            version: 1,
            type: "profile",
            cloudKitRecordName: ProfileIdentity.publicRecordName(userId: userId),
            empNo: empNo,
            displayName: displayName,
            userId: userId,
            scheduleShareToken: scheduleShareToken()
        )
    }

    // MARK: - Generate Group Rollcall QR Payload

    static func makeGroupRollcallPayload(
        username: String,
        password: String,
        displayName: String,
        userId: Int
    ) -> GroupRollcallQRPayload {
        GroupRollcallQRPayload(
            version: 1,
            type: "group_rollcall",
            username: username,
            password: password,
            sharerDisplayName: displayName,
            sharerUserId: userId,
            issuedAt: Date()
        )
    }

    // MARK: - Generate Mutual Add QR Payload

    static func makeMutualPayload(
        userId: Int,
        empNo: String,
        displayName: String
    ) -> MutualQRPayload {
        MutualQRPayload(
            version: 1,
            type: "mutual",
            cloudKitRecordName: ProfileIdentity.publicRecordName(userId: userId),
            empNo: empNo,
            displayName: displayName,
            userId: userId,
            scheduleShareToken: scheduleShareToken()
        )
    }

    // MARK: - Generate Combined QR Payload (profile + credentials)

    static func makeCombinedPayload(
        userId: Int,
        empNo: String,
        displayName: String,
        username: String,
        password: String
    ) -> CombinedQRPayload {
        CombinedQRPayload(
            version: 1,
            type: "combined",
            cloudKitRecordName: ProfileIdentity.publicRecordName(userId: userId),
            empNo: empNo,
            displayName: displayName,
            userId: userId,
            username: username,
            password: password,
            scheduleShareToken: scheduleShareToken(),
            issuedAt: Date()
        )
    }

    // MARK: - Encode to QR Image

    static func generateQRImage(for payload: some Encodable, size: CGFloat = 300) -> UIImage? {
        guard let data = try? JSONEncoder().encode(payload),
              let jsonString = String(data: data, encoding: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(jsonString.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        let scale = size / ciImage.extent.width
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Parse Scanned QR String

    static func parse(qrString: String) -> ScannedQRType {
        guard let data = qrString.data(using: .utf8) else { return .unknown(qrString) }

        // Try to read the "type" field first to avoid decoding the wrong struct
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String {
            switch type {
            case "profile":
                if let payload = try? JSONDecoder().decode(ProfileQRPayload.self, from: data) {
                    return .profile(payload)
                }
            case "group_rollcall":
                if let payload = try? JSONDecoder().decode(GroupRollcallQRPayload.self, from: data) {
                    return .groupRollcall(payload)
                }
            case "combined":
                if let payload = try? JSONDecoder().decode(CombinedQRPayload.self, from: data) {
                    return .combined(payload)
                }
            case "mutual":
                if let payload = try? JSONDecoder().decode(MutualQRPayload.self, from: data) {
                    return .mutual(payload)
                }
            default:
                break
            }
        }
        return .unknown(qrString)
    }
}
