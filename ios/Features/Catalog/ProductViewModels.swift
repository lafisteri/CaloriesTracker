import Foundation
import Observation
import OSLog

struct FoodSelectionAmountDefault: Hashable, Sendable {
    let amount: Double
    let unitToken: String
    let unitLabel: String
}

struct FoodSelectionDisplay: Hashable, Sendable {
    let defaultValue: FoodSelectionAmountDefault
    let nutrition: Nutrition?
}

@MainActor
@Observable
final class ProductListViewModel {
    private let productService: ProductService
    private let diaryService: DiaryService?
    private var currentQuery = ""
    private var latestLoadRequestID: UUID?

    private(set) var products: [ProductListItem] = []
    private(set) var isLoading = false
    private var usageDefaults: [FoodSourceReference: DiaryUsageDefault] = [:]
    private var selectionDisplays: [UUID: FoodSelectionDisplay] = [:]
    var errorMessage: String?

    init(productService: ProductService, diaryService: DiaryService? = nil) {
        self.productService = productService
        self.diaryService = diaryService
    }

    func load(matching query: String) async {
        let requestID = UUID()
        latestLoadRequestID = requestID
        currentQuery = query
        isLoading = true
        errorMessage = nil

        do {
            let items = try await productService.products(matching: query)
            guard shouldPublish(requestID) else {
                return
            }

            let loadedUsageDefaults: [FoodSourceReference: DiaryUsageDefault]
            if let diaryService {
                loadedUsageDefaults = try await diaryService.latestUsageDefaults(
                    for: items.map { item in
                        FoodSourceReference(sourceType: .product, sourceID: item.product.id)
                    },
                )
            } else {
                loadedUsageDefaults = [:]
            }
            guard shouldPublish(requestID) else {
                return
            }

            products = items
            usageDefaults = loadedUsageDefaults
            refreshSelectionDisplays(for: items)
        } catch is CancellationError {
            return
        } catch {
            guard shouldPublish(requestID) else {
                return
            }
            errorMessage = productErrorMessage(error, fallback: "Не удалось загрузить продукты.")
        }

        guard shouldPublish(requestID) else {
            return
        }
        isLoading = false
    }

    func softDelete(productID: UUID) async {
        errorMessage = nil

        do {
            try await productService.softDelete(productID: productID)
            await load(matching: currentQuery)
        } catch {
            errorMessage = productErrorMessage(error, fallback: "Не удалось удалить продукт.")
        }
    }

    func selectionDefault(for item: ProductListItem) -> FoodSelectionAmountDefault {
        let fallback = FoodSelectionAmountDefault(
            amount: FoodAmountDefaults.fallbackAmount(for: item.currentVersion.baseUnit.rawValue),
            unitToken: item.currentVersion.baseUnit.rawValue,
            unitLabel: item.currentVersion.baseUnit.russianLabel,
        )
        let source = FoodSourceReference(sourceType: .product, sourceID: item.product.id)
        guard let usageDefault = usageDefaults[source],
              usageDefault.amount.isFinite,
              usageDefault.amount > 0,
              let unitLabel = productUnitLabel(
                  for: usageDefault.unitToken,
                  version: item.currentVersion,
              )
        else {
            return fallback
        }

        return FoodSelectionAmountDefault(
            amount: usageDefault.amount,
            unitToken: usageDefault.unitToken,
            unitLabel: unitLabel,
        )
    }

    func selectionDisplay(for item: ProductListItem) -> FoodSelectionDisplay {
        selectionDisplays[item.id] ?? FoodSelectionDisplay(
            defaultValue: selectionDefault(for: item),
            nutrition: nil,
        )
    }

    private func refreshSelectionDisplays(for items: [ProductListItem]) {
        guard let diaryService else {
            selectionDisplays = [:]
            return
        }

        var displays: [UUID: FoodSelectionDisplay] = [:]
        var calculationErrorMessage: String?

        for item in items {
            let defaultValue = selectionDefault(for: item)
            let nutrition: Nutrition?

            do {
                nutrition = try diaryService.preview(
                    calculationSource: .product(item.currentVersion),
                    amount: defaultValue.amount,
                    unitToken: defaultValue.unitToken,
                )
            } catch {
                nutrition = nil
                if calculationErrorMessage == nil {
                    calculationErrorMessage = productErrorMessage(
                        error,
                        fallback: "Не удалось рассчитать КБЖУ.",
                    )
                }
            }

            displays[item.id] = FoodSelectionDisplay(
                defaultValue: defaultValue,
                nutrition: nutrition,
            )
        }

        selectionDisplays = displays
        if let calculationErrorMessage {
            errorMessage = calculationErrorMessage
        }
    }

    private func productUnitLabel(for token: String, version: ProductVersion) -> String? {
        token == version.baseUnit.rawValue ? version.baseUnit.russianLabel : nil
    }

    private func shouldPublish(_ requestID: UUID) -> Bool {
        latestLoadRequestID == requestID && !Task.isCancelled
    }
}

@MainActor
@Observable
final class ProductDetailViewModel {
    private let productService: ProductService
    private let productID: UUID

    private(set) var details: ProductDetails?
    private(set) var isLoading = false
    var errorMessage: String?

    init(productID: UUID, productService: ProductService) {
        self.productID = productID
        self.productService = productService
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            details = try await productService.details(id: productID)
        } catch {
            errorMessage = productErrorMessage(error, fallback: "Не удалось загрузить продукт.")
        }

        isLoading = false
    }

    @discardableResult
    func softDelete() async -> Bool {
        errorMessage = nil

        do {
            try await productService.softDelete(productID: productID)
            return true
        } catch {
            errorMessage = productErrorMessage(error, fallback: "Не удалось удалить продукт.")
            return false
        }
    }
}

