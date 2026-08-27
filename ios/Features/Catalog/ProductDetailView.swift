import SwiftUI

enum ProductDetailPresentation: Equatable {
    case catalog
    case diarySelection(DiaryContext)
}

struct ProductDetailView: View {
    let productID: UUID
    let router: AppRouter
    let presentation: ProductDetailPresentation

    @State private var model: ProductDetailViewModel

    init(
        productID: UUID,
        router: AppRouter,
        productService: ProductService,
        presentation: ProductDetailPresentation = .catalog,
    ) {
        self.productID = productID
        self.router = router
        self.presentation = presentation
        _model = State(initialValue: ProductDetailViewModel(productID: productID, productService: productService))
    }

    var body: some View {
        content
            .appScreenBackground()
            .navigationTitle(model.details?.product.name ?? "Продукт")
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationChrome()
            .toolbar {
                if model.details != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            openEditor()
                        } label: {
                            AppCircularControl {
                                Image(systemName: "pencil")
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .accessibilityLabel("Редактировать")
                    }

                    if case .catalog = presentation {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("Версии", systemImage: "clock.arrow.circlepath") {
                                    router.catalogPath.append(.productVersionHistory(productID))
                                }
                                Divider()
                                Button("Удалить", systemImage: "trash", role: .destructive) {
                                    Task {
                                        if await model.softDelete() {
                                            router.catalogPath = []
                                        }
                                    }
                                }
                            } label: {
                                AppCircularControl {
                                    Image(systemName: "ellipsis")
                                        .font(.body.weight(.semibold))
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                Task {
                    await model.load()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.details == nil {
            ProgressView()
        } else if let details = model.details {
            List {
                Section {
                    LabeledContent("Название", value: details.product.name)
                    if let barcode = details.product.barcode {
                        LabeledContent("Штрихкод", value: barcode)
                    }
                }

                Section("Текущая версия v\(details.currentVersion.versionNumber)") {
                    LabeledContent(
                        "Единица",
                        value: details.currentVersion.baseUnit.russianLabel,
                    )
                    LabeledContent(
                        "Количество",
                        value: "\(formattedNumber(details.currentVersion.baseAmount)) \(details.currentVersion.baseUnit.russianLabel)",
                    )
                }

                Section("Пищевая ценность") {
                    LabeledContent(
                        "Калории",
                        value: "\(formattedNumber(details.currentVersion.nutrition.calories)) ккал",
                    )
                    LabeledContent("Белки", value: "\(formattedNumber(details.currentVersion.nutrition.protein)) г")
                    LabeledContent("Жиры", value: "\(formattedNumber(details.currentVersion.nutrition.fat)) г")
                    LabeledContent("Углеводы", value: "\(formattedNumber(details.currentVersion.nutrition.carbs)) г")
                }

                if let errorMessage = model.errorMessage {
                    Section {
                        InlineErrorView(message: errorMessage)
                    }
                }
            }
            .appPlainListStyle()
        } else {
            ContentUnavailableView(
                "Продукт недоступен",
                systemImage: "shippingbox",
                description: model.errorMessage.map(Text.init),
            )
        }
    }

    private func openEditor() {
        switch presentation {
        case .catalog:
            router.catalogPath.append(.productEditor(productID))
        case let .diarySelection(context):
            router.todayPath.append(.productEditorForDiarySelection(productID: productID, context: context))
        }
    }
}
