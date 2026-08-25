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

struct DiaryUsageDefault: Hashable, Sendable {
    let amount: Double
    let unitToken: String
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

struct FoodSelectionItem: Identifiable, Hashable, Sendable {
    let source: FoodSourceReference
    let displayName: String
    let subtitle: String

    var id: FoodSourceReference {
        source
    }
}

@MainActor
final class DiaryService {
    private let diaryRepository: any DiaryRepository
    private let productRepository: any ProductRepository
    private let recipeRepository: any RecipeRepository

    init(
        diaryRepository: any DiaryRepository,
        productRepository: any ProductRepository,
        recipeRepository: any RecipeRepository,
    ) {
        self.diaryRepository = diaryRepository
        self.productRepository = productRepository
        self.recipeRepository = recipeRepository
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

    func foodSources(matching query: String) async throws -> [FoodSelectionItem] {
        let products = try await productRepository.activeProducts(matching: query)
        let recipes = try await recipeRepository.activeRecipes(matching: query)
        var items: [FoodSelectionItem] = []

        for product in products {
            guard let version = try await productRepository.version(id: product.currentVersionID),
                  version.productID == product.id
            else {
                throw DiaryServiceError.currentVersionNotFound
            }
            items.append(
                FoodSelectionItem(
                    source: FoodSourceReference(sourceType: .product, sourceID: product.id),
                    displayName: product.name,
                    subtitle: "Продукт · \(displayNumber(version.nutrition.calories)) ккал",
                ),
            )
        }

        for recipe in recipes {
            guard let version = try await recipeRepository.version(id: recipe.currentVersionID),
                  version.recipeID == recipe.id
            else {
                throw DiaryServiceError.currentVersionNotFound
            }
            items.append(
                FoodSelectionItem(
                    source: FoodSourceReference(sourceType: .recipe, sourceID: recipe.id),
                    displayName: recipe.name,
                    subtitle: "Рецепт · \(displayNumber(version.totalNutrition.calories)) ккал",
                ),
            )
        }

        return items.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
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
            sourceName: entry.sourceName,
            initialAmount: entry.amount,
            initialUnitToken: entry.unitToken,
        )
    }

    func latestUsageDefaults(for sources: [FoodSourceReference]) async throws -> [FoodSourceReference: DiaryUsageDefault] {
        let entries = try await diaryRepository.activeEntries(for: sources)
        var latestEntries: [FoodSourceReference: DiaryEntry] = [:]

        for entry in entries {
            let source = FoodSourceReference(sourceType: entry.sourceType, sourceID: entry.sourceID)
            if let existing = latestEntries[source], !isMoreRecent(entry, than: existing) {
                continue
            }
            latestEntries[source] = entry
        }

        return latestEntries.mapValues { entry in
            DiaryUsageDefault(amount: entry.amount, unitToken: entry.unitToken)
        }
    }

    func preview(
        source: DiaryAmountSource,
        amount: Double,
        unitToken: String,
    ) throws -> Nutrition {
        try preview(source: source.calculationSource, amount: amount, unitToken: unitToken)
    }

    /// Calculates nutrition from an already-resolved immutable source version.
    /// This is used by selection UI that already has the current version and
    /// must match the Amount preview without resolving the source again.
    func preview(
        calculationSource: DiaryAmountCalculationSource,
        amount: Double,
        unitToken: String,
    ) throws -> Nutrition {
        try preview(source: calculationSource, amount: amount, unitToken: unitToken)
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
        let amount = preferredAmount.isFinite && preferredAmount > 0 ? preferredAmount : 100
        let unitToken = compatibleUnitToken(
            preferredUnitToken,
            options: amountSource.unitOptions,
        ) ?? amountSource.initialUnitToken

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
            source: source.calculationSource,
            amount: amount,
            unitToken: unitToken,
        )
        let existingEntries = try await diaryRepository.entries(on: context.day)
        let now = Date()
        let entry = DiaryEntry(
            id: UUID(),
            day: context.day,
            mealType: context.meal,
            sortOrder: nextSortOrder(for: existingEntries.filter { $0.mealType == context.meal }),
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
        let nutrition = try preview(source: source.calculationSource, amount: command.amount, unitToken: command.unitToken)
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
        }
    }

    private func makeAmountSource(
        from source: ResolvedDiarySource,
        sourceName: String? = nil,
        initialAmount: Double?,
        initialUnitToken: String?,
    ) -> DiaryAmountSource {
        switch source.calculationSource {
        case let .product(version):
            return DiaryAmountSource(
                sourceName: sourceName ?? source.sourceName,
                calculationSource: source.calculationSource,
                unitOptions: productUnitOptions(for: version),
                initialAmount: initialAmount,
                initialUnitToken: initialUnitToken ?? version.baseUnit.rawValue,
            )
        case let .recipe(version):
            let options = recipeUnitOptions(for: version)
            return DiaryAmountSource(
                sourceName: sourceName ?? source.sourceName,
                calculationSource: source.calculationSource,
                unitOptions: options,
                initialAmount: initialAmount,
                initialUnitToken: initialUnitToken ?? options.first?.token ?? "",
            )
        }
    }

    private func compatibleUnitToken(_ preferredToken: String, options: [DiaryUnitOption]) -> String? {
        if options.contains(where: { $0.token == preferredToken }) {
            return preferredToken
        }
        return nil
    }

    private func isMoreRecent(_ candidate: DiaryEntry, than existing: DiaryEntry) -> Bool {
        if candidate.updatedAt != existing.updatedAt {
            return candidate.updatedAt > existing.updatedAt
        }
        if candidate.createdAt != existing.createdAt {
            return candidate.createdAt > existing.createdAt
        }
        return candidate.id.uuidString > existing.id.uuidString
    }

    private func preview(
        source: DiaryAmountCalculationSource,
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

    private func displayNumber(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0 ... 2)))
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
    case recipeNotFound
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
        case .invalidReorder:
            "Не удалось изменить порядок записей."
        case .invalidMove:
            "Не удалось переместить запись."
        }
    }
}
