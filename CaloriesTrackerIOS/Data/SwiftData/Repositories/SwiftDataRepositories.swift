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

    func recipe(id: UUID) async throws -> Recipe? {
        let descriptor = FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first?.toDomain()
    }
}

@MainActor
final class SwiftDataDiaryRepository: DiaryRepository {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        modelContext = ModelContext(modelContainer)
    }

    func entry(id: UUID) async throws -> DiaryEntry? {
        let descriptor = FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first.map { try $0.toDomain() }
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
}
