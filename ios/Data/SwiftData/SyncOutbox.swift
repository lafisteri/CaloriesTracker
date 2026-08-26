import Foundation
import SwiftData

struct SyncOutboxItem: Equatable, Sendable {
    let key: String
    let entityKey: SyncEntityKey
    let changeToken: UUID
    let enqueuedAt: Date
}

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

    func syncEntityKey() throws -> SyncEntityKey {
        guard let entityType = SyncEntityType(rawValue: entityTypeRaw) else {
            throw SyncOutboxError.invalidEntityType(entityTypeRaw)
        }
        let key = SyncEntityKey(entityType: entityType, entityID: entityID)
        guard self.key == key.rawValue else {
            throw SyncOutboxError.inconsistentKey(self.key)
        }
        return key
    }
}

enum SyncOutboxError: Error, LocalizedError {
    case invalidEntityType(String)
    case inconsistentKey(String)

    var errorDescription: String? {
        switch self {
        case let .invalidEntityType(rawValue):
            "Неизвестный тип sync outbox: \(rawValue)."
        case let .inconsistentKey(key):
            "Некорректный ключ sync outbox: \(key)."
        }
    }
}

@MainActor
enum SyncOutboxStore {
    static let defaultPendingLimit = 50

    static func markChanged(
        type: SyncEntityType,
        id: UUID,
        in modelContext: ModelContext,
    ) throws {
        try markChanged(
            key: SyncEntityKey(entityType: type, entityID: id),
            in: modelContext,
        )
    }

    static func markChanged(
        key: SyncEntityKey,
        in modelContext: ModelContext,
    ) throws {
        let rawKey = key.rawValue
        let now = Date()
        let changeToken = UUID()

        if let record = try record(key: rawKey, in: modelContext) {
            record.changeToken = changeToken
            record.enqueuedAt = now
        } else {
            modelContext.insert(
                SyncOutboxRecord(
                    key: rawKey,
                    entityTypeRaw: key.entityType.rawValue,
                    entityID: key.entityID,
                    changeToken: changeToken,
                    enqueuedAt: now,
                ),
            )
        }
    }

    /// Ensures a key is pending without rotating an in-flight change token.
    @discardableResult
    static func ensurePending(
        key: SyncEntityKey,
        in modelContext: ModelContext,
    ) throws -> Bool {
        guard try record(key: key.rawValue, in: modelContext) == nil else {
            return false
        }

        modelContext.insert(
            SyncOutboxRecord(
                key: key.rawValue,
                entityTypeRaw: key.entityType.rawValue,
                entityID: key.entityID,
                changeToken: UUID(),
                enqueuedAt: Date(),
            ),
        )
        return true
    }

    static func pending(in modelContext: ModelContext) throws -> [SyncOutboxRecord] {
        let descriptor = FetchDescriptor<SyncOutboxRecord>(
            sortBy: [SortDescriptor(\SyncOutboxRecord.enqueuedAt)],
        )
        return try modelContext.fetch(descriptor)
    }

    static func pendingCount(in modelContext: ModelContext) throws -> Int {
        try pending(in: modelContext).count
    }

    static func pending(
        limit: Int = defaultPendingLimit,
        in modelContext: ModelContext,
    ) throws -> [SyncOutboxItem] {
        guard limit > 0 else {
            return []
        }

        var descriptor = FetchDescriptor<SyncOutboxRecord>(
            sortBy: [
                SortDescriptor(\SyncOutboxRecord.enqueuedAt),
                SortDescriptor(\SyncOutboxRecord.key),
            ],
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map { record in
            SyncOutboxItem(
                key: record.key,
                entityKey: try record.syncEntityKey(),
                changeToken: record.changeToken,
                enqueuedAt: record.enqueuedAt,
            )
        }
    }

    static func pendingItem(
        key: SyncEntityKey,
        in modelContext: ModelContext,
    ) throws -> SyncOutboxItem? {
        guard let record = try record(key: key.rawValue, in: modelContext) else {
            return nil
        }
        return SyncOutboxItem(
            key: record.key,
            entityKey: try record.syncEntityKey(),
            changeToken: record.changeToken,
            enqueuedAt: record.enqueuedAt,
        )
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
