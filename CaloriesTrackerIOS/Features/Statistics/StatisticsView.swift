import Charts
import SwiftUI

struct StatisticsView: View {
    let router: AppRouter

    @State private var model: StatisticsViewModel

    init(router: AppRouter, statisticsService: StatisticsService) {
        self.router = router
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

                Section {
                    WeeklyCaloriesChart(days: statistics.days)
                        .frame(height: 190)
                }

                Section {
                    LabeledContent("Баланс недели", value: calorieBalanceLabel(statistics.weeklyCalorieBalance))
                }

                Section {
                    WeeklyMacroDistribution(distribution: statistics.macroDistribution)
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
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Настроить цели") {
                    router.statisticsPath.append(.goals)
                }
            }
        }
        .onAppear {
            Task {
                await model.load()
            }
        }
        .onChange(of: router.statisticsPath) { _, path in
            guard path.isEmpty else {
                return
            }
            Task {
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func weekNavigation(for statistics: WeekStatistics) -> some View {
        Section {
            HStack {
                Button {
                    Task {
                        await model.previousWeek()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                VStack(spacing: 2) {
                    Text(weekRangeLabel(for: statistics))
                        .font(.headline)
                    if !model.isCurrentWeek {
                        Button("Текущая неделя") {
                            Task {
                                await model.goToCurrentWeek()
                            }
                        }
                        .font(.caption)
                    }
                }

                Spacer()

                Button {
                    Task {
                        await model.nextWeek()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.borderless)
        }
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

private struct WeeklyMacroDistribution: View {
    let distribution: MacroDistribution

    var body: some View {
        if distribution.hasEnergy {
            VStack(spacing: 10) {
                Chart(distribution.components) { component in
                    SectorMark(
                        angle: .value("Энергия", component.energy),
                        innerRadius: .ratio(0.62),
                        angularInset: 1,
                    )
                    .foregroundStyle(color(for: component.nutrient))
                }
                .chartLegend(.hidden)
                .frame(height: 130)

                HStack(spacing: 12) {
                    ForEach(distribution.components) { component in
                        Text("\(macroLabel(component.nutrient)) \(formattedNumber(component.percentage))%")
                            .font(.footnote)
                            .foregroundStyle(color(for: component.nutrient))
                    }
                }
            }
        } else {
            Text("Нет данных за неделю.")
                .foregroundStyle(.secondary)
        }
    }

    private func color(for nutrient: MacroNutrient) -> Color {
        switch nutrient {
        case .protein: .blue
        case .fat: .orange
        case .carbs: .green
        }
    }

    private func macroLabel(_ nutrient: MacroNutrient) -> String {
        switch nutrient {
        case .protein: "Б"
        case .fat: "Ж"
        case .carbs: "У"
        }
    }
}

private func calorieBalanceLabel(_ balance: Double?) -> String {
    guard let balance else {
        return "—"
    }
    let prefix = balance > 0 ? "+" : ""
    return "\(prefix)\(formattedNumber(balance)) ккал"
}

private struct StatisticsInlineErrorView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
