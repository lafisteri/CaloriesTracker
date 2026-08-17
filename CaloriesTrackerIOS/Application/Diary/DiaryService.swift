import Foundation

struct DiaryMealReadModel: Identifiable, Hashable, Sendable {
    let mealType: MealType
    let entries: [DiaryEntry]
    let totalNutrition: Nutrition

    var id: MealType {
        mealType
    }
}

struct DiaryDayReadModel: Hashable, Sendable {
    let day: LocalDay
    let meals: [DiaryMealReadModel]
    let totalNutrition: Nutrition
}

struct DiaryUnitOption: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case base(ProductBaseUnit)
        case serving(name: String)
    }

    let token: String
    let kind: Kind

    var id: String {
        token
    }
}

struct DiaryAmountSource: Hashable, Sendable {
    let sourceName: String
    let version: ProductVersion
    let unitOptions: [DiaryUnitOption]
    let initialAmount: Double?
    let initialUnitToken: String
}

@MainActor
final class DiaryService {
    private let diaryRepository: any DiaryRepository
    private let productRepository: any ProductRepository

    init(
        diaryRepository: any DiaryRepository,
        productRepository: any ProductRepository,
    ) {
        self.diaryRepository = diaryRepository
        self.productRepository = productRepository
    }

    func day(for day: LocalDay) async throws -> DiaryDayReadModel {
        let entries = try await diaryRepository.entries(on: day)
        let meals = MealType.allCases.map { mealType in
            let mealEntries = entries
                .filter { $0.mealType == mealType }
                .sorted(by: diaryEntryOrder)
            return DiaryMealReadModel(
                mealType: mealType,
                entries: mealEntries,
                totalNutrition: nutritionTotal(for: mealEntries),
            )
        }

        return DiaryDayReadModel(
            day: day,
            meals: meals,
            totalNutrition: nutritionTotal(for: entries),
        )
    }

    func amountSource(for source: FoodSourceReference) async throws -> DiaryAmountSource {
        let productAndVersion = try await currentProductVersion(for: source)
        return DiaryAmountSource(
            sourceName: productAndVersion.product.name,
            version: productAndVersion.version,
            unitOptions: unitOptions(for: productAndVersion.version),
            initialAmount: nil,
            initialUnitToken: productAndVersion.version.baseUnit.rawValue,
        )
    }

    func amountSource(forEntryID entryID: UUID) async throws -> DiaryAmountSource {
        guard let entry = try await diaryRepository.entry(id: entryID, includingDeleted: false) else {
            throw DiaryServiceError.entryNotFound
        }
        guard entry.sourceType == .product else {
            throw DiaryServiceError.unsupportedSource
        }
        guard let version = try await productRepository.version(id: entry.sourceVersionID),
              version.productID == entry.sourceID
        else {
            throw DiaryServiceError.historicalVersionNotFound
        }

        return DiaryAmountSource(
            sourceName: entry.sourceName,
            version: version,
            unitOptions: unitOptions(for: version),
            initialAmount: entry.amount,
            initialUnitToken: entry.unitToken,
        )
    }

    func preview(
        version: ProductVersion,
        amount: Double,
        unitToken: String,
    ) throws -> Nutrition {
        try validatePositiveAmount(amount)
        let normalizedAmount = try normalizedAmount(
            amount: amount,
            unitToken: unitToken,
            version: version,
        )
        return try NutritionCalculator.calculate(
            nutrition: version.nutrition,
            baseAmount: version.baseAmount,
            normalizedAmount: normalizedAmount,
        )
    }

    func create(_ command: CreateDiaryEntryCommand) async throws {
        try validatePositiveAmount(command.amount)
        let productAndVersion = try await currentProductVersion(for: command.source)
        let nutrition = try preview(
            version: productAndVersion.version,
            amount: command.amount,
            unitToken: command.unitToken,
        )
        let existingEntries = try await diaryRepository.entries(on: command.context.day)
        let now = Date()
        let entry = DiaryEntry(
            id: UUID(),
            day: command.context.day,
            mealType: command.context.meal,
            sortOrder: nextSortOrder(
                for: existingEntries.filter { $0.mealType == command.context.meal },
            ),
            sourceType: .product,
            sourceID: productAndVersion.product.id,
            sourceVersionID: productAndVersion.version.id,
            sourceName: productAndVersion.product.name,
            amount: command.amount,
            unitToken: command.unitToken,
            nutrition: nutrition,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
        )

        try await diaryRepository.create(entry)
    }

