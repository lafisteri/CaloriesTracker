import SwiftUI

struct RootApplicationView: View {
    let dependencies: AppDependencies

    @State private var router = AppRouter()

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.statisticsPath) {
                StatisticsView(
                    router: router,
                    statisticsService: dependencies.statisticsService,
                )
                .navigationDestination(for: StatisticsRoute.self) { route in
                    switch route {
                    case .goals:
                        GoalEditorView(router: router, goalService: dependencies.goalService)
                    }
                }
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
            )
            .tabItem {
                Label("Продукты", systemImage: "shippingbox")
            }
            .tag(AppTab.catalog)
        }
    }
}
