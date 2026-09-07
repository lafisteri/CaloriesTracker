import Observation
import SwiftUI

@MainActor
@Observable
final class ChartSettingsViewModel {
    private let service: ChartSettingsService
    var items: [ChartSettingsItem] = []
    var errorMessage: String?
    var isSaving = false

    init(service: ChartSettingsService) {
        self.service = service
    }

    func load() async {
        do {
            items = try await service.settings().orderedKnownItems
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ updated: [ChartSettingsItem]) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.save(knownItems: updated)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
struct ChartSettingsView: View {
    @State private var model: ChartSettingsViewModel

    init(service: ChartSettingsService) {
        _model = State(initialValue: ChartSettingsViewModel(service: service))
    }

    var body: some View {
        @Bindable var model = model

        List {
            Section {
                ForEach($model.items) { $item in
                    Toggle(item.chartType?.russianTitle ?? item.chartTypeRaw, isOn: $item.isEnabled)
                        .onChange(of: item.isEnabled) { _, _ in
                            Task { await model.save(model.items) }
                        }
                }
                .onMove { indices, destination in
                    var updated = model.items
                    updated.move(fromOffsets: indices, toOffset: destination)
                    Task { await model.save(updated) }
                }
            } footer: {
                Text("Выберите графики для статистики и задайте их порядок.")
            }
        }
        .disabled(model.isSaving)
        .navigationTitle("Графики")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton().disabled(model.isSaving || model.items.isEmpty)
            }
        }
        .task { await model.load() }
        .alert("Графики", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } },
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
