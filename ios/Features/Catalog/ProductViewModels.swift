import Foundation
import Observation

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
        currentQuery = query
        isLoading = true
        errorMessage = nil

        do {
            let items = try await productService.products(matching: query)
            products = items
            if let diaryService {
                usageDefaults = try await diaryService.latestUsageDefaults(
                    for: items.map { item in
                        FoodSourceReference(sourceType: .product, sourceID: item.product.id)
                    },
                )
            } else {
                usageDefaults = [:]
            }
            refreshSelectionDisplays(for: items)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func softDelete(productID: UUID) async {
        errorMessage = nil

        do {
            try await productService.softDelete(productID: productID)
            await load(matching: currentQuery)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectionDefault(for item: ProductListItem) -> FoodSelectionAmountDefault {
        let fallback = FoodSelectionAmountDefault(
            amount: 100,
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
                    calculationErrorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            baseAmount = numericString(details.currentVersion.baseAmount)
            calories = numericString(details.currentVersion.nutrition.calories)
            protein = numericString(details.currentVersion.nutrition.protein)
            fat = numericString(details.currentVersion.nutrition.fat)
            carbs = numericString(details.currentVersion.nutrition.carbs)
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func makeDraft() throws -> ProductDraft {
        ProductDraft(
            name: name,
            barcode: barcode,
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

    private func numericValue(_ text: String, field: String) throws -> Double {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite else {
            throw ProductEditorError.invalidNumber(field: field)
        }
        return value
    }

    private func numericString(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0 ... 3)))
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
            errorMessage = error.localizedDescription
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
