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
    static let interactiveBodyMaxHeight: CGFloat = 260
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

    // Redesign palette (docs/bubble-content-redesign.html). Custom dark accents +
    // a darker footer bar and codebox stroke, replicated from the visual mockup.
    static let accentGreen = Color(red: 0x4f / 255, green: 0xc9 / 255, blue: 0x79 / 255)
    static let accentBlue = Color(red: 0x62 / 255, green: 0xb4 / 255, blue: 0xff / 255)
    static let accentOrange = Color(red: 0xff / 255, green: 0xb0 / 255, blue: 0x4f / 255)
    static let accentRed = Color(red: 0xff / 255, green: 0x6b / 255, blue: 0x6b / 255)
    static let footerBarBackground = Color.black.opacity(0.11)
    static let codeboxBorder = Color.white.opacity(0.10)

    static let dashboardPanelTint = Color(nsColor: .black).opacity(0.42)
    static let dashboardCardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.18)
    static let dashboardBorder = Color.white.opacity(0.14)
    static let dashboardPrimaryText = Color.white.opacity(0.94)
    static let dashboardSecondaryText = Color.white.opacity(0.64)
    static let dashboardPillBackground = Color.white.opacity(0.10)
    static let dashboardActivePillBackground = Color.white.opacity(0.20)
    static let dashboardCornerRadius: CGFloat = 14
    static let footerButtonSpacing: CGFloat = 6

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

    /// Risk text color for the approval section title (mockup `.risk` / `.risk.high`).
    static func riskTextColor(_ risk: RiskLevel) -> Color {
        switch risk {
        case .high: Color(red: 1, green: 0xb2 / 255, blue: 0xb2 / 255)
        case .medium: Color(red: 1, green: 0xd3 / 255, blue: 0x9a / 255)
        case .low: mutedText
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

/// Flat translucent action buttons replicating the redesign palette
/// (docs/bubble-content-redesign.html): neutral / danger / primary / trust.
/// Shared by `ApprovalCard` and `QuestionCard` footers.
struct BubbleActionButtonStyle: ButtonStyle {
    enum Variant {
        case neutral
        case danger
        case primary
        case trust
    }

    let variant: Variant
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.72 : (isEnabled ? 1 : 0.42))
    }

    private var foreground: Color {
        switch variant {
        case .neutral: Color.white.opacity(0.88)
        case .danger: Color(red: 1, green: 0xd2 / 255, blue: 0xd2 / 255)
        case .primary: Color(red: 0xd8 / 255, green: 0xef / 255, blue: 1)
        case .trust: Color(red: 0xc9 / 255, green: 1, blue: 0xd9 / 255)
        }
    }

    private var fill: Color {
        switch variant {
        case .neutral: Color.white.opacity(0.07)
        case .danger: BubbleTheme.accentRed.opacity(0.10)
        case .primary: BubbleTheme.accentBlue.opacity(0.20)
        case .trust: BubbleTheme.accentGreen.opacity(0.10)
        }
    }

    private var border: Color {
        switch variant {
        case .neutral: Color.white.opacity(0.18)
        case .danger: BubbleTheme.accentRed.opacity(0.42)
        case .primary: BubbleTheme.accentBlue.opacity(0.52)
        case .trust: BubbleTheme.accentGreen.opacity(0.42)
        }
    }
}

extension View {
    /// The footer bar treatment from the mockup: a top hairline and a slightly
    /// darker full-width band beneath the card body.
    func bubbleFooterBar() -> some View {
        self
            .padding(.horizontal, BubbleTheme.padding)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BubbleTheme.footerBarBackground)
            .overlay(alignment: .top) {
                Rectangle().fill(BubbleTheme.separator).frame(height: 1)
            }
    }
}

/// Responsive footer: a single row (Back · spacer · trailing actions) that
/// collapses to a stacked column when it cannot fit the card width — mirroring
/// the mockup's narrow-width `flex-direction: column` behavior.
struct BubbleFooter<Back: View, Trailing: View>: View {
    @ViewBuilder var back: () -> Back
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BubbleTheme.footerButtonSpacing) {
                back()
                Spacer(minLength: 8)
                trailing()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: BubbleTheme.footerButtonSpacing) {
                    back()
                    Spacer(minLength: 0)
                }
                HStack(spacing: BubbleTheme.footerButtonSpacing) {
                    Spacer(minLength: 0)
                    trailing()
                }
            }
        }
        .bubbleFooterBar()
    }
}
