import Foundation
import SwiftData

@Model
final class ChartSettingsRecord {
    @Attribute(.unique) var id: UUID
    var itemsData: Data
    var createdAt: Date
    var updatedAt: Date

    init(_ settings: ChartSettings) throws {
        id = settings.id
        itemsData = try JSONEncoder().encode(settings.items)
        createdAt = settings.createdAt
        updatedAt = settings.updatedAt
    }

    func settings() throws -> ChartSettings {
        ChartSettings(
            id: id,
            items: try JSONDecoder().decode([ChartSettingsItem].self, from: itemsData),
            createdAt: createdAt,
            updatedAt: updatedAt,
        )
    }

    func apply(_ settings: ChartSettings) throws {
        guard id == settings.id else { throw ChartSettingsError.invalidIdentity }
        itemsData = try JSONEncoder().encode(settings.items)
        createdAt = settings.createdAt
        updatedAt = settings.updatedAt
    }
}

@MainActor
enum ChartSettingsStore {
    static func prepare(in context: ModelContext) throws {
        let id = ChartSettingsIdentity.id
        let descriptor = FetchDescriptor<ChartSettingsRecord>(
            predicate: #Predicate { $0.id == id },
        )
        guard try context.fetch(descriptor).isEmpty else { return }

        let initial = ChartSettings.default
        context.insert(try ChartSettingsRecord(initial))
        try SyncOutboxStore.markChanged(type: .chartSettings, id: initial.id, in: context)
        try context.save()
    }
}

@MainActor
final class SwiftDataChartSettingsRepository: ChartSettingsRepository {
    private let container: ModelContainer
    private let notifier: SyncChangeNotifier?

    init(modelContainer: ModelContainer, syncChangeNotifier: SyncChangeNotifier?) {
        container = modelContainer
        notifier = syncChangeNotifier
    }

    func settings() async throws -> ChartSettings {
        let context = ModelContext(container)
        guard let record = try chartSettingsRecord(in: context) else {
            return .default
        }
        let settings = try record.settings()
        try settings.validate()
        return settings
    }

    func save(_ settings: ChartSettings) async throws {
        try settings.validate()
        let context = ModelContext(container)
        if let existing = try chartSettingsRecord(in: context) {
            try existing.apply(settings)
        } else {
            context.insert(try ChartSettingsRecord(settings))
        }
        try SyncOutboxStore.markChanged(type: .chartSettings, id: settings.id, in: context)
        try context.save()
        notifier?.localSyncableMutationCommitted()
    }

    private func chartSettingsRecord(in context: ModelContext) throws -> ChartSettingsRecord? {
        let id = ChartSettingsIdentity.id
        var descriptor = FetchDescriptor<ChartSettingsRecord>(
            predicate: #Predicate { $0.id == id },
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
