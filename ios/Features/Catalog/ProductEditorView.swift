import OSLog
import SwiftUI

struct ProductEditorView: View {
    private static let logger = Logger(subsystem: "com.caloriestracker.ios", category: "ProductEditor")

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
        .navigationTitle(model.productID == nil ? "Новый продукт" : "Редактировать продукт")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isLoading || model.isSaving)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Self.logger.notice("action=product_save_tapped focused_field=\(focusedField?.diagnosticName ?? "none", privacy: .public)")
                    Self.logger.notice("focus=editor_resign_before_save")
                    focusedField = nil
                    Task {
                        let didSave = await model.save()
                        Self.logger.notice("action=product_save_finished success=\(didSave)")
                        if didSave {
                            self.didSave = true
                            if let onSaved {
                                Self.logger.notice("navigation=editor_save_return_requested")
                                onSaved()
                            } else {
                                router.catalogPath = []
                            }
                        }
                    }
                } label: {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .accessibilityLabel(model.isSaving ? "Сохранение" : "Сохранить")
                .disabled(model.isLoading || model.isSaving)
            }
        }
        .task {
            Self.logger.debug("lifecycle=editor_load_started")
            await model.loadForEditing()
            Self.logger.debug("lifecycle=editor_load_finished")
        }
        .onAppear {
            Self.logger.notice("lifecycle=editor_appear")
        }
        .onDisappear {
            Self.logger.notice("lifecycle=editor_disappear focused_field=\(focusedField?.diagnosticName ?? "none", privacy: .public)")
            focusedField = nil
            guard let onDismissed else {
                return
            }
            Task { @MainActor in
                await Task.yield()
                Self.logger.notice("lifecycle=editor_dismissed_callback")
                onDismissed(didSave)
            }
        }
        .onChange(of: focusedField) { previousField, currentField in
            Self.logger.notice("focus=editor_changed previous=\(previousField?.diagnosticName ?? "none", privacy: .public) current=\(currentField?.diagnosticName ?? "none", privacy: .public)")
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

    var diagnosticName: String {
        switch self {
        case .name:
            "name"
        case .barcode:
            "barcode"
        case .baseAmount:
            "base_amount"
        case .calories:
            "calories"
        case .protein:
            "protein"
        case .fat:
            "fat"
        case .carbs:
            "carbs"
        }
    }
}
