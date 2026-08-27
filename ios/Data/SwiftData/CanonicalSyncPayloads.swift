import Foundation

enum SyncPayloadFormat {
    static let currentSchemaVersion = 1
}

/// The only timestamp precision used at the sync canonical boundary.
///
/// Unix milliseconds are the source of truth. `Date` cannot represent every
/// millisecond exactly, so a canonical `Date` can print just below its integer
/// millisecond. The ULP-sized snap below only recovers that representation noise;
/// all original, non-boundary timestamps still truncate to milliseconds.
enum SyncTimestamp {
    private static let millisecondsPerSecond = 1_000.0
    private static let integerSnapULPs = 4.0

    /// Converts a `Date` to the authoritative Unix-millisecond representation.
    ///
    /// This is deliberately not a fuzzy comparison: only a value within a few
    /// floating-point ULPs of an integer millisecond is snapped to that integer.
    /// Every other timestamp is truncated to milliseconds.
    static func millisecondsSinceEpoch(_ date: Date) -> Int64? {
        let milliseconds = date.timeIntervalSince1970 * millisecondsPerSecond
        guard
            milliseconds.isFinite,
            milliseconds >= Double(Int64.min),
            milliseconds <= Double(Int64.max)
        else {
            return nil
        }

        let nearestInteger = milliseconds.rounded(.toNearestOrAwayFromZero)
        if abs(milliseconds - nearestInteger) <= milliseconds.ulp * integerSnapULPs,
           nearestInteger >= Double(Int64.min),
           nearestInteger <= Double(Int64.max)
        {
            return Int64(nearestInteger)
        }

        return Int64(milliseconds.rounded(.down))
    }

