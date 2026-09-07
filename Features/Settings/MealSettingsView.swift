import SwiftUI
import Observation

@MainActor
@Observable
final class MealSettingsViewModel {
    let service: MealConfigurationService
    var meals: [MealConfigurationItem] = []
    var errorMessage: String?
    var isSaving = false
    init(service: MealConfigurationService) { self.service = service }

    func load() async {
        do { meals = try await service.configuration(for: .current()).meals }
        catch { errorMessage = error.localizedDescription }
    }

    func save(_ updated: [MealConfigurationItem]) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.saveToday(updated)
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}

@MainActor
struct MealSettingsView: View {
    @State private var model: MealSettingsViewModel
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var showingEditor = false

    init(service: MealConfigurationService) {
        _model = State(initialValue: MealSettingsViewModel(service: service))
    }

    var body: some View {
        List {
            Section {
                ForEach(model.meals) { meal in
                    Button(meal.name) {
                        editingID = meal.mealID
                        name = meal.name
                        showingEditor = true
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { indices in
                    var updated = model.meals
                    updated.remove(atOffsets: indices)
                    Task { await model.save(updated) }
                }
                .onMove { indices, destination in
                    var updated = model.meals
                    updated.move(fromOffsets: indices, toOffset: destination)
                    Task { await model.save(updated) }
                }
            } footer: {
                Text("Изменения действуют с сегодняшнего дня. Прошлые дни сохраняют свои названия и порядок.")
            }
        }
        .disabled(model.isSaving)
        .navigationTitle("Приёмы пищи")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton().disabled(model.isSaving || model.meals.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingID = nil
                    name = ""
                    showingEditor = true
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Добавить приём пищи")
                .disabled(model.isSaving || model.meals.isEmpty)
            }
        }
        .task { await model.load() }
        .alert(editingID == nil ? "Новый приём пищи" : "Название приёма пищи", isPresented: $showingEditor) {
            TextField("Название", text: $name)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") {
                var updated = model.meals
                if let editingID, let index = updated.firstIndex(where: { $0.mealID == editingID }) {
                    updated[index].name = name
                } else {
                    updated.append(MealConfigurationItem(mealID: UUID(), name: name, position: updated.count))
                }
                Task { await model.save(updated) }
            }
        }
        .alert("Приёмы пищи", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }
}
