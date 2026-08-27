import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class CatalogQuickAddState {
    private(set) var activeSource: FoodSourceReference?

    var isInProgress: Bool {
        activeSource != nil
    }

    func begin(for source: FoodSourceReference) -> Bool {
        guard activeSource == nil else {
            return false
        }
        activeSource = source
        return true
    }

    func finish(for source: FoodSourceReference) {
        guard activeSource == source else {
            return
        }
        activeSource = nil
    }
}

struct FoodSelectionContext {
    let quickAddState: CatalogQuickAddState?
    let onSelectProduct: @MainActor (UUID, FoodSelectionAmountDefault?) -> Void
    let onSelectRecipe: @MainActor (UUID, FoodSelectionAmountDefault?) -> Void
    let onQuickAddProduct: @MainActor (UUID, FoodSelectionAmountDefault) async throws -> Void
    let onQuickAddRecipe: @MainActor (UUID, FoodSelectionAmountDefault) async throws -> Void
    let onCreateProduct: @MainActor () -> Void
    let onCreateRecipe: @MainActor () -> Void

    init(
        quickAddState: CatalogQuickAddState? = nil,
        onSelectProduct: @escaping @MainActor (UUID, FoodSelectionAmountDefault?) -> Void,
        onSelectRecipe: @escaping @MainActor (UUID, FoodSelectionAmountDefault?) -> Void,
        onQuickAddProduct: @escaping @MainActor (UUID, FoodSelectionAmountDefault) async throws -> Void,
        onQuickAddRecipe: @escaping @MainActor (UUID, FoodSelectionAmountDefault) async throws -> Void,
        onCreateProduct: @escaping @MainActor () -> Void,
        onCreateRecipe: @escaping @MainActor () -> Void,
    ) {
        self.quickAddState = quickAddState
        self.onSelectProduct = onSelectProduct
        self.onSelectRecipe = onSelectRecipe
        self.onQuickAddProduct = onQuickAddProduct
        self.onQuickAddRecipe = onQuickAddRecipe
        self.onCreateProduct = onCreateProduct
        self.onCreateRecipe = onCreateRecipe
    }
}

enum CatalogMode {
    case management
    case selection(FoodSelectionContext)

    var productListMode: ProductListMode {
        switch self {
        case .management:
            .management
        case let .selection(context):
            .selection(context)
        }
    }

    var recipeListMode: RecipeListMode {
        switch self {
        case .management:
            .management
        case let .selection(context):
            .selection(context)
        }
    }
}

enum ProductListMode {
    case management
    case selection(FoodSelectionContext)
}

enum RecipeListMode {
    case management
    case selection(FoodSelectionContext)
}

struct ProductCatalogRootView: View {
    let router: AppRouter
    let productService: ProductService
    let recipeService: RecipeService
    let diaryService: DiaryService

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.catalogPath) {
            CatalogView(
                mode: .management,
                router: router,
                productService: productService,
                recipeService: recipeService,
                diaryService: nil,
            )
            .navigationDestination(for: CatalogRoute.self) { route in
                switch route {
                case let .product(id):
                    ProductDetailView(productID: id, router: router, productService: productService)
                case let .productEditor(id):
                    if let id {
                        ProductEditorView(
                            productID: id,
                            router: router,
                            productService: productService,
                            onSaved: {
                                router.popCatalog(ifTopIs: .productEditor(id))
                            },
                        )
                    } else {
                        ProductEditorView(productID: nil, router: router, productService: productService)
                    }
                case let .productVersionHistory(id):
                    ProductVersionHistoryView(productID: id, productService: productService)
                case let .recipe(id):
                    RecipeDetailView(recipeID: id, router: router, recipeService: recipeService)
                case let .recipeEditor(id):
                    RecipeEditorView(
                        recipeID: id,
                        router: router,
                        productService: productService,
                        recipeService: recipeService,
                        diaryService: diaryService,
                    )
                case let .recipeVersionHistory(id):
                    RecipeVersionHistoryView(recipeID: id, recipeService: recipeService)
                }
            }
        }
    }
}