    /// Reconstructs a Date from the authoritative Unix-millisecond representation.
    static func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / millisecondsPerSecond)
    }

    static func canonical(_ date: Date) -> Date {
        guard let milliseconds = millisecondsSinceEpoch(date) else { return date }
        return Self.date(fromMilliseconds: milliseconds)
    }

    static func canonical(_ date: Date?) -> Date? {
        date.map { canonical($0) }
    }

    /// Encodes a canonical domain timestamp without handing its reconstructed
    /// `Date` to another formatter. The payload JSON remains ISO-8601 strings.
    static func encode<Key: CodingKey>(
        _ date: Date,
        to container: inout KeyedEncodingContainer<Key>,
        forKey key: Key,
    ) throws {
        guard let milliseconds = millisecondsSinceEpoch(date) else {
            throw EncodingError.invalidValue(
                date,
                .init(codingPath: container.codingPath + [key], debugDescription: "Timestamp is not representable as Unix milliseconds"),
            )
        }
        try container.encode(iso8601String(fromMilliseconds: milliseconds), forKey: key)
    }

    static func encode<Key: CodingKey>(
        _ date: Date?,
        to container: inout KeyedEncodingContainer<Key>,
        forKey key: Key,
    ) throws {
        guard let date else {
            try container.encodeNil(forKey: key)
            return
        }
        try encode(date, to: &container, forKey: key)
    }

    static func decode<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key,
    ) throws -> Date {
        let wireValue = try container.decode(String.self, forKey: key)
        guard let milliseconds = milliseconds(fromISO8601: wireValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Timestamp is not a supported ISO-8601 value",
            )
        }
        return date(fromMilliseconds: milliseconds)
    }

    static func decodeIfPresent<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key,
    ) throws -> Date? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else { return nil }
        return try decode(from: container, forKey: key)
    }

    private static func milliseconds(fromISO8601 value: String) -> Int64? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSecondFormatter = ISO8601DateFormatter()
        wholeSecondFormatter.formatOptions = [.withInternetDateTime]
        guard let date = fractionalFormatter.date(from: value) ?? wholeSecondFormatter.date(from: value) else {
            return nil
        }
        return millisecondsSinceEpoch(date)
    }

    private static func iso8601String(fromMilliseconds milliseconds: Int64) -> String {
        let wholeSeconds = milliseconds / 1_000
        let remainder = milliseconds % 1_000
        let normalizedSeconds: Int64
        let fractionalMilliseconds: Int64
        if remainder < 0 {
            normalizedSeconds = wholeSeconds - 1
            fractionalMilliseconds = remainder + 1_000
        } else {
            normalizedSeconds = wholeSeconds
            fractionalMilliseconds = remainder
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let wholeSecondValue = formatter.string(
            from: Date(timeIntervalSince1970: TimeInterval(normalizedSeconds)),
        )
        let fraction = String(fractionalMilliseconds)
        let paddedFraction = String(repeating: "0", count: 3 - fraction.count) + fraction
        return "\(wholeSecondValue.dropLast()).\(paddedFraction)Z"
    }
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

    /// Reconstructs every domain payload with sync-canonical timestamps. This is
    /// deliberately exhaustive so a new payload Date cannot bypass the boundary.
    func canonicalizedTimestamps() -> SyncPayload {
        switch self {
        case let .product(payload):
            .product(
                ProductPayload(
                    id: payload.id,
                    name: payload.name,
                    barcode: payload.barcode,
                    currentVersionID: payload.currentVersionID,
                    createdAt: SyncTimestamp.canonical(payload.createdAt),
                    updatedAt: SyncTimestamp.canonical(payload.updatedAt),
                    deletedAt: SyncTimestamp.canonical(payload.deletedAt),
                ),
            )
        case let .productVersion(payload):
            .productVersion(
                ProductVersionPayload(
                    id: payload.id,
                    productID: payload.productID,
                    basedOnVersionID: payload.basedOnVersionID,
                    versionNumber: payload.versionNumber,
                    baseUnit: payload.baseUnit,
                    baseAmount: payload.baseAmount,
                    nutrition: payload.nutrition,
                    createdAt: SyncTimestamp.canonical(payload.createdAt),
                ),
            )
        case let .recipe(payload):
            .recipe(
                RecipePayload(
                    id: payload.id,
                    name: payload.name,
                    currentVersionID: payload.currentVersionID,
                    createdAt: SyncTimestamp.canonical(payload.createdAt),
                    updatedAt: SyncTimestamp.canonical(payload.updatedAt),
                    deletedAt: SyncTimestamp.canonical(payload.deletedAt),
                ),
            )
        case let .recipeVersion(payload):
            .recipeVersion(
                RecipeVersionPayload(
                    id: payload.id,
                    recipeID: payload.recipeID,
                    basedOnVersionID: payload.basedOnVersionID,
                    versionNumber: payload.versionNumber,
                    totalNutrition: payload.totalNutrition,
                    cookedWeight: payload.cookedWeight,
                    servingsCount: payload.servingsCount,
                    ingredients: payload.ingredients,
                    createdAt: SyncTimestamp.canonical(payload.createdAt),
                ),
            )
        case let .diaryEntry(payload):
            .diaryEntry(
                DiaryEntryPayload(
                    id: payload.id,
                    day: payload.day,
                    mealType: payload.mealType,
                    sortOrder: payload.sortOrder,
                    sourceType: payload.sourceType,
                    sourceID: payload.sourceID,
                    sourceVersionID: payload.sourceVersionID,
                    sourceName: payload.sourceName,
                    amount: payload.amount,
                    unitToken: payload.unitToken,
                    nutrition: payload.nutrition,
                    createdAt: SyncTimestamp.canonical(payload.createdAt),
                    updatedAt: SyncTimestamp.canonical(payload.updatedAt),
                    deletedAt: SyncTimestamp.canonical(payload.deletedAt),
                ),
            )
        case let .weeklyGoal(payload):
            .weeklyGoal(
                WeeklyGoalPayload(
                    id: payload.id,
                    effectiveFrom: payload.effectiveFrom,
                    days: payload.days,
                    createdAt: SyncTimestamp.canonical(payload.createdAt),
                    updatedAt: SyncTimestamp.canonical(payload.updatedAt),
                ),
            )
        }
    }

    /// Rewrites only WeeklyGoal's logical identity at the sync boundary.
    /// Remote legacy aliases keep their physical record key outside this value;
    /// the payload itself always represents the canonical local aggregate.
    func canonicalizedIdentity() -> SyncPayload {
        switch self {
        case let .weeklyGoal(payload):
            .weeklyGoal(payload.canonicalizedIdentity())
        case .product, .productVersion, .recipe, .recipeVersion, .diaryEntry:
            self
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
    let updatedAt: Date
}

extension WeeklyGoalPayload {
    func canonicalizedIdentity() -> WeeklyGoalPayload {
        let canonicalID = WeeklyGoalIdentity.id(for: effectiveFrom)
        return WeeklyGoalPayload(
            id: canonicalID,
            effectiveFrom: effectiveFrom,
            days: days.map { day in
                Day(
                    id: day.id,
                    weeklyGoalID: canonicalID,
                    weekday: day.weekday,
                    position: day.position,
                    goal: day.goal,
                )
            },
            createdAt: createdAt,
            updatedAt: updatedAt,
        )
    }
}

// Domain timestamp fields use this explicit codec instead of the enclosing
// JSONEncoder's Date strategy. That makes canonical JSON and Supabase RPC JSON
// originate from the same integer millisecond values.
extension ProductPayload {
    private enum CodingKeys: String, CodingKey {
        case id, name, barcode, currentVersionID, createdAt, updatedAt, deletedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            barcode: try container.decodeIfPresent(String.self, forKey: .barcode),
            currentVersionID: try container.decode(UUID.self, forKey: .currentVersionID),
            createdAt: try SyncTimestamp.decode(from: container, forKey: .createdAt),
            updatedAt: try SyncTimestamp.decode(from: container, forKey: .updatedAt),
            deletedAt: try SyncTimestamp.decodeIfPresent(from: container, forKey: .deletedAt),
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(barcode, forKey: .barcode)
        try container.encode(currentVersionID, forKey: .currentVersionID)
        try SyncTimestamp.encode(createdAt, to: &container, forKey: .createdAt)
        try SyncTimestamp.encode(updatedAt, to: &container, forKey: .updatedAt)
        try SyncTimestamp.encode(deletedAt, to: &container, forKey: .deletedAt)
    }
}

extension ProductVersionPayload {
    private enum CodingKeys: String, CodingKey {
        case id, productID, basedOnVersionID, versionNumber, baseUnit, baseAmount, nutrition, createdAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            productID: try container.decode(UUID.self, forKey: .productID),
            basedOnVersionID: try container.decodeIfPresent(UUID.self, forKey: .basedOnVersionID),
            versionNumber: try container.decode(Int.self, forKey: .versionNumber),
            baseUnit: try container.decode(ProductBaseUnit.self, forKey: .baseUnit),
            baseAmount: try container.decode(Double.self, forKey: .baseAmount),
            nutrition: try container.decode(Nutrition.self, forKey: .nutrition),
            createdAt: try SyncTimestamp.decode(from: container, forKey: .createdAt),
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(productID, forKey: .productID)
        try container.encodeIfPresent(basedOnVersionID, forKey: .basedOnVersionID)
        try container.encode(versionNumber, forKey: .versionNumber)
        try container.encode(baseUnit, forKey: .baseUnit)
        try container.encode(baseAmount, forKey: .baseAmount)
        try container.encode(nutrition, forKey: .nutrition)
        try SyncTimestamp.encode(createdAt, to: &container, forKey: .createdAt)
    }
}

extension RecipePayload {
    private enum CodingKeys: String, CodingKey {
        case id, name, currentVersionID, createdAt, updatedAt, deletedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            currentVersionID: try container.decode(UUID.self, forKey: .currentVersionID),
            createdAt: try SyncTimestamp.decode(from: container, forKey: .createdAt),
            updatedAt: try SyncTimestamp.decode(from: container, forKey: .updatedAt),
            deletedAt: try SyncTimestamp.decodeIfPresent(from: container, forKey: .deletedAt),
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(currentVersionID, forKey: .currentVersionID)
        try SyncTimestamp.encode(createdAt, to: &container, forKey: .createdAt)
        try SyncTimestamp.encode(updatedAt, to: &container, forKey: .updatedAt)
        try SyncTimestamp.encode(deletedAt, to: &container, forKey: .deletedAt)
    }
}

extension RecipeVersionPayload {
    private enum CodingKeys: String, CodingKey {
        case id, recipeID, basedOnVersionID, versionNumber, totalNutrition, cookedWeight, servingsCount, ingredients, createdAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            recipeID: try container.decode(UUID.self, forKey: .recipeID),
            basedOnVersionID: try container.decodeIfPresent(UUID.self, forKey: .basedOnVersionID),
            versionNumber: try container.decode(Int.self, forKey: .versionNumber),
            totalNutrition: try container.decode(Nutrition.self, forKey: .totalNutrition),
            cookedWeight: try container.decodeIfPresent(Double.self, forKey: .cookedWeight),
            servingsCount: try container.decodeIfPresent(Double.self, forKey: .servingsCount),
            ingredients: try container.decode([Ingredient].self, forKey: .ingredients),
            createdAt: try SyncTimestamp.decode(from: container, forKey: .createdAt),
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(recipeID, forKey: .recipeID)
        try container.encodeIfPresent(basedOnVersionID, forKey: .basedOnVersionID)
        try container.encode(versionNumber, forKey: .versionNumber)
        try container.encode(totalNutrition, forKey: .totalNutrition)
        try container.encodeIfPresent(cookedWeight, forKey: .cookedWeight)
        try container.encodeIfPresent(servingsCount, forKey: .servingsCount)
        try container.encode(ingredients, forKey: .ingredients)
        try SyncTimestamp.encode(createdAt, to: &container, forKey: .createdAt)
    }
}

extension DiaryEntryPayload {
    private enum CodingKeys: String, CodingKey {
        case id, day, mealType, sortOrder, sourceType, sourceID, sourceVersionID, sourceName, amount, unitToken, nutrition, createdAt, updatedAt, deletedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            day: try container.decode(LocalDay.self, forKey: .day),
            mealType: try container.decode(MealType.self, forKey: .mealType),
            sortOrder: try container.decode(Int.self, forKey: .sortOrder),
            sourceType: try container.decode(SourceType.self, forKey: .sourceType),
            sourceID: try container.decode(UUID.self, forKey: .sourceID),
            sourceVersionID: try container.decode(UUID.self, forKey: .sourceVersionID),
            sourceName: try container.decode(String.self, forKey: .sourceName),
            amount: try container.decode(Double.self, forKey: .amount),
            unitToken: try container.decode(String.self, forKey: .unitToken),
            nutrition: try container.decode(Nutrition.self, forKey: .nutrition),
            createdAt: try SyncTimestamp.decode(from: container, forKey: .createdAt),
            updatedAt: try SyncTimestamp.decode(from: container, forKey: .updatedAt),
            deletedAt: try SyncTimestamp.decodeIfPresent(from: container, forKey: .deletedAt),
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(day, forKey: .day)
        try container.encode(mealType, forKey: .mealType)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(sourceType, forKey: .sourceType)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encode(sourceVersionID, forKey: .sourceVersionID)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(amount, forKey: .amount)
        try container.encode(unitToken, forKey: .unitToken)
        try container.encode(nutrition, forKey: .nutrition)
        try SyncTimestamp.encode(createdAt, to: &container, forKey: .createdAt)
        try SyncTimestamp.encode(updatedAt, to: &container, forKey: .updatedAt)
        try SyncTimestamp.encode(deletedAt, to: &container, forKey: .deletedAt)
    }
}

extension WeeklyGoalPayload {
    private enum CodingKeys: String, CodingKey {
        case id, effectiveFrom, days, createdAt, updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdAt = try SyncTimestamp.decode(from: container, forKey: .createdAt)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            effectiveFrom: try container.decode(LocalDay.self, forKey: .effectiveFrom),
            days: try container.decode([Day].self, forKey: .days),
            createdAt: createdAt,
            updatedAt: try SyncTimestamp.decodeIfPresent(from: container, forKey: .updatedAt) ?? createdAt,
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(effectiveFrom, forKey: .effectiveFrom)
        try container.encode(days, forKey: .days)
        try SyncTimestamp.encode(createdAt, to: &container, forKey: .createdAt)
        try SyncTimestamp.encode(updatedAt, to: &container, forKey: .updatedAt)
    }
}

enum SyncPayloadCanonicalizer {
    static func compare(_ lhs: SyncPayload, _ rhs: SyncPayload) throws -> ComparisonResult {
        let lhsData = try canonicalData(for: lhs.canonicalizedTimestamps())
        let rhsData = try canonicalData(for: rhs.canonicalizedTimestamps())
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
