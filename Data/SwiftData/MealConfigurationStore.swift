import Foundation
import SwiftData

@Model
final class MealConfigurationRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var effectiveFromKey: String
    var mealsData: Data
    var createdAt: Date
    var updatedAt: Date

    init(_ configuration: MealConfiguration) throws {
        id = configuration.id
        effectiveFromKey = configuration.effectiveFrom.rawValue
        mealsData = try JSONEncoder().encode(configuration.meals)
        createdAt = configuration.createdAt
        updatedAt = configuration.updatedAt
    }

    func configuration() throws -> MealConfiguration {
        guard let day = LocalDay(rawValue: effectiveFromKey) else { throw MealConfigurationError.invalidConfiguration }
        let result = MealConfiguration(id: id, effectiveFrom: day,
            meals: try JSONDecoder().decode([MealConfigurationItem].self, from: mealsData),
            createdAt: createdAt, updatedAt: updatedAt)
        try result.validate()
        return result
    }

    func apply(_ configuration: MealConfiguration) throws {
        mealsData = try JSONEncoder().encode(configuration.meals)
        createdAt = configuration.createdAt
        updatedAt = configuration.updatedAt
    }
}

enum MealMigration {
    static func normalizeEntries(in context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<DiaryEntryRecord>()) where record.mealID == nil {
            guard let legacy = LegacyMealType(rawValue: record.mealTypeRaw) else {
                throw MealConfigurationError.invalidConfiguration
            }
            record.mealID = legacy.mealID
            // All snapshots, timestamps and tombstones remain byte-for-byte unchanged.
        }
    }

    @MainActor
    static func prepare(in context: ModelContext) throws {
        try normalizeEntries(in: context)
        if try context.fetchCount(FetchDescriptor<MealConfigurationRecord>()) == 0 {
            let initial = InitialMeals.configuration
            context.insert(try MealConfigurationRecord(initial))
            try SyncOutboxStore.markChanged(type: .mealConfiguration, id: initial.id, in: context)
            // An ordinary installation only seeds the timeless baseline: its
            // installation date must not shadow a real configuration from sync.
            // The migration exception is an existing active snack TODAY. Persist
            // that section until the user can empty and explicitly remove it.
            let today = LocalDay.current()
            let todayKey = today.rawValue
            let snackID = LegacyMealType.snack.mealID
            let entries = try context.fetch(FetchDescriptor<DiaryEntryRecord>(
                predicate: #Predicate { $0.dayKey == todayKey && $0.deletedAt == nil }))
            if entries.contains(where: { $0.mealID == snackID && !$0.mealTypeRaw.isEmpty }) {
                var meals = initial.meals
                meals.append(MealConfigurationItem(mealID: snackID,
                    name: LegacyMealType.snack.russianLabel, position: meals.count))
                let now = SyncTimestamp.canonical(Date())
                let migrated = MealConfiguration(id: MealConfigurationIdentity.id(for: today),
                    effectiveFrom: today, meals: meals, createdAt: now, updatedAt: now)
                context.insert(try MealConfigurationRecord(migrated))
                try SyncOutboxStore.markChanged(type: .mealConfiguration, id: migrated.id, in: context)
            }
        }
        if context.hasChanges { try context.save() }
    }
}

@MainActor
final class SwiftDataMealConfigurationRepository: MealConfigurationRepository {
    private let container: ModelContainer
    private let notifier: SyncChangeNotifier?
    init(modelContainer: ModelContainer, syncChangeNotifier: SyncChangeNotifier?) {
        container = modelContainer
        notifier = syncChangeNotifier
    }

    func configuration(for day: LocalDay) async throws -> MealConfiguration {
        try resolve(day: day, in: ModelContext(container))
    }

    private func resolve(day: LocalDay, in context: ModelContext) throws -> MealConfiguration {
        let key = day.rawValue
        let records = try context.fetch(FetchDescriptor<MealConfigurationRecord>(
            predicate: #Predicate { $0.effectiveFromKey <= key },
            sortBy: [SortDescriptor(\MealConfigurationRecord.effectiveFromKey, order: .reverse)]))
        var result = try records.first?.configuration() ?? InitialMeals.configuration
        let entries = try context.fetch(FetchDescriptor<DiaryEntryRecord>(
            predicate: #Predicate { $0.dayKey == key && $0.deletedAt == nil }))
        let known = Set(result.meals.map(\.mealID))
        let missing = Set(entries.compactMap(\.mealID)).subtracting(known).sorted { $0.uuidString < $1.uuidString }
        // Never hide entries when their configuration arrives later or a
        // concurrent configuration edit removes their section.
        for id in missing {
            let priorName = try records.lazy.compactMap { try $0.configuration().meals.first { $0.mealID == id }?.name }.first
            var unresolvedName = "Приём пищи"
            var suffix = 1
            while result.meals.contains(where: { $0.name.lowercased() == unresolvedName.lowercased() }) {
                suffix += 1
                unresolvedName = "Приём пищи \(suffix)"
            }
            result.meals.append(MealConfigurationItem(mealID: id,
                name: priorName ?? LegacyMealType.historicalName(for: id) ?? unresolvedName,
                position: result.meals.count))
        }
        return result
    }

    func saveToday(meals: [MealConfigurationItem], today: LocalDay, at timestamp: Date) async throws -> MealConfiguration {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let key = today.rawValue
        let existing = try context.fetch(FetchDescriptor<MealConfigurationRecord>(
            predicate: #Predicate { $0.effectiveFromKey == key })).first
        let now = SyncTimestamp.canonical(timestamp)
        let configuration = MealConfiguration(id: MealConfigurationIdentity.id(for: today), effectiveFrom: today,
            meals: meals, createdAt: existing?.createdAt ?? now, updatedAt: max(now, existing?.updatedAt ?? now))
        try configuration.validate()
        let activeIDs = Set(meals.map(\.mealID))
        let entries = try context.fetch(FetchDescriptor<DiaryEntryRecord>(
            predicate: #Predicate { $0.dayKey == key && $0.deletedAt == nil }))
        guard entries.allSatisfy({ $0.mealID.map(activeIDs.contains) == true }) else {
            throw MealConfigurationError.hasEntries
        }
        if let existing { try existing.apply(configuration) }
        else { context.insert(try MealConfigurationRecord(configuration)) }
        try SyncOutboxStore.markChanged(type: .mealConfiguration, id: configuration.id, in: context)
        try context.save()
        notifier?.localSyncableMutationCommitted()
        return configuration
    }
}
