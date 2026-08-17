import SwiftUI

struct DiaryAmountView: View {
    let router: AppRouter

    @State private var model: AmountViewModel
    @FocusState private var amountIsFocused: Bool

    init(mode: DiaryAmountEditorMode, router: AppRouter, diaryService: DiaryService) {
        self.router = router
        _model = State(initialValue: AmountViewModel(mode: mode, diaryService: diaryService))
    }

    var body: some View {
        @Bindable var model = model

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.isLoading && model.source == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else if let source = model.source {
                    Text(source.sourceName)
                        .font(.title2.weight(.semibold))

                    nutritionPreview

                    if let previewErrorMessage = model.previewErrorMessage {
                        DiaryInlineErrorView(message: previewErrorMessage)
                    }
                } else {
                    ContentUnavailableView(
                        "Источник недоступен",
                        systemImage: "fork.knife",
                        description: model.errorMessage.map(Text.init),
                    )
                }

                if let errorMessage = model.errorMessage, model.source != nil {
                    DiaryInlineErrorView(message: errorMessage)
                }
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isLoading || model.isSaving)
        .safeAreaInset(edge: .bottom) {
            if let source = model.source {
                HStack(spacing: 10) {
                    TextField("Количество", text: $model.amountText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($amountIsFocused)

                    Picker("Единица", selection: $model.selectedUnitToken) {
                        ForEach(source.unitOptions) { option in
                            Text(unitLabel(option)).tag(option.token)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Button(model.isSaving ? "…" : model.actionTitle) {
                        Task {
                            if await model.save() {
                                amountIsFocused = false
                                router.todayPath = []
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoading || model.isSaving)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    amountIsFocused = false
                }
            }
        }
        .task {
            await model.load()
        }
        .onChange(of: model.amountText) { _, _ in
            model.refreshPreview()
        }
        .onChange(of: model.selectedUnitToken) { _, _ in
            model.refreshPreview()
        }
    }

    @ViewBuilder
    private var nutritionPreview: some View {
        if let preview = model.preview {
            VStack(alignment: .leading, spacing: 6) {
                Text("КБЖУ")
                    .font(.headline)
                Text("\(diaryNumber(preview.calories)) ккал")
                    .font(.title3.weight(.semibold))
                Text("Б \(diaryNumber(preview.protein)) · Ж \(diaryNumber(preview.fat)) · У \(diaryNumber(preview.carbs))")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Введите количество, чтобы увидеть КБЖУ.")
                .foregroundStyle(.secondary)
        }
    }

    private func unitLabel(_ option: DiaryUnitOption) -> String {
        switch option.kind {
        case let .base(baseUnit):
            baseUnit.russianLabel
        case let .serving(name):
            name
        case .recipeGrams:
            "г"
        case .recipeServing:
            "порция"
        }
    }
}
