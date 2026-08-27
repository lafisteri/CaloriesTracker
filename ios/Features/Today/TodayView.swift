import SwiftUI

struct TodayRootView: View {
    let router: AppRouter
    let diaryService: DiaryService
    let goalService: GoalService
    let productService: ProductService
    let recipeService: RecipeService
    let supabaseAuth: SupabaseAuthService?
    let syncStatus: SyncStatusStore?
    let syncOrchestrator: SyncOrchestrator?

    @State private var model: TodayViewModel
    @State private var draggedEntryID: UUID?
    @State private var quickAddState = CatalogQuickAddState()
    @State private var isSettingsPresented = false

    init(
        router: AppRouter,
        diaryService: DiaryService,
        goalService: GoalService,
        productService: ProductService,
        recipeService: RecipeService,
        supabaseAuth: SupabaseAuthService?,
        syncStatus: SyncStatusStore?,
        syncOrchestrator: SyncOrchestrator?,
    ) {
        self.router = router
        self.diaryService = diaryService
        self.goalService = goalService
        self.productService = productService
        self.recipeService = recipeService
        self.supabaseAuth = supabaseAuth
        self.syncStatus = syncStatus
        self.syncOrchestrator = syncOrchestrator
        _model = State(initialValue: TodayViewModel(diaryService: diaryService, goalService: goalService))
    }

