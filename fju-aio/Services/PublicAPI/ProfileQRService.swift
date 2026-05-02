import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - ProfileQRService
// Generates and parses QR codes for profile sharing and group rollcall credential sharing.
// All data stays on-device and peer-to-peer — nothing transits a server.

enum ProfileQRService {

    // MARK: - Stable Device Token
    // Generated once per install and stored in Keychain.
    // Used as the CloudKit record name so it's consistent across sessions.

    static func stableDeviceToken() -> String {
        let key = "com.nelsongx.apps.fju-aio.stableDeviceToken"
        if let existing = try? KeychainManager.shared.retrieveString(for: key) {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try? KeychainManager.shared.save(token, for: key)
        return token
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
            cloudKitRecordName: stableDeviceToken(),
            empNo: empNo,
            displayName: displayName,
            userId: userId
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
            cloudKitRecordName: stableDeviceToken(),
            empNo: empNo,
            displayName: displayName,
            userId: userId
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
            cloudKitRecordName: stableDeviceToken(),
            empNo: empNo,
            displayName: displayName,
            userId: userId,
            username: username,
            password: password,
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
