import SwiftUI

/// A predictable action-button treatment for iOS, iPadOS, and Mac Catalyst.
///
/// Catalyst's disabled `borderedProminent` rendering can use a black label on
/// a black disabled capsule in dark mode. Keeping the enabled/disabled colors
/// explicit avoids that platform-specific contrast failure.
struct EditorActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? Color.accentColor : Color.secondary.opacity(0.18))
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