    func updateAmount(_ command: UpdateDiaryEntryAmountCommand) async throws {
        try validatePositiveAmount(command.amount)
        guard let entry = try await diaryRepository.entry(id: command.entryID, includingDeleted: false) else {
            throw DiaryServiceError.entryNotFound
        }
        guard entry.sourceType == .product else {
            throw DiaryServiceError.unsupportedSource
        }
        guard let version = try await productRepository.version(id: entry.sourceVersionID),
              version.productID == entry.sourceID
        else {
            throw DiaryServiceError.historicalVersionNotFound
        }

        let nutrition = try preview(version: version, amount: command.amount, unitToken: command.unitToken)
        let updatedEntry = DiaryEntry(
            id: entry.id,
            day: entry.day,
            mealType: entry.mealType,
            sortOrder: entry.sortOrder,
            sourceType: entry.sourceType,
            sourceID: entry.sourceID,
            sourceVersionID: entry.sourceVersionID,
            sourceName: entry.sourceName,
            amount: command.amount,
            unitToken: command.unitToken,
            nutrition: nutrition,
            createdAt: entry.createdAt,
            updatedAt: Date(),
            deletedAt: entry.deletedAt,
        )

        try await diaryRepository.save(updatedEntry)
    }

    func softDelete(entryID: UUID) async throws {
        guard try await diaryRepository.entry(id: entryID, includingDeleted: false) != nil else {
            throw DiaryServiceError.entryNotFound
        }

        try await diaryRepository.softDeleteEntry(id: entryID, at: Date())
    }

    func reorder(day: LocalDay, meal: MealType, orderedEntryIDs: [UUID]) async throws {
        let entries = try await diaryRepository.entries(on: day)
        let currentMealEntries = entries.filter { $0.mealType == meal }.sorted(by: diaryEntryOrder)
        guard currentMealEntries.map(\.id).count == orderedEntryIDs.count,
              Set(currentMealEntries.map(\.id)) == Set(orderedEntryIDs),
              Set(orderedEntryIDs).count == orderedEntryIDs.count
        else {
            throw DiaryServiceError.invalidReorder
        }

        let entriesByID = Dictionary(uniqueKeysWithValues: currentMealEntries.map { ($0.id, $0) })
        let orderedEntries = orderedEntryIDs.compactMap { entriesByID[$0] }
        try await diaryRepository.save(normalized(entries: orderedEntries, meal: meal, at: Date()))
    }

    func move(_ command: MoveDiaryEntryCommand) async throws {
        guard command.targetIndex >= 0 else {
            throw DiaryServiceError.invalidMove
        }
        guard let entry = try await diaryRepository.entry(id: command.entryID, includingDeleted: false) else {
            throw DiaryServiceError.entryNotFound
        }

        let allEntries = try await diaryRepository.entries(on: entry.day)
        let now = Date()
        var sourceEntries = allEntries
            .filter { $0.mealType == entry.mealType }
            .sorted(by: diaryEntryOrder)
        sourceEntries.removeAll { $0.id == entry.id }

        if command.targetMeal == entry.mealType {
            let insertionIndex = min(command.targetIndex, sourceEntries.count)
            sourceEntries.insert(entry, at: insertionIndex)
            try await diaryRepository.save(normalized(entries: sourceEntries, meal: entry.mealType, at: now))
            return
        }

        var targetEntries = allEntries
            .filter { $0.mealType == command.targetMeal }
            .sorted(by: diaryEntryOrder)
        let insertionIndex = min(command.targetIndex, targetEntries.count)
        targetEntries.insert(entry, at: insertionIndex)

        let sourceUpdates = normalized(entries: sourceEntries, meal: entry.mealType, at: now)
        let targetUpdates = normalized(entries: targetEntries, meal: command.targetMeal, at: now)
        try await diaryRepository.save(sourceUpdates + targetUpdates)
    }

