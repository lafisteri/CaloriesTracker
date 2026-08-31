import SwiftUI

struct ProductEditorView: View {
    let router: AppRouter
    let onSaved: (@MainActor () -> Void)?
    let onDismissed: (@MainActor (Bool) -> Void)?

    @State private var model: ProductEditorViewModel
    @FocusState private var focusedField: ProductEditorField?
    @State private var didSave = false
    @State private var isUnitPickerPresented = false

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
                    ProductFormLayout(
                        mode: model.productID == nil ? .create(editingFields) : .edit(editingFields),
                        values: ProductFormValues(
                            name: model.name,
                            barcode: model.barcode.isEmpty ? nil : model.barcode,
                            baseAmount: model.baseAmount,
                            baseUnit: model.baseUnit,
                            calories: model.calories,
                            protein: model.protein,
                            fat: model.fat,
                            carbs: model.carbs,
                            versionNumber: model.currentVersionNumber,
                        ),
                        fieldErrors: model.fieldErrors,
                    )
                }

                if let errorMessage = model.errorMessage {
                    Section {
                        InlineErrorView(message: errorMessage)
                    }
                }
            }
        }
        .overlayPreferenceValue(UnitPickerAnchorPreferenceKey.self) { anchor in
            GeometryReader { proxy in
                if isUnitPickerPresented, let anchor {
                    let frame = proxy[anchor]

                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isUnitPickerPresented = false
                            }

                        unitPickerMenu(selection: $model.baseUnit)
                            .offset(
                                x: frame.maxX - ProductEditorLayout.unitMenuWidth,
                                y: frame.maxY + AppStyle.controlSpacing,
                            )
                    }
                    .zIndex(1)
                }
            }
        }
        .appScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .disabled(model.isLoading || model.isSaving)
        .task {
            await model.loadForEditing()
        }
        .onChange(of: model.name) { _, _ in
            model.clearFieldError(for: .name)
        }
        .onChange(of: model.baseAmount) { _, _ in
            model.clearFieldError(for: .baseAmount)
        }
        .onChange(of: model.calories) { _, _ in
            model.clearFieldError(for: .calories)
        }
        .onChange(of: model.protein) { _, _ in
            model.clearFieldError(for: .protein)
        }
        .onChange(of: model.fat) { _, _ in
            model.clearFieldError(for: .fat)
        }
        .onChange(of: model.carbs) { _, _ in
            model.clearFieldError(for: .carbs)
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

    private func unitPickerMenu(selection: Binding<ProductBaseUnit>) -> some View {
        VStack(spacing: 0) {
            ForEach(ProductBaseUnit.allCases, id: \.self) { unit in
                Button {
                    selection.wrappedValue = unit
                    isUnitPickerPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Text(unit.russianLabel)
                        Spacer(minLength: 0)
                        if selection.wrappedValue == unit {
                            Image(systemName: "checkmark")
                        }
                    }
                    .frame(height: AppStyle.controlHeight)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                if unit != ProductBaseUnit.allCases.last {
                    Divider()
                }
            }
        }
        .frame(width: ProductEditorLayout.unitMenuWidth)
        .background(AppStyle.controlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(
            color: AppStyle.controlShadowColor,
            radius: AppStyle.controlShadowRadius,
            y: AppStyle.controlShadowY,
        )
    }

    private var editingFields: ProductFormEditing {
        ProductFormEditing(
            name: $model.name,
            baseAmount: $model.baseAmount,
            baseUnit: $model.baseUnit,
            calories: $model.calories,
            protein: $model.protein,
            fat: $model.fat,
            carbs: $model.carbs,
            focusedField: $focusedField,
            onUnitPickerRequested: {
                focusedField = nil
                isUnitPickerPresented = true
            },
        )
    }
}

enum ProductEditorField: Hashable {
    case name
    case baseAmount
    case calories
    case protein
    case fat
    case carbs
}

private enum ProductEditorLayout {
    static let unitPickerWidth: CGFloat = 100
    static let unitMenuWidth: CGFloat = 132
}

enum ProductFormMode {
    case create(ProductFormEditing)
    case edit(ProductFormEditing)
    case readOnly

    var editingFields: ProductFormEditing? {
        switch self {
        case let .create(fields), let .edit(fields):
            fields
        case .readOnly:
            nil
        }
    }
}

struct ProductFormEditing {
    let name: Binding<String>
    let baseAmount: Binding<String>
    let baseUnit: Binding<ProductBaseUnit>
    let calories: Binding<String>
    let protein: Binding<String>
    let fat: Binding<String>
    let carbs: Binding<String>
    let focusedField: FocusState<ProductEditorField?>.Binding
    let onUnitPickerRequested: @MainActor () -> Void
}

struct ProductFormValues {
    let name: String
    let barcode: String?
    let baseAmount: String
    let baseUnit: ProductBaseUnit
    let calories: String
    let protein: String
    let fat: String
    let carbs: String
    let versionNumber: Int?

    init(details: ProductDetails) {
        name = details.product.name
        barcode = details.product.barcode
        baseAmount = formattedNumber(details.currentVersion.baseAmount)
        baseUnit = details.currentVersion.baseUnit
        calories = formattedNumber(details.currentVersion.nutrition.calories)
        protein = formattedNumber(details.currentVersion.nutrition.protein)
        fat = formattedNumber(details.currentVersion.nutrition.fat)
        carbs = formattedNumber(details.currentVersion.nutrition.carbs)
        versionNumber = details.currentVersion.versionNumber
    }

    init(
        name: String,
        barcode: String?,
        baseAmount: String,
        baseUnit: ProductBaseUnit,
        calories: String,
        protein: String,
        fat: String,
        carbs: String,
        versionNumber: Int?,
    ) {
        self.name = name
        self.barcode = barcode
        self.baseAmount = baseAmount
        self.baseUnit = baseUnit
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.versionNumber = versionNumber
    }
}

struct ProductFormLayout: View {
    let mode: ProductFormMode
    let values: ProductFormValues
    let fieldErrors: [ProductEditorField: String]

    var body: some View {
        Section {
            nameRow
            barcodeRow
            amountAndUnitRow
        }

        Section(nutritionTitle) {
            nutritionRow("Калории", value: values.calories, binding: editingFields?.calories, field: .calories)
            nutritionRow("Белки", value: values.protein, binding: editingFields?.protein, field: .protein)
            nutritionRow("Жиры", value: values.fat, binding: editingFields?.fat, field: .fat)
            nutritionRow("Углеводы", value: values.carbs, binding: editingFields?.carbs, field: .carbs)
        }
    }

    private var editingFields: ProductFormEditing? {
        mode.editingFields
    }

    private var nutritionTitle: String {
        guard let versionNumber = values.versionNumber else {
            return "Пищевая ценность"
        }
        return "Пищевая ценность (v\(versionNumber))"
    }

    @ViewBuilder
    private var nameRow: some View {
        if let fields = editingFields {
            editorRow(errorFor: .name) {
                TextField("Название", text: fields.name)
                    .textInputAutocapitalization(.sentences)
                    .focused(fields.focusedField, equals: .name)
            }
        } else {
            readOnlyText(values.name)
        }
    }

    @ViewBuilder
    private var barcodeRow: some View {
        if editingFields == nil, let barcode = values.barcode {
            readOnlyText(barcode)
        }
    }

    @ViewBuilder
    private var amountAndUnitRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: AppStyle.controlSpacing) {
                if let fields = editingFields {
                    amountField(text: fields.baseAmount, focusedField: fields.focusedField)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 0) {
                        unitPicker(fields: fields)
                        Divider()
                    }
                    .frame(width: ProductEditorLayout.unitPickerWidth)
                } else {
                    readOnlyAmountField(values.baseAmount)
                        .frame(maxWidth: .infinity)

                    readOnlyUnit(values.baseUnit.russianLabel)
                        .frame(width: ProductEditorLayout.unitPickerWidth)
                }
            }

            if editingFields != nil {
                fieldError(for: .baseAmount)
            }
        }
        .listRowSeparator(.hidden)
    }

    private func amountField(
        text: Binding<String>,
        focusedField: FocusState<ProductEditorField?>.Binding,
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppStyle.controlSpacing) {
                Text("Количество")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                decimalField("", text: text, field: .baseAmount, focusedField: focusedField)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 44, maxWidth: 120, alignment: .trailing)
                    .accessibilityLabel("Количество")
            }
            .frame(height: AppStyle.controlHeight)
            Divider()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField.wrappedValue = .baseAmount
        }
    }

    private func readOnlyAmountField(_ value: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppStyle.controlSpacing) {
                Text("Количество")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                Text(value)
                    .frame(minWidth: 44, maxWidth: 120, alignment: .trailing)
                    .accessibilityLabel("Количество")
            }
            .frame(height: AppStyle.controlHeight)
            Divider()
        }
    }

    private func unitPicker(fields: ProductFormEditing) -> some View {
        Button {
            fields.focusedField.wrappedValue = nil
            fields.onUnitPickerRequested()
        } label: {
            HStack(spacing: 4) {
                Text(fields.baseUnit.wrappedValue.russianLabel)
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(
            width: ProductEditorLayout.unitPickerWidth,
            height: AppStyle.controlHeight,
            alignment: .trailing,
        )
        .contentShape(Rectangle())
        .anchorPreference(key: UnitPickerAnchorPreferenceKey.self, value: .bounds) { $0 }
        .accessibilityLabel("Единица")
        .accessibilityValue(fields.baseUnit.wrappedValue.russianLabel)
    }

    private func readOnlyUnit(_ label: String) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .frame(
                    width: ProductEditorLayout.unitPickerWidth,
                    height: AppStyle.controlHeight,
                    alignment: .trailing,
                )
                .accessibilityLabel("Единица")
                .accessibilityValue(label)
            Divider()
        }
    }

    private func nutritionRow(
        _ title: String,
        value: String,
        binding: Binding<String>?,
        field: ProductEditorField,
    ) -> some View {
        editorRow(errorFor: field) {
            HStack(spacing: AppStyle.controlSpacing) {
                Text(title)
                Spacer(minLength: 0)

                if let binding, let focusedField = editingFields?.focusedField {
                    decimalField("", text: binding, field: field, focusedField: focusedField)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .accessibilityLabel(title)
                } else {
                    Text(value)
                        .frame(width: 120, alignment: .trailing)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingFields?.focusedField.wrappedValue = field
        }
    }

    private func decimalField(
        _ title: String,
        text: Binding<String>,
        field: ProductEditorField,
        focusedField: FocusState<ProductEditorField?>.Binding,
    ) -> some View {
        TextField(title, text: EditableDecimal.binding(text))
            .keyboardType(.decimalPad)
            .focused(focusedField, equals: field)
    }

    private func readOnlyText(_ value: String) -> some View {
        Text(value)
            .frame(maxWidth: .infinity, alignment: .leading)
            .standardProductFormSeparator()
    }

    @ViewBuilder
    private func editorRow<Content: View>(
        errorFor field: ProductEditorField,
        @ViewBuilder content: () -> Content,
    ) -> some View {
        if let message = fieldErrors[field] {
            content()
                .standardProductFormSeparator()
            InlineErrorView(message: message)
                .listRowSeparator(.hidden)
        } else {
            content()
                .standardProductFormSeparator()
        }
    }

    @ViewBuilder
    private func fieldError(for field: ProductEditorField) -> some View {
        if let message = fieldErrors[field] {
            InlineErrorView(message: message)
        }
    }
}

private extension View {
    func standardProductFormSeparator() -> some View {
        listRowSeparator(.visible, edges: .bottom)
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                dimensions[.leading]
            }
            .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                dimensions[.trailing]
            }
    }
}

private struct UnitPickerAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
