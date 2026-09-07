import Foundation
import Observation

@MainActor
@Observable
final class MealConfigurationService {
    private let repository: any MealConfigurationRepository
    private(set) var revision = 0

    init(repository: any MealConfigurationRepository) { self.repository = repository }

    func configuration(for day: LocalDay) async throws -> MealConfiguration {
        try await repository.configuration(for: day)
    }

    func saveToday(_ meals: [MealConfigurationItem]) async throws {
        let normalized = meals.enumerated().map {
            MealConfigurationItem(mealID: $0.element.mealID,
                                  name: MealConfiguration.normalizedName($0.element.name), position: $0.offset)
        }
        _ = try await repository.saveToday(meals: normalized, today: .current(), at: Date())
        revision += 1
    }
}
