import Foundation

struct DiaryMealReadModel: Identifiable, Hashable, Sendable {
    let mealID: UUID
    let name: String
    let entries: [DiaryEntry]
    let totalNutrition: Nutrition

    var id: UUID {
        mealID
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
        case recipeGrams
        case recipeServing
    }

    let token: String
    let kind: Kind

    var id: String {
        token
    }
}

struct DiaryAmountSource: Hashable, Sendable {
    let sourceName: String
    let calculationSource: DiaryAmountCalculationSource
    let unitOptions: [DiaryUnitOption]
    let initialAmount: Double?
    let initialUnitToken: String
}

enum DiaryAmountCalculationSource: Hashable, Sendable {
    case product(ProductVersion)
    case recipe(RecipeVersion)
}

private struct ResolvedDiarySource: Hashable, Sendable {
    let sourceType: SourceType
    let sourceID: UUID
    let sourceVersionID: UUID
    let sourceName: String
    let calculationSource: DiaryAmountCalculationSource
}

@MainActor
final class DiaryService {
    let mealConfigurationService: MealConfigurationService
    private let diaryRepository: any DiaryRepository
    private let productRepository: any ProductRepository
    private let recipeRepository: any RecipeRepository

    init(
        mealConfigurationService: MealConfigurationService,
        diaryRepository: any DiaryRepository,
        productRepository: any ProductRepository,
        recipeRepository: any RecipeRepository,
    ) {
        self.mealConfigurationService = mealConfigurationService
        self.diaryRepository = diaryRepository
        self.productRepository = productRepository
        self.recipeRepository = recipeRepository
    }

    func day(for day: LocalDay) async throws -> DiaryDayReadModel {
        let entries = try await diaryRepository.entries(on: day)
        let configuration = try await mealConfigurationService.configuration(for: day)
        let entriesByMeal = Dictionary(grouping: entries, by: \.mealID)
        let meals = try configuration.meals.sorted { $0.position < $1.position }.map { item in
            let mealID = item.mealID
            let mealEntries = (entriesByMeal[mealID] ?? []).sorted(by: diaryEntryOrder)
            return DiaryMealReadModel(
                mealID: mealID,
                name: item.name,
                entries: mealEntries,
                totalNutrition: try mealEntries.nutritionTotal(),
            )
        }

        return DiaryDayReadModel(
            day: day,
            meals: meals,
            totalNutrition: try entries.nutritionTotal(),
        )
    }

    func amountSource(for source: FoodSourceReference) async throws -> DiaryAmountSource {
        let resolved = try await currentSource(for: source)
        return makeAmountSource(from: resolved, initialAmount: nil, initialUnitToken: nil)
    }

    func amountSource(forEntryID entryID: UUID) async throws -> DiaryAmountSource {
        guard let entry = try await diaryRepository.entry(id: entryID, includingDeleted: false) else {
            throw DiaryServiceError.entryNotFound
        }
        let resolved = try await historicalSource(for: entry)
        return makeAmountSource(
            from: resolved,
            initialAmount: entry.amount,
            initialUnitToken: entry.unitToken,
        )
    }

    func latestUsageDefaults(for sources: [FoodSourceReference]) async throws -> [FoodSourceReference: LatestDiaryUsage] {
        let usages = try await diaryRepository.latestActiveUsages(for: sources)
        return Dictionary(
            uniqueKeysWithValues: usages.map { usage in
                (usage.source, usage)
            },
        )
    }

    func preview(
        source: DiaryAmountSource,
        amount: Double,
        unitToken: String,
    ) throws -> Nutrition {
        try preview(calculationSource: source.calculationSource, amount: amount, unitToken: unitToken)
    }

    func create(_ command: CreateDiaryEntryCommand) async throws {
        try validatePositiveAmount(command.amount)
        let source = try await currentSource(for: command.source)
        try await create(
            context: command.context,
            source: source,
            amount: command.amount,
            unitToken: command.unitToken,
        )
    }

    func createManualEntry(_ command: CreateManualDiaryEntryCommand) async throws {
        try await validateMeal(command.context.mealID, on: command.context.day)
        let sourceName = try validatedManualName(command.sourceName)
        try validatePositiveAmount(command.amount)
        try validateManualUnit(command.unitToken)
        try validateManualNutrition(command.nutrition)

        let existingEntries = try await diaryRepository.entries(on: command.context.day)
        let now = Date()
        let entryID = UUID()
        let entry = DiaryEntry(
            id: entryID,
            day: command.context.day,
            mealID: command.context.mealID,
            sortOrder: nextSortOrder(for: existingEntries.filter { $0.mealID == command.context.mealID }),
            sourceType: .manual,
            sourceID: entryID,
            sourceVersionID: entryID,
            sourceName: sourceName,
            amount: command.amount,
            unitToken: command.unitToken,
            nutrition: command.nutrition,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
        )

        try await diaryRepository.create(entry)
    }

