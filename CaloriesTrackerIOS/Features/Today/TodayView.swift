import SwiftUI

struct TodayRootView: View {
    let router: AppRouter
    let diaryService: DiaryService
    let productService: ProductService

    @State private var model: TodayViewModel

    init(router: AppRouter, diaryService: DiaryService, productService: ProductService) {
        self.router = router
        self.diaryService = diaryService
        self.productService = productService
        _model = State(initialValue: TodayViewModel(diaryService: diaryService))
    }

    var body: some View {
        List {
            dateNavigation

            Section("За день") {
                if let day = model.day {
                    DailyNutritionSummary(nutrition: day.totalNutrition)
                } else {
                    ProgressView()
                }
            }

            if let day = model.day {
                ForEach(day.meals) { meal in
                    Section {
                        ForEach(meal.entries) { entry in
                            NavigationLink(value: TodayRoute.entryEditor(entry.id)) {
                                DiaryEntryRow(entry: entry)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task {
                                        await model.delete(entryID: entry.id)
                                    }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Menu("Переместить в") {
                                    ForEach(MealType.allCases.filter { $0 != meal.mealType }, id: \.self) { targetMeal in
                                        Button(targetMeal.russianLabel) {
                                            Task {
                                                await model.move(entryID: entry.id, to: targetMeal)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .onMove { offsets, newOffset in
                            var orderedEntryIDs = meal.entries.map(\.id)
                            orderedEntryIDs.move(fromOffsets: offsets, toOffset: newOffset)
                            Task {
                                await model.reorder(meal: meal.mealType, orderedEntryIDs: orderedEntryIDs)
                            }
                        }

                        Button {
                            router.todayPath.append(
                                .foodSelection(DiaryContext(day: model.selectedDay, meal: meal.mealType)),
                            )
                        } label: {
                            Label("Добавить", systemImage: "plus")
                        }
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
        .navigationTitle("Сегодня")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
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
            case let .foodSelection(context):
                FoodSelectionView(context: context, router: router, productService: productService)
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
            case .productEditor, .productDetails, .recipeDetails:
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

private struct DailyNutritionSummary: View {
    let nutrition: Nutrition

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(diaryNumber(nutrition.calories)) ккал")
                .font(.title3.weight(.semibold))
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
            Text("\(diaryNumber(entry.amount)) \(diaryUnitLabel(for: entry.unitToken)) · \(diaryNumber(entry.nutrition.calories)) ккал")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Б \(diaryNumber(entry.nutrition.protein)) · Ж \(diaryNumber(entry.nutrition.fat)) · У \(diaryNumber(entry.nutrition.carbs))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

func diaryNumber(_ value: Double) -> String {
    value.formatted(.number.grouping(.never).precision(.fractionLength(0 ... 2)))
}

func diaryUnitLabel(for token: String) -> String {
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
