import Foundation
import Observation

@MainActor
@Observable
final class ChartSettingsService {
    private let repository: any ChartSettingsRepository
    private var retainedUnknownItems: [ChartSettingsItem] = []
    private(set) var revision = 0

    init(repository: any ChartSettingsRepository) {
        self.repository = repository
    }

    func settings() async throws -> ChartSettings {
        let settings = try await repository.settings()
        retainedUnknownItems = settings.items.filter { $0.chartType == nil }
        return settings
    }

    func save(knownItems: [ChartSettingsItem]) async throws {
        let normalizedKnownItems = knownItems.enumerated().map {
            ChartSettingsItem(
                chartTypeRaw: $0.element.chartTypeRaw,
                isEnabled: $0.element.isEnabled,
                position: $0.offset,
            )
        }
        let unknownItems = retainedUnknownItems.enumerated().map {
            ChartSettingsItem(
                chartTypeRaw: $0.element.chartTypeRaw,
                isEnabled: $0.element.isEnabled,
                position: normalizedKnownItems.count + $0.offset,
            )
        }
        let existing = try await repository.settings()
        let now = SyncTimestamp.canonical(Date())
        let updated = ChartSettings(
            id: existing.id,
            items: normalizedKnownItems + unknownItems,
            createdAt: existing.createdAt,
            updatedAt: max(now, existing.updatedAt),
        )
        try updated.validate()
        try await repository.save(updated)
        retainedUnknownItems = unknownItems
        revision += 1
    }
}
