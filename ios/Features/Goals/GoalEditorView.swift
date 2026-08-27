import SwiftUI

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: GoalEditorViewModel

    init(goalService: GoalService) {
        _model = State(initialValue: GoalEditorViewModel(goalService: goalService))
    }

    var body: some View {
        @Bindable var model = model

        Form {
            if model.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Загрузка целей")
                        Spacer()
                    }
                }
            } else {
                Section {
                    WeekdaySelector(selectedWeekday: $model.selectedWeekday)

                    let selectedDayIndex = model.days.firstIndex { $0.weekday == model.selectedWeekday } ?? 0

                    Group {
                        TextField("Калории", text: EditableDecimal.binding($model.days[selectedDayIndex].caloriesText))
                            .keyboardType(.decimalPad)
                        TextField("Белки", text: EditableDecimal.binding($model.days[selectedDayIndex].proteinText))
                            .keyboardType(.decimalPad)
                        TextField("Жиры", text: EditableDecimal.binding($model.days[selectedDayIndex].fatText))
                            .keyboardType(.decimalPad)
                        TextField("Углеводы", text: EditableDecimal.binding($model.days[selectedDayIndex].carbsText))
                            .keyboardType(.decimalPad)
                    }
                    .id(model.selectedWeekday)

                    Button {
                        model.applyToAllDays()
                    } label: {
                        Text("Применить ко всем дням")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
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
        .disabled(model.isSaving || model.isLoading)
        .task {
            await model.load()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        if await model.save() {
                            dismiss()
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

private struct WeekdaySelector: View {
    @Binding var selectedWeekday: LocalDay.Weekday

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LocalDay.Weekday.allCases, id: \.self) { weekday in
                let isSelected = weekday == selectedWeekday

                Button {
                    selectedWeekday = weekday
                } label: {
                    Text(weekday.russianShortLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: Circle(),
                        )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(weekday.russianLabel)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
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
