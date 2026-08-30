import SwiftUI

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: GoalEditorViewModel

    init(goalService: GoalService) {
        _model = State(initialValue: GoalEditorViewModel(goalService: goalService))
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            AppTopNavigationHeader(title: "Цели") {
                Button {
                    Task {
                        if await model.save() {
                            dismiss()
                        }
                    }
                } label: {
                    AppCircularControl {
                        if model.isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                        }
                    }
                }
                .accessibilityLabel(model.isSaving ? "Сохранение" : "Сохранить")
                .disabled(model.isSaving)
            }

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .disabled(model.isSaving || model.isLoading)
        .task {
            await model.load()
        }
    }
}

private struct WeekdaySelector: View {
    @Binding var selectedWeekday: LocalDay.Weekday

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LocalDay.Weekday.allCases, id: \.self) { weekday in
                let isSelected = weekday == selectedWeekday

                Button {
                    selectedWeekday = weekday
                } label: {
                    Text(weekday.russianShortLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            isSelected ? AppStyle.controlBackground : Color.clear,
                            in: Capsule(),
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weekday.russianLabel)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(AppStyle.selectedControlBackground, in: Capsule())
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