    var body: some View {
        List {
            dateNavigation
                .listRowInsets(DateNavigatorLayout.listRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Section {
                if let day = model.day {
                    DailyNutritionSummary(nutrition: day.totalNutrition, calorieGoal: model.calorieGoal)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                } else {
                    ProgressView()
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                }
            } header: {
                Text("За день")
                    .textCase(nil)
            }

            if let day = model.day {
                ForEach(day.meals) { meal in
                    FoodCompositionSection(
                        title: meal.mealType.russianLabel,
                        nutrition: meal.totalNutrition,
                    ) {
                        ForEach(meal.entries) { entry in
                            DiaryListEntryRow(
                                entry: entry,
                                isDragging: draggedEntryID == entry.id,
                                onDragStarted: {
                                    draggedEntryID = entry.id
                                },
                                onDragEnded: {
                                    clearDraggedEntryID(entry.id)
                                },
                                onDelete: {
                                    Task {
                                        await model.delete(entryID: entry.id)
                                    }
                                },
                            )
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        }
                        .dropDestination(for: String.self) { identifiers, displayedTargetIndex in
                            guard let identifier = identifiers.first,
                                  let entryID = UUID(uuidString: identifier)
                            else {
                                return
                            }

                            move(
                                entryID: entryID,
                                to: meal.mealType,
                                displayedTargetIndex: displayedTargetIndex,
                            )
                            clearDraggedEntryID(entryID)
                        }

                    } addRow: {
                        FoodCompositionAddRow(
                            onAdd: {
                                router.todayPath.append(
                                    .catalogSelection(DiaryContext(day: model.selectedDay, meal: meal.mealType)),
                                )
                            },
                            onDrop: { entryID in
                                move(
                                    entryID: entryID,
                                    to: meal.mealType,
                                    displayedTargetIndex: meal.entries.count,
                                )
                                clearDraggedEntryID(entryID)
                            },
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                DiaryInlineErrorView(message: errorMessage)
                    .listRowSeparator(.hidden)
            }
        }
        .appPlainListStyle()
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await model.load()
        }
        .onAppear {
            Task {
                await model.load()
            }
        }
        .onChange(of: router.todayPath) { _, path in
            guard path.isEmpty else {
                return
            }
            Task {
                await model.load()
            }
        }
        .navigationDestination(for: TodayRoute.self) { route in
            switch route {
            case let .catalogSelection(context):
                CatalogView(
                    mode: .selection(foodSelectionContext(for: context)),
                    router: router,
                    productService: productService,
                    recipeService: recipeService,
                    diaryService: diaryService,
                )
            case let .amount(context, source, selectionDefault):
                DiaryAmountView(
                    mode: .create(context: context, source: source, selectionDefault: selectionDefault),
                    router: router,
                    diaryService: diaryService,
                )
            case let .entryEditor(entryID):
                DiaryAmountView(
                    mode: .edit(entryID: entryID),
                    router: router,
                    diaryService: diaryService,
                )
            case let .productEditor(context, _):
                ProductEditorView(
                    productID: nil,
                    router: router,
                    productService: productService,
                    onSaved: {
                        if let context {
                            router.todayPath = [.catalogSelection(context)]
                        } else {
                            router.todayPath = []
                        }
                    },
                )
            case let .productEditorForDiarySelection(productID, context):
                ProductEditorView(
                    productID: productID,
                    router: router,
                    productService: productService,
                    onSaved: {
                        router.requestCreateAmountSourceRefresh(
                            for: FoodSourceReference(sourceType: .product, sourceID: productID),
                        )
                        router.popToday(
                            ifTopIs: .productEditorForDiarySelection(productID: productID, context: context),
                        )
                    },
                    onDismissed: { didSave in
                        guard !didSave else {
                            return
                        }
                        router.amountFocusRestorationRevision += 1
                    },
                )
            case let .productEditorForEntryAmount(productID, entryID):
                ProductEditorView(
                    productID: productID,
                    router: router,
                    productService: productService,
                    onSaved: {
                        router.requestEntryProductRebase(entryID: entryID)
                        router.popToday(
                            ifTopIs: .productEditorForEntryAmount(productID: productID, entryID: entryID),
                        )
                    },
                    onDismissed: { didSave in
                        guard !didSave else {
                            return
                        }
                        router.amountFocusRestorationRevision += 1
                    },
                )
            case let .recipeEditor(context, recipeID):
                RecipeEditorView(
                    recipeID: recipeID,
                    router: router,
                    productService: productService,
                    recipeService: recipeService,
                    diaryService: diaryService,
                ) {
                    router.todayPath = [.catalogSelection(context)]
                }
            case let .productDetails(productID, context):
                ProductDetailView(
                    productID: productID,
                    router: router,
                    productService: productService,
                    presentation: .diarySelection(context),
                )
            case .recipeDetails:
                ContentUnavailableView("Этот экран пока недоступен", systemImage: "fork.knife")
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView(
                    goalService: goalService,
                    supabaseAuth: supabaseAuth,
                    syncStatus: syncStatus,
                    syncOrchestrator: syncOrchestrator,
                )
            }
        }
    }

    private func foodSelectionContext(for context: DiaryContext) -> FoodSelectionContext {
        FoodSelectionContext(
            quickAddState: quickAddState,
            onSelectProduct: { productID, selectionDefault in
                router.todayPath.append(
                    .amount(
                        context: context,
                        source: FoodSourceReference(sourceType: .product, sourceID: productID),
                        selectionDefault: selectionDefault,
                    ),
                )
            },
            onSelectRecipe: { recipeID, selectionDefault in
                router.todayPath.append(
                    .amount(
                        context: context,
                        source: FoodSourceReference(sourceType: .recipe, sourceID: recipeID),
                        selectionDefault: selectionDefault,
                    ),
                )
            },
            onQuickAddProduct: { productID, defaultValue in
                try await model.quickAdd(
                    context: context,
                    source: FoodSourceReference(sourceType: .product, sourceID: productID),
                    defaultValue: defaultValue,
                )
                router.todayPath = []
            },
            onQuickAddRecipe: { recipeID, defaultValue in
                try await model.quickAdd(
                    context: context,
                    source: FoodSourceReference(sourceType: .recipe, sourceID: recipeID),
                    defaultValue: defaultValue,
                )
                router.todayPath = []
            },
            onCreateProduct: {
                router.todayPath.append(.productEditor(context: context, prefilledBarcode: nil))
            },
            onCreateRecipe: {
                router.todayPath.append(.recipeEditor(context: context, recipeID: nil))
            },
        )
    }

    private var dateNavigation: some View {
        let isSelectedDayToday = model.selectedDay == .current()

        return HStack(spacing: DateNavigatorLayout.pairedControlSpacing) {
            DateNavigator(
                previousAccessibilityLabel: "Предыдущий день",
                nextAccessibilityLabel: "Следующий день",
                previousAction: {
                    Task {
                        await model.previousDay()
                    }
                },
                nextAction: {
                    Task {
                        await model.nextDay()
                    }
                },
                secondaryActionTitle: isSelectedDayToday ? nil : "Сегодня",
                secondaryAction: isSelectedDayToday ? nil : {
                    Task {
                        await model.goToToday()
                    }
                },
            ) {
                Text(model.selectedDay.presentationDate(), format: .dateTime.day().month(.wide).year())
            }
            .frame(maxWidth: .infinity)

            Button {
                isSettingsPresented = true
            } label: {
                AppCircularControl {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.semibold))
                }
            }
            .accessibilityLabel("Настройки")
            .contentShape(Circle())
            .fixedSize()
        }
        .buttonStyle(.borderless)
    }

    private func move(entryID: UUID, to meal: MealType, displayedTargetIndex: Int) {
        Task {
            await model.move(
                entryID: entryID,
                to: meal,
                displayedTargetIndex: displayedTargetIndex,
            )
        }
    }

    private func clearDraggedEntryID(_ entryID: UUID) {
        if draggedEntryID == entryID {
            draggedEntryID = nil
        }
    }
}

private struct DiaryListEntryRow: View {
    let entry: DiaryEntry
    let isDragging: Bool
    let onDragStarted: @MainActor () -> Void
    let onDragEnded: @MainActor () -> Void
    let onDelete: @MainActor () -> Void

