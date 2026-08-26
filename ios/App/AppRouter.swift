import Observation
import SwiftUI

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var statisticsPath: [StatisticsRoute] = []
    var todayPath: [TodayRoute] = []
    var catalogPath: [CatalogRoute] = []
    var amountFocusRestorationRevision = 0
    private var pendingCreateAmountSourceRefresh: FoodSourceReference?
    private var pendingEntryProductRebase: UUID?

    func resetTodayNavigationWhenLeavingTab() {
        todayPath = []
        pendingCreateAmountSourceRefresh = nil
        pendingEntryProductRebase = nil
    }

    func requestCreateAmountSourceRefresh(for source: FoodSourceReference) {
        pendingCreateAmountSourceRefresh = source
    }

    func consumeCreateAmountSourceRefresh(for source: FoodSourceReference) -> Bool {
        guard pendingCreateAmountSourceRefresh == source else {
            return false
        }
        pendingCreateAmountSourceRefresh = nil
        return true
    }

    func requestEntryProductRebase(entryID: UUID) {
        pendingEntryProductRebase = entryID
    }

    func consumeEntryProductRebase(entryID: UUID) -> Bool {
        guard pendingEntryProductRebase == entryID else {
            return false
        }
        pendingEntryProductRebase = nil
        return true
    }

    func popToday(ifTopIs expectedRoute: TodayRoute) {
        guard todayPath.last == expectedRoute else {
            return
        }
        todayPath.removeLast()
    }

    func popCatalog(ifTopIs expectedRoute: CatalogRoute) {
        guard catalogPath.last == expectedRoute else {
            return
        }
        catalogPath.removeLast()
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
    case productEditorForEntryAmount(productID: UUID, entryID: UUID)
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
