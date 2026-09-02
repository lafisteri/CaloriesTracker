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

                StatisticsChartCard(title: "Калории по дням", unit: "ккал") {
                    WeeklyCaloriesChart(days: statistics.days)
                }
                .statisticsChartCardRow()

                StatisticsChartCard(title: "БЖУ по дням", unit: "г") {
                    WeeklyMacrosChart(days: statistics.days)
                } legend: {
                    MacrosLegend()
                }
                .statisticsChartCardRow()
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

private enum StatisticsChartLayout {
    static let cardPadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 20
    static let cardContentSpacing: CGFloat = 12
    static let chartHeight: CGFloat = 180
    static let axisLabelWidth: CGFloat = 48
    static let caloriesBarWidth: CGFloat = 28
    static let weekdayLabels = LocalDay.Weekday.allCases.map(\.russianShortLabel)
}

private struct StatisticsChartCard<ChartContent: View, Legend: View>: View {
    let title: String
    let unit: String
    private let chartContent: ChartContent
    private let legend: Legend?

    init(
        title: String,
        unit: String,
        @ViewBuilder chart: () -> ChartContent,
    ) where Legend == EmptyView {
        self.title = title
        self.unit = unit
        chartContent = chart()
        legend = nil
    }

    init(
        title: String,
        unit: String,
        @ViewBuilder chart: () -> ChartContent,
        @ViewBuilder legend: () -> Legend,
    ) {
        self.title = title
        self.unit = unit
        chartContent = chart()
        self.legend = legend()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsChartLayout.cardContentSpacing) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            chartContent

            if let legend {
                legend
            }
        }
        .padding(StatisticsChartLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppStyle.controlBackground,
            in: RoundedRectangle(
                cornerRadius: StatisticsChartLayout.cardCornerRadius,
                style: .continuous,
            ),
        )
        .shadow(
            color: AppStyle.controlShadowColor,
            radius: AppStyle.controlShadowRadius,
            y: AppStyle.controlShadowY,
        )
    }
}

private struct WeeklyCaloriesChart: View {
    let days: [DayStatistics]

    var body: some View {
        Chart {
            ForEach(days) { day in
                let consumedCalories = day.consumedNutrition.calories

                if consumedCalories > 0 {
                    if let calorieGoal = day.calorieGoal, consumedCalories > calorieGoal {
                        BarMark(
                            x: .value("День", day.weekday.russianShortLabel),
                            y: .value("Ккал", consumedCalories),
                            width: .fixed(StatisticsChartLayout.caloriesBarWidth),
                        )
                        .foregroundStyle(.red)
                        .cornerRadius(4)
                        .accessibilityLabel("Превышение цели калорий")
                        .accessibilityValue(NutritionFormatting.calories(consumedCalories - calorieGoal))

                        BarMark(
                            x: .value("День", day.weekday.russianShortLabel),
                            yStart: .value("Ккал", 0),
                            yEnd: .value("Ккал", calorieGoal),
                            width: .fixed(StatisticsChartLayout.caloriesBarWidth),
                        )
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Фактические калории")
                        .accessibilityValue(NutritionFormatting.calories(calorieGoal))
                    } else {
                        BarMark(
                            x: .value("День", day.weekday.russianShortLabel),
                            y: .value("Ккал", consumedCalories),
                            width: .fixed(StatisticsChartLayout.caloriesBarWidth),
                        )
                        .foregroundStyle(.tint)
                        .cornerRadius(4)
                        .accessibilityLabel("Фактические калории")
                        .accessibilityValue(NutritionFormatting.calories(consumedCalories))
                    }
                }

                if let calorieGoal = day.calorieGoal {
                    PointMark(
                        x: .value("День", day.weekday.russianShortLabel),
                        y: .value("Цель", calorieGoal),
                    )
                    .foregroundStyle(.secondary)
                    .symbol {
                        Rectangle()
                            .frame(width: StatisticsChartLayout.caloriesBarWidth, height: 2)
                    }
                    .accessibilityLabel("Цель калорий")
                    .accessibilityValue(NutritionFormatting.calories(calorieGoal))
                }
            }
        }
        .statisticsChartAxes { NutritionFormatting.calories($0) }
    }
}

private struct WeeklyMacrosChart: View {
    let days: [DayStatistics]

    var body: some View {
        Chart {
            ForEach(days) { day in
                ForEach(MacroNutrient.allCases, id: \.self) { nutrient in
                    let amount = nutrient.amount(in: day.consumedNutrition)

                    if amount > 0 {
                        BarMark(
                            x: .value("День", day.weekday.russianShortLabel),
                            y: .value("Граммы", amount),
                        )
                        .position(by: .value("БЖУ", nutrient.shortLabel))
                        .foregroundStyle(nutrient.color)
                        .cornerRadius(3)
                        .accessibilityLabel(nutrient.fullLabel)
                        .accessibilityValue(NutritionFormatting.macro(amount))
                    }

                    if let macroGoal = day.macroGoal {
                        let goal = nutrient.goal(in: macroGoal)

                        PointMark(
                            x: .value("День", day.weekday.russianShortLabel),
                            y: .value("Цель", goal),
                        )
                        .position(by: .value("БЖУ", nutrient.shortLabel))
                        .foregroundStyle(nutrient.color)
                        .symbol(Circle())
                        .symbolSize(24)
                        .accessibilityLabel("Цель: \(nutrient.fullLabel)")
                        .accessibilityValue(NutritionFormatting.macro(goal))
                    }
                }
            }
        }
        .statisticsChartAxes { NutritionFormatting.macro($0) }
    }
}

private struct MacrosLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(MacroNutrient.allCases, id: \.self) { nutrient in
                StatisticsLegendItem(nutrient.fullLabel) {
                    Circle()
                        .fill(nutrient.color)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }
}

private struct StatisticsLegendItem<Marker: View>: View {
    let title: String
    private let marker: Marker

    init(_ title: String, @ViewBuilder marker: () -> Marker) {
        self.title = title
        self.marker = marker()
    }

    var body: some View {
        HStack(spacing: 6) {
            marker
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
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

    var fullLabel: String {
        switch self {
        case .protein: "Белки"
        case .fat: "Жиры"
        case .carbs: "Углеводы"
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

    func goal(in goal: DailyMacroGoal) -> Double {
        switch self {
        case .protein: goal.protein
        case .fat: goal.fat
        case .carbs: goal.carbs
        }
    }
}

private extension View {
    func statisticsChartCardRow() -> some View {
        listRowInsets(
            EdgeInsets(
                top: 0,
                leading: AppStyle.screenHorizontalMargin,
                bottom: AppStyle.sectionSpacing,
                trailing: AppStyle.screenHorizontalMargin,
            ),
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    func statisticsChartAxes(
        valueLabel: @escaping (Double) -> String,
    ) -> some View {
        chartLegend(.hidden)
            .chartXScale(domain: StatisticsChartLayout.weekdayLabels)
            .chartYScale(domain: .automatic(includesZero: true))
            .chartXAxis {
                AxisMarks(values: StatisticsChartLayout.weekdayLabels) { _ in
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.secondary.opacity(0.15))

                    if let value = value.as(Double.self) {
                        AxisValueLabel {
                            Text(valueLabel(value))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(
                                    width: StatisticsChartLayout.axisLabelWidth,
                                    alignment: .trailing,
                                )
                        }
                    }
                }
            }
            .frame(height: StatisticsChartLayout.chartHeight)
    }
}

private struct StatisticsInlineErrorView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
