import SwiftUI

/// Centralized bubble styling (technical design §5.3.6). Keeping colors / radii /
/// fonts and the width bounds in one place lets later milestones theme the bubble
/// with the pet skin without touching the rendering code.
enum BubbleTheme {
    static let minWidth: CGFloat = 240
    static let maxWidth: CGFloat = 380
    static let cornerRadius: CGFloat = 14
    static let contentMaxHeight: CGFloat = 132 // ~6 lines before internal scroll
    static let padding: CGFloat = 12
    static let tailSize = CGSize(width: 18, height: 9)

    static let background = Color(nsColor: .windowBackgroundColor)
    static let border = Color.primary.opacity(0.12)
    static let headerText = Color.secondary
    static let bodyText = Color.primary
    static let errorAccent = Color(nsColor: .systemRed)

    static let headerFont = Font.caption2
    static let bodyFont = Font.callout
}