    func manualEntry(for entryID: UUID) async throws -> DiaryEntry {
        guard let entry = try await diaryRepository.entry(id: entryID, includingDeleted: false) else {
            throw DiaryServiceError.entryNotFound
        }
        guard entry.sourceType == .manual else {
            throw DiaryServiceError.unsupportedSource
        }
        return entry
    }

    func updateManualEntry(_ command: UpdateManualDiaryEntryCommand) async throws {
        let sourceName = try validatedManualName(command.sourceName)
        try validatePositiveAmount(command.amount)
        try validateManualUnit(command.unitToken)
        try validateManualNutrition(command.nutrition)
        let entry = try await manualEntry(for: command.entryID)
        let updatedEntry = updatedSnapshot(
            from: entry,
            sourceName: sourceName,
            amount: command.amount,
            unitToken: command.unitToken,
            nutrition: command.nutrition,
        )

        try await diaryRepository.saveManualSnapshot(updatedEntry)
    }

    func quickAdd(
        context: DiaryContext,
        source sourceReference: FoodSourceReference,
        preferredAmount: Double,
        preferredUnitToken: String,
    ) async throws {
        let source = try await currentSource(for: sourceReference)
        let amountSource = makeAmountSource(
            from: source,
            initialAmount: nil,
            initialUnitToken: nil,
        )
        let unitToken = compatibleUnitToken(
            preferredUnitToken,
            options: amountSource.unitOptions,
        ) ?? amountSource.initialUnitToken
        let amount = preferredAmount.isFinite && preferredAmount > 0
            ? preferredAmount
            : FoodAmountDefaults.fallbackAmount(for: unitToken)

        try await create(
            context: context,
            source: source,
            amount: amount,
            unitToken: unitToken,
        )
    }

