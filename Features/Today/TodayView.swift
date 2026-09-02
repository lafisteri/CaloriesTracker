import SwiftData
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
                .listRowInsets(
                    EdgeInsets(
                        top: 0,
                        leading: 0,
                        bottom: DateNavigatorLayout.rootHeaderContentSpacing,
                        trailing: 0,
                    ),
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            VStack(alignment: .leading, spacing: 0) {
                if let day = model.day {
                    DailyNutritionSummary(nutrition: day.totalNutrition, goal: model.dailyGoal)
                } else {
                    ProgressView()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppStyle.controlBackground,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            )
            .shadow(
                color: AppStyle.controlShadowColor,
                radius: AppStyle.controlShadowRadius,
                y: AppStyle.controlShadowY,
            )
            .listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: 0,
                    bottom: 0,
                    trailing: 0,
                ),
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if let day = model.day {
                ForEach(day.meals) { meal in
                    DiaryMealCardSection(
                        mealID: meal.mealType.rawValue,
                        title: meal.mealType.russianLabel,
                        nutrition: meal.totalNutrition,
                        hasEntries: !meal.entries.isEmpty,
                        onAdd: {
                            router.todayPath.append(
                                .catalogSelection(DiaryContext(day: model.selectedDay, meal: meal.mealType)),
                            )
                        },
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
                            )
                            .diaryMealCardEntryRow(
                                mealID: meal.mealType.rawValue,
                                isLast: entry.id == meal.entries.last?.id,
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task {
                                        await model.delete(entryID: entry.id)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Удалить")
                            }
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
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                DiaryInlineErrorView(message: errorMessage)
                    .listRowSeparator(.hidden)
            }
        }
        .backgroundPreferenceValue(DiaryMealCardBoundsPreferenceKey.self) { cardBounds in
            GeometryReader { proxy in
                ForEach(cardBounds.keys.sorted(), id: \.self) { mealID in
                    if let anchors = cardBounds[mealID],
                       let top = anchors.top,
                       let bottom = anchors.bottom {
                        let topFrame = proxy[top]
                        let bottomFrame = proxy[bottom]

                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AppStyle.controlBackground)
                            .frame(
                                width: topFrame.width,
                                height: bottomFrame.maxY - topFrame.minY,
                            )
                            .position(
                                x: topFrame.midX,
                                y: (topFrame.minY + bottomFrame.maxY) / 2,
                            )
                            .shadow(
                                color: AppStyle.controlShadowColor,
                                radius: AppStyle.controlShadowRadius,
                                y: AppStyle.controlShadowY,
                            )
                    }
                }
            }
        }
        .appPlainListStyle()
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.horizontal, AppStyle.screenHorizontalMargin, for: .scrollContent)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await model.load()
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
            case .settings:
                SettingsView(
                    goalService: goalService,
                    supabaseAuth: supabaseAuth,
                    syncStatus: syncStatus,
                    syncOrchestrator: syncOrchestrator,
                )
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
            case let .manualEntry(context, initialName):
                ProductEditorView(
                    manualMode: .create(context: context, initialName: initialName),
                    router: router,
                    diaryService: diaryService,
                )
            case let .manualEntryEditor(entryID):
                ProductEditorView(
                    manualMode: .edit(entryID: entryID),
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
            onCreateManualEntry: { initialName in
                router.todayPath.append(.manualEntry(context: context, initialName: initialName))
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
                router.todayPath.append(.settings)
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

    var body: some View {
        NavigationLink(
            value: entry.sourceType == .manual
                ? TodayRoute.manualEntryEditor(entry.id)
                : TodayRoute.entryEditor(entry.id),
        ) {
            DiaryEntryRow(entry: entry)
                .draggable(entry.id.uuidString) {
                    DiaryEntryDragPreview(
                        entry: entry,
                        onDragStarted: onDragStarted,
                        onDragEnded: onDragEnded,
                    )
                }
        }
        .opacity(isDragging ? 0 : 1)
        .accessibilityHidden(isDragging)
        .allowsHitTesting(!isDragging)
    }
}

private struct DiaryMealCardAnchors {
    var top: Anchor<CGRect>?
    var bottom: Anchor<CGRect>?
}

private struct DiaryMealCardBoundsPreferenceKey: PreferenceKey {
    static let defaultValue: [String: DiaryMealCardAnchors] = [:]

    static func reduce(
        value: inout [String: DiaryMealCardAnchors],
        nextValue: () -> [String: DiaryMealCardAnchors],
    ) {
        for (mealID, nextAnchors) in nextValue() {
            var anchors = value[mealID] ?? DiaryMealCardAnchors()
            anchors.top = anchors.top ?? nextAnchors.top
            anchors.bottom = nextAnchors.bottom ?? anchors.bottom
            value[mealID] = anchors
        }
    }
}

private struct DiaryMealCardSection<Rows: View>: View {
    let mealID: String
    let title: String
    let nutrition: Nutrition
    let hasEntries: Bool
    let onAdd: @MainActor () -> Void
    private let rows: Rows

    init(
        mealID: String,
        title: String,
        nutrition: Nutrition,
        hasEntries: Bool,
        onAdd: @escaping @MainActor () -> Void,
        @ViewBuilder rows: () -> Rows,
    ) {
        self.mealID = mealID
        self.title = title
        self.nutrition = nutrition
        self.hasEntries = hasEntries
        self.onAdd = onAdd
        self.rows = rows()
    }

    var body: some View {
        Section {
            DiaryMealCardHeader(
                mealID: mealID,
                title: title,
                nutrition: nutrition,
                hasEntries: hasEntries,
                onAdd: onAdd,
            )
            .listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: 0,
                    bottom: 0,
                    trailing: 0,
                ),
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            rows
        }
    }
}