    var body: some View {
        NavigationLink(value: TodayRoute.entryEditor(entry.id)) {
            DiaryEntryRow(entry: entry)
                .draggable(entry.id.uuidString) {
                    DiaryEntryDragPreview(
                        entry: entry,
                        onDragStarted: onDragStarted,
                        onDragEnded: onDragEnded,
                    )
                }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Удалить")
        }
        .opacity(isDragging ? 0 : 1)
        .accessibilityHidden(isDragging)
        .allowsHitTesting(!isDragging)
    }
}

private struct DiaryEntryDragPreview: View {
    let entry: DiaryEntry
    let onDragStarted: @MainActor () -> Void
    let onDragEnded: @MainActor () -> Void

    var body: some View {
        DiaryEntryRow(entry: entry)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
            .onAppear(perform: onDragStarted)
            .onDisappear(perform: onDragEnded)
    }
}

struct FoodCompositionSection<Rows: View, AddRow: View>: View {
    let title: String
    let nutrition: Nutrition
    private let rows: Rows
    private let addRow: AddRow

    init(
        title: String,
        nutrition: Nutrition,
        @ViewBuilder rows: () -> Rows,
        @ViewBuilder addRow: () -> AddRow,
    ) {
        self.title = title
        self.nutrition = nutrition
        self.rows = rows()
        self.addRow = addRow()
    }

    var body: some View {
        Section {
            rows
            addRow
        } header: {
            HStack {
                Text(title)
                Spacer()
                Text("\(diaryNumber(nutrition.calories)) ккал")
                    .foregroundStyle(.secondary)
            }
            .textCase(nil)
        }
    }
}

struct FoodCompositionEntryRow: View {
    let title: String
    let amount: Double
    let unitLabel: String
    let calories: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body.weight(.medium))

            HStack {
                Text("\(diaryNumber(amount)) \(unitLabel)")
                Spacer()
                Text("\(diaryNumber(calories)) ккал")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

struct FoodCompositionAddRow: View {
    let onAdd: @MainActor () -> Void
    let onDrop: (@MainActor (UUID) -> Void)?

    @State private var isDropTarget = false

    init(
        onAdd: @escaping @MainActor () -> Void,
        onDrop: (@MainActor (UUID) -> Void)? = nil,
    ) {
        self.onAdd = onAdd
        self.onDrop = onDrop
    }

    var body: some View {
        if let onDrop {
            addButton
                .dropDestination(
                    for: String.self,
                    action: { identifiers, _ in
                        guard let identifier = identifiers.first,
                              let entryID = UUID(uuidString: identifier)
                        else {
                            return false
                        }

                        onDrop(entryID)
                        return true
                    },
                    isTargeted: { isDropTarget = $0 },
                )
                .background {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isDropTarget)
        } else {
            addButton
        }
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Label("Добавить", systemImage: "plus")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct DailyNutritionSummary: View {
    let nutrition: Nutrition
    let calorieGoal: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let calorieGoal {
                Text("\(diaryNumber(nutrition.calories)) / \(diaryNumber(calorieGoal)) ккал")
                    .font(.title3.weight(.semibold))
            } else {
                Text("\(diaryNumber(nutrition.calories)) ккал")
                    .font(.title3.weight(.semibold))
            }
            Text("Б \(diaryNumber(nutrition.protein)) · Ж \(diaryNumber(nutrition.fat)) · У \(diaryNumber(nutrition.carbs))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DiaryEntryRow: View {
    let entry: DiaryEntry

    var body: some View {
        FoodCompositionEntryRow(
            title: entry.sourceName,
            amount: entry.amount,
            unitLabel: diaryUnitLabel(for: entry.unitToken, sourceType: entry.sourceType),
            calories: entry.nutrition.calories,
        )
    }
}

func diaryNumber(_ value: Double) -> String {
    value.formatted(.number.grouping(.never).precision(.fractionLength(0 ... 2)))
}

func diaryUnitLabel(for token: String, sourceType: SourceType) -> String {
    if sourceType == .recipe, let recipeUnit = RecipeDiaryUnit(rawValue: token) {
        switch recipeUnit {
        case .grams:
            return "г"
        case .serving:
            return "порция"
        }
    }
    if let baseUnit = ProductBaseUnit(rawValue: token) {
        return baseUnit.russianLabel
    }
    return "—"
}

struct DiaryInlineErrorView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
