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
        ScrollView {
            LazyVStack(spacing: 16) {
            dateNavigation
                .padding(.horizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("За день")
                    .font(.headline)
                if let day = model.day {
                    DailyNutritionSummary(nutrition: day.totalNutrition, calorieGoal: model.calorieGoal)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let day = model.day {
                ForEach(day.meals) { meal in
                    VStack(spacing: 0) {
                        HStack {
                            Text(meal.mealType.russianLabel)
                                .font(.headline)
                            Spacer()
                            Text("\(diaryNumber(meal.totalNutrition.calories)) ккал")
                                .foregroundStyle(.secondary)
                        }
                        .padding()

                        Divider()

                        VStack(spacing: 0) {
                            DiaryMealDropZone(isEmptyMeal: meal.entries.isEmpty) { draggedEntryID in
                                move(
                                    entryID: draggedEntryID,
                                    to: meal.mealType,
                                    displayedTargetIndex: 0,
                                )
                                self.draggedEntryID = nil
                            }

                            ForEach(Array(meal.entries.enumerated()), id: \.element.id) { item in
                            DiaryDraggableEntryRow(
                                    entry: item.element,
                                    isDragging: draggedEntryID == item.element.id,
                                    onTap: {
                                        router.todayPath.append(.entryEditor(item.element.id))
                                    },
                                    onDragStarted: {
                                        draggedEntryID = item.element.id
                                    },
                                    onDragEnded: {
                                        draggedEntryID = nil
                                    },
                                    onDelete: {
                                        Task {
                                            await model.delete(entryID: item.element.id)
                                        }
                                    },
                                )

                                DiaryMealDropZone { draggedEntryID in
                                    move(
                                        entryID: draggedEntryID,
                                        to: meal.mealType,
                                        displayedTargetIndex: item.offset + 1,
                                    )
                                    self.draggedEntryID = nil
                                }
                            }

                            DiaryMealAddButton {
                                router.todayPath.append(
                                    .catalogSelection(DiaryContext(day: model.selectedDay, meal: meal.mealType)),
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            if let errorMessage = model.errorMessage {
                DiaryInlineErrorView(message: errorMessage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
            case let .recipeEditor(context, recipeID):
                RecipeEditorView(
                    recipeID: recipeID,
                    router: router,
                    productService: productService,
                    recipeService: recipeService,
                ) {
                    router.todayPath = [.catalogSelection(context)]
                }
            case .productDetails, .recipeDetails:
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
}

private struct DiaryDraggableEntryRow: View {
    let entry: DiaryEntry
    let isDragging: Bool
    let onTap: @MainActor () -> Void
    let onDragStarted: @MainActor () -> Void
    let onDragEnded: @MainActor () -> Void
    let onDelete: @MainActor () -> Void

    @State private var swipeOffset: CGFloat = 0
    @State private var suppressTapAfterSwipe = false

    private let swipeActionWidth: CGFloat = 72

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Удалить")
            .frame(width: swipeActionWidth)
            .frame(maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(.red)

            Button {
                guard !suppressTapAfterSwipe else {
                    return
                }
                onTap()
            } label: {
                DiaryEntryRow(entry: entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(.background)
            .offset(x: swipeOffset)
            .draggable(entry.id.uuidString) {
                DiaryEntryDragPreview(
                    entry: entry,
                    onDragStarted: onDragStarted,
                    onDragEnded: onDragEnded,
                )
            }
            .simultaneousGesture(swipeGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isDragging ? 0 : 1)
        .accessibilityHidden(isDragging)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                suppressTapAfterSwipe = true
                swipeOffset = min(0, max(-swipeActionWidth, value.translation.width))
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                withAnimation(.easeOut(duration: 0.15)) {
                    swipeOffset = value.translation.width < -swipeActionWidth / 2 ? -swipeActionWidth : 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    suppressTapAfterSwipe = false
                }
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

private struct DiaryMealDropZone: View {
    let isEmptyMeal: Bool
    let onDrop: @MainActor (UUID) -> Void

    @State private var isTargeted = false

    init(
        isEmptyMeal: Bool = false,
        onDrop: @escaping @MainActor (UUID) -> Void,
    ) {
        self.isEmptyMeal = isEmptyMeal
        self.onDrop = onDrop
    }

    var body: some View {
        Group {
            if isEmptyMeal {
                VStack(spacing: 6) {
                    Image(systemName: isTargeted ? "arrow.down.to.line" : "arrow.left.and.right")
                    Text(isTargeted ? "Отпустите запись здесь" : "Перетащите запись сюда")
                }
                .font(.subheadline)
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity, minHeight: 84)
                .background(
                    isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                )
            } else {
                Capsule()
                    .fill(isTargeted ? Color.accentColor : Color.clear)
                    .frame(maxWidth: .infinity)
                    .frame(height: isTargeted ? 3 : 12)
                    .padding(.horizontal, 8)
                    .padding(.vertical, isTargeted ? 8 : 0)
            }
        }
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
            isTargeted: { isTargeted = $0 },
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .accessibilityHidden(true)
    }
}

private struct DiaryMealAddButton: View {
    let onAdd: @MainActor () -> Void

    var body: some View {
        Button(action: onAdd) {
            Label("Добавить", systemImage: "plus")
        }
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
        VStack(alignment: .leading, spacing: 4) {
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
        .padding(.vertical, 2)
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
