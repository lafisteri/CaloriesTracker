import Charts
import SwiftUI

struct StatisticsView: View {
    let chartSettingsService: ChartSettingsService
    let syncStatus: SyncStatusStore?

    @State private var model: StatisticsViewModel
    @State private var chartSettings = ChartSettings.default

    init(
        statisticsService: StatisticsService,
        chartSettingsService: ChartSettingsService,
        syncStatus: SyncStatusStore?,
    ) {
        self.chartSettingsService = chartSettingsService
        self.syncStatus = syncStatus
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

                let visibleCharts = chartSettings.orderedKnownItems.filter(\.isEnabled)
                if visibleCharts.isEmpty {
                    ContentUnavailableView(
                        "Нет выбранных графиков",
                        systemImage: "chart.bar",
                        description: Text("Настройте отображение в разделе «Графики»."),
                    )
                    .statisticsChartCardRow()
                } else {
                    ForEach(visibleCharts) { item in
                        if let chartType = item.chartType {
                            StatisticsChartCard(title: chartType.chartTitle, unit: chartType.unit) {
                                WeeklyMetricChart(chartType: chartType, days: statistics.days)
                            }
                            .statisticsChartCardRow()
                        }
                    }
                }
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
                await loadChartSettings()
            }
        }
        .onChange(of: syncStatus?.lastSuccessfulSyncAt) { _, _ in
            Task { await loadChartSettings() }
        }
        .onChange(of: chartSettingsService.revision) { _, _ in
            Task { await loadChartSettings() }
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

    private func loadChartSettings() async {
        do {
            chartSettings = try await chartSettingsService.settings()
        } catch {
            chartSettings = .default
        }
    }
}

private enum StatisticsChartLayout {
    static let cardPadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 20
    static let cardContentSpacing: CGFloat = 12
    static let chartHeight: CGFloat = 180
    static let axisLabelWidth: CGFloat = 48
    static let barWidth: CGFloat = 28
    static let weekdayLabels = LocalDay.Weekday.allCases.map(\.russianShortLabel)
}

private struct StatisticsChartCard<ChartContent: View>: View {
    let title: String
    let unit: String
    private let chartContent: ChartContent

    init(
        title: String,
        unit: String,
        @ViewBuilder chart: () -> ChartContent,
    ) {
        self.title = title
        self.unit = unit
        chartContent = chart()
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

private struct WeeklyMetricChart: View {
    let chartType: StatisticsChartType
    let days: [DayStatistics]

    var body: some View {
        Chart {
            ForEach(days) { day in
                let actual = chartType.actual(in: day)
                let goal = chartType.goal(in: day)

                if actual > 0 {
                    if chartType.showsOverGoal, let goal, actual > goal {
                        BarMark(
                            x: .value("День", day.weekday.russianShortLabel),
                            y: .value(chartType.valueAxisTitle, actual),
                            width: .fixed(StatisticsChartLayout.barWidth),
                        )
                        .foregroundStyle(.red)
                        .cornerRadius(4)
                        .accessibilityLabel(chartType.overGoalAccessibilityLabel)
                        .accessibilityValue(chartType.formatted(actual - goal))

                        BarMark(
                            x: .value("День", day.weekday.russianShortLabel),
                            yStart: .value(chartType.valueAxisTitle, 0),
                            yEnd: .value(chartType.valueAxisTitle, goal),
                            width: .fixed(StatisticsChartLayout.barWidth),
                        )
                        .foregroundStyle(chartType.color)
                        .accessibilityLabel(chartType.actualAccessibilityLabel)
                        .accessibilityValue(chartType.formatted(goal))
                    } else {
                        BarMark(
                            x: .value("День", day.weekday.russianShortLabel),
                            y: .value(chartType.valueAxisTitle, actual),
                            width: .fixed(StatisticsChartLayout.barWidth),
                        )
                        .foregroundStyle(chartType.color)
                        .cornerRadius(4)
                        .accessibilityLabel(chartType.actualAccessibilityLabel)
                        .accessibilityValue(chartType.formatted(actual))
                    }
                }

                if let goal {
                    LineMark(
                        x: .value("День", day.weekday.russianShortLabel),
                        y: .value("Цель", goal),
                    )
                    // Keeps goal values in the Chart scale and accessibility
                    // tree. The visible line is drawn in chartOverlay so it
                    // can start and end at the plot-area boundaries.
                    .opacity(0)
                    .accessibilityLabel(chartType.goalAccessibilityLabel)
                    .accessibilityValue(chartType.formatted(goal))
                }
            }
        }
        .statisticsChartAxes { chartType.formatted($0) }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    StatisticsGoalDashedLine(
                        points: goalPoints,
                        proxy: proxy,
                        plotFrame: geometry[plotFrame],
                    )
                }
            }
        }
    }

    private var goalPoints: [StatisticsGoalPoint] {
        days.enumerated().compactMap { index, day in
            chartType.goal(in: day).map {
                StatisticsGoalPoint(
                    weekday: day.weekday.russianShortLabel,
                    value: $0,
                    dayIndex: index,
                )
            }
        }
    }
}

