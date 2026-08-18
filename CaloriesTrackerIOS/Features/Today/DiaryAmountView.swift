import SwiftUI
import UIKit

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

        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.isLoading && model.source == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if model.source != nil {
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
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(model.source?.sourceName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isLoading || model.isSaving)
        .toolbar {
            if case let .create(context, _) = model.mode, let productID {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Редактировать") {
                        router.todayPath.append(.productEditorForDiarySelection(productID: productID, context: context))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let source = model.source {
                HStack(spacing: 8) {
                    TextField("", text: $model.amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.body.weight(.semibold))
                        .focused($amountIsFocused)
                        .frame(width: 64)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(amountIsFocused ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
                        }
                        .accessibilityLabel("Количество")

                    Picker("Единица", selection: $model.selectedUnitToken) {
                        ForEach(source.unitOptions) { option in
                            Text(unitLabel(option)).tag(option.token)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 64)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button(model.isSaving ? "…" : model.actionTitle) {
                        Task {
                            if await model.save() {
                                amountIsFocused = false
                                router.todayPath = []
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(model.isLoading || model.isSaving)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .task {
            await model.load()
            if model.source != nil {
                focusAndSelectAmount()
            }
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
        let preview = model.preview ?? .zero
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Калории")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(diaryNumber(preview.calories))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("ккал")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 12) {
                macroValue(title: "Белки", value: preview.protein)
                macroValue(title: "Жиры", value: preview.fat)
                macroValue(title: "Углеводы", value: preview.carbs)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func macroValue(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(diaryNumber(value)) г")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func focusAndSelectAmount() {
        amountIsFocused = true
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
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

    private var productID: UUID? {
        guard let source = model.source,
              case let .product(version) = source.calculationSource
        else {
            return nil
        }
        return version.productID
    }
}
