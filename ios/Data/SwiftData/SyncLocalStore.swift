import Foundation
import SwiftData

enum SyncLocalStoreError: Error, LocalizedError {
    case unsupportedPayloadSchema(Int)
    case missingEntity(SyncEntityKey)
    case invalidPayload(SyncEntityKey, reason: String)
    case inconsistentIdentity(SyncEntityKey)
    case immutableCollision(SyncEntityKey)

    var errorDescription: String? {
        switch self {
        case let .unsupportedPayloadSchema(version):
            "Неподдерживаемая версия sync payload: \(version)."
        case let .missingEntity(key):
            "Не найдена локальная sync-сущность \(key.rawValue)."
        case let .invalidPayload(key, reason):
            "Некорректный sync payload \(key.rawValue): \(reason)."
        case let .inconsistentIdentity(key):
            "Локальная sync-идентичность не согласована для \(key.rawValue)."
        case let .immutableCollision(key):
            "Неизменяемая sync-сущность \(key.rawValue) имеет конфликтующее содержимое."
        }
    }
}

enum SyncMergeResult: Equatable, Sendable {
    case inserted(SyncEntityKey, needsRepublish: [SyncEntityKey])
    case remoteApplied(SyncEntityKey, needsRepublish: [SyncEntityKey])
    case localKept(SyncEntityKey, needsRepublish: [SyncEntityKey])
    case identical(SyncEntityKey)
    case deferred(SyncEntityKey, missing: [SyncEntityKey])
}

final class SyncLocalStore {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func payload(for key: SyncEntityKey) throws -> SyncPayload {
        let modelContext = ModelContext(modelContainer)
        return try payload(for: key, in: modelContext)
    }

    func envelope(for key: SyncEntityKey) throws -> SyncPayloadEnvelope {
        SyncPayloadEnvelope(payload: try payload(for: key))
    }

    /// Returns all top-level sync identities without exporting their canonical payloads.
    func syncEntityKeys() throws -> [SyncEntityKey] {
        let modelContext = ModelContext(modelContainer)
        return try syncEntityKeys(in: modelContext)
    }

    /// Returns all top-level sync identities in deterministic dependency-friendly order.
    func syncEntityKeys(in modelContext: ModelContext) throws -> [SyncEntityKey] {
        let productVersions = try modelContext.fetch(FetchDescriptor<ProductVersionRecord>())
        let products = try modelContext.fetch(FetchDescriptor<ProductRecord>())
        let recipeVersions = try modelContext.fetch(FetchDescriptor<RecipeVersionRecord>())
        let recipes = try modelContext.fetch(FetchDescriptor<RecipeRecord>())
        let weeklyGoals = try modelContext.fetch(FetchDescriptor<WeeklyGoalRecord>())
        let diaryEntries = try modelContext.fetch(FetchDescriptor<DiaryEntryRecord>())

        func keys<T>(_ records: [T], type: SyncEntityType, id: (T) -> UUID) -> [SyncEntityKey] {
            records
                .map { SyncEntityKey(entityType: type, entityID: id($0)) }
                .sorted { $0.rawValue < $1.rawValue }
        }

        return keys(productVersions, type: .productVersion, id: { $0.id })
            + keys(products, type: .product, id: { $0.id })
            + keys(recipeVersions, type: .recipeVersion, id: { $0.id })
            + keys(recipes, type: .recipe, id: { $0.id })
            + keys(weeklyGoals, type: .weeklyGoal, id: { $0.id })
            + keys(diaryEntries, type: .diaryEntry, id: { $0.id })
    }