struct CatalogView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: CatalogMode
    let router: AppRouter
    let productService: ProductService
    let recipeService: RecipeService
    let diaryService: DiaryService?

    @State private var selectedSection: CatalogSection = .products
    @State private var productSearchText = ""
    @State private var recipeSearchText = ""

    var body: some View {
        ZStack {
            AppStyle.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                catalogHeader

                Picker("Каталог", selection: $selectedSection) {
                    ForEach(CatalogSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .clipShape(Capsule())
                .padding(.horizontal, DateNavigatorLayout.screenHorizontalMargin)
                .padding(.bottom, DateNavigatorLayout.headerBottomSpacing)

                switch selectedSection {
                case .products:
                    ProductListView(
                        productService: productService,
                        diaryService: diaryService,
                        mode: mode.productListMode,
                        onSelect: selectProduct,
                        searchText: $productSearchText,
                    )
                case .recipes:
                    RecipeListView(
                        recipeService: recipeService,
                        diaryService: diaryService,
                        mode: mode.recipeListMode,
                        onSelect: selectRecipe,
                        searchText: $recipeSearchText,
                    )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var isManagementMode: Bool {
        if case .management = mode {
            true
        } else {
            false
        }
    }

    private var catalogHeader: some View {
        HStack(spacing: AppStyle.controlSpacing) {
            if !isManagementMode {
                AppCircularButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Назад",
                    action: { dismiss() }
                )
            }

            Group {
                switch selectedSection {
                case .products:
                    CatalogInlineSearchField(text: $productSearchText)
                case .recipes:
                    CatalogInlineSearchField(text: $recipeSearchText)
                }
            }
            .frame(maxWidth: .infinity)

            AppCircularButton(
                systemName: "plus",
                accessibilityLabel: "Добавить",
                action: addSelectedSection
            )
        }
        .padding(.horizontal, DateNavigatorLayout.screenHorizontalMargin)
        .padding(.bottom, DateNavigatorLayout.rootHeaderContentSpacing)
        .frame(maxWidth: .infinity, minHeight: DateNavigatorLayout.height)
        .buttonStyle(.borderless)
    }

    private func selectProduct(_ productID: UUID, selectionDefault: FoodSelectionAmountDefault?) {
        switch mode {
        case .management:
            router.catalogPath.append(.product(productID))
        case let .selection(context):
            context.onSelectProduct(productID, selectionDefault)
        }
    }

    private func selectRecipe(_ recipeID: UUID, selectionDefault: FoodSelectionAmountDefault?) {
        switch mode {
        case .management:
            router.catalogPath.append(.recipe(recipeID))
        case let .selection(context):
            context.onSelectRecipe(recipeID, selectionDefault)
        }
    }

    private func createProduct() {
        switch mode {
        case .management:
            router.catalogPath.append(.productEditor(nil))
        case let .selection(context):
            context.onCreateProduct()
        }
    }

    private func createRecipe() {
        switch mode {
        case .management:
            router.catalogPath.append(.recipeEditor(nil))
        case let .selection(context):
            context.onCreateRecipe()
        }
    }

    private func addSelectedSection() {
        switch selectedSection {
        case .products:
            createProduct()
        case .recipes:
            createRecipe()
        }
    }
}

private struct ProductListView: View {
    let onSelect: (UUID, FoodSelectionAmountDefault?) -> Void
    let mode: ProductListMode

    @State private var model: ProductListViewModel
    @Binding private var searchText: String
    @State private var quickAddingProductID: UUID?

    init(
        productService: ProductService,
        diaryService: DiaryService?,
        mode: ProductListMode,
        onSelect: @escaping (UUID, FoodSelectionAmountDefault?) -> Void,
        searchText: Binding<String>,
    ) {
        self.onSelect = onSelect
        self.mode = mode
        _model = State(initialValue: ProductListViewModel(productService: productService, diaryService: diaryService))
        _searchText = searchText
    }

    var body: some View {
        productList
            .appPlainListStyle()
        .task {
            await model.load(matching: searchText)
        }
        .onAppear {
            Task {
                await model.load(matching: searchText)
            }
        }
        .onChange(of: searchText) { _, newValue in
            Task {
                await model.load(matching: newValue)
            }
        }
    }

    private var productList: some View {
        List {
            if model.isLoading && model.products.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if model.products.isEmpty, model.errorMessage == nil {
                ContentUnavailableView(
                    "Продуктов пока нет",
                    systemImage: "shippingbox",
                    description: Text("Добавьте первый продукт с помощью кнопки выше."),
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(model.products) { item in
                    switch mode {
                    case .management:
                        NavigationLink(value: CatalogRoute.product(item.id)) {
                            ProductListRow(item: item)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await model.softDelete(productID: item.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Удалить")
                        }
                        .catalogListRow()
                    case let .selection(context):
                        let selectionDisplay = model.selectionDisplay(for: item)
                        let defaultValue = selectionDisplay.defaultValue
                        let source = FoodSourceReference(sourceType: .product, sourceID: item.product.id)
                        HStack(spacing: 12) {
                            Button {
                                onSelect(item.product.id, defaultValue)
                            } label: {
                                HStack(spacing: 0) {
                                    ProductListRow(item: item, selectionDisplay: selectionDisplay)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityLabel("Открыть \(item.product.name)")

                            if isQuickAdding(source: source, context: context) {
                                ProgressView()
                                    .frame(minWidth: 44, minHeight: 44)
                            } else {
                                Button {
                                    Task { @MainActor in
                                        await quickAdd(
                                            source: source,
                                            productID: item.product.id,
                                            defaultValue: defaultValue,
                                            context: context,
                                        )
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                }
                                .buttonStyle(.borderless)
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel("Добавить \(item.product.name)")
                                .disabled(context.quickAddState?.isInProgress == true)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .catalogListRow()
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                Section {
                    InlineErrorView(message: errorMessage)
                }
            }
        }
    }

    @MainActor
    private func quickAdd(
        source: FoodSourceReference,
        productID: UUID,
        defaultValue: FoodSelectionAmountDefault,
        context: FoodSelectionContext,
    ) async {
        let quickAddState = context.quickAddState
        if let quickAddState {
            guard quickAddState.begin(for: source) else {
                return
            }
        } else {
            quickAddingProductID = productID
        }
        defer {
            if let quickAddState {
                quickAddState.finish(for: source)
            } else {
                quickAddingProductID = nil
            }
        }

        do {
            try await context.onQuickAddProduct(productID, defaultValue)
        } catch {
            model.errorMessage = catalogQuickAddErrorMessage(
                error,
                fallback: "Не удалось добавить запись.",
            )
        }
    }

    private func isQuickAdding(source: FoodSourceReference, context: FoodSelectionContext) -> Bool {
        context.quickAddState?.activeSource == source || quickAddingProductID == source.sourceID
    }
}

struct CatalogInlineSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Поиск", text: $text)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: AppStyle.controlHeight)
        .background(
            AppStyle.controlBackground,
            in: Capsule(),
        )
        .shadow(
            color: AppStyle.controlShadowColor,
            radius: AppStyle.controlShadowRadius,
            y: AppStyle.controlShadowY
        )
    }
}

extension View {
    func catalogListRow() -> some View {
        listRowInsets(
            EdgeInsets(
                top: 10,
                leading: DateNavigatorLayout.screenHorizontalMargin,
                bottom: 10,
                trailing: DateNavigatorLayout.screenHorizontalMargin,
            )
        )
        .listRowBackground(AppStyle.background)
    }
}

private let catalogQuickAddErrorLogger = Logger(
    subsystem: "com.caloriestracker.ios",
    category: "CatalogQuickAdd",
)

func catalogQuickAddErrorMessage(_ error: Error, fallback: String) -> String {
    switch error {
    case let error as DiaryServiceError:
        return error.errorDescription ?? fallback
    case let error as RecipeServiceError:
        return error.errorDescription ?? fallback
    case let error as RecipeCalculatorError:
        return error.errorDescription ?? fallback
    case let error as NutritionCalculatorError:
        return error.errorDescription ?? fallback
    case let error as NutritionError:
        return error.errorDescription ?? fallback
    default:
        catalogQuickAddErrorLogger.error(
            "unexpected_user_facing_error fallback=\(fallback, privacy: .public) technical_error=\(String(reflecting: error), privacy: .public)",
        )
        return fallback
    }
}

private struct ProductListRow: View {
    let item: ProductListItem
    let selectionDisplay: FoodSelectionDisplay?

    init(item: ProductListItem, selectionDisplay: FoodSelectionDisplay? = nil) {
        self.item = item
        self.selectionDisplay = selectionDisplay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.product.name)
                .font(.headline)

            Group {
                if let selectionDisplay {
                    if let nutrition = selectionDisplay.nutrition {
                        Text("\(formattedNumber(selectionDisplay.defaultValue.amount)) \(selectionDisplay.defaultValue.unitLabel) · \(formattedNumber(nutrition.calories)) ккал")
                    } else {
                        Text("\(formattedNumber(selectionDisplay.defaultValue.amount)) \(selectionDisplay.defaultValue.unitLabel) · КБЖУ недоступно")
                    }
                } else {
                    Text("\(formattedNumber(item.currentVersion.baseAmount)) \(item.currentVersion.baseUnit.russianLabel) · \(formattedNumber(item.currentVersion.nutrition.calories)) ккал")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let barcode = item.product.barcode {
                Text(barcode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private enum CatalogSection: String, CaseIterable, Identifiable {
    case products
    case recipes

    var id: Self { self }

    var title: String {
        switch self {
        case .products: "Продукты"
        case .recipes: "Рецепты"
        }
    }
}

extension ProductBaseUnit {
    var russianLabel: String {
        switch self {
        case .g: "г"
        case .serving: "порция"
        }
    }
}

func formattedNumber(_ value: Double) -> String {
    value.formatted(.number.grouping(.never).precision(.fractionLength(0 ... 2)))
}

struct InlineErrorView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
