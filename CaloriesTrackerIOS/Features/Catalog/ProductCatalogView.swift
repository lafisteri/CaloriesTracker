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
            )
            .navigationDestination(for: CatalogRoute.self) { route in
                switch route {
                case let .product(id):
                    ProductDetailView(productID: id, router: router, productService: productService)
                case let .productEditor(id):
                    ProductEditorView(productID: id, router: router, productService: productService)
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
                    onSelect: selectProduct,
                    onAdd: createProduct,
                    allowsManagementActions: mode.allowsManagementActions,
                )
            case .recipes:
                RecipeListView(
                    recipeService: recipeService,
                    onSelect: selectRecipe,
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
    let onAdd: () -> Void
    let allowsManagementActions: Bool

    @State private var model: ProductListViewModel
    @State private var searchText = ""

    init(
        productService: ProductService,
        onSelect: @escaping (UUID) -> Void,
        onAdd: @escaping () -> Void,
        allowsManagementActions: Bool,
    ) {
        self.onSelect = onSelect
        self.onAdd = onAdd
        self.allowsManagementActions = allowsManagementActions
        _model = State(initialValue: ProductListViewModel(productService: productService))
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
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    } else {
                        Button {
                            onSelect(item.product.id)
                        } label: {
                            ProductListRow(item: item)
                        }
                        .foregroundStyle(.primary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.product.name)
                .font(.body.weight(.medium))

            Text("\(formattedNumber(item.currentVersion.baseAmount)) \(item.currentVersion.baseUnit.russianLabel) · \(formattedNumber(item.currentVersion.nutrition.calories)) ккал")
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
