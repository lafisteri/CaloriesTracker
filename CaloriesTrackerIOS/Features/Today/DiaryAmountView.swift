import OSLog
import SwiftUI
import UIKit

struct DiaryAmountView: View {
    private static let logger = Logger(subsystem: "com.caloriestracker.ios", category: "AmountFlow")

    let router: AppRouter

    @State private var model: AmountViewModel
    @State private var hasLoadedInitialState = false
    @State private var isAmountFocusEnabled = true
    @FocusState private var amountIsFocused: Bool

    init(mode: DiaryAmountEditorMode, router: AppRouter, diaryService: DiaryService) {
        self.router = router
        _model = State(initialValue: AmountViewModel(mode: mode, diaryService: diaryService))
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
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

            if let source = model.source {
                HStack(spacing: 8) {
                    amountTextField(text: $model.amountText)

                    Text(selectedUnitLabel(for: source))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 64, alignment: .leading)
                        .accessibilityLabel("Единица: \(selectedUnitLabel(for: source))")

                    Button(model.isSaving ? "…" : model.actionTitle) {
                        Self.logger.notice("action=amount_save_tapped mode=\(modeDiagnostic, privacy: .public)")
                        Task {
                            let didSave = await model.save()
                            Self.logger.notice("action=amount_save_finished success=\(didSave)")
                            if didSave {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(model.source?.sourceName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isLoading || model.isSaving)
        .toolbar {
            if case let .create(context, _) = model.mode, let productID {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Редактировать") {
                        Self.logger.notice("action=product_edit_tapped mode=\(modeDiagnostic, privacy: .public)")
                        Self.logger.notice("focus=amount_disabled_for_product_editor")
                        isAmountFocusEnabled = false
                        amountIsFocused = false
                        router.todayPath.append(.productEditorForDiarySelection(productID: productID, context: context))
                        Self.logger.debug("navigation=product_editor_pushed path_count=\(router.todayPath.count)")
                    }
                }
            }
        }
        .task {
            guard !hasLoadedInitialState else {
                Self.logger.debug("lifecycle=task_load_skipped_already_loaded")
                return
            }
            hasLoadedInitialState = true
            Self.logger.debug("lifecycle=task_load_started mode=\(modeDiagnostic, privacy: .public)")
            await model.load()
            Self.logger.debug("lifecycle=task_load_finished source_available=\(model.source != nil)")
            restoreAmountFocus()
        }
        .onAppear {
            Self.logger.notice("lifecycle=appear focus=\(amountIsFocused) top_route=\(Self.routeLabel(router.todayPath.last), privacy: .public)")
        }
        .onDisappear {
            Self.logger.notice("lifecycle=disappear focus_before_clear=\(amountIsFocused) top_route=\(Self.routeLabel(router.todayPath.last), privacy: .public)")
            amountIsFocused = false
        }
        .onChange(of: router.todayPath) { _, path in
            let isCurrentRoute = isCurrentAmountRoute
            Self.logger.notice("navigation=today_path_changed path_count=\(path.count) top_route=\(Self.routeLabel(path.last), privacy: .public) current_amount_route=\(isCurrentRoute)")
        }
        .onChange(of: router.amountFocusRestorationRevision) { _, revision in
            guard isCurrentAmountRoute else {
                Self.logger.debug("focus=amount_restore_after_editor_skipped revision=\(revision) current_amount_route=false")
                return
            }
            Self.logger.notice("focus=amount_restore_after_editor_requested revision=\(revision)")
            isAmountFocusEnabled = true
            restoreAmountFocus()
        }
        .onChange(of: amountIsFocused) { previousFocus, currentFocus in
            Self.logger.notice("focus=amount_changed previous=\(previousFocus) current=\(currentFocus)")
        }
        .onChange(of: model.amountText) { _, _ in
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

    @ViewBuilder
    private func amountTextField(text: Binding<String>) -> some View {
        if isAmountFocusEnabled {
            styledAmountTextField(text: text)
                .focused($amountIsFocused)
        } else {
            styledAmountTextField(text: text)
        }
    }

    private func styledAmountTextField(text: Binding<String>) -> some View {
        TextField("", text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.body.weight(.semibold))
            .frame(width: 64)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(amountIsFocused ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
            }
            .accessibilityLabel("Количество")
    }

    private func restoreAmountFocus() {
        Self.logger.debug("focus=amount_restore_scheduled")
        Task { @MainActor in
            await Task.yield()
            guard model.source != nil, isCurrentAmountRoute else {
                Self.logger.debug("focus=amount_restore_skipped source_available=\(model.source != nil) current_amount_route=\(isCurrentAmountRoute)")
                return
            }
            Self.logger.notice("focus=amount_requested")
            amountIsFocused = true
            await Task.yield()
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
            Self.logger.debug("focus=amount_select_all_sent")
        }
    }

    private var modeDiagnostic: String {
        switch model.mode {
        case .create:
            "create"
        case .edit:
            "edit"
        }
    }

    private static func routeLabel(_ route: TodayRoute?) -> String {
        guard let route else {
            return "none"
        }

        return switch route {
        case .catalogSelection:
            "catalog_selection"
        case .amount:
            "amount"
        case .entryEditor:
            "entry_editor"
        case .productEditor:
            "product_editor"
        case .productEditorForDiarySelection:
            "product_editor_for_diary_selection"
        case .recipeEditor:
            "recipe_editor"
        case .productDetails:
            "product_details"
        case .recipeDetails:
            "recipe_details"
        }
    }

    private var isCurrentAmountRoute: Bool {
        guard let route = router.todayPath.last else {
            return false
        }

        switch (model.mode, route) {
        case let (.create(context, source), .amount(routeContext, routeSource)):
            return context == routeContext && source == routeSource
        case let (.edit(entryID), .entryEditor(routeEntryID)):
            return entryID == routeEntryID
        default:
            return false
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

    private func selectedUnitLabel(for source: DiaryAmountSource) -> String {
        guard let option = source.unitOptions.first(where: { $0.token == model.selectedUnitToken }) else {
            return model.selectedUnitToken
        }
        return unitLabel(option)
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
