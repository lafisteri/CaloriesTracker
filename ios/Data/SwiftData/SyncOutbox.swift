import Foundation
import SwiftData

@Model
final class SyncOutboxRecord {
    @Attribute(.unique) var key: String
    var entityTypeRaw: String
    var entityID: UUID
    var changeToken: UUID
    var enqueuedAt: Date

    init(
        key: String,
        entityTypeRaw: String,
        entityID: UUID,
        changeToken: UUID,
        enqueuedAt: Date,
    ) {
        self.key = key
        self.entityTypeRaw = entityTypeRaw
        self.entityID = entityID
        self.changeToken = changeToken
        self.enqueuedAt = enqueuedAt
    }
}

enum SyncOutboxEntityType: String, CaseIterable, Sendable {
    case product
    case productVersion
    case recipe
    case recipeVersion
    case diaryEntry
    case weeklyGoal

    func outboxKey(for entityID: UUID) -> String {
        "\(rawValue):\(entityID.uuidString.lowercased())"
    }
}

@MainActor
enum SyncOutboxStore {
    static func markChanged(
        type: SyncOutboxEntityType,
        id: UUID,
        in modelContext: ModelContext,
    ) throws {
        let key = type.outboxKey(for: id)
        let now = Date()
        let changeToken = UUID()

        if let record = try record(key: key, in: modelContext) {
            record.changeToken = changeToken
            record.enqueuedAt = now
        } else {
            modelContext.insert(
                SyncOutboxRecord(
                    key: key,
                    entityTypeRaw: type.rawValue,
                    entityID: id,
                    changeToken: changeToken,
                    enqueuedAt: now,
                ),
            )
        }
    }

    static func pending(in modelContext: ModelContext) throws -> [SyncOutboxRecord] {
        let descriptor = FetchDescriptor<SyncOutboxRecord>(
            sortBy: [SortDescriptor(\SyncOutboxRecord.enqueuedAt)],
        )
        return try modelContext.fetch(descriptor)
    }

    @discardableResult
    static func acknowledge(
        key: String,
        token: UUID,
        in modelContext: ModelContext,
    ) throws -> Bool {
        guard let record = try record(key: key, in: modelContext), record.changeToken == token else {
            return false
        }

        modelContext.delete(record)
        return true
    }

    private static func record(key: String, in modelContext: ModelContext) throws -> SyncOutboxRecord? {
        var descriptor = FetchDescriptor<SyncOutboxRecord>(
            predicate: #Predicate { $0.key == key },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
