import Foundation

struct MealConfigurationItem: Identifiable, Hashable, Codable, Sendable {
    let mealID: UUID
    var name: String
    var position: Int
    var id: UUID { mealID }
}

struct MealConfiguration: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let effectiveFrom: LocalDay
    var meals: [MealConfigurationItem]
    let createdAt: Date
    var updatedAt: Date

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func validate() throws {
        guard !meals.isEmpty else { throw MealConfigurationError.lastMeal }
        let names = meals.map { Self.normalizedName($0.name).lowercased() }
        guard meals.allSatisfy({ !$0.name.isEmpty && $0.name == Self.normalizedName($0.name) }) else {
            throw MealConfigurationError.invalidName
        }
        guard Set(names).count == names.count else { throw MealConfigurationError.duplicateName }
        guard Set(meals.map(\.mealID)).count == meals.count,
              meals.map(\.position) == Array(meals.indices),
              id == MealConfigurationIdentity.id(for: effectiveFrom),
              SyncTimestamp.millisecondsSinceEpoch(createdAt) != nil,
              SyncTimestamp.millisecondsSinceEpoch(updatedAt) != nil,
              updatedAt >= createdAt
        else { throw MealConfigurationError.invalidConfiguration }
    }
}

enum MealConfigurationError: LocalizedError {
    case lastMeal, hasEntries, invalidName, duplicateName, invalidConfiguration
    var errorDescription: String? {
        switch self {
        case .lastMeal: "Должен остаться хотя бы один приём пищи."
        case .hasEntries: "Нельзя удалить приём пищи: в нём есть записи за сегодня."
        case .invalidName: "Введите название приёма пищи."
        case .duplicateName: "Приём пищи с таким названием уже существует."
        case .invalidConfiguration: "Некорректная конфигурация приёмов пищи."
        }
    }
}

extension LegacyMealType {
    // Permanent cross-device compatibility identities; never regenerate.
    var mealID: UUID {
        switch self {
        case .breakfast: UUID(uuidString: "C42E7260-4759-5F47-8000-000000000001")!
        case .lunch: UUID(uuidString: "C42E7260-4759-5F47-8000-000000000002")!
        case .dinner: UUID(uuidString: "C42E7260-4759-5F47-8000-000000000003")!
        case .snack: UUID(uuidString: "C42E7260-4759-5F47-8000-000000000004")!
        }
    }

    static func historicalName(for id: UUID) -> String? {
        allCases.first { $0.mealID == id }?.russianLabel
    }
}

enum InitialMeals {
    static let effectiveFrom = LocalDay(rawValue: "0001-01-01")!
    static var configuration: MealConfiguration {
        MealConfiguration(
            id: MealConfigurationIdentity.id(for: effectiveFrom),
            effectiveFrom: effectiveFrom,
            meals: [LegacyMealType.breakfast, .lunch, .dinner].enumerated().map {
                MealConfigurationItem(mealID: $0.element.mealID, name: $0.element.russianLabel, position: $0.offset)
            },
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