private struct DiaryMealCardHeader: View {
    let mealID: String
    let title: String
    let nutrition: Nutrition
    let hasEntries: Bool
    let onAdd: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.black)

            Text("\(NutritionFormatting.calories(nutrition.calories)) ккал")
                .font(.body.weight(.regular))
                .foregroundStyle(Color.black)

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.title2.weight(.regular))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Добавить в \(title)")
        }
        .padding(.horizontal, 16)
        .anchorPreference(key: DiaryMealCardBoundsPreferenceKey.self, value: .bounds) { bounds in
            [
                mealID: DiaryMealCardAnchors(
                    top: bounds,
                    bottom: hasEntries ? nil : bounds,
                ),
            ]
        }
    }
}

private extension View {
    func diaryMealCardEntryRow(mealID: String, isLast: Bool) -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                AppStyle.controlBackground,
                in: UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 0,
                        bottomLeading: isLast ? 20 : 0,
                        bottomTrailing: isLast ? 20 : 0,
                        topTrailing: 0,
                    ),
                    style: .continuous,
                ),
            )
            .compositingGroup()
            .listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: 0,
                    bottom: 0,
                    trailing: 0,
                ),
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .anchorPreference(key: DiaryMealCardBoundsPreferenceKey.self, value: .bounds) { bounds in
                isLast ? [mealID: DiaryMealCardAnchors(bottom: bounds)] : [:]
            }
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
    let numberStyle: FoodCompositionNumberStyle
    let showsAddRow: Bool
    let onAdd: (@MainActor () -> Void)?
    private let rows: Rows
    private let addRow: AddRow

    init(
        title: String,
        nutrition: Nutrition,
        numberStyle: FoodCompositionNumberStyle = .compact,
        showsAddRow: Bool = true,
        onAdd: (@MainActor () -> Void)? = nil,
        @ViewBuilder rows: () -> Rows,
        @ViewBuilder addRow: () -> AddRow,
    ) {
        self.title = title
        self.nutrition = nutrition
        self.numberStyle = numberStyle
        self.showsAddRow = showsAddRow
        self.onAdd = onAdd
        self.rows = rows()
        self.addRow = addRow()
    }

    var body: some View {
        Section {
            rows
            if showsAddRow {
                addRow
            }
        } header: {
            headerContent
        }
    }

    private var headerContent: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.black)

            Text("\(numberStyle.calories(nutrition.calories)) ккал")
                .font(.body.weight(.regular))
                .foregroundStyle(Color.black)

            Spacer()

            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.regular))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Добавить в \(title)")
            }
        }
        .textCase(nil)
    }
}

struct FoodCompositionEntryRow: View {
    let title: String
    let amount: Double
    let unitLabel: String
    let calories: Double
    let numberStyle: FoodCompositionNumberStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.black)

            HStack {
                Text("\(numberStyle.amount(amount)) \(unitLabel)")
                Spacer()
                Text("\(numberStyle.calories(calories)) ккал")
            }
            .font(.subheadline)
            .foregroundStyle(Color.black)
        }
    }
}

struct FoodCompositionAddRow: View {
    let alignment: Alignment
    let onAdd: @MainActor () -> Void
    let onDrop: (@MainActor (UUID) -> Void)?

    @State private var isDropTarget = false

    init(
        alignment: Alignment = .leading,
        onAdd: @escaping @MainActor () -> Void,
        onDrop: (@MainActor (UUID) -> Void)? = nil,
    ) {
        self.alignment = alignment
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
        .frame(maxWidth: .infinity, alignment: alignment)
        .contentShape(Rectangle())
    }
}

private struct DailyNutritionSummary: View {
    let nutrition: Nutrition
    let goal: DailyMacroGoal?

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                calorieValue

                Spacer(minLength: 0)

