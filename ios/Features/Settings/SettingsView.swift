import Foundation
import Observation
import OSLog
import SwiftUI

@MainActor
struct SettingsView: View {
    let goalService: GoalService
    let supabaseAuth: SupabaseAuthService?
    let syncStatus: SyncStatusStore?
    let syncOrchestrator: SyncOrchestrator?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    GoalEditorView(goalService: goalService)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Цели")
                        Text("Калории и БЖУ по дням недели")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    SyncSettingsView(
                        supabaseAuth: supabaseAuth,
                        syncStatus: syncStatus,
                        syncOrchestrator: syncOrchestrator,
                    )
                } label: {
                    LabeledContent("Синхронизация") {
                        Text(SyncStatusPresentation.title(for: syncStatus))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .appPlainListStyle()
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .appNavigationChrome()
    }
}

@MainActor
struct SyncSettingsView: View {
    let syncStatus: SyncStatusStore?

    @State private var model: SettingsViewModel

    init(
        supabaseAuth: SupabaseAuthService?,
        syncStatus: SyncStatusStore?,
        syncOrchestrator: SyncOrchestrator?,
    ) {
        self.syncStatus = syncStatus
        _model = State(
            initialValue: SettingsViewModel(
                authService: supabaseAuth,
                syncOrchestrator: syncOrchestrator,
            ),
        )
    }

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Синхронизация") {
                if model.isConfigured {
                    if model.isLoadingSession {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Проверка аккаунта…")
                        }
                    } else if let session = model.session {
                        signedInContent(session: session)
                    } else {
                        TextField("Email", text: $model.email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(model.isAuthActionInFlight)
                            .onChange(of: model.email) { _, _ in
                                model.emailDidChange()
                            }

                        if model.hasRequestedCode {
                            Text("Код отправлен на \(model.deliveryEmail ?? model.email).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            TextField("Код подтверждения", text: $model.verificationCode)
                                .textContentType(.oneTimeCode)
                                .keyboardType(.numberPad)
                                .disabled(model.isAuthActionInFlight)
                                .onChange(of: model.verificationCode) { _, _ in
                                    model.normalizeVerificationCode()
                                }

                            Button {
                                Task {
                                    await model.verifyOTP()
                                }
                            } label: {
                                authButtonLabel(title: "Войти", action: .verifying)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isAuthActionInFlight || model.verificationCode.count != 6)

                            resendControl
                        } else {
                            Button {
                                Task {
                                    await model.requestOTP()
                                }
                            } label: {
                                authButtonLabel(title: "Отправить код", action: .requestingCode)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isAuthActionInFlight || !model.canRequestCode)
                        }
                    }

                    if let errorMessage = model.errorMessage {
                        SettingsInlineErrorView(message: errorMessage)
                    }
                } else {
                    Text("Синхронизация недоступна")
                        .font(.body.weight(.medium))
                    Text("Сервис синхронизации не настроен.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .appScreenBackground()
        .navigationTitle("Синхронизация")
        .navigationBarTitleDisplayMode(.inline)
        .appNavigationChrome()
        .task {
            await model.loadCurrentSession()
        }
    }

    @ViewBuilder
    private func signedInContent(session: SupabaseAuthSession) -> some View {
        Text(session.email ?? "Аккаунт подключён")

        LabeledContent("Статус") {
            HStack(spacing: 6) {
                if currentSyncStatus == .syncing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(SyncStatusPresentation.title(for: syncStatus))
            }
        }

        LabeledContent("Последняя", value: lastSuccessfulSyncLabel)

        Button("Синхронизировать сейчас") {
            Task {
                await model.requestSyncNow()
            }
        }
        .disabled(model.isAuthActionInFlight || currentSyncStatus == .syncing)

        if currentSyncStatus == .blocked {
            SettingsInlineErrorView(message: "Не удалось выполнить синхронизацию. Попробуйте позже.")
        }

        Button(role: .destructive) {
            Task {
                await model.signOut()
            }
        } label: {
            authButtonLabel(title: "Выйти", action: .signingOut)
        }
        .disabled(model.isAuthActionInFlight)
    }

    private var resendControl: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = model.resendRemaining(at: context.date)
            Button {
                Task {
                    await model.requestOTP()
                }
            } label: {
                authButtonLabel(
                    title: remaining > 0 ? "Повторить через \(remaining) с" : "Отправить код повторно",
                    action: .requestingCode,
                )
            }
            .disabled(model.isAuthActionInFlight || remaining > 0)
        }
    }

    @ViewBuilder
    private func authButtonLabel(title: String, action: SettingsViewModel.AuthAction) -> some View {
        if model.authAction == action {
            ProgressView()
        } else {
            Text(title)
        }
    }

    private var currentSyncStatus: SyncStatus {
        syncStatus?.status ?? .disabled
    }

    private var lastSuccessfulSyncLabel: String {
        guard let date = syncStatus?.lastSuccessfulSyncAt else {
            return "Никогда"
        }

        let calendar = Calendar.autoupdatingCurrent
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDateInToday(date) {
            return "Сегодня, \(time)"
        }
        if calendar.isDateInYesterday(date) {
            return "Вчера, \(time)"
        }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute())
    }

}

