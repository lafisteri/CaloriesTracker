import SwiftUI

struct RootApplicationView: View {
    @State private var router = AppRouter()

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.statisticsPath) {
                StatisticsPlaceholderView()
            }
            .tabItem {
                Label("Статистика", systemImage: "chart.bar")
            }
            .tag(AppTab.statistics)

            NavigationStack(path: $router.todayPath) {
                TodayPlaceholderView()
            }
            .tabItem {
                Label("Сегодня", systemImage: "fork.knife")
            }
            .tag(AppTab.today)

            NavigationStack(path: $router.catalogPath) {
                CatalogPlaceholderView()
            }
            .tabItem {
                Label("Продукты", systemImage: "shippingbox")
            }
            .tag(AppTab.catalog)
        }
    }
}
