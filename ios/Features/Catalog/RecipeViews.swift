import Combine
import SwiftUI

struct RecipeListView: View {
    let onSelect: (UUID, FoodSelectionAmountDefault?) -> Void
    let mode: RecipeListMode

    @State private var model: RecipeListViewModel
    @Binding private var searchText: String
    @State private var quickAddingRecipeID: UUID?

    init(
        recipeService: RecipeService,
        diaryService: DiaryService?,
        mode: RecipeListMode,
        onSelect: @escaping (UUID, FoodSelectionAmountDefault?) -> Void,
        searchText: Binding<String>,
    ) {
        self.onSelect = onSelect
        self.mode = mode
        _model = State(initialValue: RecipeListViewModel(recipeService: recipeService, diaryService: diaryService))
        _searchText = searchText
    }

    var body: some View {
        recipeList
            .appPlainListStyle()
        .task(id: searchText) {
            await model.load(matching: searchText)
        }
    }

    private var recipeList: some View {
        List {
            if model.isLoading && model.recipes.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if model.recipes.isEmpty, model.errorMessage == nil {
                ContentUnavailableView(
                    "У вас пока нет рецептов",
                    systemImage: "book.closed",
                    description: Text("Создайте первый рецепт с помощью кнопки выше."),
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(model.recipes) { item in
                    switch mode {
                    case .management:
                        NavigationLink(value: CatalogRoute.recipe(item.id)) {
                            RecipeListRow(item: item)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await model.softDelete(recipeID: item.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Удалить")
                        }
                        .catalogListRow()
                    case let .selection(context):
                        if let selectionDisplay = model.selectionDisplay(for: item) {
                            let defaultValue = selectionDisplay.defaultValue
                            let source = FoodSourceReference(sourceType: .recipe, sourceID: item.recipe.id)
                            HStack(spacing: 12) {
                                Button {
                                    onSelect(item.recipe.id, defaultValue)
                                } label: {
                                    HStack(spacing: 0) {
                                        RecipeListRow(item: item, selectionDisplay: selectionDisplay)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                                if isQuickAdding(source: source, context: context) {
                                    ProgressView()
                                        .frame(minWidth: 44, minHeight: 44)
                                } else {
                                    Button {
                                        Task { @MainActor in
                                            await quickAdd(
                                                source: source,
                                                recipeID: item.recipe.id,
                                                defaultValue: defaultValue,
                                                context: context,
                                            )
                                        }
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title2)
                                    }
                                    .buttonStyle(.borderless)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel("Добавить \(item.recipe.name)")
                                    .disabled(context.quickAddState?.isInProgress == true)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .catalogListRow()
                        } else {
                            Button {
                                onSelect(item.recipe.id, nil)
                            } label: {
                                HStack(spacing: 0) {
                                    RecipeListRow(item: item)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .catalogListRow()
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
    }

    @MainActor
    private func quickAdd(
        source: FoodSourceReference,
        recipeID: UUID,
        defaultValue: FoodSelectionAmountDefault,
        context: FoodSelectionContext,
    ) async {
        let quickAddState = context.quickAddState
        if let quickAddState {
            guard quickAddState.begin(for: source) else {
                return
            }
        } else {
            quickAddingRecipeID = recipeID
        }
        defer {
            if let quickAddState {
                quickAddState.finish(for: source)
            } else {
                quickAddingRecipeID = nil
            }
        }

        do {
            try await context.onQuickAddRecipe(recipeID, defaultValue)
        } catch {
            model.errorMessage = catalogQuickAddErrorMessage(
                error,
                fallback: "Не удалось добавить запись.",
            )
        }
    }

    private func isQuickAdding(source: FoodSourceReference, context: FoodSelectionContext) -> Bool {
        context.quickAddState?.activeSource == source || quickAddingRecipeID == source.sourceID
    }
}

private struct RecipeListRow: View {
    let item: RecipeListItem
    let selectionDisplay: FoodSelectionDisplay?

    init(item: RecipeListItem, selectionDisplay: FoodSelectionDisplay? = nil) {
        self.item = item
        self.selectionDisplay = selectionDisplay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.recipe.name)
                .font(.headline)
            Group {
                if let selectionDisplay {
                    if let nutrition = selectionDisplay.nutrition {
                        Text("\(formattedNumber(selectionDisplay.defaultValue.amount)) \(selectionDisplay.defaultValue.unitLabel) · \(formattedNumber(nutrition.calories)) ккал")
                    } else {
                        Text("\(formattedNumber(selectionDisplay.defaultValue.amount)) \(selectionDisplay.defaultValue.unitLabel) · КБЖУ недоступно")
                    }
                } else {
                    Text(recipeOutputSummary(for: item.currentVersion))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct RecipeDetailView: View {
    let recipeID: UUID
    let router: AppRouter

    @State private var model: RecipeDetailViewModel

    init(recipeID: UUID, router: AppRouter, recipeService: RecipeService) {
        self.recipeID = recipeID
        self.router = router
        _model = State(initialValue: RecipeDetailViewModel(recipeID: recipeID, recipeService: recipeService))
    }

    var body: some View {
        VStack(spacing: 0) {
            AppTopNavigationHeader(title: model.details?.recipe.name ?? "Рецепт") {
                if model.details != nil {
                    HStack(spacing: AppStyle.controlSpacing) {
                        Button {
                            router.catalogPath.append(.recipeEditor(recipeID))
                        } label: {
                            AppCircularControl {
                                Image(systemName: "pencil")
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .accessibilityLabel("Редактировать")

                        Menu {
                            Button("Версии", systemImage: "clock.arrow.circlepath") {
                                router.catalogPath.append(.recipeVersionHistory(recipeID))
                            }
                            if model.details?.outdatedIngredientCount ?? 0 > 0 {
                                Button("Обновить ингредиенты", systemImage: "arrow.triangle.2.circlepath") {
                                    Task {
                                        await model.updateIngredients()
                                    }
                                }
                                .disabled(model.isUpdatingIngredients)
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

            content
        }
        .appScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await model.load()
        }
        .onChange(of: router.catalogPath) { oldPath, newPath in
            guard oldPath.last == .recipeEditor(recipeID),
                  newPath.last == .recipe(recipeID)
            else {
                return
            }
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
                Section("Текущая версия v\(details.currentVersion.versionNumber)") {
                    LabeledContent("Ингредиентов", value: "\(details.ingredients.count)")
                    if let cookedWeight = details.currentVersion.cookedWeight {
                        LabeledContent("Готовый вес", value: "\(formattedNumber(cookedWeight)) г")
                    }
                    if let servings = details.currentVersion.servingsCount {
                        LabeledContent("Количество порций", value: formattedNumber(servings))
                    }
                }

                Section("Пищевая ценность") {
                    RecipeNutritionRows(nutrition: details.currentVersion.totalNutrition)
                    if let per100 = details.nutritionPer100Grams {
                        LabeledContent("На 100 г", value: "\(formattedNumber(per100.calories)) ккал")
                    }
                    if let perServing = details.nutritionPerServing {
                        LabeledContent("На порцию", value: "\(formattedNumber(perServing.calories)) ккал")
                    }
                }

                if details.outdatedIngredientCount > 0 {
                    Section {
                        Label(
                            "Есть обновлённые ингредиенты: \(details.outdatedIngredientCount)",
                            systemImage: "arrow.triangle.2.circlepath",
                        )
                        .foregroundStyle(.orange)
                    }
                }

                Section("Ингредиенты") {
                    ForEach(details.ingredients) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.productName)
                            Text("\(formattedNumber(item.ingredient.amount)) \(recipeIngredientUnitLabel(item.ingredient.unitToken)) · v\(item.productVersion.versionNumber)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                "Рецепт недоступен",
                systemImage: "book.closed",
                description: model.errorMessage.map(Text.init),
            )
        }
    }
}

private struct RecipeNutritionRows: View {
    let nutrition: Nutrition

    var body: some View {
        LabeledContent("Калории", value: "\(formattedNumber(nutrition.calories)) ккал")
        LabeledContent("Белки", value: "\(formattedNumber(nutrition.protein)) г")
        LabeledContent("Жиры", value: "\(formattedNumber(nutrition.fat)) г")
        LabeledContent("Углеводы", value: "\(formattedNumber(nutrition.carbs)) г")
    }
}

struct RecipeEditorView: View {
    let router: AppRouter
    let productService: ProductService
    let recipeService: RecipeService
    let diaryService: DiaryService
    let onSaved: (@MainActor () -> Void)?

    @State private var model: RecipeEditorViewModel
    @State private var showsIngredientSelection = false
    @State private var ingredientQuickAddState = CatalogQuickAddState()
    @State private var selectedIngredientProduct: RecipeIngredientProductSelection?
    @State private var selectedIngredientRecipe: RecipeIngredientRecipeSelection?
    @State private var showsIngredientProductCreation = false
    @State private var showsIngredientRecipeCreation = false
    @State private var editingIngredient: RecipeIngredientEditorItem?
    @State private var isKeyboardVisible = false
    @State private var isIngredientSelectionPending = false
    @State private var isOutputUnitPickerPresented = false
    @FocusState private var focusedField: RecipeEditorField?

    init(
        recipeID: UUID?,
        router: AppRouter,
        productService: ProductService,
        recipeService: RecipeService,
        diaryService: DiaryService,
        onSaved: (@MainActor () -> Void)? = nil,
    ) {
        self.router = router
        self.productService = productService
        self.recipeService = recipeService
        self.diaryService = diaryService
        self.onSaved = onSaved
        _model = State(initialValue: RecipeEditorViewModel(recipeID: recipeID, recipeService: recipeService))
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            AppTopNavigationHeader(
                title: model.recipeID == nil ? "Новый рецепт" : "Редактировать рецепт",
            ) {
                Button {
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

            List {
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

                        HStack(alignment: .bottom, spacing: AppStyle.controlSpacing) {
                            recipeOutputAmountField(text: $model.outputAmountText)
                                .frame(maxWidth: .infinity)

                            VStack(spacing: 0) {
                                recipeOutputUnitPicker(selection: $model.outputUnit)
                                Divider()
                            }
                            .frame(width: RecipeEditorLayout.unitPickerWidth)
                        }
                        .listRowSeparator(.hidden)
                    }

                    FoodCompositionSection(
                        title: "Ингредиенты",
                        nutrition: model.preview?.totalNutrition ?? .zero,
                    ) {
                        ForEach(model.ingredients) { item in
                            RecipeIngredientListEntryRow(
                                item: item,
                                onSelect: {
                                    editingIngredient = item
                                },
                                onDelete: {
                                    model.removeIngredient(id: item.id)
                                    Task {
                                        await model.refreshCompositionPreview()
                                    }
                                },
                            )
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        }
                    } addRow: {
                        FoodCompositionAddRow {
                            requestIngredientSelection()
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))
                    }

                    Section("Пищевая ценность") {
                        if let preview = model.preview {
                            RecipeNutritionRows(nutrition: preview.totalNutrition)
                        } else {
                            Text("Добавьте ингредиенты и укажите выход рецепта.")
                                .foregroundStyle(.secondary)
                        }
                        if let previewErrorMessage = model.previewErrorMessage {
                            InlineErrorView(message: previewErrorMessage)
                        }
                    }
                }

                if let errorMessage = model.errorMessage {
                    Section {
                        InlineErrorView(message: errorMessage)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
        }
        .overlayPreferenceValue(RecipeOutputUnitAnchorPreferenceKey.self) { anchor in
            GeometryReader { proxy in
                if isOutputUnitPickerPresented, let anchor {
                    let frame = proxy[anchor]

                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isOutputUnitPickerPresented = false
                            }

                        recipeOutputUnitPickerMenu(selection: $model.outputUnit)
                            .offset(
                                x: frame.maxX - RecipeEditorLayout.unitMenuWidth,
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
        .onChange(of: model.cookedWeightText) { _, _ in
            model.refreshOutputPreview()
        }
        .onChange(of: model.servingsCountText) { _, _ in
            model.refreshOutputPreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            isKeyboardVisible = false
            presentIngredientSelectionIfPending()
        }
        .onDisappear {
            isIngredientSelectionPending = false
            isKeyboardVisible = false
        }
        .navigationDestination(isPresented: $showsIngredientSelection) {
            CatalogView(
                mode: .selection(
                    FoodSelectionContext(
                        quickAddState: ingredientQuickAddState,
                        onSelectProduct: { productID, defaultValue in
                            selectedIngredientProduct = RecipeIngredientProductSelection(
                                productID: productID,
                                defaultValue: defaultValue,
                            )
                        },
                        onSelectRecipe: { recipeID, defaultValue in
                            selectedIngredientRecipe = RecipeIngredientRecipeSelection(
                                recipeID: recipeID,
                                defaultValue: defaultValue,
                            )
                        },
                        onQuickAddProduct: { productID, defaultValue in
                            try await model.quickAddIngredient(productID: productID, defaultValue: defaultValue)
                            showsIngredientSelection = false
                        },
                        onQuickAddRecipe: { recipeID, defaultValue in
                            try await model.quickAddRecipeComposition(recipeID: recipeID, defaultValue: defaultValue)
                            showsIngredientSelection = false
                        },
                        onCreateProduct: {
                            showsIngredientProductCreation = true
                        },
                        onCreateRecipe: {
                            showsIngredientRecipeCreation = true
                        },
                    ),
                ),
                router: router,
                productService: productService,
                recipeService: recipeService,
                diaryService: diaryService,
            )
            .navigationDestination(item: $selectedIngredientProduct) { selection in
                RecipeIngredientAmountDestination(
                    productID: selection.productID,
                    selectionDefault: selection.defaultValue,
                    recipeService: recipeService,
                ) { draft, productName in
                    await model.appendIngredient(draft, productName: productName)
                    selectedIngredientProduct = nil
                    showsIngredientSelection = false
                }
            }
            .navigationDestination(item: $selectedIngredientRecipe) { selection in
                RecipeIngredientRecipeAmountDestination(
                    recipeID: selection.recipeID,
                    selectionDefault: selection.defaultValue,
                    recipeService: recipeService,
                ) { drafts in
                    Task {
                        if await model.addIngredients(drafts) {
                            selectedIngredientRecipe = nil
                            showsIngredientSelection = false
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showsIngredientProductCreation) {
                ProductEditorView(
                    productID: nil,
                    router: router,
                    productService: productService,
                    onSaved: {
                        showsIngredientProductCreation = false
                    },
                )
            }
            .navigationDestination(isPresented: $showsIngredientRecipeCreation) {
                RecipeEditorView(
                    recipeID: nil,
                    router: router,
                    productService: productService,
                    recipeService: recipeService,
                    diaryService: diaryService,
                    onSaved: {
                        showsIngredientRecipeCreation = false
                    },
                )
            }
        }
        .navigationDestination(item: $editingIngredient) { item in
            ExistingRecipeIngredientAmountDestination(
                draft: item.draft,
                recipeService: recipeService,
            ) { draft, productName in
                model.replaceIngredient(draft, productName: productName)
                editingIngredient = nil
                Task {
                    await model.refreshCompositionPreview()
                }
            }
        }
    }

    @MainActor
    private func requestIngredientSelection() {
        isIngredientSelectionPending = true
        focusedField = nil

        if !isKeyboardVisible {
            presentIngredientSelectionIfPending()
        }
    }

    @MainActor
    private func presentIngredientSelectionIfPending() {
        guard isIngredientSelectionPending else {
            return
        }

        isIngredientSelectionPending = false
        showsIngredientSelection = true
    }

    private func recipeOutputAmountField(text: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppStyle.controlSpacing) {
                Text("Количество")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                TextField("", text: EditableDecimal.binding(text))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 44, maxWidth: 120, alignment: .trailing)
                    .focused($focusedField, equals: .outputAmount)
                    .accessibilityLabel("Количество")
            }
            .frame(height: AppStyle.controlHeight)
            Divider()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = .outputAmount
        }
    }

    private func recipeOutputUnitPicker(selection: Binding<RecipeDiaryUnit>) -> some View {
        Button {
            focusedField = nil
            isOutputUnitPickerPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(recipeOutputUnitLabel(selection.wrappedValue))
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(
            width: RecipeEditorLayout.unitPickerWidth,
            height: AppStyle.controlHeight,
            alignment: .trailing,
        )
        .contentShape(Rectangle())
        .anchorPreference(key: RecipeOutputUnitAnchorPreferenceKey.self, value: .bounds) { $0 }
        .accessibilityLabel("Единица")
        .accessibilityValue(recipeOutputUnitLabel(selection.wrappedValue))
    }

    private func recipeOutputUnitPickerMenu(selection: Binding<RecipeDiaryUnit>) -> some View {
        VStack(spacing: 0) {
            ForEach(RecipeDiaryUnit.allCases, id: \.self) { unit in
                Button {
                    selection.wrappedValue = unit
                    isOutputUnitPickerPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Text(recipeOutputUnitLabel(unit))
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

                if unit != RecipeDiaryUnit.allCases.last {
                    Divider()
                }
            }
        }
        .frame(width: RecipeEditorLayout.unitMenuWidth)
        .background(AppStyle.controlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(
            color: AppStyle.controlShadowColor,
            radius: AppStyle.controlShadowRadius,
            y: AppStyle.controlShadowY,
        )
    }

}

private struct RecipeIngredientListEntryRow: View {
    let item: RecipeIngredientEditorItem
    let onSelect: @MainActor () -> Void
    let onDelete: @MainActor () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                FoodCompositionEntryRow(
                    title: item.productName,
                    amount: item.draft.amount,
                    unitLabel: recipeIngredientTokenLabel(item.draft.unitToken),
                    calories: item.nutrition?.calories ?? 0,
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Удалить")
        }
    }
}

private enum RecipeEditorField: Hashable {
    case name
    case outputAmount
}

private enum RecipeEditorLayout {
    static let unitPickerWidth: CGFloat = 100
    static let unitMenuWidth: CGFloat = 132
}

private struct RecipeOutputUnitAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct RecipeVersionHistoryView: View {
    let recipeID: UUID

    @State private var model: RecipeVersionHistoryViewModel

    init(recipeID: UUID, recipeService: RecipeService) {
        self.recipeID = recipeID
        _model = State(initialValue: RecipeVersionHistoryViewModel(recipeID: recipeID, recipeService: recipeService))
    }

    var body: some View {
        List {
            if model.isLoading && model.versions.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else {
                ForEach(model.versions) { version in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Версия v\(version.versionNumber)")
                                .font(.body.weight(.medium))
                            if model.currentVersionID == version.id {
                                Text("Текущая")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.tint)
                            }
                        }
                        Text(version.createdAt, format: .dateTime.day().month().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(version.ingredients.count) ингред. · \(recipeOutputSummary(for: version))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            if let errorMessage = model.errorMessage {
                Section {
                    InlineErrorView(message: errorMessage)
                }
            }
        }
        .appPlainListStyle()
        .navigationTitle("Версии")
        .navigationBarTitleDisplayMode(.inline)
        .appNavigationChrome()
        .task {
            await model.load()
        }
    }
}

private struct RecipeIngredientProductSelection: Hashable, Identifiable {
    let productID: UUID
    let defaultValue: FoodSelectionAmountDefault?

    var id: UUID {
        productID
    }
}

private struct RecipeIngredientRecipeSelection: Hashable, Identifiable {
    let recipeID: UUID
    let defaultValue: FoodSelectionAmountDefault?

    var id: UUID {
        recipeID
    }
}

private struct RecipeIngredientAmountDestination: View {
    let productID: UUID
    let selectionDefault: FoodSelectionAmountDefault?
    let recipeService: RecipeService
    let onComplete: @MainActor (RecipeIngredientDraft, String) async -> Void

    @State private var source: RecipeIngredientSource?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let source {
                RecipeIngredientAmountView(
                    source: source,
                    selectionDefault: selectionDefault,
                    recipeService: recipeService,
                    onComplete: onComplete,
                )
            } else if let errorMessage {
                ContentUnavailableView(
                    "Продукт недоступен",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage),
                )
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                source = try await recipeService.ingredientSource(forProductID: productID)
            } catch {
                errorMessage = recipeErrorMessage(error, fallback: "Не удалось выбрать продукт.")
            }
        }
    }
}

private struct RecipeIngredientRecipeAmountDestination: View {
    let recipeID: UUID
    let selectionDefault: FoodSelectionAmountDefault?
    let recipeService: RecipeService
    let onComplete: ([RecipeIngredientDraft]) -> Void

    @State private var source: RecipeCompositionSource?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let source {
                RecipeCompositionAmountView(
                    source: source,
                    selectionDefault: selectionDefault,
                    recipeService: recipeService,
                    onComplete: onComplete,
                )
            } else if let errorMessage {
                ContentUnavailableView(
                    "Рецепт недоступен",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage),
                )
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                source = try await recipeService.compositionSource(forRecipeID: recipeID)
            } catch {
                errorMessage = recipeErrorMessage(error, fallback: "Не удалось выбрать рецепт.")
            }
        }
    }
}

private struct ExistingRecipeIngredientAmountDestination: View {
    let draft: RecipeIngredientDraft
    let recipeService: RecipeService
    let onComplete: @MainActor (RecipeIngredientDraft, String) async -> Void

    @State private var source: RecipeIngredientSource?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let source {
                RecipeIngredientAmountView(
                    source: source,
                    replacing: draft,
                    recipeService: recipeService,
                    onComplete: onComplete,
                )
            } else if let errorMessage {
                ContentUnavailableView(
                    "Ингредиент недоступен",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage),
                )
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                source = try await recipeService.ingredientSource(for: draft)
            } catch {
                errorMessage = recipeErrorMessage(error, fallback: "Не удалось загрузить ингредиент.")
            }
        }
    }
}

private struct RecipeIngredientAmountView: View {
    let source: RecipeIngredientSource
    let onComplete: @MainActor (RecipeIngredientDraft, String) async -> Void

    @State private var model: RecipeIngredientAmountViewModel
    @State private var isCompleting = false
    @FocusState private var amountIsFocused: Bool

    init(
        source: RecipeIngredientSource,
        replacing: RecipeIngredientDraft? = nil,
        selectionDefault: FoodSelectionAmountDefault? = nil,
        recipeService: RecipeService,
        onComplete: @escaping @MainActor (RecipeIngredientDraft, String) async -> Void,
    ) {
        self.source = source
        self.onComplete = onComplete
        _model = State(
            initialValue: RecipeIngredientAmountViewModel(
                source: source,
                replacing: replacing,
                selectionDefault: selectionDefault,
                recipeService: recipeService,
            ),
        )
    }

    var body: some View {
        @Bindable var model = model

        AmountEditorView(
            title: source.productName,
            isLoading: false,
            isAvailable: true,
            preview: model.preview,
            previewErrorMessage: model.previewErrorMessage,
            errorMessage: model.errorMessage,
            unavailableTitle: "Продукт недоступен",
            unavailableSystemImage: "shippingbox",
            amountText: $model.amountText,
            selectedUnitToken: $model.selectedUnitToken,
            unitOptions: source.unitOptions.map { option in
                AmountUnitOption(token: option.token, label: recipeIngredientOptionLabel(option))
            },
            amountIsFocused: amountIsFocused,
            amountFocus: $amountIsFocused,
            autoFocusAmount: true,
            actionTitle: "Добавить",
            isSaving: isCompleting,
            headerTrailing: {
                EmptyView()
            },
            onConfirm: {
                guard !isCompleting, let draft = model.makeDraft() else {
                    return
                }

                amountIsFocused = false
                isCompleting = true
                Task { @MainActor in
                    await onComplete(draft, source.productName)
                }
            },
        )
        .onAppear {
            model.refreshPreview()
        }
        .onChange(of: model.amountText) { _, _ in
            model.refreshPreview()
        }
        .onChange(of: model.selectedUnitToken) { _, _ in
            model.refreshPreview()
        }
    }
}

private struct RecipeCompositionAmountView: View {
    let source: RecipeCompositionSource
    let onComplete: ([RecipeIngredientDraft]) -> Void

    @State private var model: RecipeCompositionAmountViewModel
    @FocusState private var amountIsFocused: Bool

    init(
        source: RecipeCompositionSource,
        selectionDefault: FoodSelectionAmountDefault? = nil,
        recipeService: RecipeService,
        onComplete: @escaping ([RecipeIngredientDraft]) -> Void,
    ) {
        self.source = source
        self.onComplete = onComplete
        _model = State(
            initialValue: RecipeCompositionAmountViewModel(
                source: source,
                selectionDefault: selectionDefault,
                recipeService: recipeService,
            ),
        )
    }

    var body: some View {
        @Bindable var model = model

        AmountEditorView(
            title: source.recipeName,
            isLoading: false,
            isAvailable: true,
            preview: model.preview,
            previewErrorMessage: model.previewErrorMessage,
            errorMessage: model.errorMessage,
            unavailableTitle: "Рецепт недоступен",
            unavailableSystemImage: "book.closed",
            amountText: $model.amountText,
            selectedUnitToken: $model.selectedUnitToken,
            unitOptions: source.outputUnits.map { option in
                AmountUnitOption(token: option.token, label: option.label)
            },
            amountIsFocused: amountIsFocused,
            amountFocus: $amountIsFocused,
            autoFocusAmount: true,
            actionTitle: "Добавить",
            isSaving: false,
            headerTrailing: {
                EmptyView()
            },
            onConfirm: {
                if let drafts = model.makeDrafts() {
                    amountIsFocused = false
                    onComplete(drafts)
                }
            },
        )
        .onAppear {
            model.refreshPreview()
        }
        .onChange(of: model.amountText) { _, _ in
            model.refreshPreview()
        }
        .onChange(of: model.selectedUnitToken) { _, _ in
            model.refreshPreview()
        }
    }
}

private func recipeOutputUnitLabel(_ unit: RecipeDiaryUnit) -> String {
    switch unit {
    case .grams:
        "г"
    case .serving:
        "порция"
    }
}

private func recipeOutputSummary(for version: RecipeVersion) -> String {
    var components = [
        "\(formattedNumber(version.totalNutrition.calories)) ккал",
        "Б \(formattedNumber(version.totalNutrition.protein)) · Ж \(formattedNumber(version.totalNutrition.fat)) · У \(formattedNumber(version.totalNutrition.carbs))",
    ]
    if let cookedWeight = version.cookedWeight {
        components.append("\(formattedNumber(cookedWeight)) г")
    }
    if let servings = version.servingsCount {
        components.append("\(formattedNumber(servings)) порц.")
    }
    return components.joined(separator: " · ")
}

private func recipeIngredientOptionLabel(_ option: RecipeIngredientUnitOption) -> String {
    switch option.kind {
    case let .base(unit):
        unit.russianLabel
    }
}

private func recipeIngredientTokenLabel(_ token: String) -> String {
    ProductBaseUnit(rawValue: token)?.russianLabel ?? "—"
}

private func recipeIngredientUnitLabel(_ token: String) -> String {
    ProductBaseUnit(rawValue: token)?.russianLabel ?? "—"
}