@MainActor
@Observable
final class ProductEditorViewModel {
    private let productService: ProductService
    let productID: UUID?

    var name = ""
    var barcode = ""
    var baseUnit: ProductBaseUnit = .g
    var baseAmount = ""
    var calories = ""
    var protein = ""
    var fat = ""
    var carbs = ""
    private(set) var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?
    private var loadedVersion: ProductVersion?

    init(productID: UUID?, productService: ProductService) {
        self.productID = productID
        self.productService = productService
    }

    func loadForEditing() async {
        guard let productID else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            guard let details = try await productService.details(id: productID) else {
                throw ProductServiceError.productNotFound
            }

            name = details.product.name
            barcode = details.product.barcode ?? ""
            baseUnit = details.currentVersion.baseUnit
            baseAmount = EditableDecimal.string(from: details.currentVersion.baseAmount)
            calories = EditableDecimal.string(from: details.currentVersion.nutrition.calories)
            protein = EditableDecimal.string(from: details.currentVersion.nutrition.protein)
            fat = EditableDecimal.string(from: details.currentVersion.nutrition.fat)
            carbs = EditableDecimal.string(from: details.currentVersion.nutrition.carbs)
            loadedVersion = details.currentVersion
        } catch {
            errorMessage = productErrorMessage(error, fallback: "Не удалось загрузить продукт.")
        }

        isLoading = false
    }

    @discardableResult
    func save() async -> Bool {
        errorMessage = nil

        do {
            let draft = try makeDraft()
            isSaving = true

            if let productID {
                try await productService.update(productID: productID, draft: draft)
            } else {
                try await productService.create(draft: draft)
            }

            isSaving = false
            return true
        } catch {
            isSaving = false
            errorMessage = productErrorMessage(error, fallback: "Не удалось сохранить продукт.")
            return false
        }
    }

    private func makeDraft() throws -> ProductDraft {
        let versionedValues: (baseUnit: ProductBaseUnit, baseAmount: Double, nutrition: Nutrition)
        if let loadedVersion, versionedInputsMatch(loadedVersion) {
            // The editor intentionally displays at most two fractional digits.
            // Preserve the stored values when those inputs were not touched so a
            // name or barcode edit cannot manufacture a ProductVersion.
            versionedValues = (
                baseUnit: loadedVersion.baseUnit,
                baseAmount: loadedVersion.baseAmount,
                nutrition: loadedVersion.nutrition,
            )
        } else {
            versionedValues = (
                baseUnit: baseUnit,
                baseAmount: try numericValue(baseAmount, field: "Количество"),
                nutrition: Nutrition(
                    calories: try numericValue(calories, field: "Калории"),
                    protein: try numericValue(protein, field: "Белки"),
                    fat: try numericValue(fat, field: "Жиры"),
                    carbs: try numericValue(carbs, field: "Углеводы"),
                ),
            )
        }

        return ProductDraft(
            name: name,
            barcode: barcode,
            baseUnit: versionedValues.baseUnit,
            baseAmount: versionedValues.baseAmount,
            nutrition: versionedValues.nutrition,
        )
    }

    private func versionedInputsMatch(_ version: ProductVersion) -> Bool {
        baseUnit == version.baseUnit
            && baseAmount == EditableDecimal.string(from: version.baseAmount)
            && calories == EditableDecimal.string(from: version.nutrition.calories)
            && protein == EditableDecimal.string(from: version.nutrition.protein)
            && fat == EditableDecimal.string(from: version.nutrition.fat)
            && carbs == EditableDecimal.string(from: version.nutrition.carbs)
    }

    private func numericValue(_ text: String, field: String) throws -> Double {
        guard let value = EditableDecimal.value(from: text) else {
            throw ProductEditorError.invalidNumber(field: field)
        }
        return value
    }
}

@MainActor
@Observable
final class ProductVersionHistoryViewModel {
    private let productService: ProductService
    private let productID: UUID

    private(set) var versions: [ProductVersion] = []
    private(set) var currentVersionID: UUID?
    private(set) var isLoading = false
    var errorMessage: String?

    init(productID: UUID, productService: ProductService) {
        self.productID = productID
        self.productService = productService
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let details = try await productService.details(id: productID) else {
                throw ProductServiceError.productNotFound
            }
            currentVersionID = details.product.currentVersionID
            versions = try await productService.versions(for: productID)
        } catch {
            errorMessage = productErrorMessage(error, fallback: "Не удалось загрузить версии продукта.")
        }

        isLoading = false
    }
}

private enum ProductEditorError: LocalizedError {
    case invalidNumber(field: String)

    var errorDescription: String? {
        switch self {
        case let .invalidNumber(field):
            "Введите корректное значение для поля «\(field)»."
        }
    }
}

private let productErrorLogger = Logger(subsystem: "com.caloriestracker.ios", category: "Product")

func productErrorMessage(_ error: Error, fallback: String) -> String {
    switch error {
    case let error as ProductServiceError:
        return error.errorDescription ?? fallback
    case let error as ProductEditorError:
        return error.errorDescription ?? fallback
    case let error as DiaryServiceError:
        return error.errorDescription ?? fallback
    case let error as NutritionCalculatorError:
        return error.errorDescription ?? fallback
    case let error as NutritionError:
        return error.errorDescription ?? fallback
    default:
        productErrorLogger.error(
            "unexpected_user_facing_error fallback=\(fallback, privacy: .public) technical_error=\(String(reflecting: error), privacy: .public)",
        )
        return fallback
    }
}
