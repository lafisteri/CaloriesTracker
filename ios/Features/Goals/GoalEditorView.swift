import SwiftUI

struct GoalEditorView: View {
    let router: AppRouter

    @State private var model: GoalEditorViewModel

    init(router: AppRouter, goalService: GoalService) {
        self.router = router
        _model = State(initialValue: GoalEditorViewModel(goalService: goalService))
    }

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                DatePicker(
                    "Действует с",
                    selection: Binding(
                        get: { model.effectiveFrom.presentationDate() },
                        set: { model.setEffectiveFrom($0) },
                    ),
                    displayedComponents: .date,
                )
            }

            ForEach(model.days.indices, id: \.self) { index in
                Section(model.days[index].weekday.russianLabel) {
                    TextField("Калории", text: EditableDecimal.binding($model.days[index].caloriesText))
                        .keyboardType(.decimalPad)
                    TextField("Белки", text: EditableDecimal.binding($model.days[index].proteinText))
                        .keyboardType(.decimalPad)
                    TextField("Жиры", text: EditableDecimal.binding($model.days[index].fatText))
                        .keyboardType(.decimalPad)
                    TextField("Углеводы", text: EditableDecimal.binding($model.days[index].carbsText))
                        .keyboardType(.decimalPad)
                }
            }

            Section {
                Picker("Источник", selection: $model.applySourceWeekday) {
                    ForEach(LocalDay.Weekday.allCases, id: \.self) { weekday in
                        Text(weekday.russianShortLabel).tag(weekday)
                    }
                }
                Button("Применить ко всем дням") {
                    model.applyToAllDays()
                }
            }

            if let errorMessage = model.errorMessage {
                Section {
                    GoalInlineErrorView(message: errorMessage)
                }
            }
        }
        .navigationTitle("Цели")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isSaving)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        if await model.save() {
                            router.statisticsPath = []
                        }
                    }
                } label: {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .accessibilityLabel(model.isSaving ? "Сохранение" : "Сохранить")
                .disabled(model.isSaving)
            }
        }
    }
}

private struct GoalInlineErrorView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
