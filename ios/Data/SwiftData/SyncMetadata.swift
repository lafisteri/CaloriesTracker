import Foundation
import SwiftData

@Model
final class SyncRemoteStateRecord {
    @Attribute(.unique) var key: String
    var accountID: UUID
    var entityTypeRaw: String
    var entityID: UUID
    var serverRevision: Int64
    var updatedAt: Date

    init(
        key: String,
        accountID: UUID,
        entityTypeRaw: String,
        entityID: UUID,
        serverRevision: Int64,
        updatedAt: Date,
    ) {
        self.key = key
        self.accountID = accountID
        self.entityTypeRaw = entityTypeRaw
        self.entityID = entityID
        self.serverRevision = serverRevision
        self.updatedAt = updatedAt
    }
}

@Model
final class SyncPullStateRecord {
    @Attribute(.unique) var accountID: UUID
    var lastPulledRevision: Int64
    var updatedAt: Date

    init(accountID: UUID, lastPulledRevision: Int64, updatedAt: Date) {
        self.accountID = accountID
        self.lastPulledRevision = lastPulledRevision
        self.updatedAt = updatedAt
    }
}

enum SyncMetadataStoreError: Error, LocalizedError {
    case invalidRemoteRevision(Int64)
    case invalidPullCursor(Int64)
    case revisionRegression(stored: Int64, attempted: Int64)
    case invalidEntityType(String)
    case corruptRemoteState(String)
    case corruptPullState(UUID)

    var errorDescription: String? {
        switch self {
        case let .invalidRemoteRevision(revision):
            "Некорректная remote revision: \(revision)."
        case let .invalidPullCursor(revision):
            "Некорректный sync pull cursor: \(revision)."
        case let .revisionRegression(stored, attempted):
            "Нельзя уменьшить sync revision с \(stored) до \(attempted)."
        case let .invalidEntityType(rawValue):
            "Неизвестный тип sync metadata: \(rawValue)."
        case let .corruptRemoteState(key):
            "Неконсистентный remote sync metadata: \(key)."
        case let .corruptPullState(accountID):
            "Неконсистентный pull sync metadata для account \(accountID.uuidString)."
        }
    }
}

/// Account-scoped sync metadata. Callers own the enclosing ModelContext save boundary.
@MainActor
enum SyncMetadataStore {
    static func remoteRevision(
        accountID: UUID,
        entityKey: SyncEntityKey,
        in modelContext: ModelContext,
    ) throws -> Int64? {
        guard let state = try remoteState(
            accountID: accountID,
            entityKey: entityKey,
            in: modelContext,
        ) else {
            return nil
        }

        try validate(state, accountID: accountID, entityKey: entityKey)
        return state.serverRevision
    }

    static func setRemoteRevision(
        _ revision: Int64,
        accountID: UUID,
        entityKey: SyncEntityKey,
        in modelContext: ModelContext,
    ) throws {
        guard revision > 0 else {
            throw SyncMetadataStoreError.invalidRemoteRevision(revision)
        }

        if let state = try remoteState(
            accountID: accountID,
            entityKey: entityKey,
            in: modelContext,
        ) {
            try validate(state, accountID: accountID, entityKey: entityKey)
            if revision < state.serverRevision {
                throw SyncMetadataStoreError.revisionRegression(
                    stored: state.serverRevision,
                    attempted: revision,
                )
            }
            guard revision > state.serverRevision else {
                return
            }

            state.serverRevision = revision
            state.updatedAt = Date()
            return
        }

        modelContext.insert(
            SyncRemoteStateRecord(
                key: remoteStateKey(accountID: accountID, entityKey: entityKey),
                accountID: accountID,
                entityTypeRaw: entityKey.entityType.rawValue,
                entityID: entityKey.entityID,
                serverRevision: revision,
                updatedAt: Date(),
            ),
        )
    }

    static func pullCursor(
        accountID: UUID,
        in modelContext: ModelContext,
    ) throws -> Int64 {
        guard let state = try pullState(accountID: accountID, in: modelContext) else {
            return 0
        }

        try validate(state, accountID: accountID)
        return state.lastPulledRevision
    }

    static func setPullCursor(
        _ revision: Int64,
        accountID: UUID,
        in modelContext: ModelContext,
    ) throws {
        guard revision >= 0 else {
            throw SyncMetadataStoreError.invalidPullCursor(revision)
        }

        if let state = try pullState(accountID: accountID, in: modelContext) {
            try validate(state, accountID: accountID)
            if revision < state.lastPulledRevision {
                throw SyncMetadataStoreError.revisionRegression(
                    stored: state.lastPulledRevision,
                    attempted: revision,
                )
            }
            guard revision > state.lastPulledRevision else {
                return
            }

            state.lastPulledRevision = revision
            state.updatedAt = Date()
            return
        }

        // A missing state already represents cursor zero, so preserve that empty state for no-op writes.
        guard revision > 0 else {
            return
        }
        modelContext.insert(
            SyncPullStateRecord(
                accountID: accountID,
                lastPulledRevision: revision,
                updatedAt: Date(),
            ),
        )
    }

    static func remoteStateKey(accountID: UUID, entityKey: SyncEntityKey) -> String {
        "\(accountID.uuidString.lowercased()):\(entityKey.rawValue)"
    }

    private static func remoteState(
        accountID: UUID,
        entityKey: SyncEntityKey,
        in modelContext: ModelContext,
    ) throws -> SyncRemoteStateRecord? {
        let key = remoteStateKey(accountID: accountID, entityKey: entityKey)
        var descriptor = FetchDescriptor<SyncRemoteStateRecord>(
            predicate: #Predicate { $0.accountID == accountID && $0.key == key },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func pullState(
        accountID: UUID,
        in modelContext: ModelContext,
    ) throws -> SyncPullStateRecord? {
        var descriptor = FetchDescriptor<SyncPullStateRecord>(
            predicate: #Predicate { $0.accountID == accountID },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func validate(
        _ state: SyncRemoteStateRecord,
        accountID: UUID,
        entityKey: SyncEntityKey,
    ) throws {
        guard
            state.accountID == accountID,
            state.key == remoteStateKey(accountID: accountID, entityKey: entityKey),
            state.entityID == entityKey.entityID,
            state.serverRevision > 0
        else {
            throw SyncMetadataStoreError.corruptRemoteState(state.key)
        }
        guard let entityType = SyncEntityType(rawValue: state.entityTypeRaw) else {
            throw SyncMetadataStoreError.invalidEntityType(state.entityTypeRaw)
        }
        guard entityType == entityKey.entityType else {
            throw SyncMetadataStoreError.corruptRemoteState(state.key)
        }
    }

    private static func validate(_ state: SyncPullStateRecord, accountID: UUID) throws {
        guard state.accountID == accountID, state.lastPulledRevision >= 0 else {
            throw SyncMetadataStoreError.corruptPullState(state.accountID)
        }
    }
}
