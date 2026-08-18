import SwiftUI

struct RecipeListView: View {
    let onSelect: (UUID) -> Void
    let onQuickAddComplete: @MainActor () -> Void
    let onAdd: () -> Void
    let allowsManagementActions: Bool
    let selectionContext: DiaryContext?

    @State private var model: RecipeListViewModel
    @State private var searchText = ""

    init(
        recipeService: RecipeService,
        diaryService: DiaryService?,
        selectionContext: DiaryContext?,
        onSelect: @escaping (UUID) -> Void,
        onQuickAddComplete: @escaping @MainActor () -> Void,
        onAdd: @escaping () -> Void,
        allowsManagementActions: Bool,
    ) {
        self.onSelect = onSelect
        self.onQuickAddComplete = onQuickAddComplete
        self.onAdd = onAdd
        self.allowsManagementActions = allowsManagementActions
        self.selectionContext = selectionContext
        _model = State(initialValue: RecipeListViewModel(recipeService: recipeService, diaryService: diaryService))
    }

    var body: some View {
        List {
            if model.isLoading && model.recipes.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if model.recipes.isEmpty, model.errorMessage == nil {
                ContentUnavailableView(
                    "У вас пока нет рецептов",
                    systemImage: "book.closed",
                    description: Text("Создайте первый рецепт с помощью кнопки выше."),
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(model.recipes) { item in
                    if allowsManagementActions {
                        NavigationLink(value: CatalogRoute.recipe(item.id)) {
                            RecipeListRow(item: item)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task {
                                    await model.softDelete(recipeID: item.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Удалить")
                        }
                    } else {
                        if let defaultValue = model.selectionDefault(for: item) {
                            HStack(spacing: 12) {
                                Button {
                                    onSelect(item.recipe.id)
                                } label: {
                                    RecipeListRow(item: item, selectionDefault: defaultValue)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary)
                                .contentShape(Rectangle())
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if model.quickAddingRecipeID == item.recipe.id {
                                    ProgressView()
                                        .frame(minWidth: 44, minHeight: 44)
                                } else {
                                    Button {
                                        guard let selectionContext else {
                                            return
                                        }
                                        Task {
                                            if await model.quickAdd(
                                                recipeID: item.recipe.id,
                                                context: selectionContext,
                                                defaultValue: defaultValue,
                                            ) {
                                                onQuickAddComplete()
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                    }
                                    .buttonStyle(.borderless)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel("Добавить \(item.recipe.name)")
                                }
                            }
                        } else {
                            Button {
                                onSelect(item.recipe.id)
                            } label: {
                                RecipeListRow(item: item)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
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
                    onAdd()
                } label: {
                    Label("Создать рецепт", systemImage: "plus")
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
        .onChange(of: searchText) { _, query in
            Task {
                await model.load(matching: query)
            }
        }
    }
}

private struct RecipeListRow: View {
    let item: RecipeListItem
    let selectionDefault: DiarySelectionAmountDefault?

    init(item: RecipeListItem, selectionDefault: DiarySelectionAmountDefault? = nil) {
        self.item = item
        self.selectionDefault = selectionDefault
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.recipe.name)
                .font(.body.weight(.medium))
            Group {
                if let selectionDefault {
                    Text("\(formattedNumber(selectionDefault.amount)) \(selectionDefault.unitLabel) · \(formattedNumber(item.currentVersion.totalNutrition.calories)) ккал")
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
        content
            .navigationTitle(model.details?.recipe.name ?? "Рецепт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.details != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            router.catalogPath.append(.recipeEditor(recipeID))
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel("Редактировать")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
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
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .task {
                await model.load()
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
                            Text("\(formattedNumber(item.ingredient.amount)) \(recipeIngredientUnitLabel(item.ingredient.unitToken, version: item.productVersion)) · v\(item.productVersion.versionNumber)")
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
    let onSaved: (@MainActor () -> Void)?

    @State private var model: RecipeEditorViewModel
    @State private var showsIngredientSelection = false
    @State private var editingIngredient: RecipeIngredientEditorItem?
    @FocusState private var focusedField: RecipeEditorField?

    init(
        recipeID: UUID?,
        router: AppRouter,
        productService: ProductService,
        recipeService: RecipeService,
        onSaved: (@MainActor () -> Void)? = nil,
    ) {
        self.router = router
        self.productService = productService
        self.recipeService = recipeService
        self.onSaved = onSaved
        _model = State(initialValue: RecipeEditorViewModel(recipeID: recipeID, recipeService: recipeService))
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
                    TextField("Готовый вес", text: $model.cookedWeightText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .cookedWeight)
                    TextField("Количество порций", text: $model.servingsCountText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .servings)
                }

                Section("Ингредиенты") {
                    ForEach(model.ingredients) { item in
                        Button {
                            editingIngredient = item
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.productName)
                                    .foregroundStyle(.primary)
                                Text("\(formattedNumber(item.draft.amount)) \(recipeIngredientTokenLabel(item.draft.unitToken))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        model.removeIngredients(at: offsets)
                        Task {
                            await model.refreshPreview()
                        }
                    }

                    Button {
                        showsIngredientSelection = true
                    } label: {
                        Label("Добавить ингредиент", systemImage: "plus")
                    }
                }

                Section("Пищевая ценность") {
                    if let preview = model.preview {
                        RecipeNutritionRows(nutrition: preview)
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
        .navigationTitle(model.recipeID == nil ? "Новый рецепт" : "Редактировать рецепт")
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
        .onChange(of: model.cookedWeightText) { _, _ in
            Task {
                await model.refreshPreview()
            }
        }
        .onChange(of: model.servingsCountText) { _, _ in
            Task {
                await model.refreshPreview()
            }
        }
        .sheet(isPresented: $showsIngredientSelection) {
            RecipeIngredientPickerView(
                productService: productService,
                recipeService: recipeService,
            ) { draft, productName in
                model.addIngredient(draft, productName: productName)
                Task {
                    await model.refreshPreview()
                }
            }
        }
        .sheet(item: $editingIngredient) { item in
            ExistingRecipeIngredientEditorSheet(
                draft: item.draft,
                recipeService: recipeService,
            ) { draft, productName in
                model.replaceIngredient(draft, productName: productName)
                Task {
                    await model.refreshPreview()
                }
            }
        }
    }
}

private enum RecipeEditorField: Hashable {
    case cookedWeight
    case servings
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
        .listStyle(.plain)
        .navigationTitle("Версии")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
        }
    }
}

private struct RecipeIngredientPickerView: View {
    let recipeService: RecipeService
    let onComplete: (RecipeIngredientDraft, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: RecipeIngredientSelectionViewModel
    @State private var searchText = ""
    @State private var selectedSource: RecipeIngredientSource?
    @State private var sourceErrorMessage: String?

    init(
        productService: ProductService,
        recipeService: RecipeService,
        onComplete: @escaping (RecipeIngredientDraft, String) -> Void,
    ) {
        self.recipeService = recipeService
        self.onComplete = onComplete
        _model = State(initialValue: RecipeIngredientSelectionViewModel(productService: productService))
    }

    var body: some View {
        NavigationStack {
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
                        description: Text("Сначала создайте продукт во вкладке «Продукты»"),
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(model.products) { item in
                        Button {
                            Task {
                                do {
                                    selectedSource = try await recipeService.ingredientSource(forProductID: item.product.id)
                                } catch {
                                    sourceErrorMessage = recipeErrorMessage(error, fallback: "Не удалось выбрать продукт.")
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.product.name)
                                    .foregroundStyle(.primary)
                                Text("\(formattedNumber(item.currentVersion.baseAmount)) \(item.currentVersion.baseUnit.russianLabel) · \(formattedNumber(item.currentVersion.nutrition.calories)) ккал")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let errorMessage = model.errorMessage ?? sourceErrorMessage {
                    Section {
                        InlineErrorView(message: errorMessage)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Ингредиент")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Поиск продукта")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
            .task {
                await model.load(matching: searchText)
            }
            .onChange(of: searchText) { _, query in
                Task {
                    await model.load(matching: query)
                }
            }
            .navigationDestination(item: $selectedSource) { source in
                RecipeIngredientAmountView(source: source, recipeService: recipeService) { draft, productName in
                    onComplete(draft, productName)
                    dismiss()
                }
            }
        }
    }
}

private struct ExistingRecipeIngredientEditorSheet: View {
    let draft: RecipeIngredientDraft
    let recipeService: RecipeService
    let onComplete: (RecipeIngredientDraft, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var source: RecipeIngredientSource?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let source {
                    RecipeIngredientAmountView(
                        source: source,
                        replacing: draft,
                        recipeService: recipeService,
                    ) { updatedDraft, productName in
                        onComplete(updatedDraft, productName)
                        dismiss()
                    }
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
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
}

private struct RecipeIngredientAmountView: View {
    let source: RecipeIngredientSource
    let onComplete: (RecipeIngredientDraft, String) -> Void

    @State private var model: RecipeIngredientAmountViewModel
    @FocusState private var amountIsFocused: Bool

    init(
        source: RecipeIngredientSource,
        replacing: RecipeIngredientDraft? = nil,
        recipeService: RecipeService,
        onComplete: @escaping (RecipeIngredientDraft, String) -> Void,
    ) {
        self.source = source
        self.onComplete = onComplete
        _model = State(
            initialValue: RecipeIngredientAmountViewModel(
                source: source,
                replacing: replacing,
                recipeService: recipeService,
            ),
        )
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 20) {
            Text(source.productName)
                .font(.title2.weight(.semibold))

            if let preview = model.preview {
                VStack(alignment: .leading, spacing: 6) {
                    Text("КБЖУ")
                        .font(.headline)
                    Text("\(formattedNumber(preview.calories)) ккал")
                        .font(.title3.weight(.semibold))
                    Text("Б \(formattedNumber(preview.protein)) · Ж \(formattedNumber(preview.fat)) · У \(formattedNumber(preview.carbs))")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Введите количество, чтобы увидеть КБЖУ.")
                    .foregroundStyle(.secondary)
            }

            if let previewErrorMessage = model.previewErrorMessage {
                InlineErrorView(message: previewErrorMessage)
            }
            if let errorMessage = model.errorMessage {
                InlineErrorView(message: errorMessage)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Количество")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                TextField("Количество", text: $model.amountText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($amountIsFocused)

                Picker("Единица", selection: $model.selectedUnitToken) {
                    ForEach(source.unitOptions) { option in
                        Text(recipeIngredientOptionLabel(option)).tag(option.token)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Button("Добавить") {
                    if let draft = model.makeDraft() {
                        amountIsFocused = false
                        onComplete(draft, source.productName)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    amountIsFocused = false
                }
            }
        }
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
    case let .serving(name):
        name
    }
}

private func recipeIngredientTokenLabel(_ token: String) -> String {
    if let baseUnit = ProductBaseUnit(rawValue: token) {
        return baseUnit.russianLabel
    }
    return "порция"
}

private func recipeIngredientUnitLabel(_ token: String, version: ProductVersion) -> String {
    if let baseUnit = ProductBaseUnit(rawValue: token) {
        return baseUnit.russianLabel
    }
    let prefix = "serving:"
    guard token.hasPrefix(prefix),
          let identifier = UUID(uuidString: String(token.dropFirst(prefix.count))),
          let unit = version.servingUnits.first(where: { $0.id == identifier })
    else {
        return "порция"
    }
    return unit.name
}
