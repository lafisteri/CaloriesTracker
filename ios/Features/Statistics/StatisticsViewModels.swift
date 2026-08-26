import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class StatisticsViewModel {
    private let statisticsService: StatisticsService

    private(set) var selectedDay: LocalDay
    private(set) var statistics: WeekStatistics?
    private(set) var isLoading = false
    var errorMessage: String?

    init(statisticsService: StatisticsService, selectedDay: LocalDay = .current()) {
        self.statisticsService = statisticsService
        self.selectedDay = selectedDay
    }

    var isCurrentWeek: Bool {
        selectedDay.mondayOfWeek() == LocalDay.current().mondayOfWeek()
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            statistics = try await statisticsService.week(containing: selectedDay)
        } catch {
            statisticsErrorLogger.error(
                "user_facing_error technical_error=\(String(reflecting: error), privacy: .public)",
            )
            errorMessage = "Не удалось загрузить статистику."
        }

        isLoading = false
    }

    func previousWeek() async {
        selectedDay = selectedDay.adding(days: -7)
        await load()
    }

    func nextWeek() async {
        selectedDay = selectedDay.adding(days: 7)
        await load()
    }

    func goToCurrentWeek() async {
        selectedDay = .current()
        await load()
    }
}

private let statisticsErrorLogger = Logger(subsystem: "com.caloriestracker.ios", category: "Statistics")
