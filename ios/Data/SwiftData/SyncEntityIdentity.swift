import CryptoKit
import Foundation

enum SyncEntityType: String, CaseIterable, Codable, Sendable {
    case product
    case productVersion
    case recipe
    case recipeVersion
    case diaryEntry
    case weeklyGoal
}

struct SyncEntityKey: Hashable, Codable, Sendable {
    let entityType: SyncEntityType
    let entityID: UUID

    init(entityType: SyncEntityType, entityID: UUID) {
        self.entityType = entityType
        self.entityID = entityID
    }

    var rawValue: String {
        "\(entityType.rawValue):\(entityID.uuidString.lowercased())"
    }
}

/// Stable logical identity for one effective WeeklyGoal day.
///
/// The namespace is intentionally fixed. UUIDv5 derives its value from the
/// namespace bytes and the exact UTF-8 `LocalDay.rawValue` (`YYYY-MM-DD`), so
/// it has no dependency on the device locale, time zone or process lifetime.
enum WeeklyGoalIdentity {
    static let namespace = UUID(uuidString: "6E770171-4E9D-4E0C-8BC7-0C64A5CB6D52")!

    static func id(for effectiveFrom: LocalDay) -> UUID {
        var namespaceUUID = namespace.uuid
        let namespaceBytes = withUnsafeBytes(of: &namespaceUUID) { Array($0) }
        let nameBytes = Array(effectiveFrom.rawValue.utf8)
        let digest = Insecure.SHA1.hash(data: Data(namespaceBytes + nameBytes))
        var bytes = Array(digest.prefix(16))

        // RFC 4122, section 4.3: UUIDv5 and the RFC 4122 variant.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15],
        ))
    }
}
