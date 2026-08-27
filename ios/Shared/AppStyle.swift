import SwiftUI

enum AppStyle {
    static let background = Color(uiColor: .systemBackground)
    static let controlBackground = Color(uiColor: .systemBackground)
    static let selectedControlBackground = Color(uiColor: .tertiarySystemFill)
    static let screenHorizontalMargin: CGFloat = 16
    static let controlHeight: CGFloat = 48
    static let compactControlSize: CGFloat = 44
    static let controlSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 14

    static let controlShadowColor = Color.black.opacity(0.08)
    static let controlShadowRadius: CGFloat = 12
    static let controlShadowY: CGFloat = 5
}

struct AppCircularControl<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: AppStyle.compactControlSize, height: AppStyle.compactControlSize)
            .background(AppStyle.controlBackground, in: Circle())
            .shadow(
                color: AppStyle.controlShadowColor,
                radius: AppStyle.controlShadowRadius,
                y: AppStyle.controlShadowY
            )
            .contentShape(Circle())
    }
}

struct AppCircularButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            AppCircularControl {
                Image(systemName: systemName)
                    .font(.title3.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct AppNavigationChromeModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    let showsBackButton: Bool

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(showsBackButton)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if showsBackButton {
                    ToolbarItem(placement: .topBarLeading) {
                        AppCircularButton(
                            systemName: "chevron.left",
                            accessibilityLabel: "Назад",
                            action: { dismiss() }
                        )
                    }
                }
            }
    }
}

extension View {
    func appScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppStyle.background.ignoresSafeArea())
    }

    func appPlainListStyle() -> some View {
        listStyle(.plain)
            .appScreenBackground()
    }

    func appNavigationChrome(showsBackButton: Bool = true) -> some View {
        modifier(AppNavigationChromeModifier(showsBackButton: showsBackButton))
    }
}
