import SwiftUI

struct FoodSelectionContext {
    let onSelectProduct: @MainActor (UUID) -> Void
    let onSelectRecipe: @MainActor (UUID) -> Void
    let onQuickAddProduct: @MainActor (UUID, FoodSelectionAmountDefault) async throws -> Void
    let onQuickAddRecipe: @MainActor (UUID, FoodSelectionAmountDefault) async throws -> Void
    let onCreateProduct: @MainActor () -> Void
    let onCreateRecipe: @MainActor () -> Void
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
                                router.catalogPath.removeLast()
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
    let mode: CatalogMode
    let router: AppRouter
    let productService: ProductService
    let recipeService: RecipeService
    let diaryService: DiaryService?

    @State private var selectedSection: CatalogSection = .products

    var body: some View {
        VStack(spacing: 0) {
            Picker("Каталог", selection: $selectedSection) {
                ForEach(CatalogSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            switch selectedSection {
            case .products:
                ProductListView(
                    productService: productService,
                    diaryService: diaryService,
                    mode: mode.productListMode,
                    onSelect: selectProduct,
                    onAdd: createProduct,
                )
            case .recipes:
                RecipeListView(
                    recipeService: recipeService,
                    diaryService: diaryService,
                    mode: mode.recipeListMode,
                    onSelect: selectRecipe,
                    onAdd: createRecipe,
                )
            }
        }
    }

    private func selectProduct(_ productID: UUID) {
        switch mode {
        case .management:
            router.catalogPath.append(.product(productID))
        case let .selection(context):
            context.onSelectProduct(productID)
        }
    }

    private func selectRecipe(_ recipeID: UUID) {
        switch mode {
        case .management:
            router.catalogPath.append(.recipe(recipeID))
        case let .selection(context):
            context.onSelectRecipe(recipeID)
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
}

private struct ProductListView: View {
    let onSelect: (UUID) -> Void
    let onAdd: () -> Void
    let mode: ProductListMode

    @State private var model: ProductListViewModel
    @State private var searchText = ""
    @State private var quickAddingProductID: UUID?

    init(
        productService: ProductService,
        diaryService: DiaryService?,
        mode: ProductListMode,
        onSelect: @escaping (UUID) -> Void,
        onAdd: @escaping () -> Void,
    ) {
        self.onSelect = onSelect
        self.onAdd = onAdd
        self.mode = mode
        _model = State(initialValue: ProductListViewModel(productService: productService, diaryService: diaryService))
    }

    var body: some View {
        List {
            if model.isLoading && model.products.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if model.products.isEmpty, model.errorMessage == nil {
                ContentUnavailableView(
                    "Продуктов пока нет",
                    systemImage: "shippingbox",
                    description: Text("Добавьте первый продукт с помощью кнопки выше."),
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(model.products) { item in
                    switch mode {
                    case .management:
                        NavigationLink(value: CatalogRoute.product(item.id)) {
                            ProductListRow(item: item)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task {
                                    await model.softDelete(productID: item.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Удалить")
                        }
                    case let .selection(context):
                        let defaultValue = model.selectionDefault(for: item)
                        HStack(spacing: 12) {
                            Button {
                                onSelect(item.product.id)
                            } label: {
                                HStack(spacing: 0) {
                                    ProductListRow(item: item, selectionDefault: defaultValue)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityLabel("Открыть \(item.product.name)")

                            if quickAddingProductID == item.product.id {
                                ProgressView()
                                    .frame(minWidth: 44, minHeight: 44)
                            } else {
                                Button {
                                    Task {
                                        quickAddingProductID = item.product.id
                                        defer { quickAddingProductID = nil }
                                        do {
                                            try await context.onQuickAddProduct(item.product.id, defaultValue)
                                        } catch {
                                            model.errorMessage = error.localizedDescription
                                        }
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                }
                                .buttonStyle(.borderless)
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel("Добавить \(item.product.name)")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                Section {
                    InlineErrorView(message: errorMessage)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Поиск")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onAdd()
                } label: {
                    Label("Добавить продукт", systemImage: "plus")
                }
            }
        }
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
}

private struct ProductListRow: View {
    let item: ProductListItem
    let selectionDefault: FoodSelectionAmountDefault?

    init(item: ProductListItem, selectionDefault: FoodSelectionAmountDefault? = nil) {
        self.item = item
        self.selectionDefault = selectionDefault
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.product.name)
                .font(.body.weight(.medium))

            Group {
                if let selectionDefault {
                    Text("\(formattedNumber(selectionDefault.amount)) \(selectionDefault.unitLabel) · \(formattedNumber(item.currentVersion.nutrition.calories)) ккал")
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
        case .ml: "мл"
        case .piece: "шт"
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
