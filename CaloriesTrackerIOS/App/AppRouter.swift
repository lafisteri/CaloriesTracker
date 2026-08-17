import Observation
import SwiftUI

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var statisticsPath: [StatisticsRoute] = []
    var todayPath: [TodayRoute] = []
    var catalogPath: [CatalogRoute] = []
}

enum StatisticsRoute: Hashable {
    case goals
}

enum TodayRoute: Hashable {
    case catalogSelection(DiaryContext)
    case amount(context: DiaryContext, source: FoodSourceReference)
    case entryEditor(UUID)
    case productEditor(context: DiaryContext?, prefilledBarcode: String?)
    case recipeEditor(context: DiaryContext, recipeID: UUID?)
    case productDetails(UUID)
    case recipeDetails(UUID)
}

enum CatalogRoute: Hashable {
    case product(UUID)
    case productEditor(UUID?)
    case productVersionHistory(UUID)
    case recipe(UUID)
    case recipeEditor(UUID?)
    case recipeVersionHistory(UUID)
}