    private func currentProductVersion(
        for source: FoodSourceReference,
    ) async throws -> (product: Product, version: ProductVersion) {
        guard source.sourceType == .product else {
            throw DiaryServiceError.unsupportedSource
        }
        guard let product = try await productRepository.product(id: source.sourceID, includingDeleted: false) else {
            throw DiaryServiceError.productNotFound
        }
        guard let version = try await productRepository.version(id: product.currentVersionID),
              version.productID == product.id
        else {
            throw DiaryServiceError.currentVersionNotFound
        }

        return (product, version)
    }

    private func unitOptions(for version: ProductVersion) -> [DiaryUnitOption] {
        let baseOption = DiaryUnitOption(token: version.baseUnit.rawValue, kind: .base(version.baseUnit))
        let servingOptions = version.servingUnits
            .sorted { $0.position < $1.position }
            .map { unit in
                DiaryUnitOption(
                    token: "serving:\(unit.id.uuidString)",
                    kind: .serving(name: unit.name),
                )
            }
        return [baseOption] + servingOptions
    }

    private func normalizedAmount(
        amount: Double,
        unitToken: String,
        version: ProductVersion,
    ) throws -> Double {
        guard amount.isFinite, amount > 0 else {
            throw DiaryServiceError.invalidAmount
        }

        if unitToken == version.baseUnit.rawValue {
            return amount
        }

        let prefix = "serving:"
        guard unitToken.hasPrefix(prefix),
              let servingID = UUID(uuidString: String(unitToken.dropFirst(prefix.count))),
              let servingUnit = version.servingUnits.first(where: { $0.id == servingID })
        else {
            throw DiaryServiceError.invalidUnit
        }

        return try UnitConverter.baseAmount(
            from: amount,
            servingUnit: servingUnit,
            expectedBaseUnit: version.baseUnit,
        )
    }

    private func validatePositiveAmount(_ amount: Double) throws {
        guard amount.isFinite, amount > 0 else {
            throw DiaryServiceError.invalidAmount
        }
    }

    private func nutritionTotal(for entries: [DiaryEntry]) -> Nutrition {
        entries.reduce(.zero) { partial, entry in
            partial.adding(entry.nutrition)
        }
    }

    private func nextSortOrder(for entries: [DiaryEntry]) -> Int {
        guard let lastOrder = entries.map(\.sortOrder).max() else {
            return 0
        }
        let (nextOrder, overflow) = lastOrder.addingReportingOverflow(100)
        return overflow ? entries.count * 100 : nextOrder
    }

    private func normalized(entries: [DiaryEntry], meal: MealType, at date: Date) -> [DiaryEntry] {
        entries.enumerated().map { index, entry in
            DiaryEntry(
                id: entry.id,
                day: entry.day,
                mealType: meal,
                sortOrder: index * 100,
                sourceType: entry.sourceType,
                sourceID: entry.sourceID,
                sourceVersionID: entry.sourceVersionID,
                sourceName: entry.sourceName,
                amount: entry.amount,
                unitToken: entry.unitToken,
                nutrition: entry.nutrition,
                createdAt: entry.createdAt,
                updatedAt: date,
                deletedAt: entry.deletedAt,
            )
        }
    }

    private func diaryEntryOrder(_ lhs: DiaryEntry, _ rhs: DiaryEntry) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

enum DiaryServiceError: LocalizedError {
    case entryNotFound
    case productNotFound
    case currentVersionNotFound
    case historicalVersionNotFound
    case unsupportedSource
    case invalidAmount
    case invalidUnit
    case invalidReorder
    case invalidMove

    var errorDescription: String? {
        switch self {
        case .entryNotFound:
            "Запись дневника не найдена."
        case .productNotFound:
            "Продукт не найден или удалён."
        case .currentVersionNotFound:
            "Не удалось найти текущую версию продукта."
        case .historicalVersionNotFound:
            "Не удалось найти историческую версию продукта."
        case .unsupportedSource:
            "Этот тип источника пока не поддерживается."
        case .invalidAmount:
            "Количество должно быть больше нуля."
        case .invalidUnit:
            "Выберите доступную единицу продукта."
        case .invalidReorder:
            "Не удалось изменить порядок записей."
        case .invalidMove:
            "Не удалось переместить запись."
        }
    }
}
