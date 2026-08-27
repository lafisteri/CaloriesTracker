import SwiftUI

enum DateNavigatorLayout {
    static let height: CGFloat = 44
    static let cornerRadius: CGFloat = 12
    static let listRowInsets = EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16)
}

struct DateNavigator<Title: View>: View {
    let previousAccessibilityLabel: String
    let nextAccessibilityLabel: String
    let previousAction: () -> Void
    let nextAction: () -> Void
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?
    let title: Title

    init(
        previousAccessibilityLabel: String,
        nextAccessibilityLabel: String,
        previousAction: @escaping () -> Void,
        nextAction: @escaping () -> Void,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder title: () -> Title,
    ) {
        self.previousAccessibilityLabel = previousAccessibilityLabel
        self.nextAccessibilityLabel = nextAccessibilityLabel
        self.previousAction = previousAction
        self.nextAction = nextAction
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
        self.title = title()
    }

    var body: some View {
        HStack(spacing: 0) {
            navigationButton(
                systemName: "chevron.left",
                accessibilityLabel: previousAccessibilityLabel,
                action: previousAction,
            )

            VStack(spacing: 2) {
                title
                    .font(.headline)
                    .lineLimit(1)

                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity)

            navigationButton(
                systemName: "chevron.right",
                accessibilityLabel: nextAccessibilityLabel,
                action: nextAction,
            )
        }
        .frame(maxWidth: .infinity, minHeight: DateNavigatorLayout.height)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: DateNavigatorLayout.cornerRadius, style: .continuous),
        )
        .buttonStyle(.borderless)
    }

    private func navigationButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .frame(width: DateNavigatorLayout.height, height: DateNavigatorLayout.height)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(accessibilityLabel)
    }
}