@MainActor
private enum SyncStatusPresentation {
    static func title(for syncStatus: SyncStatusStore?) -> String {
        let status = syncStatus?.status ?? .disabled
        return switch status {
        case .disabled:
            "Недоступно"
        case .signedOut:
            "Не выполнен вход"
        case .idle:
            if syncStatus?.lastSuccessfulSyncAt != nil, syncStatus?.lastErrorCategory == nil {
                "Синхронизировано"
            } else {
                "Ожидание синхронизации"
            }
        case .syncing:
            "Синхронизация…"
        case .waitingForRetry:
            "Ожидание сети…"
        case .blocked:
            "Требуется внимание"
        }
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    enum AuthAction: Equatable {
        case requestingCode
        case verifying
        case signingOut
    }

    private static let resendInterval: TimeInterval = 60
    private static let logger = Logger(subsystem: "com.caloriestracker.ios", category: "Settings")

    private let authService: SupabaseAuthService?
    private let syncOrchestrator: SyncOrchestrator?

    var email = ""
    var verificationCode = ""
    private(set) var session: SupabaseAuthSession?
    private(set) var deliveryEmail: String?
    private(set) var hasRequestedCode = false
    private(set) var resendAvailableAt: Date?
    private(set) var isLoadingSession = false
    private(set) var authAction: AuthAction?
    var errorMessage: String?

    init(authService: SupabaseAuthService?, syncOrchestrator: SyncOrchestrator?) {
        self.authService = authService
        self.syncOrchestrator = syncOrchestrator
    }

    var isConfigured: Bool {
        authService != nil
    }

    var isAuthActionInFlight: Bool {
        authAction != nil
    }

    var canRequestCode: Bool {
        !normalizedEmail.isEmpty
    }

    func loadCurrentSession() async {
        guard let authService, !isLoadingSession else {
            return
        }
        isLoadingSession = true
        errorMessage = nil
        defer { isLoadingSession = false }

        do {
            session = try await authService.currentSession()
        } catch {
            logFailure(operation: "load_session", error: error)
            errorMessage = "Не удалось проверить состояние аккаунта. Попробуйте позже."
        }
    }

    func emailDidChange() {
        guard hasRequestedCode else {
            return
        }
        hasRequestedCode = false
        deliveryEmail = nil
        verificationCode = ""
        resendAvailableAt = nil
        errorMessage = nil
    }

    func normalizeVerificationCode() {
        let normalized = String(verificationCode.filter(\.isNumber).prefix(6))
        guard verificationCode != normalized else {
            return
        }
        verificationCode = normalized
    }

    func resendRemaining(at date: Date) -> Int {
        guard let resendAvailableAt else {
            return 0
        }
        return max(0, Int(ceil(resendAvailableAt.timeIntervalSince(date))))
    }

    func requestOTP() async {
        guard let authService, !isAuthActionInFlight else {
            return
        }
        guard !normalizedEmail.isEmpty else {
            errorMessage = "Введите email."
            return
        }

        let requestedEmail = normalizedEmail
        errorMessage = nil
        authAction = .requestingCode
        defer { authAction = nil }

        do {
            try await authService.requestOTP(email: requestedEmail)
            deliveryEmail = requestedEmail
            hasRequestedCode = true
            verificationCode = ""
            resendAvailableAt = Date().addingTimeInterval(Self.resendInterval)
        } catch {
            logFailure(operation: "request_otp", error: error)
            errorMessage = requestOTPErrorMessage(for: error)
        }
    }

    func verifyOTP() async {
        guard let authService,
              !isAuthActionInFlight,
              verificationCode.count == 6,
              let deliveryEmail
        else {
            return
        }

        errorMessage = nil
        authAction = .verifying
        defer { authAction = nil }

        do {
            session = try await authService.verifyOTP(email: deliveryEmail, token: verificationCode)
            verificationCode = ""
            hasRequestedCode = false
            resendAvailableAt = nil
        } catch {
            logFailure(operation: "verify_otp", error: error)
            errorMessage = verifyOTPErrorMessage(for: error)
        }
    }

    func requestSyncNow() async {
        await syncOrchestrator?.userRequestedSync()
    }

    func signOut() async {
        guard let authService, !isAuthActionInFlight else {
            return
        }

        errorMessage = nil
        authAction = .signingOut
        defer { authAction = nil }

        do {
            try await authService.signOut()
            session = nil
            email = ""
            verificationCode = ""
            deliveryEmail = nil
            hasRequestedCode = false
            resendAvailableAt = nil
        } catch {
            logFailure(operation: "sign_out", error: error)
            errorMessage = signOutErrorMessage(for: error)
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestOTPErrorMessage(for error: Error) -> String {
        switch error as? SupabaseInfrastructureError {
        case .network:
            "Не удалось отправить код.\nПроверьте подключение к интернету."
        case .notConfigured:
            "Сервис синхронизации не настроен."
        default:
            "Не удалось отправить код. Попробуйте позже."
        }
    }

    private func verifyOTPErrorMessage(for error: Error) -> String {
        switch error as? SupabaseInfrastructureError {
        case .network:
            "Не удалось подтвердить код.\nПроверьте подключение к интернету."
        case .notAuthenticated, .unauthorized, .server:
            "Неверный или просроченный код."
        case .notConfigured:
            "Сервис синхронизации не настроен."
        default:
            "Не удалось подтвердить код. Попробуйте позже."
        }
    }

    private func signOutErrorMessage(for error: Error) -> String {
        switch error as? SupabaseInfrastructureError {
        case .network:
            "Не удалось выйти из аккаунта.\nПроверьте подключение к интернету."
        default:
            "Не удалось выйти из аккаунта. Попробуйте позже."
        }
    }

    private func logFailure(operation: String, error: Error) {
        let category: String
        switch error as? SupabaseInfrastructureError {
        case .network:
            category = "network"
        case .server:
            category = "server"
        case .notAuthenticated, .unauthorized:
            category = "authentication"
        case .notConfigured:
            category = "configuration"
        case .decode, .invalidResponse, .none:
            category = "unexpected"
        }
        Self.logger.error("Settings operation \(operation, privacy: .public) failed category=\(category, privacy: .public)")
    }
}

private struct SettingsInlineErrorView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
