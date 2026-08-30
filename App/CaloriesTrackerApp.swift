import SwiftData
import SwiftUI

@main
@MainActor
struct CaloriesTrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let dependencies: AppDependencies?
    private let startupMessage: String?

    init() {
        do {
            dependencies = try AppDependencies()
            startupMessage = nil
        } catch {
            dependencies = nil
            startupMessage = "Не удалось подготовить локальное хранилище. Закройте приложение и попробуйте снова."
        }
    }

    var body: some Scene {
        WindowGroup {
            if let dependencies {
                RootApplicationView(dependencies: dependencies)
                    .modelContainer(dependencies.modelContainer)
                    .onChange(of: scenePhase, initial: true) { _, phase in
                        Task {
                            if phase == .active {
                                await dependencies.syncOrchestrator?.applicationDidBecomeActive()
                            } else {
                                await dependencies.syncOrchestrator?.applicationDidLeaveActive()
                            }
                        }
                    }
            } else {
                StartupFailureView(message: startupMessage ?? "Не удалось запустить приложение.")
            }
        }
    }
}

private struct StartupFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Не удалось запустить приложение",
            systemImage: "exclamationmark.triangle",
            description: Text(message),
        )
    }
}
