import SwiftUI

/// Live presentation state for the front approval card. Held by the surface so the
/// "还有 N 个待处理" count and the peeking stack update without recreating the card
/// (which would reset its countdown).
@MainActor
final class ApprovalPresentation: ObservableObject {
    @Published var pendingCount: Int

    init(pendingCount: Int) {
        self.pendingCount = pendingCount
    }

    nonisolated static func peekCount(for pendingCount: Int) -> Int {
        min(max(pendingCount, 0), 2)
    }
}

/// Renders the front approval card with up to two cards peeking a thin edge behind
/// it when more approvals are queued (technical design §5.3.5). The "还有 N 个待处理"
/// label lives in the card footer; this view only draws the stacked depth cue.
struct BubbleStackView<Front: View>: View {
    @ObservedObject var presentation: ApprovalPresentation
    let tailEdge: SpeechBubble.TailEdge
    let front: Front

    init(
        presentation: ApprovalPresentation,
        tailEdge: SpeechBubble.TailEdge,
        @ViewBuilder front: () -> Front
    ) {
        self.presentation = presentation
        self.tailEdge = tailEdge
        self.front = front()
    }

    private var peekCount: Int { ApprovalPresentation.peekCount(for: presentation.pendingCount) }

    var body: some View {
        ZStack {
            ForEach(0..<peekCount, id: \.self) { index in
                peekingCard(depth: index + 1)
            }
            front
                .zIndex(10)
        }
    }

    /// A thin rounded edge behind the front card. Deeper cards inset more and shift
    /// toward the pet-facing edge so they read as a stack.
    private func peekingCard(depth: Int) -> some View {
        let inset = CGFloat(depth) * 7
        let shift = CGFloat(depth) * 6
        return RoundedRectangle(cornerRadius: BubbleTheme.cornerRadius)
            .fill(BubbleTheme.background)
            .overlay(
                RoundedRectangle(cornerRadius: BubbleTheme.cornerRadius)
                    .stroke(BubbleTheme.border, lineWidth: 1)
            )
            .padding(.horizontal, inset)
            .padding(tailEdge == .bottom ? .top : .bottom, shift)
            .padding(tailEdge == .bottom ? .bottom : .top, BubbleTheme.tailSize.height)
            .zIndex(Double(depth))
            .accessibilityHidden(true)
    }
}
