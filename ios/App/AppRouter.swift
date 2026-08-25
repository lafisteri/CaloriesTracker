import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class AppRouter {
    private static let logger = Logger(subsystem: "com.caloriestracker.ios", category: "Navigation")

    var selectedTab: AppTab = .today
    var statisticsPath: [StatisticsRoute] = []
    var todayPath: [TodayRoute] = []
    var catalogPath: [CatalogRoute] = []
    var amountFocusRestorationRevision = 0

    func resetTodayNavigationWhenLeavingTab() {
        todayPath = []
    }

    func popToday(ifTopIs expectedRoute: TodayRoute) {
        guard todayPath.last == expectedRoute else {
            Self.logSkippedPop(path: "today")
            return
        }
        todayPath.removeLast()
    }

    func popCatalog(ifTopIs expectedRoute: CatalogRoute) {
        guard catalogPath.last == expectedRoute else {
            Self.logSkippedPop(path: "catalog")
            return
        }
        catalogPath.removeLast()
    }

    private static func logSkippedPop(path: String) {
        #if DEBUG
        logger.debug("navigation_pop_skipped path=\(path, privacy: .public) reason=unexpected_top_route")
        #endif
    }
}

enum StatisticsRoute: Hashable {
    case goals
}

enum TodayRoute: Hashable {
    case catalogSelection(DiaryContext)
    case amount(context: DiaryContext, source: FoodSourceReference, selectionDefault: FoodSelectionAmountDefault?)
    case entryEditor(UUID)
    case productEditor(context: DiaryContext?, prefilledBarcode: String?)
    case productEditorForDiarySelection(productID: UUID, context: DiaryContext)
    case productEditorForEntryAmount(productID: UUID)
    case recipeEditor(context: DiaryContext, recipeID: UUID?)
    case productDetails(productID: UUID, context: DiaryContext)
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
