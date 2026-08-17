import SwiftUI

struct ProductCatalogRootView: View {
    let router: AppRouter
    let productService: ProductService

    @State private var selectedSection: CatalogSection = .products

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.catalogPath) {
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
                    ProductListView(router: router, productService: productService)
                case .recipes:
                    ContentUnavailableView(
                        "Рецепты пока недоступны",
                        systemImage: "book.closed",
                        description: Text("Управление рецептами появится в следующей фазе."),
                    )
                }
            }
            .navigationDestination(for: CatalogRoute.self) { route in
                switch route {
                case let .product(id):
                    ProductDetailView(productID: id, router: router, productService: productService)
                case let .productEditor(id):
                    ProductEditorView(productID: id, router: router, productService: productService)
                case let .productVersionHistory(id):
                    ProductVersionHistoryView(productID: id, productService: productService)
                case .recipe:
                    ContentUnavailableView(
                        "Рецепты пока недоступны",
                        systemImage: "book.closed",
                    )
                }
            }
        }
    }
}

private struct ProductListView: View {
    let router: AppRouter

    @State private var model: ProductListViewModel
    @State private var searchText = ""

    init(router: AppRouter, productService: ProductService) {
        self.router = router
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
                    router.catalogPath.append(.productEditor(nil))
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
