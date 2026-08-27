import SwiftUI

struct ProductVersionHistoryView: View {
    @State private var model: ProductVersionHistoryViewModel

    init(productID: UUID, productService: ProductService) {
        _model = State(initialValue: ProductVersionHistoryViewModel(productID: productID, productService: productService))
    }

    var body: some View {
        List {
            if model.isLoading && model.versions.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if model.versions.isEmpty, model.errorMessage == nil {
                ContentUnavailableView("Версий пока нет", systemImage: "clock.arrow.circlepath")
                    .listRowSeparator(.hidden)
            } else {
                ForEach(model.versions) { version in
                    VersionHistoryRow(
                        version: version,
                        isCurrent: version.id == model.currentVersionID,
                    )
                }
            }

            if let errorMessage = model.errorMessage {
                Section {
                    InlineErrorView(message: errorMessage)
                }
            }
        }
        .appPlainListStyle()
        .navigationTitle("Версии")
        .navigationBarTitleDisplayMode(.inline)
        .appNavigationChrome()
        .task {
            await model.load()
        }
    }
}

private struct VersionHistoryRow: View {
    let version: ProductVersion
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Версия v\(version.versionNumber)")
                    .font(.headline)
                Spacer()
                if isCurrent {
                    Text("Текущая")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }

            Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(formattedNumber(version.baseAmount)) \(version.baseUnit.russianLabel) · \(formattedNumber(version.nutrition.calories)) ккал")
                .font(.subheadline)

            Text("Б \(formattedNumber(version.nutrition.protein)) · Ж \(formattedNumber(version.nutrition.fat)) · У \(formattedNumber(version.nutrition.carbs))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
