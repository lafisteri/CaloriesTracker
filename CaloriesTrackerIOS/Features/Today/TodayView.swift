import SwiftUI
import UniformTypeIdentifiers

struct TodayRootView: View {
    let router: AppRouter
    let diaryService: DiaryService
    let goalService: GoalService
    let productService: ProductService
    let recipeService: RecipeService

    @State private var model: TodayViewModel

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

            Section("За день") {
                if let day = model.day {
                    DailyNutritionSummary(nutrition: day.totalNutrition, calorieGoal: model.calorieGoal)
                } else {
                    ProgressView()
                }
            }

            if let day = model.day {
                ForEach(day.meals) { meal in
                    Section {
                        ForEach(meal.entries) { entry in
                            DiaryDraggableEntryRow(
                                entry: entry,
                                onDrop: { draggedEntryID, insertion in
                                    guard let targetIndex = meal.entries.firstIndex(where: { $0.id == entry.id }) else {
                                        return
                                    }

                                    let displayedTargetIndex = targetIndex + (insertion == .after ? 1 : 0)
                                    Task {
                                        await model.move(
                                            entryID: draggedEntryID,
                                            to: meal.mealType,
                                            displayedTargetIndex: displayedTargetIndex,
                                        )
                                    }
                                },
                                onDelete: {
                                    Task {
                                        await model.delete(entryID: entry.id)
                                    }
                                },
                            )
                            .listRowSeparator(.hidden)
                        }

                        DiaryMealDropButton(
                            onAdd: {
                                router.todayPath.append(
                                    .catalogSelection(DiaryContext(day: model.selectedDay, meal: meal.mealType)),
                                )
                            },
                            onDrop: { draggedEntryID in
                                Task {
                                    await model.move(
                                        entryID: draggedEntryID,
                                        to: meal.mealType,
                                        displayedTargetIndex: meal.entries.count,
                                    )
                                }
                            },
                        )
                    } header: {
                        HStack {
                            Text(meal.mealType.russianLabel)
                            Spacer()
                            Text("\(diaryNumber(meal.totalNutrition.calories)) ккал")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                Section {
                    DiaryInlineErrorView(message: errorMessage)
                }
            }
        }
        .listStyle(.insetGrouped)
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
}

private enum DiaryDropInsertion {
    case before
    case after
}

private enum DiaryEntryDragPayload {
    static let contentType = UTType(exportedAs: "com.caloriestracker.diary-entry-id")

    static func makeItemProvider(for entryID: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: contentType.identifier,
            visibility: .all,
        ) { completion in
            completion(Data(entryID.uuidString.utf8), nil)
            return nil
        }
        return provider
    }

    @discardableResult
    static func loadEntryID(
        from info: DropInfo,
        completion: @escaping @MainActor (UUID) -> Void,
    ) -> Bool {
        guard let provider = info.itemProviders(for: [contentType]).first else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: contentType.identifier) { data, _ in
            guard let data,
                  let rawValue = String(data: data, encoding: .utf8),
                  let entryID = UUID(uuidString: rawValue)
            else {
                return
            }

            Task { @MainActor in
                completion(entryID)
            }
        }
        return true
    }
}

private struct DiaryDraggableEntryRow: View {
    let entry: DiaryEntry
    let onDrop: @MainActor (UUID, DiaryDropInsertion) -> Void
    let onDelete: @MainActor () -> Void

    @State private var rowHeight: CGFloat = 1
    @State private var isDropTarget = false
    @State private var insertion: DiaryDropInsertion?

    var body: some View {
        NavigationLink(value: TodayRoute.entryEditor(entry.id)) {
            DiaryEntryRow(entry: entry)
        }
        .swipeActions {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Удалить")
        }
        .onDrag {
            DiaryEntryDragPayload.makeItemProvider(for: entry.id)
        } preview: {
            DiaryEntryRow(entry: entry)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
        }
        .onDrop(
            of: [DiaryEntryDragPayload.contentType],
            delegate: DiaryEntryDropDelegate(
                targetHeight: rowHeight,
                onTargetChange: { isTargeted, insertion in
                    isDropTarget = isTargeted
                    self.insertion = insertion
                },
                onDrop: { draggedEntryID, insertion in
                    guard draggedEntryID != entry.id else {
                        return
                    }
                    onDrop(draggedEntryID, insertion)
                },
            ),
        )
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        rowHeight = proxy.size.height
                    }
                    .onChange(of: proxy.size.height) { _, height in
                        rowHeight = height
                    }
            }
        }
        .overlay(alignment: insertion == .before ? .top : .bottom) {
            if isDropTarget, insertion != nil {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .padding(.horizontal, 8)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct DiaryMealDropButton: View {
    let onAdd: @MainActor () -> Void
    let onDrop: @MainActor (UUID) -> Void

    @State private var isDropTarget = false

    var body: some View {
        Button(action: onAdd) {
            Label(
                isDropTarget ? "Переместить сюда" : "Добавить",
                systemImage: isDropTarget ? "arrow.down.to.line" : "plus",
            )
        }
        .onDrop(
            of: [DiaryEntryDragPayload.contentType],
            delegate: DiaryMealDropDelegate(
                onTargetChange: { isDropTarget = $0 },
                onDrop: onDrop,
            ),
        )
        .background {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
    }
}

private struct DiaryEntryDropDelegate: DropDelegate {
    let targetHeight: CGFloat
    let onTargetChange: @MainActor (Bool, DiaryDropInsertion?) -> Void
    let onDrop: @MainActor (UUID, DiaryDropInsertion) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: [DiaryEntryDragPayload.contentType]).isEmpty
    }

    func dropEntered(info: DropInfo) {
        updateTarget(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget(for: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onTargetChange(false, nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let insertion = insertion(for: info)
        onTargetChange(false, nil)
        return DiaryEntryDragPayload.loadEntryID(from: info) { entryID in
            onDrop(entryID, insertion)
        }
    }

    private func updateTarget(for info: DropInfo) {
        onTargetChange(true, insertion(for: info))
    }

    private func insertion(for info: DropInfo) -> DiaryDropInsertion {
        info.location.y < max(targetHeight, 1) / 2 ? .before : .after
    }
}

private struct DiaryMealDropDelegate: DropDelegate {
    let onTargetChange: @MainActor (Bool) -> Void
    let onDrop: @MainActor (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: [DiaryEntryDragPayload.contentType]).isEmpty
    }

    func dropEntered(info: DropInfo) {
        onTargetChange(true)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onTargetChange(true)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onTargetChange(false)
    }

    func performDrop(info: DropInfo) -> Bool {
        onTargetChange(false)
        return DiaryEntryDragPayload.loadEntryID(from: info, completion: onDrop)
    }
}
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