private struct StatisticsGoalPoint {
    let weekday: String
    let value: Double
    let dayIndex: Int
}

private struct StatisticsGoalDashedLine: View {
    let points: [StatisticsGoalPoint]
    let proxy: ChartProxy
    let plotFrame: CGRect

    var body: some View {
        Canvas { context, _ in
            guard var runStart = points.first else { return }
            var previous = runStart

            for point in points.dropFirst() {
                if point.dayIndex == previous.dayIndex + 1, point.value == previous.value {
                    previous = point
                    continue
                }
                strokeRun(from: runStart, through: previous, in: &context)
                runStart = point
                previous = point
            }
            strokeRun(from: runStart, through: previous, in: &context)
        }
        .allowsHitTesting(false)
    }

    private func strokeRun(
        from first: StatisticsGoalPoint,
        through last: StatisticsGoalPoint,
        in context: inout GraphicsContext,
    ) {
        guard let firstPosition = position(for: first),
              let lastPosition = position(for: last)
        else {
            return
        }

        let halfBarWidth = StatisticsChartLayout.barWidth / 2
        var path = Path()
        path.move(to: CGPoint(x: firstPosition.x - halfBarWidth, y: firstPosition.y))
        path.addLine(to: CGPoint(x: lastPosition.x + halfBarWidth, y: lastPosition.y))
        context.stroke(
            path,
            with: .color(.gray),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5]),
        )
    }

    private func position(for point: StatisticsGoalPoint) -> CGPoint? {
        guard let x = proxy.position(forX: point.weekday),
              let y = proxy.position(forY: point.value)
        else {
            return nil
        }
        return CGPoint(x: plotFrame.minX + x, y: plotFrame.minY + y)
    }
}

private extension StatisticsChartType {
    var chartTitle: String { "\(russianTitle) по дням" }

    var unit: String {
        switch self {
        case .calories: "ккал"
        case .protein, .fat, .carbs: "г"
        }
    }

    var valueAxisTitle: String {
        switch self {
        case .calories: "Ккал"
        case .protein, .fat, .carbs: "Граммы"
        }
    }

    // The Today calorie progress ring uses Color.purple.
    var color: Color {
        switch self {
        case .calories: .purple
        case .protein: .blue
        case .fat: .orange
        case .carbs: .green
        }
    }

    var showsOverGoal: Bool { true }

    var actualAccessibilityLabel: String { "Фактические \(russianTitle.lowercased())" }

    var goalAccessibilityLabel: String {
        self == .calories ? "Цель калорий" : "Цель: \(russianTitle)"
    }

    var overGoalAccessibilityLabel: String {
        self == .calories ? "Превышение цели калорий" : "Превышение цели: \(russianTitle)"
    }

    func actual(in day: DayStatistics) -> Double {
        switch self {
        case .calories: day.consumedNutrition.calories
        case .protein: day.consumedNutrition.protein
        case .fat: day.consumedNutrition.fat
        case .carbs: day.consumedNutrition.carbs
        }
    }

    func goal(in day: DayStatistics) -> Double? {
        switch self {
        case .calories: day.calorieGoal
        case .protein: day.macroGoal?.protein
        case .fat: day.macroGoal?.fat
        case .carbs: day.macroGoal?.carbs
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .calories: NutritionFormatting.calories(value)
        case .protein, .fat, .carbs: NutritionFormatting.macro(value)
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
