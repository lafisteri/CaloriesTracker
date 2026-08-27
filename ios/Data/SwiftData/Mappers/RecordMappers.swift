import Foundation

enum RecordMappingError: Error, LocalizedError {
    case invalidLocalDay(String)
    case invalidEnum(type: String, value: String)
    case invalidWeeklyGoalDays

    var errorDescription: String? {
        switch self {
        case let .invalidLocalDay(value):
            "Сохранённая дата \(value) имеет неверный формат."
        case let .invalidEnum(type, value):
            "Сохранённое значение \(value) не подходит для \(type)."
        case .invalidWeeklyGoalDays:
            "Сохранённая недельная цель должна содержать ровно семь дней."
        }
    }
}

extension ProductRecord {
    func toDomain() -> Product {
        Product(
            id: id,
            name: name,
            barcode: barcode,
            currentVersionID: currentVersionID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
        )
    }
}

extension ProductVersionRecord {
    func toDomain() throws -> ProductVersion {
        guard let baseUnit = ProductBaseUnit(rawValue: baseUnitRaw) else {
            throw RecordMappingError.invalidEnum(type: "ProductBaseUnit", value: baseUnitRaw)
        }

        return ProductVersion(
            id: id,
            productID: productID,
            basedOnVersionID: basedOnVersionID,
            versionNumber: versionNumber,
            baseUnit: baseUnit,
            baseAmount: baseAmount,
            nutrition: Nutrition(calories: calories, protein: protein, fat: fat, carbs: carbs),
            createdAt: createdAt,
        )
    }
}

extension RecipeRecord {
    func toDomain() -> Recipe {
        Recipe(
            id: id,
            name: name,
            currentVersionID: currentVersionID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
        )
    }
}

extension RecipeVersionRecord {
    func toDomain() -> RecipeVersion {
        RecipeVersion(
            id: id,
            recipeID: recipeID,
            basedOnVersionID: basedOnVersionID,
            versionNumber: versionNumber,
            totalNutrition: Nutrition(
                calories: totalCalories,
                protein: totalProtein,
                fat: totalFat,
                carbs: totalCarbs,
            ),
            cookedWeight: cookedWeight,
            servingsCount: servingsCount,
            ingredients: ingredients
                .sorted { $0.position < $1.position }
                .map { $0.toDomain() },
            createdAt: createdAt,
        )
    }
}

extension RecipeIngredientRecord {
    func toDomain() -> RecipeIngredient {
        RecipeIngredient(
            id: id,
            recipeVersionID: recipeVersionID,
            position: position,
            productID: productID,
            productVersionID: productVersionID,
            amount: amount,
            unitToken: unitToken,
            normalizedAmount: normalizedAmount,
        )
    }
}

extension DiaryEntryRecord {
    func toDomain() throws -> DiaryEntry {
        guard let day = LocalDay(rawValue: dayKey) else {
            throw RecordMappingError.invalidLocalDay(dayKey)
        }
        guard let mealType = MealType(rawValue: mealTypeRaw) else {
            throw RecordMappingError.invalidEnum(type: "MealType", value: mealTypeRaw)
        }
        guard let sourceType = SourceType(rawValue: sourceTypeRaw) else {
            throw RecordMappingError.invalidEnum(type: "SourceType", value: sourceTypeRaw)
        }

        return DiaryEntry(
            id: id,
            day: day,
            mealType: mealType,
            sortOrder: sortOrder,
            sourceType: sourceType,
            sourceID: sourceID,
            sourceVersionID: sourceVersionID,
            sourceName: sourceName,
            amount: amount,
            unitToken: unitToken,
            nutrition: Nutrition(calories: calories, protein: protein, fat: fat, carbs: carbs),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
        )
    }
}

extension WeeklyGoalRecord {
    func toDomain() throws -> WeeklyGoal {
        guard let effectiveFrom = LocalDay(rawValue: effectiveFromKey) else {
            throw RecordMappingError.invalidLocalDay(effectiveFromKey)
        }

        var mappedGoals: [LocalDay.Weekday: DailyMacroGoal] = [:]
        for record in dailyGoals {
            guard let weekday = LocalDay.Weekday(rawValue: record.weekdayRaw), mappedGoals[weekday] == nil else {
                throw RecordMappingError.invalidWeeklyGoalDays
            }
            mappedGoals[weekday] = record.toDomain()
        }

        guard mappedGoals.count == LocalDay.Weekday.allCases.count else {
            throw RecordMappingError.invalidWeeklyGoalDays
        }

        return WeeklyGoal(
            id: id,
            effectiveFrom: effectiveFrom,
            dailyGoals: mappedGoals,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
        )
    }
}

extension DailyMacroGoalRecord {
    func toDomain() -> DailyMacroGoal {
        DailyMacroGoal(calories: calories, protein: protein, fat: fat, carbs: carbs)
    }
}
