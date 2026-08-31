import Charts
import SwiftUI

struct StatisticsView: View {
    @State private var model: StatisticsViewModel

    init(statisticsService: StatisticsService) {
        _model = State(initialValue: StatisticsViewModel(statisticsService: statisticsService))
    }

    var body: some View {
        List {
            if model.isLoading && model.statistics == nil {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if let statistics = model.statistics {
                weekNavigation(for: statistics)

                WeeklyCaloriesChart(days: statistics.days)
                    .frame(height: 190)
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: DateNavigatorLayout.screenHorizontalMargin,
                            bottom: 0,
                            trailing: DateNavigatorLayout.screenHorizontalMargin,
                        ),
                    )
                    .listRowSeparator(.hidden)

                Section {
                    LabeledContent("Баланс недели", value: calorieBalanceLabel(statistics.weeklyCalorieBalance))
                }

                Section("БЖУ за неделю") {
                    WeeklyMacrosChart(days: statistics.days)
                }
                .headerProminence(.increased)
            } else {
                ContentUnavailableView(
                    "Статистика недоступна",
                    systemImage: "chart.bar",
                    description: model.errorMessage.map(Text.init),
                )
                .listRowSeparator(.hidden)
            }

            if let errorMessage = model.errorMessage, model.statistics != nil {
                Section {
                    StatisticsInlineErrorView(message: errorMessage)
                }
            }
        }
        .appPlainListStyle()
        .contentMargins(.top, 0, for: .scrollContent)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            Task {
                await model.load()
            }
        }
    }

    private func weekNavigation(for statistics: WeekStatistics) -> some View {
        DateNavigator(
            previousAccessibilityLabel: "Предыдущая неделя",
            nextAccessibilityLabel: "Следующая неделя",
            previousAction: {
                Task {
                    await model.previousWeek()
                }
            },
            nextAction: {
                Task {
                    await model.nextWeek()
                }
            },
            secondaryActionTitle: model.isCurrentWeek ? nil : "Текущая неделя",
            secondaryAction: model.isCurrentWeek ? nil : {
                Task {
                    await model.goToCurrentWeek()
                }
            },
        ) {
            Text(weekRangeLabel(for: statistics))
        }
        .listRowInsets(DateNavigatorLayout.listRowInsets)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func weekRangeLabel(for statistics: WeekStatistics) -> String {
        let start = statistics.weekStart.presentationDate()
        let end = statistics.weekStart.adding(days: 6).presentationDate()
        return "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

private struct WeeklyCaloriesChart: View {
    let days: [DayStatistics]

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("День", day.weekday.russianShortLabel),
                    y: .value("Ккал", day.consumedNutrition.calories),
                )
                .foregroundStyle(.tint)

                if let calorieGoal = day.calorieGoal {
                    PointMark(
                        x: .value("День", day.weekday.russianShortLabel),
                        y: .value("Цель", calorieGoal),
                    )
                    .foregroundStyle(.secondary)
                    .symbolSize(28)
                }
            }
        }
        .chartLegend(.hidden)
    }
}

private struct WeeklyMacrosChart: View {
    let days: [DayStatistics]

    var body: some View {
        VStack(spacing: 10) {
            Chart {
                ForEach(days) { day in
                    ForEach(MacroNutrient.allCases, id: \.self) { nutrient in
                        BarMark(
                            x: .value("День", day.weekday.russianShortLabel),
                            y: .value("Граммы", nutrient.amount(in: day.consumedNutrition)),
                        )
                        .position(by: .value("БЖУ", nutrient.shortLabel))
                        .foregroundStyle(nutrient.color)
                    }
                }
            }
            .chartLegend(.hidden)
            .chartYScale(domain: .automatic(includesZero: true))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisTick()

                    if let grams = value.as(Double.self) {
                        AxisValueLabel(NutritionFormatting.macro(grams))
                    }
                }
            }
            .frame(height: 190)

            HStack(spacing: 12) {
                ForEach(MacroNutrient.allCases, id: \.self) { nutrient in
                    Label(nutrient.shortLabel, systemImage: "circle.fill")
                        .font(.footnote)
                        .foregroundStyle(nutrient.color)
                }
            }
        }
    }
}

private extension MacroNutrient {
    var shortLabel: String {
        switch self {
        case .protein: "Б"
        case .fat: "Ж"
        case .carbs: "У"
        }
    }

    var color: Color {
        switch self {
        case .protein: .blue
        case .fat: .orange
        case .carbs: .green
        }
    }

    func amount(in nutrition: Nutrition) -> Double {
        switch self {
        case .protein: nutrition.protein
        case .fat: nutrition.fat
        case .carbs: nutrition.carbs
        }
    }
}

private func calorieBalanceLabel(_ balance: Double?) -> String {
    guard let balance else {
        return "—"
    }
    let prefix = balance > 0 ? "+" : ""
    return "\(prefix)\(NutritionFormatting.calories(balance)) ккал"
}

private struct StatisticsInlineErrorView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
