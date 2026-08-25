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

        AmountEditorView(
            title: model.isProductEditRefreshBlocked ? "Обновление продукта" : model.source?.sourceName ?? "",
            isLoading: model.isLoading,
            isAvailable: model.isSourceAvailable,
            preview: model.preview,
            previewErrorMessage: model.previewErrorMessage,
            errorMessage: model.errorMessage,
            unavailableTitle: "Источник недоступен",
            unavailableSystemImage: "fork.knife",
            amountText: $model.amountText,
            selectedUnitToken: $model.selectedUnitToken,
            unitOptions: availableUnitOptions,
            amountIsFocused: amountIsFocused,
            amountFocus: isAmountFocusEnabled ? $amountIsFocused : nil,
            actionTitle: model.actionTitle,
            isSaving: model.isSaving,
            onConfirm: {
                Self.logger.notice("action=amount_save_tapped mode=\(modeDiagnostic, privacy: .public)")
                Task {
                    let didSave = await model.save()
                    Self.logger.notice("action=amount_save_finished success=\(didSave)")
                    if didSave {
                        amountIsFocused = false
                        router.todayPath = []
                    }
                }
            },
        )
        .disabled(model.isLoading || model.isSaving)
        .toolbar {
            if model.isProductEditRefreshBlocked {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        refreshAfterProductEdit()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Повторить обновление продукта")
                }
            }
            if let productID {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Self.logger.notice("action=product_edit_tapped mode=\(modeDiagnostic, privacy: .public)")
                        Self.logger.notice("focus=amount_disabled_for_product_editor")
                        isAmountFocusEnabled = false
                        amountIsFocused = false
                        router.todayPath.append(productEditorRoute(for: productID))
                        Self.logger.debug("navigation=product_editor_pushed path_count=\(router.todayPath.count)")
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Редактировать")
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
            refreshAfterProductEditIfRequested()
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
        .onChange(of: model.selectedUnitToken) { _, _ in
            model.refreshPreview()
        }
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

    private func refreshAfterProductEditIfRequested() {
        guard isCurrentAmountRoute else {
            return
        }

        switch model.mode {
        case let .create(_, sourceReference, _):
            guard router.consumeCreateAmountSourceRefresh(for: sourceReference) else {
                return
            }
        case let .edit(entryID):
            guard router.consumeEntryProductRebase(entryID: entryID) else {
                return
            }
        }

        refreshAfterProductEdit()
    }

    private func refreshAfterProductEdit() {
        model.beginProductEditRefresh()
        isAmountFocusEnabled = false

        Task { @MainActor in
            let didRefresh = await model.refreshAfterProductEdit()
            guard didRefresh, isCurrentAmountRoute else {
                return
            }
            isAmountFocusEnabled = true
            restoreAmountFocus()
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
        case .productEditorForEntryAmount:
            "product_editor_for_entry_amount"
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
        case let (.create(context, source, _), .amount(routeContext, routeSource, _)):
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
        case .recipeGrams:
            "г"
        case .recipeServing:
            "порция"
        }
    }

    private var availableUnitOptions: [AmountUnitOption] {
        guard let source = model.source else {
            return []
        }
        return source.unitOptions.map { option in
            AmountUnitOption(token: option.token, label: unitLabel(option))
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

    private func productEditorRoute(for productID: UUID) -> TodayRoute {
        switch model.mode {
        case let .create(context, _, _):
            return .productEditorForDiarySelection(productID: productID, context: context)
        case let .edit(entryID):
            return .productEditorForEntryAmount(productID: productID, entryID: entryID)
        }
    }
}

struct AmountUnitOption: Identifiable, Hashable, Sendable {
    let token: String
    let label: String

    var id: String {
        token
    }
}

struct AmountEditorView: View {
    let title: String
    let contextDescription: String?
    let isLoading: Bool
    let isAvailable: Bool
    let preview: Nutrition?
    let previewErrorMessage: String?
    let errorMessage: String?
    let unavailableTitle: String
    let unavailableSystemImage: String
    @Binding private var amountText: String
    @Binding private var selectedUnitToken: String
    let unitOptions: [AmountUnitOption]
    let amountIsFocused: Bool
    let amountFocus: FocusState<Bool>.Binding?
    let autoFocusAmount: Bool
    let actionTitle: String
    let isSaving: Bool
    let onConfirm: () -> Void

    init(
        title: String,
        contextDescription: String? = nil,
        isLoading: Bool,
        isAvailable: Bool,
        preview: Nutrition?,
        previewErrorMessage: String?,
        errorMessage: String?,
        unavailableTitle: String,
        unavailableSystemImage: String,
        amountText: Binding<String>,
        selectedUnitToken: Binding<String>,
        unitOptions: [AmountUnitOption],
        amountIsFocused: Bool,
        amountFocus: FocusState<Bool>.Binding?,
        autoFocusAmount: Bool = false,
        actionTitle: String,
        isSaving: Bool,
        onConfirm: @escaping () -> Void,
    ) {
        self.title = title
        self.contextDescription = contextDescription
        self.isLoading = isLoading
        self.isAvailable = isAvailable
        self.preview = preview
        self.previewErrorMessage = previewErrorMessage
        self.errorMessage = errorMessage
        self.unavailableTitle = unavailableTitle
        self.unavailableSystemImage = unavailableSystemImage
        _amountText = amountText
        _selectedUnitToken = selectedUnitToken
        self.unitOptions = unitOptions
        self.amountIsFocused = amountIsFocused
        self.amountFocus = amountFocus
        self.autoFocusAmount = autoFocusAmount
        self.actionTitle = actionTitle
        self.isSaving = isSaving
        self.onConfirm = onConfirm
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading && !isAvailable {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else if isAvailable {
                    if let contextDescription {
                        Text(contextDescription)
                            .foregroundStyle(.secondary)
                    }
                    AmountNutritionPreview(nutrition: preview ?? .zero)

                    if let previewErrorMessage {
                        DiaryInlineErrorView(message: previewErrorMessage)
                    }
                } else {
                    ContentUnavailableView(
                        unavailableTitle,
                        systemImage: unavailableSystemImage,
                        description: errorMessage.map(Text.init),
                    )
                }

                if let errorMessage, isAvailable {
                    DiaryInlineErrorView(message: errorMessage)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isAvailable {
                actionBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard autoFocusAmount, let amountFocus else {
                return
            }
            await Task.yield()
            amountFocus.wrappedValue = true
            await Task.yield()
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            amountTextField
            unitControl

            Button(action: onConfirm) {
                Group {
                    if isSaving {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark")
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(actionTitle)
            .disabled(isLoading || isSaving)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var amountTextField: some View {
        if let amountFocus {
            styledAmountTextField
                .focused(amountFocus)
        } else {
            styledAmountTextField
        }
    }

    private var styledAmountTextField: some View {
        TextField("", text: EditableDecimal.binding($amountText))
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

    @ViewBuilder
    private var unitControl: some View {
        switch unitOptions.count {
        case 0:
            EmptyView()
        case 1:
            Text(unitOptions[0].label)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .leading)
                .accessibilityLabel("Единица: \(unitOptions[0].label)")
        default:
            Menu {
                ForEach(unitOptions) { option in
                    Button {
                        selectedUnitToken = option.token
                    } label: {
                        if selectedUnitToken == option.token {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedUnitLabel)
                        .font(.body.weight(.medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .frame(minWidth: 64, minHeight: 44)
                .padding(.horizontal, 8)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                )
            }
            .accessibilityLabel("Единица: \(selectedUnitLabel)")
            .accessibilityHint("Выберите единицу")
        }
    }

    private var selectedUnitLabel: String {
        unitOptions.first(where: { $0.token == selectedUnitToken })?.label ?? selectedUnitToken
    }
}

private struct AmountNutritionPreview: View {
    let nutrition: Nutrition

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Калории")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(diaryNumber(nutrition.calories))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("ккал")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 12) {
                macroValue(title: "Белки", value: nutrition.protein)
                macroValue(title: "Жиры", value: nutrition.fat)
                macroValue(title: "Углеводы", value: nutrition.carbs)
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
}