                if let calorieGoal, calorieGoal > 0 {
                    DailyCalorieProgressRing(
                        progress: DailyGoalProgress(
                            value: nutrition.calories,
                            goal: calorieGoal,
                        ),
                    )
                }
            }

            Divider()
                .overlay(Color(uiColor: .systemGray4).opacity(0.55))

            HStack(spacing: 8) {
                DailyMacroSummaryColumn(
                    label: "Б",
                    value: nutrition.protein,
                    goal: goal?.protein,
                    color: .blue,
                )

                macroDivider

                DailyMacroSummaryColumn(
                    label: "Ж",
                    value: nutrition.fat,
                    goal: goal?.fat,
                    color: .orange,
                )

                macroDivider

                DailyMacroSummaryColumn(
                    label: "У",
                    value: nutrition.carbs,
                    goal: goal?.carbs,
                    color: .green,
                )
            }
        }
    }

    private var calorieGoal: Double? {
        goal?.calories
    }

    private var calorieValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(NutritionFormatting.calories(nutrition.calories))
                .font(.title2.weight(.regular))
                .foregroundStyle(Color.black)

            if let calorieGoal {
                Text(" / \(NutritionFormatting.calories(calorieGoal)) ккал")
                    .font(.title3.weight(.regular))
                    .foregroundStyle(.secondary)
            } else {
                Text(" ккал")
                    .font(.title3.weight(.regular))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .layoutPriority(1)
    }

    private var macroDivider: some View {
        Rectangle()
            .fill(Color(uiColor: .systemGray4).opacity(0.7))
            .frame(width: 1, height: 44)
    }

}

private struct DailyCalorieProgressRing: View {
    let progress: DailyGoalProgress

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(uiColor: .systemGray5), lineWidth: 6)

            Circle()
                .trim(from: 0, to: progress.goalSegment)
                .stroke(
                    Color.purple,
                    style: StrokeStyle(
                        lineWidth: 6,
                        lineCap: progress.overflowSegment > 0 ? .butt : .round,
                    ),
                )
                .rotationEffect(.degrees(-90))

            if progress.overflowSegment > 0 {
                Circle()
                    .trim(from: 0, to: progress.overflowSegment)
                    .stroke(
                        Color.red,
                        style: StrokeStyle(lineWidth: 6, lineCap: .butt),
                    )
                    .rotationEffect(.degrees(-90 + 360 * progress.goalSegment))
            }

            Text("\(progress.percentage)%")
                .font(.subheadline.weight(.regular))
                .foregroundStyle(Color.black)
                .monospacedDigit()
        }
        .frame(width: 56, height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Выполнение цели по калориям")
        .accessibilityValue("\(progress.percentage)%")
    }
}

private struct DailyMacroSummaryColumn: View {
    let label: String
    let value: Double
    let goal: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label)
                    .font(.headline.weight(.regular))
                    .foregroundStyle(color)

                Text(NutritionFormatting.macro(value))
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(Color.black)

                if let goal {
                    Text(" / \(NutritionFormatting.macro(goal)) г")
                        .font(.caption.weight(.regular))
                        .foregroundStyle(.secondary)
                } else {
                    Text(" г")
                        .font(.caption.weight(.regular))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            DailySummaryProgressBar(
                progress: progress,
                color: color,
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var progress: DailyGoalProgress {
        DailyGoalProgress(value: value, goal: goal ?? 0)
    }
}

private struct DailySummaryProgressBar: View {
    let progress: DailyGoalProgress
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(uiColor: .systemGray5))

                if progress.overflowSegment > 0 {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(color)
                            .frame(width: proxy.size.width * progress.goalSegment)

                        Rectangle()
                            .fill(Color.red)
                            .frame(width: proxy.size.width * progress.overflowSegment)
                    }
                    .clipShape(Capsule())
                } else {
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * progress.goalSegment)
                }
            }
        }
        .frame(height: 6)
    }
}

private struct DailyGoalProgress {
    let value: Double
    let goal: Double

    var percentage: Int {
        guard goal > 0 else {
            return 0
        }

        return Int((value / goal * 100).rounded())
    }

    var goalSegment: Double {
        guard goal > 0 else {
            return 0
        }

        guard value > goal, value > 0 else {
            return min(max(value / goal, 0), 1)
        }

        return goal / value
    }

    var overflowSegment: Double {
        guard value > goal, value > 0 else {
            return 0
        }

        return (value - goal) / value
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
            numberStyle: .compact,
        )
    }
}

enum FoodCompositionNumberStyle {
    case compact
    case detailed

    func calories(_ value: Double) -> String {
        switch self {
        case .compact:
            NutritionFormatting.calories(value)
        case .detailed:
            NutritionFormatting.preciseNutrition(value)
        }
    }

    func amount(_ value: Double) -> String {
        switch self {
        case .compact:
            NutritionFormatting.amount(value)
        case .detailed:
            NutritionFormatting.preciseAmount(value)
        }
    }
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

@MainActor
private struct TodayViewPreview: View {
    @State private var router = AppRouter()

    private let dependencies: AppDependencies

    init() {
        dependencies = try! AppDependencies(isStoredInMemoryOnly: true)
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.todayPath) {
            TodayRootView(
                router: router,
                diaryService: dependencies.diaryService,
                goalService: dependencies.goalService,
                productService: dependencies.productService,
                recipeService: dependencies.recipeService,
                supabaseAuth: nil,
                syncStatus: nil,
                syncOrchestrator: nil,
            )
        }
        .modelContainer(dependencies.modelContainer)
    }
}

struct DiaryInlineErrorView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
