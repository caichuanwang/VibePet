import SwiftUI
import VibePetCore

/// Centralized bubble styling (technical design §5.3.6). Keeping colors / radii /
/// fonts and the width bounds in one place lets later milestones theme the bubble
/// with the pet skin without touching the rendering code.
enum BubbleTheme {
    static let minWidth: CGFloat = 240
    static let maxWidth: CGFloat = 380
    static let cornerRadius: CGFloat = 8
    static let innerCornerRadius: CGFloat = 6
    static let contentMaxHeight: CGFloat = 132 // Panel-like reading area before internal scroll.
    static let padding: CGFloat = 12
    static let tailSize = CGSize(width: 18, height: 9)
    static let scrollThumbWidth: CGFloat = 2

    static let background = Color(red: 0.09, green: 0.10, blue: 0.12).opacity(0.94)
    static let cardBackground = Color.white.opacity(0.07)
    static let fieldBackground = Color.black.opacity(0.22)
    static let border = Color.white.opacity(0.16)
    static let separator = Color.white.opacity(0.10)
    static let headerText = Color.white.opacity(0.62)
    static let bodyText = Color.white.opacity(0.92)
    static let mutedText = Color.white.opacity(0.54)
    static let errorAccent = Color(nsColor: .systemRed)
    static let dashboardPanelTint = Color(nsColor: .black).opacity(0.42)
    static let dashboardCardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.18)
    static let dashboardBorder = Color.white.opacity(0.14)
    static let dashboardPrimaryText = Color.white.opacity(0.94)
    static let dashboardSecondaryText = Color.white.opacity(0.64)
    static let dashboardPillBackground = Color.white.opacity(0.10)
    static let dashboardActivePillBackground = Color.white.opacity(0.20)
    static let dashboardCornerRadius: CGFloat = 14

    static let headerFont = Font.caption2
    static let bodyFont = Font.callout
    static let monoFont = Font.system(.callout, design: .monospaced)

    /// Accent color for an approval's risk level (technical design §5.3.3).
    static func riskAccent(_ risk: RiskLevel) -> Color {
        switch risk {
        case .high: Color(nsColor: .systemRed)
        case .medium: Color(nsColor: .systemOrange)
        case .low: Color.secondary
        }
    }

    static func riskLabel(_ risk: RiskLevel) -> String {
        switch risk {
        case .high: "高风险"
        case .medium: "中风险"
        case .low: "低风险"
        }
    }

    static func dashboardStatusColor(_ status: SessionDashboardProjection.Status) -> Color {
        switch status {
        case .idle:
            Color.secondary
        case .running:
            Color(nsColor: .systemGreen)
        case .attention:
            Color(nsColor: .systemOrange)
        case .error:
            Color(nsColor: .systemRed)
        case .completed:
            Color.secondary
        }
    }
}
