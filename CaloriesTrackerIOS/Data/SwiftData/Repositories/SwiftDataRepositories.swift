import Foundation
import SwiftData

@MainActor
final class SwiftDataProductRepository: ProductRepository {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func activeProducts(matching query: String) async throws -> [Product] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let records = try modelContext.fetch(FetchDescriptor<ProductRecord>())

        return records
            .map { $0.toDomain() }
            .filter { product in
                guard product.deletedAt == nil else {
                    return false
                }

                guard !query.isEmpty else {
                    return true
                }

                return product.name.localizedCaseInsensitiveContains(query)
                    || product.barcode?.localizedCaseInsensitiveContains(query) == true
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func product(id: UUID, includingDeleted: Bool) async throws -> Product? {
        let descriptor = FetchDescriptor<ProductRecord>(predicate: #Predicate { $0.id == id })
        guard let product = try modelContext.fetch(descriptor).first?.toDomain() else {
            return nil
        }

        return includingDeleted || product.deletedAt == nil ? product : nil
    }

    func product(withBarcode barcode: String) async throws -> Product? {
        try modelContext
            .fetch(FetchDescriptor<ProductRecord>())
            .map { $0.toDomain() }
            .first { $0.barcode == barcode }
    }

    func version(id: UUID) async throws -> ProductVersion? {
        let descriptor = FetchDescriptor<ProductVersionRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first.map { try $0.toDomain() }
    }

    func versions(for productID: UUID) async throws -> [ProductVersion] {
        try modelContext
            .fetch(FetchDescriptor<ProductVersionRecord>())
            .filter { $0.productID == productID }
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
        versionRecord.servingUnits = initialVersion.servingUnits.map(makeRecord)

        do {
            modelContext.insert(productRecord)
            modelContext.insert(versionRecord)
            for servingUnit in versionRecord.servingUnits {
                modelContext.insert(servingUnit)
            }
            try modelContext.save()
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
            try modelContext.save()
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
        try await ensureUniqueBarcode(product.barcode, excludingProductID: product.id)

        let versionRecord = makeRecord(version)
        versionRecord.product = productRecord
        versionRecord.servingUnits = version.servingUnits.map(makeRecord)

        productRecord.name = product.name
        productRecord.barcode = product.barcode
        productRecord.currentVersionID = product.currentVersionID
        productRecord.updatedAt = product.updatedAt
        productRecord.deletedAt = product.deletedAt

        do {
            modelContext.insert(versionRecord)
            for servingUnit in versionRecord.servingUnits {
                modelContext.insert(servingUnit)
            }
            try modelContext.save()
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
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func productRecord(id: UUID) throws -> ProductRecord? {
        let descriptor = FetchDescriptor<ProductRecord>(predicate: #Predicate { $0.id == id })
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

    private func makeRecord(_ servingUnit: ServingUnit) -> ServingUnitRecord {
        ServingUnitRecord(
            id: servingUnit.id,
            productVersionID: servingUnit.productVersionID,
            position: servingUnit.position,
            name: servingUnit.name,
            conversionAmount: servingUnit.conversionAmount,
            conversionUnitRaw: servingUnit.conversionUnit.rawValue,
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

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func activeRecipes(matching query: String) async throws -> [Recipe] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try modelContext
            .fetch(FetchDescriptor<RecipeRecord>())
            .map { $0.toDomain() }
            .filter { recipe in
                guard recipe.deletedAt == nil else {
                    return false
                }
                return query.isEmpty || recipe.name.localizedCaseInsensitiveContains(query)
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
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

    func versions(for recipeID: UUID) async throws -> [RecipeVersion] {
        try modelContext
            .fetch(FetchDescriptor<RecipeVersionRecord>())
            .filter { $0.recipeID == recipeID }
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
            try modelContext.save()
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
            try modelContext.save()
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
            try modelContext.save()
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
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func recipeRecord(id: UUID) throws -> RecipeRecord? {
        let descriptor = FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
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

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func entry(id: UUID, includingDeleted: Bool) async throws -> DiaryEntry? {
        let descriptor = FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.id == id })
        guard let entry = try modelContext.fetch(descriptor).first.map({ try $0.toDomain() }) else {
            return nil
        }

        return includingDeleted || entry.deletedAt == nil ? entry : nil
    }

    func entries(on day: LocalDay) async throws -> [DiaryEntry] {
        let dayKey = day.rawValue
        let descriptor = FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.dayKey == dayKey })

        return try modelContext
            .fetch(descriptor)
            .map { try $0.toDomain() }
            .filter { $0.deletedAt == nil }
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
        let dayKeys = Set(days.map(\.rawValue))
        guard !dayKeys.isEmpty else {
            return []
        }

        return try modelContext
            .fetch(FetchDescriptor<DiaryEntryRecord>())
            .map { try $0.toDomain() }
            .filter { $0.deletedAt == nil && dayKeys.contains($0.day.rawValue) }
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

    func create(_ entry: DiaryEntry) async throws {
        guard entry.deletedAt == nil else {
            throw DiaryRepositoryError.invalidCreate
        }

        let record = makeRecord(entry)

        do {
            modelContext.insert(record)
            try modelContext.save()
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
            try modelContext.save()
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
            updates.append((record, entry))
        }

        for (record, entry) in updates {
            record.mealTypeRaw = entry.mealType.rawValue
            record.sortOrder = entry.sortOrder
            record.updatedAt = entry.updatedAt
        }

        do {
            try modelContext.save()
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
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func entryRecord(id: UUID) throws -> DiaryEntryRecord? {
        let descriptor = FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.id == id })
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

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func weeklyGoal(id: UUID) async throws -> WeeklyGoal? {
        let descriptor = FetchDescriptor<WeeklyGoalRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first.map { try $0.toDomain() }
    }

    func latestGoal() async throws -> WeeklyGoal? {
        try allGoals().max { $0.effectiveFrom < $1.effectiveFrom }
    }

    func goal(effectiveOn day: LocalDay) async throws -> WeeklyGoal? {
        try allGoals()
            .filter { $0.effectiveFrom <= day }
            .max { $0.effectiveFrom < $1.effectiveFrom }
    }

    func goals(effectiveOn days: [LocalDay]) async throws -> [LocalDay: WeeklyGoal] {
        let goals = try allGoals().sorted { $0.effectiveFrom < $1.effectiveFrom }
        var result: [LocalDay: WeeklyGoal] = [:]

        for day in Set(days) {
            result[day] = goals.last { $0.effectiveFrom <= day }
        }

        return result
    }

    func create(_ goal: WeeklyGoal) async throws {
        try validate(goal)

        let effectiveFromKey = goal.effectiveFrom.rawValue
        let duplicateDescriptor = FetchDescriptor<WeeklyGoalRecord>(
            predicate: #Predicate { $0.effectiveFromKey == effectiveFromKey },
        )
        guard try modelContext.fetch(duplicateDescriptor).isEmpty else {
            throw GoalRepositoryError.duplicateEffectiveDate
        }

        let goalRecord = WeeklyGoalRecord(
            id: goal.id,
            effectiveFromKey: goal.effectiveFrom.rawValue,
            createdAt: goal.createdAt,
        )
        let dailyGoalRecords = try LocalDay.Weekday.allCases.enumerated().map { position, weekday in
            guard let dailyGoal = goal.dailyGoals[weekday] else {
                throw GoalRepositoryError.invalidGoal
            }
            return DailyMacroGoalRecord(
                id: UUID(),
                weeklyGoalID: goal.id,
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

        do {
            modelContext.insert(goalRecord)
            for dailyGoalRecord in dailyGoalRecords {
                modelContext.insert(dailyGoalRecord)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func allGoals() throws -> [WeeklyGoal] {
        try modelContext.fetch(FetchDescriptor<WeeklyGoalRecord>()).map { try $0.toDomain() }
    }

    private func validate(_ goal: WeeklyGoal) throws {
        let weekdays = Set(LocalDay.Weekday.allCases)
        guard Set(goal.dailyGoals.keys) == weekdays,
              goal.dailyGoals.values.allSatisfy(\.isValid)
        else {
            throw GoalRepositoryError.invalidGoal
        }
    }
}

enum GoalRepositoryError: LocalizedError {
    case invalidGoal
    case duplicateEffectiveDate

    var errorDescription: String? {
        switch self {
        case .invalidGoal:
            "Цель недели должна содержать семь корректных дней."
        case .duplicateEffectiveDate:
            "Цели с этой датой уже существуют."
        }
    }
}
