import SwiftUI

struct RootApplicationView: View {
    let dependencies: AppDependencies

    @State private var router = AppRouter()

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack {
                StatisticsView(
                    statisticsService: dependencies.statisticsService,
                )
            }
            .tabItem {
                Label("Статистика", systemImage: "chart.bar")
            }
            .tag(AppTab.statistics)

            NavigationStack(path: $router.todayPath) {
                TodayRootView(
                    router: router,
                    diaryService: dependencies.diaryService,
                    goalService: dependencies.goalService,
                    productService: dependencies.productService,
                    recipeService: dependencies.recipeService,
                    supabaseAuth: dependencies.supabaseAuth,
                    syncStatus: dependencies.syncStatus,
                    syncOrchestrator: dependencies.syncOrchestrator,
                )
            }
            .tabItem {
                Label("Сегодня", systemImage: "fork.knife")
            }
            .tag(AppTab.today)

            ProductCatalogRootView(
                router: router,
                productService: dependencies.productService,
                recipeService: dependencies.recipeService,
                diaryService: dependencies.diaryService,
            )
            .tabItem {
                Label("Продукты", systemImage: "shippingbox")
            }
            .tag(AppTab.catalog)
        }
        .onChange(of: router.selectedTab) { previousTab, selectedTab in
            guard previousTab == .today, selectedTab != .today else {
                return
            }
            router.resetTodayNavigationWhenLeavingTab()
        }
    }
}