    func applyRemote(_ envelope: SyncPayloadEnvelope) throws -> SyncMergeResult {
        let modelContext = ModelContext(modelContainer)
        do {
            let result = try applyRemote(envelope, in: modelContext)
            try modelContext.save()
            return result
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Applies a remote envelope without saving. The caller owns the transaction boundary.
    func applyRemote(
        _ envelope: SyncPayloadEnvelope,
        in modelContext: ModelContext,
    ) throws -> SyncMergeResult {
        guard envelope.schemaVersion == SyncPayloadFormat.currentSchemaVersion else {
            throw SyncLocalStoreError.unsupportedPayloadSchema(envelope.schemaVersion)
        }
        return try applyRemote(envelope.payload, in: modelContext)
    }

    func applyRemote(_ payload: SyncPayload) throws -> SyncMergeResult {
        let modelContext = ModelContext(modelContainer)
        do {
            let result = try applyRemote(payload, in: modelContext)
            try modelContext.save()
            return result
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Applies a remote payload without saving. The caller owns the transaction boundary.
    func applyRemote(
        _ payload: SyncPayload,
        in modelContext: ModelContext,
    ) throws -> SyncMergeResult {
        try apply(payload.canonicalizedTimestamps(), in: modelContext)
    }

    func applyRemote(_ payloads: [SyncPayload]) throws -> [SyncMergeResult] {
        try payloads.map { try applyRemote($0) }
    }

    private func payload(for key: SyncEntityKey, in modelContext: ModelContext) throws -> SyncPayload {
        switch key.entityType {
        case .product:
            guard let record = try productRecord(id: key.entityID, in: modelContext) else {
                throw SyncLocalStoreError.missingEntity(key)
            }
            return .product(productPayload(from: record))
        case .productVersion:
            guard let record = try productVersionRecord(id: key.entityID, in: modelContext) else {
                throw SyncLocalStoreError.missingEntity(key)
            }
            return .productVersion(try productVersionPayload(from: record))
        case .recipe:
            guard let record = try recipeRecord(id: key.entityID, in: modelContext) else {
                throw SyncLocalStoreError.missingEntity(key)
            }
            return .recipe(recipePayload(from: record))
        case .recipeVersion:
            guard let record = try recipeVersionRecord(id: key.entityID, in: modelContext) else {
                throw SyncLocalStoreError.missingEntity(key)
            }
            return .recipeVersion(recipeVersionPayload(from: record))
        case .diaryEntry:
            guard let record = try diaryEntryRecord(id: key.entityID, in: modelContext) else {
                throw SyncLocalStoreError.missingEntity(key)
            }
            return .diaryEntry(try diaryEntryPayload(from: record))
        case .weeklyGoal:
            guard let record = try weeklyGoalRecord(id: key.entityID, in: modelContext) else {
                throw SyncLocalStoreError.missingEntity(key)
            }
            return .weeklyGoal(try weeklyGoalPayload(from: record))
        }
    }

    private func apply(_ payload: SyncPayload, in modelContext: ModelContext) throws -> SyncMergeResult {
        try validate(payload)
        switch payload {
        case let .product(payload):
            return try applyProduct(payload, in: modelContext)
        case let .productVersion(payload):
            return try applyProductVersion(payload, in: modelContext)
        case let .recipe(payload):
            return try applyRecipe(payload, in: modelContext)
        case let .recipeVersion(payload):
            return try applyRecipeVersion(payload, in: modelContext)
        case let .diaryEntry(payload):
            return try applyDiaryEntry(payload, in: modelContext)
        case let .weeklyGoal(payload):
            return try applyWeeklyGoal(payload, in: modelContext)
        }
    }

    private func applyProduct(_ remote: ProductPayload, in modelContext: ModelContext) throws -> SyncMergeResult {
        let key = SyncEntityKey(entityType: .product, entityID: remote.id)
        let remotePayload = SyncPayload.product(remote)

        if let localRecord = try productRecord(id: remote.id, in: modelContext) {
            let localPayload = productPayload(from: localRecord)
            if localPayload == remote {
                return .identical(key)
            }
            if try mutableWinner(
                local: .product(localPayload),
                remote: remotePayload,
                localUpdatedAt: localPayload.updatedAt,
                remoteUpdatedAt: remote.updatedAt,
                localDeletedAt: localPayload.deletedAt,
                remoteDeletedAt: remote.deletedAt,
            ) == .local {
                return .localKept(key, needsRepublish: [key])
            }

            let missing = try missingDependencies(for: remote, in: modelContext)
            guard missing.isEmpty else {
                return .deferred(key, missing: missing)
            }

            apply(remote, to: localRecord)
            try attachProductVersions(to: localRecord, in: modelContext)
            let repairs = try repairBarcodeConflict(for: localRecord, in: modelContext)
            return .remoteApplied(key, needsRepublish: repairs)
        }

        let missing = try missingDependencies(for: remote, in: modelContext)
        guard missing.isEmpty else {
            return .deferred(key, missing: missing)
        }

        let record = makeProductRecord(from: remote)
        modelContext.insert(record)
        try attachProductVersions(to: record, in: modelContext)
        let repairs = try repairBarcodeConflict(for: record, in: modelContext)
        return .inserted(key, needsRepublish: repairs)
    }

    private func applyProductVersion(
        _ remote: ProductVersionPayload,
        in modelContext: ModelContext,
    ) throws -> SyncMergeResult {
        let key = SyncEntityKey(entityType: .productVersion, entityID: remote.id)
        if let localRecord = try productVersionRecord(id: remote.id, in: modelContext) {
            guard try productVersionPayload(from: localRecord) == remote else {
                throw SyncLocalStoreError.immutableCollision(key)
            }
            return .identical(key)
        }

        let record = makeProductVersionRecord(from: remote)
        if let owner = try productRecord(id: remote.productID, in: modelContext) {
            record.product = owner
        }
        modelContext.insert(record)
        return .inserted(key, needsRepublish: [])
    }

    private func applyRecipe(_ remote: RecipePayload, in modelContext: ModelContext) throws -> SyncMergeResult {
        let key = SyncEntityKey(entityType: .recipe, entityID: remote.id)
        let remotePayload = SyncPayload.recipe(remote)

        if let localRecord = try recipeRecord(id: remote.id, in: modelContext) {
            let localPayload = recipePayload(from: localRecord)
            if localPayload == remote {
                return .identical(key)
            }
            if try mutableWinner(
                local: .recipe(localPayload),
                remote: remotePayload,
                localUpdatedAt: localPayload.updatedAt,
                remoteUpdatedAt: remote.updatedAt,
                localDeletedAt: localPayload.deletedAt,
                remoteDeletedAt: remote.deletedAt,
            ) == .local {
                return .localKept(key, needsRepublish: [key])
            }

            let missing = try missingDependencies(for: remote, in: modelContext)
            guard missing.isEmpty else {
                return .deferred(key, missing: missing)
            }

            apply(remote, to: localRecord)
            try attachRecipeVersions(to: localRecord, in: modelContext)
            return .remoteApplied(key, needsRepublish: [])
        }

        let missing = try missingDependencies(for: remote, in: modelContext)
        guard missing.isEmpty else {
            return .deferred(key, missing: missing)
        }

        let record = makeRecipeRecord(from: remote)
        modelContext.insert(record)
        try attachRecipeVersions(to: record, in: modelContext)
        return .inserted(key, needsRepublish: [])
    }

    private func applyRecipeVersion(
        _ remote: RecipeVersionPayload,
        in modelContext: ModelContext,
    ) throws -> SyncMergeResult {
        let key = SyncEntityKey(entityType: .recipeVersion, entityID: remote.id)
        if let localRecord = try recipeVersionRecord(id: remote.id, in: modelContext) {
            guard recipeVersionPayload(from: localRecord) == remote else {
                throw SyncLocalStoreError.immutableCollision(key)
            }
            return .identical(key)
        }

        let missing = try missingDependencies(for: remote, in: modelContext)
        guard missing.isEmpty else {
            return .deferred(key, missing: missing)
        }

        let record = makeRecipeVersionRecord(from: remote)
        if let owner = try recipeRecord(id: remote.recipeID, in: modelContext) {
            record.recipe = owner
        }
        let ingredients = remote.ingredients.map { makeRecipeIngredientRecord(from: $0) }
        record.ingredients = ingredients
        for ingredient in ingredients {
            ingredient.recipeVersion = record
        }

        modelContext.insert(record)
        for ingredient in ingredients {
            modelContext.insert(ingredient)
        }
        return .inserted(key, needsRepublish: [])
    }

    private func applyDiaryEntry(
        _ remote: DiaryEntryPayload,
        in modelContext: ModelContext,
    ) throws -> SyncMergeResult {
        let key = SyncEntityKey(entityType: .diaryEntry, entityID: remote.id)
        let remotePayload = SyncPayload.diaryEntry(remote)

        if let localRecord = try diaryEntryRecord(id: remote.id, in: modelContext) {
            let localPayload = try diaryEntryPayload(from: localRecord)
            if localPayload == remote {
                return .identical(key)
            }
            if try mutableWinner(
                local: .diaryEntry(localPayload),
                remote: remotePayload,
                localUpdatedAt: localPayload.updatedAt,
                remoteUpdatedAt: remote.updatedAt,
                localDeletedAt: localPayload.deletedAt,
                remoteDeletedAt: remote.deletedAt,
            ) == .local {
                return .localKept(key, needsRepublish: [key])
            }

            let missing = try missingDependencies(for: remote, in: modelContext)
            guard missing.isEmpty else {
                return .deferred(key, missing: missing)
            }

            apply(remote, to: localRecord)
            return .remoteApplied(key, needsRepublish: [])
        }

        let missing = try missingDependencies(for: remote, in: modelContext)
        guard missing.isEmpty else {
            return .deferred(key, missing: missing)
        }

        modelContext.insert(makeDiaryEntryRecord(from: remote))
        return .inserted(key, needsRepublish: [])
    }

    private func applyWeeklyGoal(
        _ remote: WeeklyGoalPayload,
        in modelContext: ModelContext,
    ) throws -> SyncMergeResult {
        let key = SyncEntityKey(entityType: .weeklyGoal, entityID: remote.id)
        let effectiveFromKey = remote.effectiveFrom.rawValue
        let matchingID = try weeklyGoalRecord(id: remote.id, in: modelContext)
        let matchingEffectiveFrom = try weeklyGoalRecord(effectiveFromKey: effectiveFromKey, in: modelContext)

        if let matchingID,
           let matchingEffectiveFrom,
           matchingID.id != matchingEffectiveFrom.id
        {
            throw SyncLocalStoreError.inconsistentIdentity(key)
        }
        if matchingID != nil, matchingEffectiveFrom == nil {
            throw SyncLocalStoreError.inconsistentIdentity(key)
        }

        if let localRecord = matchingEffectiveFrom {
            let localPayload = try weeklyGoalPayload(from: localRecord)
            if localPayload == remote {
                return .identical(key)
            }
            if try timestampWinner(
                local: .weeklyGoal(localPayload),
                remote: .weeklyGoal(remote),
                localTimestamp: localPayload.createdAt,
                remoteTimestamp: remote.createdAt,
            ) == .local {
                let localKey = SyncEntityKey(entityType: .weeklyGoal, entityID: localPayload.id)
                return .localKept(localKey, needsRepublish: [localKey])
            }

            if localRecord.id == remote.id {
                try apply(remote, to: localRecord, in: modelContext)
            } else {
                modelContext.delete(localRecord)
                let record = makeWeeklyGoalRecord(from: remote)
                try apply(remote, to: record, in: modelContext)
                modelContext.insert(record)
            }
            return .remoteApplied(key, needsRepublish: [])
        }

        let record = makeWeeklyGoalRecord(from: remote)
        try apply(remote, to: record, in: modelContext)
        modelContext.insert(record)
        return .inserted(key, needsRepublish: [])
    }

    private func mutableWinner(
        local: SyncPayload,
        remote: SyncPayload,
        localUpdatedAt: Date,
        remoteUpdatedAt: Date,
        localDeletedAt: Date?,
        remoteDeletedAt: Date?,
    ) throws -> MergeWinner {
        if localDeletedAt != nil || remoteDeletedAt != nil {
            if localDeletedAt != nil, remoteDeletedAt == nil {
                return .local
            }
            if remoteDeletedAt != nil, localDeletedAt == nil {
                return .remote
            }
        }

        return try timestampWinner(
            local: local,
            remote: remote,
            localTimestamp: localUpdatedAt,
            remoteTimestamp: remoteUpdatedAt,
        )
    }

    private func timestampWinner(
        local: SyncPayload,
        remote: SyncPayload,
        localTimestamp: Date,
        remoteTimestamp: Date,
    ) throws -> MergeWinner {
        let localMilliseconds = SyncTimestamp.millisecondsSinceEpoch(localTimestamp)
        let remoteMilliseconds = SyncTimestamp.millisecondsSinceEpoch(remoteTimestamp)
        if let localMilliseconds, let remoteMilliseconds, localMilliseconds != remoteMilliseconds {
            return localMilliseconds > remoteMilliseconds ? .local : .remote
        }

        return try SyncPayloadCanonicalizer.compare(local, remote) == .orderedAscending ? .remote : .local
    }

    private func missingDependencies(
        for payload: ProductPayload,
        in modelContext: ModelContext,
    ) throws -> [SyncEntityKey] {
        guard let version = try productVersionRecord(id: payload.currentVersionID, in: modelContext) else {
            return [SyncEntityKey(entityType: .productVersion, entityID: payload.currentVersionID)]
        }
        guard version.productID == payload.id else {
            throw SyncLocalStoreError.invalidPayload(
                SyncEntityKey(entityType: .product, entityID: payload.id),
                reason: "currentVersionID belongs to a different product",
            )
        }
        return []
    }

    private func missingDependencies(
        for payload: RecipePayload,
        in modelContext: ModelContext,
    ) throws -> [SyncEntityKey] {
        guard let version = try recipeVersionRecord(id: payload.currentVersionID, in: modelContext) else {
            return [SyncEntityKey(entityType: .recipeVersion, entityID: payload.currentVersionID)]
        }
        guard version.recipeID == payload.id else {
            throw SyncLocalStoreError.invalidPayload(
                SyncEntityKey(entityType: .recipe, entityID: payload.id),
                reason: "currentVersionID belongs to a different recipe",
            )
        }
        return []
    }

    private func missingDependencies(
        for payload: DiaryEntryPayload,
        in modelContext: ModelContext,
    ) throws -> [SyncEntityKey] {
        switch payload.sourceType {
        case .product:
            guard let version = try productVersionRecord(id: payload.sourceVersionID, in: modelContext) else {
                return [SyncEntityKey(entityType: .productVersion, entityID: payload.sourceVersionID)]
            }
            guard version.productID == payload.sourceID,
                  payload.unitToken == version.baseUnitRaw
            else {
                throw SyncLocalStoreError.invalidPayload(
                    SyncEntityKey(entityType: .diaryEntry, entityID: payload.id),
                    reason: "product source version is incompatible with the diary snapshot",
                )
            }
        case .recipe:
            guard let version = try recipeVersionRecord(id: payload.sourceVersionID, in: modelContext) else {
                return [SyncEntityKey(entityType: .recipeVersion, entityID: payload.sourceVersionID)]
            }
            guard version.recipeID == payload.sourceID,
                  diaryUnit(payload.unitToken, isAvailableFor: version)
            else {
                throw SyncLocalStoreError.invalidPayload(
                    SyncEntityKey(entityType: .diaryEntry, entityID: payload.id),
                    reason: "recipe source version is incompatible with the diary snapshot",
                )
            }
        }
        return []
    }

    private func missingDependencies(
        for payload: RecipeVersionPayload,
        in modelContext: ModelContext,
    ) throws -> [SyncEntityKey] {
        var missing: Set<SyncEntityKey> = []
        var inputs: [RecipeIngredientCalculationInput] = []

        for ingredient in payload.ingredients {
            guard let productVersion = try productVersionRecord(id: ingredient.productVersionID, in: modelContext) else {
                missing.insert(SyncEntityKey(entityType: .productVersion, entityID: ingredient.productVersionID))
                continue
            }
            guard productVersion.productID == ingredient.productID,
                  productVersion.baseUnitRaw == ingredient.unitToken
            else {
                throw SyncLocalStoreError.invalidPayload(
                    SyncEntityKey(entityType: .recipeVersion, entityID: payload.id),
                    reason: "ingredient pin or unit is incompatible with its ProductVersion",
                )
            }
            inputs.append(
                RecipeIngredientCalculationInput(
                    draftID: ingredient.id,
                    productVersion: try productVersion.toDomain(),
                    amount: ingredient.amount,
                    unitToken: ingredient.unitToken,
                ),
            )
        }

        guard missing.isEmpty else {
            return missing.sorted { $0.rawValue < $1.rawValue }
        }

        do {
            let calculation = try RecipeCalculator.calculate(ingredients: inputs)
            guard calculation.totalNutrition == payload.totalNutrition else {
                throw SyncLocalStoreError.invalidPayload(
                    SyncEntityKey(entityType: .recipeVersion, entityID: payload.id),
                    reason: "ingredient totals do not match totalNutrition",
                )
            }
            let normalizedAmounts = Dictionary(
                uniqueKeysWithValues: calculation.ingredientCalculations.map { ($0.draftID, $0.normalizedAmount) },
            )
            guard payload.ingredients.allSatisfy({ normalizedAmounts[$0.id] == $0.normalizedAmount }) else {
                throw SyncLocalStoreError.invalidPayload(
                    SyncEntityKey(entityType: .recipeVersion, entityID: payload.id),
                    reason: "ingredient normalized amounts do not match pinned ProductVersions",
                )
            }
        } catch let error as SyncLocalStoreError {
            throw error
        } catch {
            throw SyncLocalStoreError.invalidPayload(
                SyncEntityKey(entityType: .recipeVersion, entityID: payload.id),
                reason: "recipe calculation validation failed",
            )
        }
        return []
    }

    private func repairBarcodeConflict(
        for changedRecord: ProductRecord,
        in modelContext: ModelContext,
    ) throws -> [SyncEntityKey] {
        guard let barcode = changedRecord.barcode else {
            return []
        }

        let descriptor = FetchDescriptor<ProductRecord>(predicate: #Predicate { $0.barcode == barcode })
        var records = try modelContext.fetch(descriptor)
        if !records.contains(where: { $0.id == changedRecord.id }) {
            records.append(changedRecord)
        }
        guard records.count > 1 else {
            return []
        }

        let winner = try records.dropFirst().reduce(records[0]) { currentWinner, candidate in
            let winnerPayload = SyncPayload.product(productPayload(from: currentWinner))
            let candidatePayload = SyncPayload.product(productPayload(from: candidate))
            return try timestampWinner(
                local: winnerPayload,
                remote: candidatePayload,
                localTimestamp: currentWinner.updatedAt,
                remoteTimestamp: candidate.updatedAt,
            ) == .local ? currentWinner : candidate
        }

        var republish: Set<SyncEntityKey> = []
        for record in records where record.id != winner.id && record.barcode != nil {
            record.barcode = nil
            if let recordMilliseconds = SyncTimestamp.millisecondsSinceEpoch(record.updatedAt),
               let winnerMilliseconds = SyncTimestamp.millisecondsSinceEpoch(winner.updatedAt),
               recordMilliseconds < winnerMilliseconds
            {
                record.updatedAt = winner.updatedAt
            }
            republish.insert(SyncEntityKey(entityType: .product, entityID: record.id))
        }
        return republish.sorted { $0.rawValue < $1.rawValue }
    }

    private func validate(_ payload: SyncPayload) throws {
        switch payload {
        case let .product(payload):
            try validate(payload)
        case let .productVersion(payload):
            try validate(payload)
        case let .recipe(payload):
            try validate(payload)
        case let .recipeVersion(payload):
            try validate(payload)
        case let .diaryEntry(payload):
            try validate(payload)
        case let .weeklyGoal(payload):
            try validate(payload)
        }
    }

    private func validate(_ payload: ProductPayload) throws {
        let key = SyncEntityKey(entityType: .product, entityID: payload.id)
        try validateName(payload.name, key: key)
        if let barcode = payload.barcode {
            guard !barcode.isEmpty, barcode == barcode.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw SyncLocalStoreError.invalidPayload(key, reason: "barcode must be normalized when present")
            }
        }
        try validateDates(payload.createdAt, payload.updatedAt, payload.deletedAt, key: key)
    }

    private func validate(_ payload: ProductVersionPayload) throws {
        let key = SyncEntityKey(entityType: .productVersion, entityID: payload.id)
        guard payload.versionNumber > 0,
              payload.baseAmount.isFinite,
              payload.baseAmount > 0
        else {
            throw SyncLocalStoreError.invalidPayload(key, reason: "version number or base amount is invalid")
        }
        try validateNutrition(payload.nutrition, key: key)
        try validateDate(payload.createdAt, key: key)
    }

    private func validate(_ payload: RecipePayload) throws {
        let key = SyncEntityKey(entityType: .recipe, entityID: payload.id)
        try validateName(payload.name, key: key)
        try validateDates(payload.createdAt, payload.updatedAt, payload.deletedAt, key: key)
    }

    private func validate(_ payload: RecipeVersionPayload) throws {
        let key = SyncEntityKey(entityType: .recipeVersion, entityID: payload.id)
        guard payload.versionNumber > 0,
              !payload.ingredients.isEmpty,
              Set(payload.ingredients.map(\.id)).count == payload.ingredients.count,
              payload.ingredients.map(\.position) == Array(payload.ingredients.indices)
        else {
            throw SyncLocalStoreError.invalidPayload(key, reason: "ingredient identities or ordering are invalid")
        }
        guard payload.cookedWeight != nil || payload.servingsCount != nil else {
            throw SyncLocalStoreError.invalidPayload(key, reason: "recipe output is required")
        }
        if let cookedWeight = payload.cookedWeight,
           !(cookedWeight.isFinite && cookedWeight > 0)
        {
            throw SyncLocalStoreError.invalidPayload(key, reason: "cookedWeight is invalid")
        }
        if let servingsCount = payload.servingsCount,
           !(servingsCount.isFinite && servingsCount > 0)
        {
            throw SyncLocalStoreError.invalidPayload(key, reason: "servingsCount is invalid")
        }
        try validateNutrition(payload.totalNutrition, key: key)
        try validateDate(payload.createdAt, key: key)

        for ingredient in payload.ingredients {
            guard ingredient.recipeVersionID == payload.id,
                  ingredient.amount.isFinite,
                  ingredient.amount > 0,
                  ingredient.normalizedAmount.isFinite,
                  ingredient.normalizedAmount > 0,
                  !ingredient.unitToken.isEmpty
            else {
                throw SyncLocalStoreError.invalidPayload(key, reason: "ingredient values are invalid")
            }
        }
    }

    private func validate(_ payload: DiaryEntryPayload) throws {
        let key = SyncEntityKey(entityType: .diaryEntry, entityID: payload.id)
        guard payload.sortOrder >= 0,
              payload.amount.isFinite,
              payload.amount > 0,
              !payload.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !payload.unitToken.isEmpty
        else {
            throw SyncLocalStoreError.invalidPayload(key, reason: "entry fields are invalid")
        }
        try validateNutrition(payload.nutrition, key: key)
        try validateDates(payload.createdAt, payload.updatedAt, payload.deletedAt, key: key)
    }

    private func validate(_ payload: WeeklyGoalPayload) throws {
        let key = SyncEntityKey(entityType: .weeklyGoal, entityID: payload.id)
        guard payload.days.count == LocalDay.Weekday.allCases.count,
              Set(payload.days.map(\.id)).count == payload.days.count,
              Set(payload.days.map(\.weekday)) == Set(LocalDay.Weekday.allCases),
              payload.days.map(\.position) == Array(payload.days.indices)
        else {
            throw SyncLocalStoreError.invalidPayload(key, reason: "weekly goal days are invalid")
        }
        try validateDate(payload.createdAt, key: key)
        for day in payload.days {
            guard day.weeklyGoalID == payload.id, day.goal.isValid else {
                throw SyncLocalStoreError.invalidPayload(key, reason: "daily goal values are invalid")
            }
        }
    }

    private func validateName(_ name: String, key: SyncEntityKey) throws {
        guard !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw SyncLocalStoreError.invalidPayload(key, reason: "name must be normalized and nonempty")
        }
    }

    private func validateNutrition(_ nutrition: Nutrition, key: SyncEntityKey) throws {
        guard nutrition.isFinite,
              [nutrition.calories, nutrition.protein, nutrition.fat, nutrition.carbs].allSatisfy({ $0 >= 0 })
        else {
            throw SyncLocalStoreError.invalidPayload(key, reason: "nutrition must be finite and nonnegative")
        }
    }

    private func validateDates(_ createdAt: Date, _ updatedAt: Date, _ deletedAt: Date?, key: SyncEntityKey) throws {
        try validateDate(createdAt, key: key)
        try validateDate(updatedAt, key: key)
        if let deletedAt {
            try validateDate(deletedAt, key: key)
        }
    }

    private func validateDate(_ date: Date, key: SyncEntityKey) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw SyncLocalStoreError.invalidPayload(key, reason: "timestamp must be finite")
        }
    }

    private func productRecord(id: UUID, in modelContext: ModelContext) throws -> ProductRecord? {
        var descriptor = FetchDescriptor<ProductRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func productVersionRecord(id: UUID, in modelContext: ModelContext) throws -> ProductVersionRecord? {
        var descriptor = FetchDescriptor<ProductVersionRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func recipeRecord(id: UUID, in modelContext: ModelContext) throws -> RecipeRecord? {
        var descriptor = FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func recipeVersionRecord(id: UUID, in modelContext: ModelContext) throws -> RecipeVersionRecord? {
        var descriptor = FetchDescriptor<RecipeVersionRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func diaryEntryRecord(id: UUID, in modelContext: ModelContext) throws -> DiaryEntryRecord? {
        var descriptor = FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func weeklyGoalRecord(id: UUID, in modelContext: ModelContext) throws -> WeeklyGoalRecord? {
        var descriptor = FetchDescriptor<WeeklyGoalRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func weeklyGoalRecord(effectiveFromKey: String, in modelContext: ModelContext) throws -> WeeklyGoalRecord? {
        var descriptor = FetchDescriptor<WeeklyGoalRecord>(
            predicate: #Predicate { $0.effectiveFromKey == effectiveFromKey },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func dailyGoalRecord(id: UUID, in modelContext: ModelContext) throws -> DailyMacroGoalRecord? {
        var descriptor = FetchDescriptor<DailyMacroGoalRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func attachProductVersions(to product: ProductRecord, in modelContext: ModelContext) throws {
        let productID = product.id
        let descriptor = FetchDescriptor<ProductVersionRecord>(
            predicate: #Predicate { $0.productID == productID },
        )
        for version in try modelContext.fetch(descriptor) {
            version.product = product
        }
    }

    private func attachRecipeVersions(to recipe: RecipeRecord, in modelContext: ModelContext) throws {
        let recipeID = recipe.id
        let descriptor = FetchDescriptor<RecipeVersionRecord>(
            predicate: #Predicate { $0.recipeID == recipeID },
        )
        for version in try modelContext.fetch(descriptor) {
            version.recipe = recipe
        }
    }

    private func productPayload(from record: ProductRecord) -> ProductPayload {
        ProductPayload(
            id: record.id,
            name: record.name,
            barcode: record.barcode,
            currentVersionID: record.currentVersionID,
            createdAt: SyncTimestamp.canonical(record.createdAt),
            updatedAt: SyncTimestamp.canonical(record.updatedAt),
            deletedAt: SyncTimestamp.canonical(record.deletedAt),
        )
    }

    private func productVersionPayload(from record: ProductVersionRecord) throws -> ProductVersionPayload {
        guard let baseUnit = ProductBaseUnit(rawValue: record.baseUnitRaw) else {
            throw SyncLocalStoreError.invalidPayload(
                SyncEntityKey(entityType: .productVersion, entityID: record.id),
                reason: "local base unit is invalid",
            )
        }
        return ProductVersionPayload(
            id: record.id,
            productID: record.productID,
            basedOnVersionID: record.basedOnVersionID,
            versionNumber: record.versionNumber,
            baseUnit: baseUnit,
            baseAmount: record.baseAmount,
            nutrition: Nutrition(
                calories: record.calories,
                protein: record.protein,
                fat: record.fat,
                carbs: record.carbs,
            ),
            createdAt: SyncTimestamp.canonical(record.createdAt),
        )
    }

    private func recipePayload(from record: RecipeRecord) -> RecipePayload {
        RecipePayload(
            id: record.id,
            name: record.name,
            currentVersionID: record.currentVersionID,
            createdAt: SyncTimestamp.canonical(record.createdAt),
            updatedAt: SyncTimestamp.canonical(record.updatedAt),
            deletedAt: SyncTimestamp.canonical(record.deletedAt),
        )
    }

    private func recipeVersionPayload(from record: RecipeVersionRecord) -> RecipeVersionPayload {
        RecipeVersionPayload(
            id: record.id,
            recipeID: record.recipeID,
            basedOnVersionID: record.basedOnVersionID,
            versionNumber: record.versionNumber,
            totalNutrition: Nutrition(
                calories: record.totalCalories,
                protein: record.totalProtein,
                fat: record.totalFat,
                carbs: record.totalCarbs,
            ),
            cookedWeight: record.cookedWeight,
            servingsCount: record.servingsCount,
            ingredients: record.ingredients
                .sorted { $0.position < $1.position }
                .map { recipeIngredientPayload(from: $0) },
            createdAt: SyncTimestamp.canonical(record.createdAt),
        )
    }

    private func recipeIngredientPayload(from record: RecipeIngredientRecord) -> RecipeVersionPayload.Ingredient {
        RecipeVersionPayload.Ingredient(
            id: record.id,
            recipeVersionID: record.recipeVersionID,
            position: record.position,
            productID: record.productID,
            productVersionID: record.productVersionID,
            amount: record.amount,
            unitToken: record.unitToken,
            normalizedAmount: record.normalizedAmount,
        )
    }

    private func diaryEntryPayload(from record: DiaryEntryRecord) throws -> DiaryEntryPayload {
        guard let day = LocalDay(rawValue: record.dayKey),
              let mealType = MealType(rawValue: record.mealTypeRaw),
              let sourceType = SourceType(rawValue: record.sourceTypeRaw)
        else {
            throw SyncLocalStoreError.invalidPayload(
                SyncEntityKey(entityType: .diaryEntry, entityID: record.id),
                reason: "local enum or LocalDay value is invalid",
            )
        }
        return DiaryEntryPayload(
            id: record.id,
            day: day,
            mealType: mealType,
            sortOrder: record.sortOrder,
            sourceType: sourceType,
            sourceID: record.sourceID,
            sourceVersionID: record.sourceVersionID,
            sourceName: record.sourceName,
            amount: record.amount,
            unitToken: record.unitToken,
            nutrition: Nutrition(
                calories: record.calories,
                protein: record.protein,
                fat: record.fat,
                carbs: record.carbs,
            ),
            createdAt: SyncTimestamp.canonical(record.createdAt),
            updatedAt: SyncTimestamp.canonical(record.updatedAt),
            deletedAt: SyncTimestamp.canonical(record.deletedAt),
        )
    }

    private func weeklyGoalPayload(from record: WeeklyGoalRecord) throws -> WeeklyGoalPayload {
        guard let effectiveFrom = LocalDay(rawValue: record.effectiveFromKey) else {
            throw SyncLocalStoreError.invalidPayload(
                SyncEntityKey(entityType: .weeklyGoal, entityID: record.id),
                reason: "local effectiveFrom is invalid",
            )
        }
        let days = try record.dailyGoals
            .sorted { $0.position < $1.position }
            .map { record -> WeeklyGoalPayload.Day in
                guard let weekday = LocalDay.Weekday(rawValue: record.weekdayRaw) else {
                    throw SyncLocalStoreError.invalidPayload(
                        SyncEntityKey(entityType: .weeklyGoal, entityID: record.weeklyGoalID),
                        reason: "local weekday is invalid",
                    )
                }
                return WeeklyGoalPayload.Day(
                    id: record.id,
                    weeklyGoalID: record.weeklyGoalID,
                    weekday: weekday,
                    position: record.position,
                    goal: DailyMacroGoal(
                        calories: record.calories,
                        protein: record.protein,
                        fat: record.fat,
                        carbs: record.carbs,
                    ),
                )
            }
        return WeeklyGoalPayload(
            id: record.id,
            effectiveFrom: effectiveFrom,
            days: days,
            createdAt: SyncTimestamp.canonical(record.createdAt),
        )
    }

    private func makeProductRecord(from payload: ProductPayload) -> ProductRecord {
        ProductRecord(
            id: payload.id,
            name: payload.name,
            barcode: payload.barcode,
            currentVersionID: payload.currentVersionID,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            deletedAt: payload.deletedAt,
        )
    }

    private func apply(_ payload: ProductPayload, to record: ProductRecord) {
        record.name = payload.name
        record.barcode = payload.barcode
        record.currentVersionID = payload.currentVersionID
        record.createdAt = payload.createdAt
        record.updatedAt = payload.updatedAt
        record.deletedAt = payload.deletedAt
    }

    private func makeProductVersionRecord(from payload: ProductVersionPayload) -> ProductVersionRecord {
        ProductVersionRecord(
            id: payload.id,
            productID: payload.productID,
            basedOnVersionID: payload.basedOnVersionID,
            versionNumber: payload.versionNumber,
            baseUnitRaw: payload.baseUnit.rawValue,
            baseAmount: payload.baseAmount,
            calories: payload.nutrition.calories,
            protein: payload.nutrition.protein,
            fat: payload.nutrition.fat,
            carbs: payload.nutrition.carbs,
            createdAt: payload.createdAt,
        )
    }

    private func makeRecipeRecord(from payload: RecipePayload) -> RecipeRecord {
        RecipeRecord(
            id: payload.id,
            name: payload.name,
            currentVersionID: payload.currentVersionID,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            deletedAt: payload.deletedAt,
        )
    }

    private func apply(_ payload: RecipePayload, to record: RecipeRecord) {
        record.name = payload.name
        record.currentVersionID = payload.currentVersionID
        record.createdAt = payload.createdAt
        record.updatedAt = payload.updatedAt
        record.deletedAt = payload.deletedAt
    }

    private func makeRecipeVersionRecord(from payload: RecipeVersionPayload) -> RecipeVersionRecord {
        RecipeVersionRecord(
            id: payload.id,
            recipeID: payload.recipeID,
            basedOnVersionID: payload.basedOnVersionID,
            versionNumber: payload.versionNumber,
            totalCalories: payload.totalNutrition.calories,
            totalProtein: payload.totalNutrition.protein,
            totalFat: payload.totalNutrition.fat,
            totalCarbs: payload.totalNutrition.carbs,
            cookedWeight: payload.cookedWeight,
            servingsCount: payload.servingsCount,
            createdAt: payload.createdAt,
        )
    }

    private func makeRecipeIngredientRecord(from payload: RecipeVersionPayload.Ingredient) -> RecipeIngredientRecord {
        RecipeIngredientRecord(
            id: payload.id,
            recipeVersionID: payload.recipeVersionID,
            position: payload.position,
            productID: payload.productID,
            productVersionID: payload.productVersionID,
            amount: payload.amount,
            unitToken: payload.unitToken,
            normalizedAmount: payload.normalizedAmount,
        )
    }

    private func makeDiaryEntryRecord(from payload: DiaryEntryPayload) -> DiaryEntryRecord {
        DiaryEntryRecord(
            id: payload.id,
            dayKey: payload.day.rawValue,
            mealTypeRaw: payload.mealType.rawValue,
            sortOrder: payload.sortOrder,
            sourceTypeRaw: payload.sourceType.rawValue,
            sourceID: payload.sourceID,
            sourceVersionID: payload.sourceVersionID,
            sourceName: payload.sourceName,
            amount: payload.amount,
            unitToken: payload.unitToken,
            calories: payload.nutrition.calories,
            protein: payload.nutrition.protein,
            fat: payload.nutrition.fat,
            carbs: payload.nutrition.carbs,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            deletedAt: payload.deletedAt,
        )
    }

    private func apply(_ payload: DiaryEntryPayload, to record: DiaryEntryRecord) {
        record.dayKey = payload.day.rawValue
        record.mealTypeRaw = payload.mealType.rawValue
        record.sortOrder = payload.sortOrder
        record.sourceTypeRaw = payload.sourceType.rawValue
        record.sourceID = payload.sourceID
        record.sourceVersionID = payload.sourceVersionID
        record.sourceName = payload.sourceName
        record.amount = payload.amount
        record.unitToken = payload.unitToken
        record.calories = payload.nutrition.calories
        record.protein = payload.nutrition.protein
        record.fat = payload.nutrition.fat
        record.carbs = payload.nutrition.carbs
        record.createdAt = payload.createdAt
        record.updatedAt = payload.updatedAt
        record.deletedAt = payload.deletedAt
    }

    private func makeWeeklyGoalRecord(from payload: WeeklyGoalPayload) -> WeeklyGoalRecord {
        WeeklyGoalRecord(
            id: payload.id,
            effectiveFromKey: payload.effectiveFrom.rawValue,
            createdAt: payload.createdAt,
        )
    }

    private func apply(
        _ payload: WeeklyGoalPayload,
        to record: WeeklyGoalRecord,
        in modelContext: ModelContext,
    ) throws {
        record.effectiveFromKey = payload.effectiveFrom.rawValue
        record.createdAt = payload.createdAt

        let currentDaysByID = Dictionary(uniqueKeysWithValues: record.dailyGoals.map { ($0.id, $0) })
        let incomingIDs = Set(payload.days.map(\.id))
        var updatedDays: [DailyMacroGoalRecord] = []

        for day in payload.days {
            if let current = currentDaysByID[day.id] {
                apply(day, to: current)
                current.weeklyGoal = record
                updatedDays.append(current)
            } else {
                if let existing = try dailyGoalRecord(id: day.id, in: modelContext), existing.weeklyGoalID != record.id {
                    throw SyncLocalStoreError.inconsistentIdentity(
                        SyncEntityKey(entityType: .weeklyGoal, entityID: payload.id),
                    )
                }
                let inserted = makeDailyGoalRecord(from: day)
                inserted.weeklyGoal = record
                modelContext.insert(inserted)
                updatedDays.append(inserted)
            }
        }
        for current in record.dailyGoals where !incomingIDs.contains(current.id) {
            modelContext.delete(current)
        }
        record.dailyGoals = updatedDays
    }

    private func makeDailyGoalRecord(from payload: WeeklyGoalPayload.Day) -> DailyMacroGoalRecord {
        DailyMacroGoalRecord(
            id: payload.id,
            weeklyGoalID: payload.weeklyGoalID,
            weekdayRaw: payload.weekday.rawValue,
            position: payload.position,
            calories: payload.goal.calories,
            protein: payload.goal.protein,
            fat: payload.goal.fat,
            carbs: payload.goal.carbs,
        )
    }

    private func apply(_ payload: WeeklyGoalPayload.Day, to record: DailyMacroGoalRecord) {
        record.weeklyGoalID = payload.weeklyGoalID
        record.weekdayRaw = payload.weekday.rawValue
        record.position = payload.position
        record.calories = payload.goal.calories
        record.protein = payload.goal.protein
        record.fat = payload.goal.fat
        record.carbs = payload.goal.carbs
    }

    private func diaryUnit(_ token: String, isAvailableFor version: RecipeVersionRecord) -> Bool {
        switch RecipeDiaryUnit(rawValue: token) {
        case .grams:
            return version.cookedWeight != nil
        case .serving:
            return version.servingsCount != nil
        case nil:
            return false
        }
    }
}

private enum MergeWinner {
    case local
    case remote
}
