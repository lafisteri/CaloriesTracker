import Foundation

enum SyncPayloadFormat {
    static let currentSchemaVersion = 1
}

struct SyncPayloadEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let payload: SyncPayload

    init(
        schemaVersion: Int = SyncPayloadFormat.currentSchemaVersion,
        payload: SyncPayload,
    ) {
        self.schemaVersion = schemaVersion
        self.payload = payload
    }
}

enum SyncPayload: Codable, Equatable, Sendable {
    case product(ProductPayload)
    case productVersion(ProductVersionPayload)
    case recipe(RecipePayload)
    case recipeVersion(RecipeVersionPayload)
    case diaryEntry(DiaryEntryPayload)
    case weeklyGoal(WeeklyGoalPayload)

    var key: SyncEntityKey {
        switch self {
        case let .product(payload):
            SyncEntityKey(entityType: .product, entityID: payload.id)
        case let .productVersion(payload):
            SyncEntityKey(entityType: .productVersion, entityID: payload.id)
        case let .recipe(payload):
            SyncEntityKey(entityType: .recipe, entityID: payload.id)
        case let .recipeVersion(payload):
            SyncEntityKey(entityType: .recipeVersion, entityID: payload.id)
        case let .diaryEntry(payload):
            SyncEntityKey(entityType: .diaryEntry, entityID: payload.id)
        case let .weeklyGoal(payload):
            SyncEntityKey(entityType: .weeklyGoal, entityID: payload.id)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case entityType
        case payload
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(SyncEntityType.self, forKey: .entityType) {
        case .product:
            self = .product(try container.decode(ProductPayload.self, forKey: .payload))
        case .productVersion:
            self = .productVersion(try container.decode(ProductVersionPayload.self, forKey: .payload))
        case .recipe:
            self = .recipe(try container.decode(RecipePayload.self, forKey: .payload))
        case .recipeVersion:
            self = .recipeVersion(try container.decode(RecipeVersionPayload.self, forKey: .payload))
        case .diaryEntry:
            self = .diaryEntry(try container.decode(DiaryEntryPayload.self, forKey: .payload))
        case .weeklyGoal:
            self = .weeklyGoal(try container.decode(WeeklyGoalPayload.self, forKey: .payload))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key.entityType, forKey: .entityType)
        switch self {
        case let .product(payload):
            try container.encode(payload, forKey: .payload)
        case let .productVersion(payload):
            try container.encode(payload, forKey: .payload)
        case let .recipe(payload):
            try container.encode(payload, forKey: .payload)
        case let .recipeVersion(payload):
            try container.encode(payload, forKey: .payload)
        case let .diaryEntry(payload):
            try container.encode(payload, forKey: .payload)
        case let .weeklyGoal(payload):
            try container.encode(payload, forKey: .payload)
        }
    }
}

struct ProductPayload: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let barcode: String?
    let currentVersionID: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

struct ProductVersionPayload: Codable, Equatable, Sendable {
    let id: UUID
    let productID: UUID
    let basedOnVersionID: UUID?
    let versionNumber: Int
    let baseUnit: ProductBaseUnit
    let baseAmount: Double
    let nutrition: Nutrition
    let createdAt: Date
}

struct RecipePayload: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let currentVersionID: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

struct RecipeVersionPayload: Codable, Equatable, Sendable {
    struct Ingredient: Codable, Equatable, Sendable {
        let id: UUID
        let recipeVersionID: UUID
        let position: Int
        let productID: UUID
        let productVersionID: UUID
        let amount: Double
        let unitToken: String
        let normalizedAmount: Double
    }

    let id: UUID
    let recipeID: UUID
    let basedOnVersionID: UUID?
    let versionNumber: Int
    let totalNutrition: Nutrition
    let cookedWeight: Double?
    let servingsCount: Double?
    let ingredients: [Ingredient]
    let createdAt: Date
}

struct DiaryEntryPayload: Codable, Equatable, Sendable {
    let id: UUID
    let day: LocalDay
    let mealType: MealType
    let sortOrder: Int
    let sourceType: SourceType
    let sourceID: UUID
    let sourceVersionID: UUID
    let sourceName: String
    let amount: Double
    let unitToken: String
    let nutrition: Nutrition
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

struct WeeklyGoalPayload: Codable, Equatable, Sendable {
    struct Day: Codable, Equatable, Sendable {
        let id: UUID
        let weeklyGoalID: UUID
        let weekday: LocalDay.Weekday
        let position: Int
        let goal: DailyMacroGoal
    }

    let id: UUID
    let effectiveFrom: LocalDay
    let days: [Day]
    let createdAt: Date
}

enum SyncPayloadCanonicalizer {
    static func compare(_ lhs: SyncPayload, _ rhs: SyncPayload) throws -> ComparisonResult {
        let lhsData = try canonicalData(for: lhs)
        let rhsData = try canonicalData(for: rhs)
        if lhsData == rhsData {
            return .orderedSame
        }
        return lhsData.lexicographicallyPrecedes(rhsData) ? .orderedAscending : .orderedDescending
    }

    private static func canonicalData(for payload: SyncPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(SyncPayloadEnvelope(payload: payload))
    }
}
