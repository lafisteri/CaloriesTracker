import Foundation

struct ProductListItem: Identifiable, Hashable, Sendable {
    let product: Product
    let currentVersion: ProductVersion

    var id: UUID {
        product.id
    }
}

struct ProductDetails: Hashable, Sendable {
    let product: Product
    let currentVersion: ProductVersion
}

@MainActor
final class ProductService {
    private let repository: any ProductRepository

    init(repository: any ProductRepository) {
        self.repository = repository
    }

    func products(matching query: String) async throws -> [ProductListItem] {
        let products = try await repository.activeProducts(matching: query)
        var items: [ProductListItem] = []

        for product in products {
            guard let currentVersion = try await repository.version(id: product.currentVersionID) else {
                throw ProductServiceError.currentVersionNotFound
            }
            items.append(ProductListItem(product: product, currentVersion: currentVersion))
        }

        return items
    }

    func details(id: UUID) async throws -> ProductDetails? {
        guard let product = try await repository.product(id: id, includingDeleted: false) else {
            return nil
        }
        guard let currentVersion = try await repository.version(id: product.currentVersionID) else {
            throw ProductServiceError.currentVersionNotFound
        }

        return ProductDetails(product: product, currentVersion: currentVersion)
    }

    func versions(for productID: UUID) async throws -> [ProductVersion] {
        let versions = try await repository.versions(for: productID)
        return versions.sorted {
            if $0.versionNumber == $1.versionNumber {
                return $0.createdAt > $1.createdAt
            }
            return $0.versionNumber > $1.versionNumber
        }
    }

    @discardableResult
    func create(draft: ProductDraft) async throws -> UUID {
        let draft = try await validatedDraft(from: draft, excludingProductID: nil)
        let now = Date()
        let productID = UUID()
        let versionID = UUID()
        let version = ProductVersion(
            id: versionID,
            productID: productID,
            basedOnVersionID: nil,
            versionNumber: 1,
            baseUnit: draft.baseUnit,
            baseAmount: draft.baseAmount,
            nutrition: draft.nutrition,
            servingUnits: [],
            createdAt: now,
        )
        let product = Product(
            id: productID,
            name: draft.name,
            barcode: draft.barcode,
            currentVersionID: versionID,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
        )

        try await repository.create(product, initialVersion: version)
        return productID
    }

    func update(productID: UUID, draft: ProductDraft) async throws {
        guard let details = try await details(id: productID) else {
            throw ProductServiceError.productNotFound
        }

        let draft = try await validatedDraft(from: draft, excludingProductID: productID)
        let versionedFieldsChanged = details.currentVersion.baseUnit != draft.baseUnit
            || details.currentVersion.baseAmount != draft.baseAmount
            || details.currentVersion.nutrition != draft.nutrition
        let metadataChanged = details.product.name != draft.name
            || details.product.barcode != draft.barcode

        guard versionedFieldsChanged || metadataChanged else {
            return
        }

        let now = Date()

        if versionedFieldsChanged {
            let versionID = UUID()
            let servingUnits = details.currentVersion.servingUnits.map { oldUnit in
                ServingUnit(
                    id: UUID(),
                    productVersionID: versionID,
                    position: oldUnit.position,
                    name: oldUnit.name,
                    conversionAmount: oldUnit.conversionAmount,
                    conversionUnit: oldUnit.conversionUnit,
                )
            }
            let nextVersion = ProductVersion(
                id: versionID,
                productID: details.product.id,
                basedOnVersionID: details.currentVersion.id,
                versionNumber: details.currentVersion.versionNumber + 1,
                baseUnit: draft.baseUnit,
                baseAmount: draft.baseAmount,
                nutrition: draft.nutrition,
                servingUnits: servingUnits,
                createdAt: now,
            )
            let updatedProduct = Product(
                id: details.product.id,
                name: draft.name,
                barcode: draft.barcode,
                currentVersionID: nextVersion.id,
                createdAt: details.product.createdAt,
                updatedAt: now,
                deletedAt: details.product.deletedAt,
            )

            try await repository.append(nextVersion, settingCurrentVersionOf: updatedProduct)
        } else {
            let updatedProduct = Product(
                id: details.product.id,
                name: draft.name,
                barcode: draft.barcode,
                currentVersionID: details.product.currentVersionID,
                createdAt: details.product.createdAt,
                updatedAt: now,
                deletedAt: details.product.deletedAt,
            )
            try await repository.saveLogicalMetadata(updatedProduct)
        }
    }

    func softDelete(productID: UUID) async throws {
        guard try await repository.product(id: productID, includingDeleted: false) != nil else {
            throw ProductServiceError.productNotFound
        }

        try await repository.softDeleteProduct(id: productID, at: Date())
    }

    private func validatedDraft(
        from draft: ProductDraft,
        excludingProductID: UUID?,
    ) async throws -> ProductDraft {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw ProductServiceError.nameRequired
        }
        guard draft.baseAmount.isFinite, draft.baseAmount > 0 else {
            throw ProductServiceError.invalidBaseAmount
        }
        guard nutritionIsValid(draft.nutrition) else {
            throw ProductServiceError.invalidNutrition
        }

        let barcode = draft.barcode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBarcode = barcode?.isEmpty == true ? nil : barcode
        if let normalizedBarcode,
           let existing = try await repository.product(withBarcode: normalizedBarcode),
           existing.id != excludingProductID {
            throw ProductServiceError.barcodeAlreadyInUse
        }

        return ProductDraft(
            name: name,
            barcode: normalizedBarcode,
            baseUnit: draft.baseUnit,
            baseAmount: draft.baseAmount,
            nutrition: draft.nutrition,
        )
    }

    private func nutritionIsValid(_ nutrition: Nutrition) -> Bool {
        [nutrition.calories, nutrition.protein, nutrition.fat, nutrition.carbs]
            .allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

enum ProductServiceError: LocalizedError {
    case productNotFound
    case currentVersionNotFound
    case nameRequired
    case invalidBaseAmount
    case invalidNutrition
    case barcodeAlreadyInUse

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            "Продукт не найден."
        case .currentVersionNotFound:
            "Не удалось найти текущую версию продукта."
        case .nameRequired:
            "Укажите название продукта."
        case .invalidBaseAmount:
            "Количество должно быть больше нуля."
        case .invalidNutrition:
            "Пищевая ценность должна содержать конечные неотрицательные значения."
        case .barcodeAlreadyInUse:
            "Этот штрихкод уже используется другим продуктом."
        }
    }
}
