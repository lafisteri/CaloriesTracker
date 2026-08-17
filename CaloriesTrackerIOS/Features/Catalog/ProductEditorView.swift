import SwiftUI

struct ProductEditorView: View {
    let router: AppRouter
    let onSaved: (@MainActor () -> Void)?

    @State private var model: ProductEditorViewModel
    @FocusState private var focusedField: EditorField?

    init(
        productID: UUID?,
        router: AppRouter,
        productService: ProductService,
        onSaved: (@MainActor () -> Void)? = nil,
    ) {
        self.router = router
        self.onSaved = onSaved
        _model = State(initialValue: ProductEditorViewModel(productID: productID, productService: productService))
    }

    var body: some View {
        @Bindable var model = model

        Form {
            if model.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else {
                Section {
                    TextField("Название", text: $model.name)
                        .textInputAutocapitalization(.sentences)

                    TextField("Штрихкод", text: $model.barcode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("Единица", selection: $model.baseUnit) {
                        ForEach(ProductBaseUnit.allCases, id: \.self) { unit in
                            Text(unit.russianLabel).tag(unit)
                        }
                    }

                    decimalField("Количество", text: $model.baseAmount, field: .baseAmount)
                }

                Section("Пищевая ценность") {
                    decimalField("Калории", text: $model.calories, field: .calories)
                    decimalField("Белки", text: $model.protein, field: .protein)
                    decimalField("Жиры", text: $model.fat, field: .fat)
                    decimalField("Углеводы", text: $model.carbs, field: .carbs)
                }
            }

            if let errorMessage = model.errorMessage {
                Section {
                    InlineErrorView(message: errorMessage)
                }
            }
        }
        .navigationTitle(model.productID == nil ? "Новый продукт" : "Редактировать продукт")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isLoading || model.isSaving)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.isSaving ? "Сохранение…" : "Сохранить") {
                    Task {
                        if await model.save() {
                            focusedField = nil
                            if let onSaved {
                                onSaved()
                            } else {
                                router.catalogPath = []
                            }
                        }
                    }
                }
                .disabled(model.isLoading || model.isSaving)
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    focusedField = nil
                }
            }
        }
        .task {
            await model.loadForEditing()
        }
    }

    private func decimalField(_ title: String, text: Binding<String>, field: EditorField) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: field)
    }
}

private enum EditorField: Hashable {
    case baseAmount
    case calories
    case protein
    case fat
    case carbs
}
