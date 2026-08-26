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
