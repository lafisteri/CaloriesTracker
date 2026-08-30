import Foundation

struct CreateDiaryEntryCommand: Hashable, Sendable {
    let context: DiaryContext
    let source: FoodSourceReference
    let amount: Double
    let unitToken: String
}

struct UpdateDiaryEntryAmountCommand: Hashable, Sendable {
    let entryID: UUID
    let amount: Double
    let unitToken: String
}

struct MoveDiaryEntryCommand: Hashable, Sendable {
    let entryID: UUID
    let targetMeal: MealType
    let targetIndex: Int
}
