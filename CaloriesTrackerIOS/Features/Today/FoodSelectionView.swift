import SwiftUI

struct FoodSelectionView: View {
    let context: DiaryContext
    let router: AppRouter

    @State private var model: FoodSelectionViewModel
    @State private var searchText = ""

    init(context: DiaryContext, router: AppRouter, diaryService: DiaryService) {
        self.context = context
        self.router = router
        _model = State(initialValue: FoodSelectionViewModel(diaryService: diaryService))
    }

    var body: some View {
        List {
            if model.isLoading && model.sources.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if model.sources.isEmpty, model.errorMessage == nil {
                ContentUnavailableView(
                    "В базе пока нет продуктов и рецептов",
                    systemImage: "shippingbox",
                    description: Text("Создайте продукт или рецепт во вкладке «Продукты», чтобы добавить его в дневник."),
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(model.sources) { item in
                    Button {
                        router.todayPath.append(
                            .amount(
                                context: context,
                                source: item.source,
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
        .searchable(text: $searchText, prompt: "Поиск продукта или блюда")
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
    let item: FoodSelectionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayName)
                .font(.body.weight(.medium))
            Text(item.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
