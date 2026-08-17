import SwiftUI

struct FoodSelectionView: View {
    let context: DiaryContext
    let router: AppRouter

    @State private var model: FoodSelectionViewModel
    @State private var searchText = ""

    init(context: DiaryContext, router: AppRouter, productService: ProductService) {
        self.context = context
        self.router = router
        _model = State(initialValue: FoodSelectionViewModel(productService: productService))
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
                    "В базе пока нет продуктов",
                    systemImage: "shippingbox",
                    description: Text("Создайте продукт во вкладке «Продукты», чтобы добавить его в дневник."),
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(model.products) { item in
                    Button {
                        router.todayPath.append(
                            .amount(
                                context: context,
                                source: FoodSourceReference(sourceType: .product, sourceID: item.product.id),
                            ),
                        )
                    } label: {
                        FoodSelectionRow(item: item)
                    }
                    .foregroundStyle(.primary)
                }
            }

            if let errorMessage = model.errorMessage {
                Section {
                    DiaryInlineErrorView(message: errorMessage)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Поиск продукта")
        .task {
            await model.load(matching: searchText)
        }
        .onChange(of: searchText) { _, newValue in
            Task {
                await model.load(matching: newValue)
            }
        }
    }
}

private struct FoodSelectionRow: View {
    let item: ProductListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.product.name)
                .font(.body.weight(.medium))
            Text("\(diaryNumber(item.currentVersion.baseAmount)) \(item.currentVersion.baseUnit.russianLabel) · \(diaryNumber(item.currentVersion.nutrition.calories)) ккал")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
