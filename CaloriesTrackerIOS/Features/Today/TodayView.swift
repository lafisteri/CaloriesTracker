import SwiftUI

struct TodayRootView: View {
    let router: AppRouter
    let diaryService: DiaryService
    let goalService: GoalService
    let productService: ProductService
    let recipeService: RecipeService

    @State private var model: TodayViewModel
    @State private var draggedEntryID: UUID?

    init(
        router: AppRouter,
        diaryService: DiaryService,
        goalService: GoalService,
        productService: ProductService,
        recipeService: RecipeService,
    ) {
        self.router = router
        self.diaryService = diaryService
        self.goalService = goalService
        self.productService = productService
        self.recipeService = recipeService
        _model = State(initialValue: TodayViewModel(diaryService: diaryService, goalService: goalService))
    }

    var body: some View {
        List {
            dateNavigation
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
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
                    Section {
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
                            .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                            .listRowSeparator(.hidden)
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

                        DiaryMealAddRow(
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
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                    } header: {
                        HStack {
                            Text(meal.mealType.russianLabel)
                            Spacer()
                            Text("\(diaryNumber(meal.totalNutrition.calories)) ккал")
                                .foregroundStyle(.secondary)
                        }
                        .textCase(nil)
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                DiaryInlineErrorView(message: errorMessage)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
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
                    mode: .selection(context),
                    router: router,
                    productService: productService,
                    recipeService: recipeService,
                    diaryService: diaryService,
                )
            case let .amount(context, source):
                DiaryAmountView(
                    mode: .create(context: context, source: source),
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
                ) {
                    if let context {
                        router.todayPath = [.catalogSelection(context)]
                    } else {
                        router.todayPath = []
                    }
                }
            case let .productEditorForDiarySelection(productID, _):
                ProductEditorView(
                    productID: productID,
                    router: router,
                    productService: productService,
                ) {
                    router.todayPath.removeLast()
                }
            case let .recipeEditor(context, recipeID):
                RecipeEditorView(
                    recipeID: recipeID,
                    router: router,
                    productService: productService,
                    recipeService: recipeService,
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

    private var dateNavigation: some View {
        HStack {
            Button {
                Task {
                    await model.previousDay()
                }
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            VStack(spacing: 2) {
                Text(model.selectedDay.presentationDate(), format: .dateTime.day().month(.wide).year())
                    .font(.headline)
                if model.selectedDay != .current() {
                    Button("Сегодня") {
                        Task {
                            await model.goToToday()
                        }
                    }
                    .font(.caption)
                }
            }

            Spacer()

            Button {
                Task {
                    await model.nextDay()
                }
            } label: {
                Image(systemName: "chevron.right")
            }
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

private struct DiaryMealAddRow: View {
    let onAdd: @MainActor () -> Void
    let onDrop: @MainActor (UUID) -> Void

    @State private var isDropTarget = false

    var body: some View {
        Button(action: onAdd) {
            Label("Добавить", systemImage: "plus")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.sourceName)
                .font(.body.weight(.medium))

            HStack {
                Text("\(diaryNumber(entry.amount)) \(diaryUnitLabel(for: entry.unitToken, sourceType: entry.sourceType))")
                Spacer()
                Text("\(diaryNumber(entry.nutrition.calories)) ккал")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

func diaryNumber(_ value: Double) -> String {
    value.formatted(.number.grouping(.never).precision(.fractionLength(0 ... 2)))
}

func diaryUnitLabel(for token: String, sourceType: SourceType) -> String {
    if sourceType == .recipe, let recipeUnit = RecipeDiaryUnit.resolve(token) {
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
    return "порция"
}

struct DiaryInlineErrorView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