    private func create(
        context: DiaryContext,
        source: ResolvedDiarySource,
        amount: Double,
        unitToken: String,
    ) async throws {
        try validatePositiveAmount(amount)
        let nutrition = try preview(
            calculationSource: source.calculationSource,
            amount: amount,
            unitToken: unitToken,
        )
        try await validateMeal(context.mealID, on: context.day)
        let existingEntries = try await diaryRepository.entries(on: context.day)
        let now = Date()
        let entry = DiaryEntry(
            id: UUID(),
            day: context.day,
            mealID: context.mealID,
            sortOrder: nextSortOrder(for: existingEntries.filter { $0.mealID == context.mealID }),
            sourceType: source.sourceType,
            sourceID: source.sourceID,
            sourceVersionID: source.sourceVersionID,
            sourceName: source.sourceName,
            amount: amount,
            unitToken: unitToken,
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
        let source = try await historicalSource(for: entry)
        let nutrition = try preview(calculationSource: source.calculationSource, amount: command.amount, unitToken: command.unitToken)
        let updatedEntry = updatedSnapshot(
            from: entry,
            amount: command.amount,
            unitToken: command.unitToken,
            nutrition: nutrition,
        )

        try await diaryRepository.save(updatedEntry)
    }

    func rebaseEntryToCurrentProduct(entryID: UUID) async throws {
        guard let entry = try await diaryRepository.entry(id: entryID, includingDeleted: false) else {
            throw DiaryServiceError.entryNotFound
        }
        guard entry.sourceType == .product else {
            throw DiaryServiceError.unsupportedSource
        }

        let source = try await currentSource(
            for: FoodSourceReference(sourceType: .product, sourceID: entry.sourceID),
        )
        let amountSource = makeAmountSource(from: source, initialAmount: nil, initialUnitToken: nil)
        let unitToken = compatibleUnitToken(entry.unitToken, options: amountSource.unitOptions)
            ?? amountSource.initialUnitToken
        let nutrition = try preview(
            calculationSource: source.calculationSource,
            amount: entry.amount,
            unitToken: unitToken,
        )
        let rebasedEntry = updatedSnapshot(
            from: entry,
            sourceVersionID: source.sourceVersionID,
            sourceName: source.sourceName,
            amount: entry.amount,
            unitToken: unitToken,
            nutrition: nutrition,
        )

        try await diaryRepository.rebaseSourceSnapshot(rebasedEntry)
    }

    func softDelete(entryID: UUID) async throws {
        guard try await diaryRepository.entry(id: entryID, includingDeleted: false) != nil else {
            throw DiaryServiceError.entryNotFound
        }

        try await diaryRepository.softDeleteEntry(id: entryID, at: Date())
    }

    func reorder(day: LocalDay, meal: UUID, orderedEntryIDs: [UUID]) async throws {
        let entries = try await diaryRepository.entries(on: day)
        let currentMealEntries = entries.filter { $0.mealID == meal }.sorted(by: diaryEntryOrder)
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

        try await validateMeal(command.targetMealID, on: entry.day)
        let allEntries = try await diaryRepository.entries(on: entry.day)
        let now = Date()
        var sourceEntries = allEntries
            .filter { $0.mealID == entry.mealID }
            .sorted(by: diaryEntryOrder)
        sourceEntries.removeAll { $0.id == entry.id }

        if command.targetMealID == entry.mealID {
            let insertionIndex = min(command.targetIndex, sourceEntries.count)
            sourceEntries.insert(entry, at: insertionIndex)
            try await diaryRepository.save(normalized(entries: sourceEntries, meal: entry.mealID, at: now))
            return
        }

        var targetEntries = allEntries
            .filter { $0.mealID == command.targetMealID }
            .sorted(by: diaryEntryOrder)
        let insertionIndex = min(command.targetIndex, targetEntries.count)
        targetEntries.insert(entry, at: insertionIndex)

        let sourceUpdates = normalized(entries: sourceEntries, meal: entry.mealID, at: now)
        let targetUpdates = normalized(entries: targetEntries, meal: command.targetMealID, at: now)
        try await diaryRepository.save(sourceUpdates + targetUpdates)
    }

    private func validateMeal(_ mealID: UUID, on day: LocalDay) async throws {
        let configuration = try await mealConfigurationService.configuration(for: day)
        guard configuration.meals.contains(where: { $0.mealID == mealID }) else {
            throw MealConfigurationError.invalidConfiguration
        }
    }

    private func currentSource(for source: FoodSourceReference) async throws -> ResolvedDiarySource {
        switch source.sourceType {
        case .product:
            guard let product = try await productRepository.product(id: source.sourceID, includingDeleted: false) else {
                throw DiaryServiceError.productNotFound
            }
            guard let version = try await productRepository.version(id: product.currentVersionID),
                  version.productID == product.id
            else {
                throw DiaryServiceError.currentVersionNotFound
            }
            return ResolvedDiarySource(
                sourceType: .product,
                sourceID: product.id,
                sourceVersionID: version.id,
                sourceName: product.name,
                calculationSource: .product(version),
            )
        case .recipe:
            guard let recipe = try await recipeRepository.recipe(id: source.sourceID, includingDeleted: false) else {
                throw DiaryServiceError.recipeNotFound
            }
            guard let version = try await recipeRepository.version(id: recipe.currentVersionID),
                  version.recipeID == recipe.id
            else {
                throw DiaryServiceError.currentVersionNotFound
            }
            return ResolvedDiarySource(
                sourceType: .recipe,
                sourceID: recipe.id,
                sourceVersionID: version.id,
                sourceName: recipe.name,
                calculationSource: .recipe(version),
            )
        case .manual:
            throw DiaryServiceError.unsupportedSource
        }
    }

    private func historicalSource(for entry: DiaryEntry) async throws -> ResolvedDiarySource {
        switch entry.sourceType {
        case .product:
            guard let version = try await productRepository.version(id: entry.sourceVersionID),
                  version.productID == entry.sourceID
            else {
                throw DiaryServiceError.historicalVersionNotFound
            }
            return ResolvedDiarySource(
                sourceType: .product,
                sourceID: entry.sourceID,
                sourceVersionID: version.id,
                sourceName: entry.sourceName,
                calculationSource: .product(version),
            )
        case .recipe:
            guard let version = try await recipeRepository.version(id: entry.sourceVersionID),
                  version.recipeID == entry.sourceID
            else {
                throw DiaryServiceError.historicalVersionNotFound
            }
            return ResolvedDiarySource(
                sourceType: .recipe,
                sourceID: entry.sourceID,
                sourceVersionID: version.id,
                sourceName: entry.sourceName,
                calculationSource: .recipe(version),
            )
        case .manual:
            throw DiaryServiceError.unsupportedSource
        }
    }

    private func makeAmountSource(
        from source: ResolvedDiarySource,
        initialAmount: Double?,
        initialUnitToken: String?,
    ) -> DiaryAmountSource {
        let options: [DiaryUnitOption]
        switch source.calculationSource {
        case let .product(version):
            options = productUnitOptions(for: version)
        case let .recipe(version):
            options = recipeUnitOptions(for: version)
        }
        return DiaryAmountSource(
            sourceName: source.sourceName,
            calculationSource: source.calculationSource,
            unitOptions: options,
            initialAmount: initialAmount,
            initialUnitToken: initialUnitToken ?? options.first?.token ?? "",
        )
    }

    private func compatibleUnitToken(_ preferredToken: String, options: [DiaryUnitOption]) -> String? {
        if options.contains(where: { $0.token == preferredToken }) {
            return preferredToken
        }
        return nil
    }

    /// Calculates nutrition from an already-resolved immutable source version.
    /// This is used by selection UI that already has the current version and
    /// must match the Amount preview without resolving the source again.
    func preview(
        calculationSource source: DiaryAmountCalculationSource,
        amount: Double,
        unitToken: String,
    ) throws -> Nutrition {
        switch source {
        case let .product(version):
            let normalizedAmount = try normalizedProductAmount(
                amount: amount,
                unitToken: unitToken,
                version: version,
            )
            return try NutritionCalculator.calculate(
                nutrition: version.nutrition,
                baseAmount: version.baseAmount,
                normalizedAmount: normalizedAmount,
            )
        case let .recipe(version):
            return try RecipeCalculator.diaryNutrition(
                for: version,
                amount: amount,
                unitToken: unitToken,
            )
        }
    }

    private func productUnitOptions(for version: ProductVersion) -> [DiaryUnitOption] {
        [DiaryUnitOption(token: version.baseUnit.rawValue, kind: .base(version.baseUnit))]
    }

    private func recipeUnitOptions(for version: RecipeVersion) -> [DiaryUnitOption] {
        var options: [DiaryUnitOption] = []
        if version.cookedWeight != nil {
            options.append(DiaryUnitOption(token: RecipeDiaryUnit.grams.rawValue, kind: .recipeGrams))
        }
        if version.servingsCount != nil {
            options.append(DiaryUnitOption(token: RecipeDiaryUnit.serving.rawValue, kind: .recipeServing))
        }
        return options
    }

    private func normalizedProductAmount(
        amount: Double,
        unitToken: String,
        version: ProductVersion,
    ) throws -> Double {
        guard amount.isFinite, amount > 0 else {
            throw DiaryServiceError.invalidAmount
        }

        guard unitToken == version.baseUnit.rawValue else {
            throw DiaryServiceError.invalidUnit
        }
        return amount
    }

    private func validatePositiveAmount(_ amount: Double) throws {
        guard amount.isFinite, amount > 0 else {
            throw DiaryServiceError.invalidAmount
        }
    }

    private func validatedManualName(_ name: String) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DiaryServiceError.invalidManualName
        }
        return trimmedName
    }

    private func validateManualNutrition(_ nutrition: Nutrition) throws {
        guard nutrition.isNonnegativeAndFinite else {
            throw DiaryServiceError.invalidManualNutrition
        }
    }

    private func validateManualUnit(_ unitToken: String) throws {
        guard ProductBaseUnit(rawValue: unitToken) != nil else {
            throw DiaryServiceError.invalidUnit
        }
    }

    private func updatedSnapshot(
        from entry: DiaryEntry,
        sourceVersionID: UUID? = nil,
        sourceName: String? = nil,
        amount: Double,
        unitToken: String,
        nutrition: Nutrition,
    ) -> DiaryEntry {
        DiaryEntry(
            id: entry.id,
            day: entry.day,
            mealID: entry.mealID,
            sortOrder: entry.sortOrder,
            sourceType: entry.sourceType,
            sourceID: entry.sourceID,
            sourceVersionID: sourceVersionID ?? entry.sourceVersionID,
            sourceName: sourceName ?? entry.sourceName,
            amount: amount,
            unitToken: unitToken,
            nutrition: nutrition,
            createdAt: entry.createdAt,
            updatedAt: Date(),
            deletedAt: entry.deletedAt,
        )
    }

    private func nextSortOrder(for entries: [DiaryEntry]) -> Int {
        guard let lastOrder = entries.map(\.sortOrder).max() else {
            return 0
        }
        let (nextOrder, overflow) = lastOrder.addingReportingOverflow(100)
        return overflow ? entries.count * 100 : nextOrder
    }

    private func normalized(entries: [DiaryEntry], meal: UUID, at date: Date) -> [DiaryEntry] {
        entries.enumerated().map { index, entry in
            DiaryEntry(
                id: entry.id,
                day: entry.day,
                mealID: meal,
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
    case recipeNotFound
    case currentVersionNotFound
    case historicalVersionNotFound
    case unsupportedSource
    case invalidAmount
    case invalidUnit
    case invalidManualName
    case invalidManualNutrition
    case invalidReorder
    case invalidMove

    var errorDescription: String? {
        switch self {
        case .entryNotFound:
            "Запись дневника не найдена."
        case .productNotFound:
            "Продукт не найден или удалён."
        case .recipeNotFound:
            "Рецепт не найден или удалён."
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
        case .invalidManualName:
            "Введите название записи."
        case .invalidManualNutrition:
            "Введите корректные значения КБЖУ."
        case .invalidReorder:
            "Не удалось изменить порядок записей."
        case .invalidMove:
            "Не удалось переместить запись."
        }
    }
}
