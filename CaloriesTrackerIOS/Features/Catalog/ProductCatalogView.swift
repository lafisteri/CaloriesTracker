import SwiftUI

enum CatalogMode {
    case management
    case selection(DiaryContext)

    var allowsManagementActions: Bool {
        if case .management = self {
            return true
        }
        return false
    }

    var diaryContext: DiaryContext? {
        guard case let .selection(context) = self else {
            return nil
        }
        return context
    }
}

struct ProductCatalogRootView: View {
    let router: AppRouter
    let productService: ProductService
    let recipeService: RecipeService

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
                    selectionContext: mode.diaryContext,
                    onSelect: selectProduct,
                    onQuickAddComplete: {
                        router.todayPath = []
                    },
                    onAdd: createProduct,
                    allowsManagementActions: mode.allowsManagementActions,
                )
            case .recipes:
                RecipeListView(
                    recipeService: recipeService,
                    diaryService: diaryService,
                    selectionContext: mode.diaryContext,
                    onSelect: selectRecipe,
                    onQuickAddComplete: {
                        router.todayPath = []
                    },
                    onAdd: createRecipe,
                    allowsManagementActions: mode.allowsManagementActions,
                )
            }
        }
    }

    private func selectProduct(_ productID: UUID) {
        switch mode {
        case .management:
            router.catalogPath.append(.product(productID))
        case let .selection(context):
            router.todayPath.append(
                .amount(
                    context: context,
                    source: FoodSourceReference(sourceType: .product, sourceID: productID),
                ),
            )
        }
    }

    private func selectRecipe(_ recipeID: UUID) {
        switch mode {
        case .management:
            router.catalogPath.append(.recipe(recipeID))
        case let .selection(context):
            router.todayPath.append(
                .amount(
                    context: context,
                    source: FoodSourceReference(sourceType: .recipe, sourceID: recipeID),
                ),
            )
        }
    }

    private func createProduct() {
        switch mode {
        case .management:
            router.catalogPath.append(.productEditor(nil))
        case let .selection(context):
            router.todayPath.append(.productEditor(context: context, prefilledBarcode: nil))
        }
    }

    private func createRecipe() {
        switch mode {
        case .management:
            router.catalogPath.append(.recipeEditor(nil))
        case let .selection(context):
            router.todayPath.append(.recipeEditor(context: context, recipeID: nil))
        }
    }
}

private struct ProductListView: View {
    let onSelect: (UUID) -> Void
    let onQuickAddComplete: @MainActor () -> Void
    let onAdd: () -> Void
    let allowsManagementActions: Bool
    let selectionContext: DiaryContext?

    @State private var model: ProductListViewModel
    @State private var searchText = ""

    init(
        productService: ProductService,
        diaryService: DiaryService?,
        selectionContext: DiaryContext?,
        onSelect: @escaping (UUID) -> Void,
        onQuickAddComplete: @escaping @MainActor () -> Void,
        onAdd: @escaping () -> Void,
        allowsManagementActions: Bool,
    ) {
        self.onSelect = onSelect
        self.onQuickAddComplete = onQuickAddComplete
        self.onAdd = onAdd
        self.allowsManagementActions = allowsManagementActions
        self.selectionContext = selectionContext
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
                    if allowsManagementActions {
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
                    } else {
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

                            if model.quickAddingProductID == item.product.id {
                                ProgressView()
                                    .frame(minWidth: 44, minHeight: 44)
                            } else {
                                Button {
                                    guard let selectionContext else {
                                        return
                                    }
                                    Task {
                                        if await model.quickAdd(
                                            productID: item.product.id,
                                            context: selectionContext,
                                            defaultValue: defaultValue,
                                        ) {
                                            onQuickAddComplete()
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
    let selectionDefault: DiarySelectionAmountDefault?

    init(item: ProductListItem, selectionDefault: DiarySelectionAmountDefault? = nil) {
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
