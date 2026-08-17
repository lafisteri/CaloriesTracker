import SwiftData
import SwiftUI

@main
@MainActor
struct CaloriesTrackerApp: App {
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
