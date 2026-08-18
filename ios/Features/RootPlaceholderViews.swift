import SwiftUI

struct StatisticsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView("Статистика", systemImage: "chart.bar")
    }
}

struct TodayPlaceholderView: View {
    var body: some View {
        ContentUnavailableView("Сегодня", systemImage: "fork.knife")
    }
}

struct CatalogPlaceholderView: View {
    var body: some View {
        ContentUnavailableView("Продукты", systemImage: "shippingbox")
    }
}
