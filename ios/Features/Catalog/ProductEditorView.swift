import SwiftUI

struct ProductEditorView: View {
    let router: AppRouter
    let onSaved: (@MainActor () -> Void)?
    let onDismissed: (@MainActor (Bool) -> Void)?

    @State private var model: ProductEditorViewModel
    @FocusState private var focusedField: EditorField?
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
                    Section {
                        TextField("Название", text: $model.name)
                            .textInputAutocapitalization(.sentences)
                            .focused($focusedField, equals: .name)
                            .listRowSeparator(.visible, edges: .bottom)
                            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                                dimensions[.leading]
                            }
                            .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                                dimensions[.trailing]
                            }

                        // TextField("Штрихкод", text: $model.barcode)
                        //     .textInputAutocapitalization(.never)
                        //     .autocorrectionDisabled()
                        //     .focused($focusedField, equals: .barcode)

                        HStack(alignment: .bottom, spacing: AppStyle.controlSpacing) {
                            amountField(text: $model.baseAmount)
                                .frame(maxWidth: .infinity)

                            VStack(spacing: 0) {
                                unitPicker(selection: $model.baseUnit)
                                Divider()
                            }
                            .frame(width: ProductEditorLayout.unitPickerWidth)
                        }
                        .listRowSeparator(.hidden)
                    }

                    Section("Пищевая ценность") {
                        nutritionField("Калории", text: $model.calories, field: .calories)
                        nutritionField("Белки", text: $model.protein, field: .protein)
                        nutritionField("Жиры", text: $model.fat, field: .fat)
                        nutritionField("Углеводы", text: $model.carbs, field: .carbs)
                    }
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

    private func amountField(text: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppStyle.controlSpacing) {
                Text("Количество")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                decimalField("", text: text, field: .baseAmount)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 44, maxWidth: 120, alignment: .trailing)
                    .accessibilityLabel("Количество")
            }
            .frame(height: AppStyle.controlHeight)
            Divider()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = .baseAmount
        }
    }

    private func unitPicker(selection: Binding<ProductBaseUnit>) -> some View {
        Button {
            focusedField = nil
            isUnitPickerPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(selection.wrappedValue.russianLabel)
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
        .accessibilityValue(selection.wrappedValue.russianLabel)
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

    private func nutritionField(_ title: String, text: Binding<String>, field: EditorField) -> some View {
        HStack(spacing: AppStyle.controlSpacing) {
            Text(title)
            Spacer(minLength: 0)
            decimalField("", text: text, field: field)
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
                .accessibilityLabel(title)
        }
        .listRowSeparator(.visible, edges: .bottom)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading]
        }
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
            dimensions[.trailing]
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = field
        }
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

private enum ProductEditorLayout {
    static let unitPickerWidth: CGFloat = 100
    static let unitMenuWidth: CGFloat = 132
}

private struct UnitPickerAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
