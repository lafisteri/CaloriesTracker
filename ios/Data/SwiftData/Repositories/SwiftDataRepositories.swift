import Foundation
import SwiftData

@MainActor
final class SwiftDataProductRepository: ProductRepository {
    private let modelContext: ModelContext
    private let syncChangeNotifier: SyncChangeNotifier?

    init(
        modelContainer: ModelContainer,
        syncChangeNotifier: SyncChangeNotifier? = nil,
    ) {
        modelContext = ModelContext(modelContainer)
        self.syncChangeNotifier = syncChangeNotifier
    }

    func activeProducts(matching query: String) async throws -> [Product] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = FetchDescriptor<ProductRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\ProductRecord.name),
                SortDescriptor(\ProductRecord.id),
            ],
        )
        let records = try modelContext.fetch(descriptor)

        return records
            .map { $0.toDomain() }
            .filter { product in
                guard !query.isEmpty else {
                    return true
                }

                return product.name.localizedCaseInsensitiveContains(query)
                    || product.barcode?.localizedCaseInsensitiveContains(query) == true
            }
            .sorted {
                let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                return comparison == .orderedAscending
                    || (comparison == .orderedSame && $0.id.uuidString < $1.id.uuidString)
            }
    }

    func product(id: UUID, includingDeleted: Bool) async throws -> Product? {
        let descriptor = FetchDescriptor<ProductRecord>(predicate: #Predicate { $0.id == id })
        guard let product = try modelContext.fetch(descriptor).first?.toDomain() else {
            return nil
        }

        return includingDeleted || product.deletedAt == nil ? product : nil
    }

    func products(ids: Set<UUID>, includingDeleted: Bool) async throws -> [Product] {
        guard !ids.isEmpty else {
            return []
        }
        let productIDs = Array(ids)
        let predicate: Predicate<ProductRecord>
        if includingDeleted {
            predicate = #Predicate { productIDs.contains($0.id) }
        } else {
            predicate = #Predicate { productIDs.contains($0.id) && $0.deletedAt == nil }
        }
        let descriptor = FetchDescriptor<ProductRecord>(predicate: predicate)
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func product(withBarcode barcode: String) async throws -> Product? {
        var descriptor = FetchDescriptor<ProductRecord>(
            predicate: #Predicate { $0.barcode == barcode }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { $0.toDomain() }
    }

    func version(id: UUID) async throws -> ProductVersion? {
        let descriptor = FetchDescriptor<ProductVersionRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first.map { try $0.toDomain() }
    }

    func versions(ids: Set<UUID>) async throws -> [ProductVersion] {
        guard !ids.isEmpty else {
            return []
        }
        let versionIDs = Array(ids)
        let descriptor = FetchDescriptor<ProductVersionRecord>(
            predicate: #Predicate { versionIDs.contains($0.id) },
        )
        return try modelContext.fetch(descriptor).map { try $0.toDomain() }
    }

    func versions(for productID: UUID) async throws -> [ProductVersion] {
        let descriptor = FetchDescriptor<ProductVersionRecord>(
            predicate: #Predicate { $0.productID == productID }
        )
        return try modelContext
            .fetch(descriptor)
            .map { try $0.toDomain() }
    }

    func create(_ product: Product, initialVersion: ProductVersion) async throws {
        guard initialVersion.productID == product.id,
              initialVersion.id == product.currentVersionID,
              initialVersion.versionNumber == 1,
              initialVersion.basedOnVersionID == nil
        else {
            throw ProductRepositoryError.invalidInitialVersion
        }

        try await ensureUniqueBarcode(product.barcode, excludingProductID: nil)

        let productRecord = makeRecord(product)
        let versionRecord = makeRecord(initialVersion)
        versionRecord.product = productRecord

        do {
            modelContext.insert(productRecord)
            modelContext.insert(versionRecord)
            try SyncOutboxStore.markChanged(type: .product, id: product.id, in: modelContext)
            try SyncOutboxStore.markChanged(type: .productVersion, id: initialVersion.id, in: modelContext)
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func saveLogicalMetadata(_ product: Product) async throws {
        guard let record = try productRecord(id: product.id) else {
            throw ProductRepositoryError.productNotFound
        }
        guard record.currentVersionID == product.currentVersionID else {
            throw ProductRepositoryError.invalidCurrentVersion
        }
        try await ensureUniqueBarcode(product.barcode, excludingProductID: product.id)

        record.name = product.name
        record.barcode = product.barcode
        record.updatedAt = product.updatedAt

        do {
            try SyncOutboxStore.markChanged(type: .product, id: product.id, in: modelContext)
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func append(_ version: ProductVersion, settingCurrentVersionOf product: Product) async throws {
        guard version.productID == product.id,
              product.currentVersionID == version.id,
              version.basedOnVersionID != nil,
              version.versionNumber > 1
        else {
            throw ProductRepositoryError.invalidVersionAppend
        }

        guard let productRecord = try productRecord(id: product.id) else {
            throw ProductRepositoryError.productNotFound
        }
        guard productRecord.currentVersionID == version.basedOnVersionID else {
            throw ProductRepositoryError.invalidCurrentVersion
        }
        guard let basedOnVersionID = version.basedOnVersionID,
              basedOnVersionID != version.id,
              let basedOnRecord = try productVersionRecord(id: basedOnVersionID),
              basedOnRecord.productID == version.productID,
              basedOnRecord.versionNumber > 0
        else {
            throw ProductRepositoryError.invalidVersionAppend
        }
        let (expectedVersionNumber, didOverflow) = basedOnRecord.versionNumber.addingReportingOverflow(1)
        guard !didOverflow, version.versionNumber == expectedVersionNumber else {
            throw ProductRepositoryError.invalidVersionAppend
        }
        try await ensureUniqueBarcode(product.barcode, excludingProductID: product.id)

        let versionRecord = makeRecord(version)
        versionRecord.product = productRecord

        productRecord.name = product.name
        productRecord.barcode = product.barcode
        productRecord.currentVersionID = product.currentVersionID
        productRecord.updatedAt = product.updatedAt
        productRecord.deletedAt = product.deletedAt

        do {
            modelContext.insert(versionRecord)
            try SyncOutboxStore.markChanged(type: .product, id: product.id, in: modelContext)
            try SyncOutboxStore.markChanged(type: .productVersion, id: version.id, in: modelContext)
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func softDeleteProduct(id: UUID, at date: Date) async throws {
        guard let record = try productRecord(id: id) else {
            throw ProductRepositoryError.productNotFound
        }

        record.deletedAt = date
        record.updatedAt = date

        do {
            try SyncOutboxStore.markChanged(type: .product, id: id, in: modelContext)
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func commitSyncableMutation() throws {
        try modelContext.save()
        syncChangeNotifier?.localSyncableMutationCommitted()
    }

    private func productRecord(id: UUID) throws -> ProductRecord? {
        let descriptor = FetchDescriptor<ProductRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    private func productVersionRecord(id: UUID) throws -> ProductVersionRecord? {
        var descriptor = FetchDescriptor<ProductVersionRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func ensureUniqueBarcode(_ barcode: String?, excludingProductID: UUID?) async throws {
        guard let barcode,
              let existing = try await product(withBarcode: barcode),
              existing.id != excludingProductID
        else {
            return
        }

        throw ProductRepositoryError.barcodeAlreadyInUse
    }

    private func makeRecord(_ product: Product) -> ProductRecord {
        ProductRecord(
            id: product.id,
            name: product.name,
            barcode: product.barcode,
            currentVersionID: product.currentVersionID,
            createdAt: product.createdAt,
            updatedAt: product.updatedAt,
            deletedAt: product.deletedAt,
        )
    }

    private func makeRecord(_ version: ProductVersion) -> ProductVersionRecord {
        ProductVersionRecord(
            id: version.id,
            productID: version.productID,
            basedOnVersionID: version.basedOnVersionID,
            versionNumber: version.versionNumber,
            baseUnitRaw: version.baseUnit.rawValue,
            baseAmount: version.baseAmount,
            calories: version.nutrition.calories,
            protein: version.nutrition.protein,
            fat: version.nutrition.fat,
            carbs: version.nutrition.carbs,
            createdAt: version.createdAt,
        )
    }

}

private enum ProductRepositoryError: LocalizedError {
    case productNotFound
    case invalidInitialVersion
    case invalidVersionAppend
    case invalidCurrentVersion
    case barcodeAlreadyInUse

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            "Продукт не найден."
        case .invalidInitialVersion:
            "Начальная версия продукта некорректна."
        case .invalidVersionAppend:
            "Новая версия продукта некорректна."
        case .invalidCurrentVersion:
            "Текущая версия продукта изменилась."
        case .barcodeAlreadyInUse:
            "Этот штрихкод уже используется другим продуктом."
        }
    }
}

@MainActor
final class SwiftDataRecipeRepository: RecipeRepository {
    private let modelContext: ModelContext
    private let syncChangeNotifier: SyncChangeNotifier?

    init(
        modelContainer: ModelContainer,
        syncChangeNotifier: SyncChangeNotifier? = nil,
    ) {
        modelContext = ModelContext(modelContainer)
        self.syncChangeNotifier = syncChangeNotifier
    }

    func activeRecipes(matching query: String) async throws -> [Recipe] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = FetchDescriptor<RecipeRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\RecipeRecord.name),
                SortDescriptor(\RecipeRecord.id),
            ],
        )

        return try modelContext
            .fetch(descriptor)
            .map { $0.toDomain() }
            .filter { recipe in
                return query.isEmpty || recipe.name.localizedCaseInsensitiveContains(query)
            }
            .sorted {
                let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                return comparison == .orderedAscending
                    || (comparison == .orderedSame && $0.id.uuidString < $1.id.uuidString)
            }
    }

    func recipe(id: UUID, includingDeleted: Bool) async throws -> Recipe? {
        let descriptor = FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
        guard let recipe = try modelContext.fetch(descriptor).first?.toDomain() else {
            return nil
        }
        return includingDeleted || recipe.deletedAt == nil ? recipe : nil
    }

    func version(id: UUID) async throws -> RecipeVersion? {
        let descriptor = FetchDescriptor<RecipeVersionRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first?.toDomain()
    }

    func versions(ids: Set<UUID>) async throws -> [RecipeVersion] {
        guard !ids.isEmpty else {
            return []
        }
        let versionIDs = Array(ids)
        let descriptor = FetchDescriptor<RecipeVersionRecord>(
            predicate: #Predicate { versionIDs.contains($0.id) },
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    func versions(for recipeID: UUID) async throws -> [RecipeVersion] {
        let descriptor = FetchDescriptor<RecipeVersionRecord>(
            predicate: #Predicate { $0.recipeID == recipeID }
        )
        return try modelContext
            .fetch(descriptor)
            .map { $0.toDomain() }
    }

    func create(_ recipe: Recipe, initialVersion: RecipeVersion) async throws {
        guard initialVersion.recipeID == recipe.id,
              initialVersion.id == recipe.currentVersionID,
              initialVersion.versionNumber == 1,
              initialVersion.basedOnVersionID == nil,
              initialVersion.ingredients.allSatisfy({ $0.recipeVersionID == initialVersion.id })
        else {
            throw RecipeRepositoryError.invalidInitialVersion
        }

        let recipeRecord = makeRecord(recipe)
        let versionRecord = makeRecord(initialVersion)
        versionRecord.recipe = recipeRecord
        versionRecord.ingredients = initialVersion.ingredients.map(makeRecord)
        for ingredient in versionRecord.ingredients {
            ingredient.recipeVersion = versionRecord
        }

        do {
            modelContext.insert(recipeRecord)
            modelContext.insert(versionRecord)
            for ingredient in versionRecord.ingredients {
                modelContext.insert(ingredient)
            }
            try SyncOutboxStore.markChanged(type: .recipe, id: recipe.id, in: modelContext)
            try SyncOutboxStore.markChanged(type: .recipeVersion, id: initialVersion.id, in: modelContext)
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func saveLogicalMetadata(_ recipe: Recipe) async throws {
        guard let record = try recipeRecord(id: recipe.id) else {
            throw RecipeRepositoryError.recipeNotFound
        }
        guard record.currentVersionID == recipe.currentVersionID else {
            throw RecipeRepositoryError.invalidCurrentVersion
        }

        record.name = recipe.name
        record.updatedAt = recipe.updatedAt
        record.deletedAt = recipe.deletedAt

        do {
            try SyncOutboxStore.markChanged(type: .recipe, id: recipe.id, in: modelContext)
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func append(_ version: RecipeVersion, settingCurrentVersionOf recipe: Recipe) async throws {
        guard version.recipeID == recipe.id,
              recipe.currentVersionID == version.id,
              version.basedOnVersionID != nil,
              version.versionNumber > 1,
              version.ingredients.allSatisfy({ $0.recipeVersionID == version.id })
        else {
            throw RecipeRepositoryError.invalidVersionAppend
        }
        guard let recipeRecord = try recipeRecord(id: recipe.id) else {
            throw RecipeRepositoryError.recipeNotFound
        }
        guard recipeRecord.currentVersionID == version.basedOnVersionID else {
            throw RecipeRepositoryError.invalidCurrentVersion
        }
        guard let basedOnVersionID = version.basedOnVersionID,
              basedOnVersionID != version.id,
              let basedOnRecord = try recipeVersionRecord(id: basedOnVersionID),
              basedOnRecord.recipeID == version.recipeID,
              basedOnRecord.versionNumber > 0
        else {
            throw RecipeRepositoryError.invalidVersionAppend
        }
        let (expectedVersionNumber, didOverflow) = basedOnRecord.versionNumber.addingReportingOverflow(1)
        guard !didOverflow, version.versionNumber == expectedVersionNumber else {
            throw RecipeRepositoryError.invalidVersionAppend
        }

        let versionRecord = makeRecord(version)
        versionRecord.recipe = recipeRecord
        versionRecord.ingredients = version.ingredients.map(makeRecord)
        for ingredient in versionRecord.ingredients {
            ingredient.recipeVersion = versionRecord
        }

        recipeRecord.name = recipe.name
        recipeRecord.currentVersionID = recipe.currentVersionID
        recipeRecord.updatedAt = recipe.updatedAt
        recipeRecord.deletedAt = recipe.deletedAt

        do {
            modelContext.insert(versionRecord)
            for ingredient in versionRecord.ingredients {
                modelContext.insert(ingredient)
            }
            try SyncOutboxStore.markChanged(type: .recipe, id: recipe.id, in: modelContext)
            try SyncOutboxStore.markChanged(type: .recipeVersion, id: version.id, in: modelContext)
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func softDeleteRecipe(id: UUID, at date: Date) async throws {
        guard let record = try recipeRecord(id: id) else {
            throw RecipeRepositoryError.recipeNotFound
        }
        record.deletedAt = date
        record.updatedAt = date

        do {
            try SyncOutboxStore.markChanged(type: .recipe, id: id, in: modelContext)
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func commitSyncableMutation() throws {
        try modelContext.save()
        syncChangeNotifier?.localSyncableMutationCommitted()
    }

    private func recipeRecord(id: UUID) throws -> RecipeRecord? {
        let descriptor = FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    private func recipeVersionRecord(id: UUID) throws -> RecipeVersionRecord? {
        var descriptor = FetchDescriptor<RecipeVersionRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func makeRecord(_ recipe: Recipe) -> RecipeRecord {
        RecipeRecord(
            id: recipe.id,
            name: recipe.name,
            currentVersionID: recipe.currentVersionID,
            createdAt: recipe.createdAt,
            updatedAt: recipe.updatedAt,
            deletedAt: recipe.deletedAt,
        )
    }

    private func makeRecord(_ version: RecipeVersion) -> RecipeVersionRecord {
        RecipeVersionRecord(
            id: version.id,
            recipeID: version.recipeID,
            basedOnVersionID: version.basedOnVersionID,
            versionNumber: version.versionNumber,
            totalCalories: version.totalNutrition.calories,
            totalProtein: version.totalNutrition.protein,
            totalFat: version.totalNutrition.fat,
            totalCarbs: version.totalNutrition.carbs,
            cookedWeight: version.cookedWeight,
            servingsCount: version.servingsCount,
            createdAt: version.createdAt,
        )
    }

    private func makeRecord(_ ingredient: RecipeIngredient) -> RecipeIngredientRecord {
        RecipeIngredientRecord(
            id: ingredient.id,
            recipeVersionID: ingredient.recipeVersionID,
            position: ingredient.position,
            productID: ingredient.productID,
            productVersionID: ingredient.productVersionID,
            amount: ingredient.amount,
            unitToken: ingredient.unitToken,
            normalizedAmount: ingredient.normalizedAmount,
        )
    }
}

private enum RecipeRepositoryError: LocalizedError {
    case recipeNotFound
    case invalidInitialVersion
    case invalidVersionAppend
    case invalidCurrentVersion

    var errorDescription: String? {
        switch self {
        case .recipeNotFound:
            "Рецепт не найден."
        case .invalidInitialVersion:
            "Начальная версия рецепта некорректна."
        case .invalidVersionAppend:
            "Новая версия рецепта некорректна."
        case .invalidCurrentVersion:
            "Текущая версия рецепта изменилась."
        }
    }
}

@MainActor
final class SwiftDataDiaryRepository: DiaryRepository {
    private let modelContext: ModelContext
    private let syncChangeNotifier: SyncChangeNotifier?

    init(
        modelContainer: ModelContainer,
        syncChangeNotifier: SyncChangeNotifier? = nil,
    ) {
        modelContext = ModelContext(modelContainer)
        self.syncChangeNotifier = syncChangeNotifier
    }

    func entry(id: UUID, includingDeleted: Bool) async throws -> DiaryEntry? {
        let predicate: Predicate<DiaryEntryRecord>
        if includingDeleted {
            predicate = #Predicate { $0.id == id }
        } else {
            predicate = #Predicate { $0.id == id && $0.deletedAt == nil }
        }
        var descriptor = FetchDescriptor<DiaryEntryRecord>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let entry = try modelContext.fetch(descriptor).first.map({ try $0.toDomain() }) else {
            return nil
        }

        return entry
    }

    func entries(on day: LocalDay) async throws -> [DiaryEntry] {
        let dayKey = day.rawValue
        let descriptor = FetchDescriptor<DiaryEntryRecord>(
            predicate: #Predicate { $0.dayKey == dayKey && $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\DiaryEntryRecord.mealTypeRaw),
                SortDescriptor(\DiaryEntryRecord.sortOrder),
            ],
        )

        return try modelContext
            .fetch(descriptor)
            .map { try $0.toDomain() }
            .sorted { lhs, rhs in
                if lhs.mealType.rawValue != rhs.mealType.rawValue {
                    return lhs.mealType.rawValue < rhs.mealType.rawValue
                }
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func entries(in days: [LocalDay]) async throws -> [DiaryEntry] {
        let dayKeys = Array(Set(days.map(\.rawValue)))
        guard !dayKeys.isEmpty else {
            return []
        }

        let descriptor = FetchDescriptor<DiaryEntryRecord>(
            predicate: #Predicate { $0.deletedAt == nil && dayKeys.contains($0.dayKey) },
            sortBy: [
                SortDescriptor(\DiaryEntryRecord.dayKey),
                SortDescriptor(\DiaryEntryRecord.mealTypeRaw),
                SortDescriptor(\DiaryEntryRecord.sortOrder),
            ],
        )

        return try modelContext
            .fetch(descriptor)
            .map { try $0.toDomain() }
            .sorted { lhs, rhs in
                if lhs.day != rhs.day {
                    return lhs.day < rhs.day
                }
                if lhs.mealType.rawValue != rhs.mealType.rawValue {
                    return lhs.mealType.rawValue < rhs.mealType.rawValue
                }
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func activeEntries(for sources: [FoodSourceReference]) async throws -> [DiaryEntry] {
        let sourceSet = Set(sources)
        guard !sourceSet.isEmpty else {
            return []
        }
        let sourceIDs = Array(Set(sources.map(\.sourceID)))
        let descriptor = FetchDescriptor<DiaryEntryRecord>(
            predicate: #Predicate { $0.deletedAt == nil && sourceIDs.contains($0.sourceID) },
        )

        return try modelContext
            .fetch(descriptor)
            .map { try $0.toDomain() }
            .filter { entry in
                sourceSet.contains(
                    FoodSourceReference(sourceType: entry.sourceType, sourceID: entry.sourceID),
                )
            }
    }

    func latestActiveUsages(for sources: [FoodSourceReference]) async throws -> [LatestDiaryUsage] {
        let sourceSet = Set(sources)
        guard !sourceSet.isEmpty else {
            return []
        }

        var latestBySource: [FoodSourceReference: DiaryEntryRecord] = [:]
        for sourceType in [SourceType.product, .recipe] {
            let sourceIDs = Array(
                Set(sourceSet.lazy
                    .filter { $0.sourceType == sourceType }
                    .map(\.sourceID)),
            )
            guard !sourceIDs.isEmpty else {
                continue
            }

            let sourceTypeRaw = sourceType.rawValue
            let descriptor = FetchDescriptor<DiaryEntryRecord>(
                predicate: #Predicate {
                    $0.deletedAt == nil
                        && $0.sourceTypeRaw == sourceTypeRaw
                        && sourceIDs.contains($0.sourceID)
                },
            )

            for record in try modelContext.fetch(descriptor) {
                let source = FoodSourceReference(sourceType: sourceType, sourceID: record.sourceID)
                guard sourceSet.contains(source) else {
                    continue
                }
                if let current = latestBySource[source], !isNewerUsage(record, than: current) {
                    continue
                }
                latestBySource[source] = record
            }
        }

        return latestBySource
            .map { source, record in
                LatestDiaryUsage(source: source, amount: record.amount, unitToken: record.unitToken)
            }
            .sorted { lhs, rhs in
                if lhs.source.sourceType.rawValue != rhs.source.sourceType.rawValue {
                    return lhs.source.sourceType.rawValue < rhs.source.sourceType.rawValue
                }
                return lhs.source.sourceID.uuidString < rhs.source.sourceID.uuidString
            }
    }

    private func isNewerUsage(_ candidate: DiaryEntryRecord, than current: DiaryEntryRecord) -> Bool {
        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }
        if candidate.createdAt != current.createdAt {
            return candidate.createdAt > current.createdAt
        }
        return candidate.id.uuidString > current.id.uuidString
    }

    func create(_ entry: DiaryEntry) async throws {
        guard entry.deletedAt == nil else {
            throw DiaryRepositoryError.invalidCreate
        }

        let record = makeRecord(entry)

        do {
            modelContext.insert(record)
            try SyncOutboxStore.markChanged(type: .diaryEntry, id: entry.id, in: modelContext)
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func save(_ entry: DiaryEntry) async throws {
        guard let record = try entryRecord(id: entry.id) else {
            throw DiaryRepositoryError.entryNotFound
        }
        guard matchesImmutableFields(record, entry),
              record.mealTypeRaw == entry.mealType.rawValue,
              record.sortOrder == entry.sortOrder,
              record.deletedAt == nil,
              entry.deletedAt == nil
        else {
            throw DiaryRepositoryError.invalidAmountUpdate
        }

        record.amount = entry.amount
        record.unitToken = entry.unitToken
        record.calories = entry.nutrition.calories
        record.protein = entry.nutrition.protein
        record.fat = entry.nutrition.fat
        record.carbs = entry.nutrition.carbs
        record.updatedAt = entry.updatedAt

        do {
            try SyncOutboxStore.markChanged(type: .diaryEntry, id: entry.id, in: modelContext)
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func rebaseSourceSnapshot(_ entry: DiaryEntry) async throws {
        guard let record = try entryRecord(id: entry.id) else {
            throw DiaryRepositoryError.entryNotFound
        }
        guard matchesRebaseIdentityFields(record, entry),
              record.deletedAt == nil,
              entry.deletedAt == nil
        else {
            throw DiaryRepositoryError.invalidSourceRebase
        }

        record.sourceVersionID = entry.sourceVersionID
        record.sourceName = entry.sourceName
        record.amount = entry.amount
        record.unitToken = entry.unitToken
        record.calories = entry.nutrition.calories
        record.protein = entry.nutrition.protein
        record.fat = entry.nutrition.fat
        record.carbs = entry.nutrition.carbs
        record.updatedAt = entry.updatedAt

        do {
            try SyncOutboxStore.markChanged(type: .diaryEntry, id: entry.id, in: modelContext)
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func save(_ entries: [DiaryEntry]) async throws {
        guard !entries.isEmpty else {
            return
        }
        guard Set(entries.map(\.id)).count == entries.count else {
            throw DiaryRepositoryError.duplicateEntry
        }

        var updates: [(DiaryEntryRecord, DiaryEntry)] = []
        for entry in entries {
            guard let record = try entryRecord(id: entry.id),
                  matchesImmutableFields(record, entry),
                  record.deletedAt == nil,
                  entry.deletedAt == nil
            else {
                throw DiaryRepositoryError.invalidOrderUpdate
            }
            guard record.mealTypeRaw != entry.mealType.rawValue || record.sortOrder != entry.sortOrder else {
                continue
            }
            updates.append((record, entry))
        }

        guard !updates.isEmpty else {
            return
        }

        for (record, entry) in updates {
            record.mealTypeRaw = entry.mealType.rawValue
            record.sortOrder = entry.sortOrder
            record.updatedAt = entry.updatedAt
        }

        do {
            for (_, entry) in updates {
                try SyncOutboxStore.markChanged(type: .diaryEntry, id: entry.id, in: modelContext)
            }
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func softDeleteEntry(id: UUID, at date: Date) async throws {
        guard let record = try entryRecord(id: id) else {
            throw DiaryRepositoryError.entryNotFound
        }

        record.deletedAt = date
        record.updatedAt = date

        do {
            try SyncOutboxStore.markChanged(type: .diaryEntry, id: id, in: modelContext)
            try commitSyncableMutation()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func commitSyncableMutation() throws {
        try modelContext.save()
        syncChangeNotifier?.localSyncableMutationCommitted()
    }

    private func entryRecord(id: UUID) throws -> DiaryEntryRecord? {
        var descriptor = FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func matchesImmutableFields(_ record: DiaryEntryRecord, _ entry: DiaryEntry) -> Bool {
        record.dayKey == entry.day.rawValue
            && record.sourceTypeRaw == entry.sourceType.rawValue
            && record.sourceID == entry.sourceID
            && record.sourceVersionID == entry.sourceVersionID
            && record.sourceName == entry.sourceName
            && record.createdAt == entry.createdAt
    }

    private func matchesRebaseIdentityFields(_ record: DiaryEntryRecord, _ entry: DiaryEntry) -> Bool {
        record.dayKey == entry.day.rawValue
            && record.mealTypeRaw == entry.mealType.rawValue
            && record.sortOrder == entry.sortOrder
            && record.sourceTypeRaw == entry.sourceType.rawValue
            && record.sourceID == entry.sourceID
            && record.createdAt == entry.createdAt
    }

    private func makeRecord(_ entry: DiaryEntry) -> DiaryEntryRecord {
        DiaryEntryRecord(
            id: entry.id,
            dayKey: entry.day.rawValue,
            mealTypeRaw: entry.mealType.rawValue,
            sortOrder: entry.sortOrder,
            sourceTypeRaw: entry.sourceType.rawValue,
            sourceID: entry.sourceID,
            sourceVersionID: entry.sourceVersionID,
            sourceName: entry.sourceName,
            amount: entry.amount,
            unitToken: entry.unitToken,
            calories: entry.nutrition.calories,
            protein: entry.nutrition.protein,
            fat: entry.nutrition.fat,
            carbs: entry.nutrition.carbs,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            deletedAt: entry.deletedAt,
        )
    }
}

private enum DiaryRepositoryError: LocalizedError {
    case entryNotFound
    case invalidCreate
    case invalidAmountUpdate
    case invalidSourceRebase
    case invalidOrderUpdate
    case duplicateEntry

    var errorDescription: String? {
        switch self {
        case .entryNotFound:
            "Запись дневника не найдена."
        case .invalidCreate:
            "Не удалось создать запись дневника."
        case .invalidAmountUpdate:
            "Можно изменить только количество и единицу записи."
        case .invalidSourceRebase:
            "Не удалось обновить источник записи."
        case .invalidOrderUpdate:
            "Не удалось изменить порядок записи."
        case .duplicateEntry:
            "Порядок содержит повторяющуюся запись."
        }
    }
}

@MainActor
final class SwiftDataGoalRepository: GoalRepository {
    private let modelContext: ModelContext
    private let syncChangeNotifier: SyncChangeNotifier?

    init(
        modelContainer: ModelContainer,
        syncChangeNotifier: SyncChangeNotifier? = nil,
    ) {
        modelContext = ModelContext(modelContainer)
        self.syncChangeNotifier = syncChangeNotifier
    }

    func goal(effectiveOn day: LocalDay) async throws -> WeeklyGoal? {
        let effectiveFromKey = day.rawValue
        var descriptor = FetchDescriptor<WeeklyGoalRecord>(
            predicate: #Predicate { $0.effectiveFromKey <= effectiveFromKey },
            sortBy: [SortDescriptor(\WeeklyGoalRecord.effectiveFromKey, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { try $0.toDomain() }
    }

    func goals(effectiveOn days: [LocalDay]) async throws -> [LocalDay: WeeklyGoal] {
        let goals = try allGoals().sorted { $0.effectiveFrom < $1.effectiveFrom }
        var result: [LocalDay: WeeklyGoal] = [:]

        for day in Set(days) {
            result[day] = goals.last { $0.effectiveFrom <= day }
        }

        return result
    }

    func save(draft: WeeklyGoalDraft, at timestamp: Date) async throws -> WeeklyGoal {
        try validate(draft)

        let effectiveFromKey = draft.effectiveFrom.rawValue
        var descriptor = FetchDescriptor<WeeklyGoalRecord>(
            predicate: #Predicate { $0.effectiveFromKey == effectiveFromKey },
        )
        descriptor.fetchLimit = 1

        do {
            if let goalRecord = try modelContext.fetch(descriptor).first {
                try apply(draft, to: goalRecord)
                goalRecord.updatedAt = timestamp
                try SyncOutboxStore.markChanged(type: .weeklyGoal, id: goalRecord.id, in: modelContext)
                try commitSyncableMutation()
                return try goalRecord.toDomain()
            }

            let goalID = WeeklyGoalIdentity.id(for: draft.effectiveFrom)
            let goalRecord = WeeklyGoalRecord(
                id: goalID,
                effectiveFromKey: effectiveFromKey,
                createdAt: timestamp,
                updatedAt: timestamp,
            )
            let dailyGoalRecords = try LocalDay.Weekday.allCases.enumerated().map { position, weekday in
                guard let dailyGoal = draft.dailyGoals[weekday] else {
                    throw GoalRepositoryError.invalidGoal
                }
                return DailyMacroGoalRecord(
                    id: UUID(),
                    weeklyGoalID: goalID,
                    weekdayRaw: weekday.rawValue,
                    position: position,
                    calories: dailyGoal.calories,
                    protein: dailyGoal.protein,
                    fat: dailyGoal.fat,
                    carbs: dailyGoal.carbs,
                )
            }
            goalRecord.dailyGoals = dailyGoalRecords
            for dailyGoalRecord in dailyGoalRecords {
                dailyGoalRecord.weeklyGoal = goalRecord
            }

            modelContext.insert(goalRecord)
            for dailyGoalRecord in dailyGoalRecords {
                modelContext.insert(dailyGoalRecord)
            }
            try SyncOutboxStore.markChanged(type: .weeklyGoal, id: goalID, in: modelContext)
            try commitSyncableMutation()
            return try goalRecord.toDomain()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func commitSyncableMutation() throws {
        try modelContext.save()
        syncChangeNotifier?.localSyncableMutationCommitted()
    }

    private func allGoals() throws -> [WeeklyGoal] {
        try modelContext.fetch(FetchDescriptor<WeeklyGoalRecord>()).map { try $0.toDomain() }
    }

    private func validate(_ draft: WeeklyGoalDraft) throws {
        let weekdays = Set(LocalDay.Weekday.allCases)
        guard Set(draft.dailyGoals.keys) == weekdays,
              draft.dailyGoals.values.allSatisfy(\.isValid)
        else {
            throw GoalRepositoryError.invalidGoal
        }
    }

    private func apply(_ draft: WeeklyGoalDraft, to record: WeeklyGoalRecord) throws {
        var dailyGoalsByWeekday: [LocalDay.Weekday: DailyMacroGoalRecord] = [:]
        for dailyGoalRecord in record.dailyGoals {
            guard let weekday = LocalDay.Weekday(rawValue: dailyGoalRecord.weekdayRaw),
                  dailyGoalsByWeekday[weekday] == nil
            else {
                throw GoalRepositoryError.invalidGoal
            }
            dailyGoalsByWeekday[weekday] = dailyGoalRecord
        }

        guard Set(dailyGoalsByWeekday.keys) == Set(LocalDay.Weekday.allCases) else {
            throw GoalRepositoryError.invalidGoal
        }

        for (position, weekday) in LocalDay.Weekday.allCases.enumerated() {
            guard let draftGoal = draft.dailyGoals[weekday],
                  let dailyGoalRecord = dailyGoalsByWeekday[weekday]
            else {
                throw GoalRepositoryError.invalidGoal
            }

            dailyGoalRecord.weeklyGoalID = record.id
            dailyGoalRecord.weekdayRaw = weekday.rawValue
            dailyGoalRecord.position = position
            dailyGoalRecord.calories = draftGoal.calories
            dailyGoalRecord.protein = draftGoal.protein
            dailyGoalRecord.fat = draftGoal.fat
            dailyGoalRecord.carbs = draftGoal.carbs
        }
    }
}

enum GoalRepositoryError: LocalizedError {
    case invalidGoal

    var errorDescription: String? {
        switch self {
        case .invalidGoal:
            "Цель недели должна содержать семь корректных дней."
        }
    }
}
