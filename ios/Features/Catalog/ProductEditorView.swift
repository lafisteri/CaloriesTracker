import SwiftUI

struct ProductEditorView: View {
    let router: AppRouter
    let onSaved: (@MainActor () -> Void)?
    let onDismissed: (@MainActor (Bool) -> Void)?

    @State private var model: ProductEditorViewModel
    @FocusState private var focusedField: EditorField?
    @State private var didSave = false

    init(
        productID: UUID?,
        router: AppRouter,
        productService: ProductService,
        onSaved: (@MainActor () -> Void)? = nil,
        onDismissed: (@MainActor (Bool) -> Void)? = nil,
    ) {
        self.router = router
        self.onSaved = onSaved
        self.onDismissed = onDismissed
        _model = State(initialValue: ProductEditorViewModel(productID: productID, productService: productService))
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            AppTopNavigationHeader(
                title: model.productID == nil ? "Новый продукт" : "Редактировать продукт",
            ) {
                Button {
                    focusedField = nil
                    Task {
                        let didSave = await model.save()
                        if didSave {
                            self.didSave = true
                            if let onSaved {
                                onSaved()
                            } else {
                                router.catalogPath = []
                            }
                        }
                    }
                } label: {
                    AppCircularControl {
                        if model.isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                        }
                    }
                }
                .accessibilityLabel(model.isSaving ? "Сохранение" : "Сохранить")
                .disabled(model.isLoading || model.isSaving)
            }

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
                            .focused($focusedField, equals: .name)

                        TextField("Штрихкод", text: $model.barcode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .barcode)

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
        }
        .appScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .disabled(model.isLoading || model.isSaving)
        .task {
            await model.loadForEditing()
        }
        .onDisappear {
            focusedField = nil
            guard let onDismissed else {
                return
            }
            Task { @MainActor in
                await Task.yield()
                onDismissed(didSave)
            }
        }
    }

    private func decimalField(_ title: String, text: Binding<String>, field: EditorField) -> some View {
        TextField(title, text: EditableDecimal.binding(text))
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: field)
    }
}

private enum EditorField: Hashable {
    case name
    case barcode
    case baseAmount
    case calories
    case protein
    case fat
    case carbs
}
