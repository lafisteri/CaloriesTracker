import Foundation

enum StatisticsChartType: String, CaseIterable, Codable, Hashable, Sendable {
    case calories
    case protein
    case fat
    case carbs
}

extension StatisticsChartType {
    var russianTitle: String {
        switch self {
        case .calories: "Калории"
        case .protein: "Белки"
        case .fat: "Жиры"
        case .carbs: "Углеводы"
        }
    }
}

struct ChartSettingsItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    let chartTypeRaw: String
    var isEnabled: Bool
    var position: Int

    var id: String { chartTypeRaw }
    var chartType: StatisticsChartType? { StatisticsChartType(rawValue: chartTypeRaw) }

    init(chartType: StatisticsChartType, isEnabled: Bool = true, position: Int) {
        chartTypeRaw = chartType.rawValue
        self.isEnabled = isEnabled
        self.position = position
    }

    init(chartTypeRaw: String, isEnabled: Bool, position: Int) {
        self.chartTypeRaw = chartTypeRaw
        self.isEnabled = isEnabled
        self.position = position
    }
}

struct ChartSettings: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var items: [ChartSettingsItem]
    let createdAt: Date
    var updatedAt: Date

    static let `default` = ChartSettings(
        id: ChartSettingsIdentity.id,
        items: StatisticsChartType.allCases.enumerated().map {
            ChartSettingsItem(chartType: $0.element, position: $0.offset)
        },
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
    )

    var orderedKnownItems: [ChartSettingsItem] {
        items
            .filter { $0.chartType != nil }
            .sorted { $0.position < $1.position }
    }

    func validate() throws {
        guard id == ChartSettingsIdentity.id else {
            throw ChartSettingsError.invalidIdentity
        }
        guard !items.contains(where: { $0.chartTypeRaw.isEmpty }) else {
            throw ChartSettingsError.emptyChartType
        }
        guard Set(items.map(\.chartTypeRaw)).count == items.count else {
            throw ChartSettingsError.duplicateChartType
        }
        guard items.map(\.position) == Array(items.indices) else {
            throw ChartSettingsError.invalidPositions
        }

        let knownTypes = items.compactMap(\.chartType)
        guard knownTypes.count == StatisticsChartType.allCases.count,
              Set(knownTypes) == Set(StatisticsChartType.allCases)
        else {
            throw ChartSettingsError.missingKnownChartType
        }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite
        else {
            throw ChartSettingsError.invalidTimestamp
        }
    }
}

enum ChartSettingsError: Error, LocalizedError {
    case invalidIdentity
    case emptyChartType
    case duplicateChartType
    case invalidPositions
    case missingKnownChartType
    case invalidTimestamp

    var errorDescription: String? {
        switch self {
        case .invalidIdentity: "Некорректный идентификатор настроек графиков."
        case .emptyChartType: "Идентификатор графика пуст."
        case .duplicateChartType: "Графики не должны повторяться."
        case .invalidPositions: "Порядок графиков некорректен."
        case .missingKnownChartType: "В настройках отсутствует известный график."
        case .invalidTimestamp: "Время изменения настроек некорректно."
        }
    }
}
