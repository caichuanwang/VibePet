import SwiftUI
import VibePetCore

@MainActor
final class SessionDashboardModel: ObservableObject {
    @Published var state: SessionState
    @Published var activePetName: String
    @Published var contentVersion = 0

    init(state: SessionState, activePetName: String) {
        self.state = state
        self.activePetName = activePetName
    }

    func update(state: SessionState, activePetName: String) {
        self.state = state
        self.activePetName = activePetName
    }

    func refreshContent() {
        contentVersion += 1
    }
}

@MainActor
struct SessionDashboardCard {
    let id: String
    let view: AnyView
    let resolve: (BridgeResponse) -> Void
}

enum DashboardTranscriptDisplayText {
    static func plainText(from markdown: String) -> String {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DashboardTranscriptLayout {
    static let showsSourceHeader = false
    static let scrollThumbWidth: CGFloat = 2
}

private struct DashboardTranscriptContent: View {
    let session: AgentSession
    let detailSummary: String

    private var bodyText: String {
        DashboardTranscriptDisplayText.plainText(from: detailSummary)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 1)
            ThinDashboardScrollView {
                Text(bodyText)
                    .font(BubbleTheme.bodyFont)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.trailing, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusIcon: String {
        if session.phase == .completed {
            return session.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        }
        return "message.fill"
    }

    private var statusColor: Color {
        if session.phase == .completed {
            return session.isError ? BubbleTheme.errorAccent : Color(nsColor: .systemGreen)
        }
        return Color(nsColor: .systemBlue)
    }

    private var textColor: Color {
        session.isError ? BubbleTheme.errorAccent : BubbleTheme.bodyText
    }
}

private struct ThinDashboardScrollView<Content: View>: View {
    private let content: () -> Content
    private let coordinateSpaceName = "thinDashboardScroll"

    @State private var viewportHeight: CGFloat = 1
    @State private var contentHeight: CGFloat = 1
    @State private var contentMinY: CGFloat = 0

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    private var trackHeight: CGFloat {
        max(viewportHeight - 2, 1)
    }

    private var thumbHeight: CGFloat {
        guard contentHeight > viewportHeight else { return trackHeight }
        return min(trackHeight, max(20, trackHeight * viewportHeight / contentHeight))
    }

    private var thumbOffset: CGFloat {
        let maxScroll = max(contentHeight - viewportHeight, 1)
        let scrollOffset = min(max(-contentMinY, 0), maxScroll)
        return scrollOffset / maxScroll * max(trackHeight - thumbHeight, 0)
    }

    var body: some View {
        GeometryReader { viewport in
            ZStack(alignment: .trailing) {
                ScrollView(.vertical, showsIndicators: false) {
                    content()
                        .background(
                            GeometryReader { contentProxy in
                                Color.clear.preference(
                                    key: ThinDashboardScrollMetricsKey.self,
                                    value: ThinDashboardScrollMetrics(
                                        height: contentProxy.size.height,
                                        minY: contentProxy.frame(in: .named(coordinateSpaceName)).minY
                                    )
                                )
                            }
                        )
                }
                .coordinateSpace(name: coordinateSpaceName)
                .onAppear {
                    viewportHeight = max(viewport.size.height, 1)
                }
                .onChange(of: viewport.size.height) { _, height in
                    viewportHeight = max(height, 1)
                }
                .onPreferenceChange(ThinDashboardScrollMetricsKey.self) { metrics in
                    contentHeight = max(metrics.height, 1)
                    contentMinY = metrics.minY
                }

                if contentHeight > viewportHeight + 1 {
                    VStack {
                        Capsule()
                            .fill(BubbleTheme.dashboardSecondaryText.opacity(0.34))
                            .frame(width: DashboardTranscriptLayout.scrollThumbWidth, height: thumbHeight)
                            .offset(y: thumbOffset)
                        Spacer(minLength: 0)
                    }
                    .frame(width: DashboardTranscriptLayout.scrollThumbWidth, height: trackHeight, alignment: .top)
                    .padding(.vertical, 1)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct ThinDashboardScrollMetrics: Equatable {
    var height: CGFloat = 1
    var minY: CGFloat = 0
}

private struct ThinDashboardScrollMetricsKey: PreferenceKey {
    static let defaultValue = ThinDashboardScrollMetrics()

    static func reduce(value: inout ThinDashboardScrollMetrics, nextValue: () -> ThinDashboardScrollMetrics) {
        value = nextValue()
    }
}

struct SessionDashboardView: View {
    @ObservedObject var model: SessionDashboardModel
    let cardProvider: (String) -> SessionDashboardCard?
    let onJump: (JumpTarget) -> Void
    let onSelectedSessionChanged: (String?, JumpTarget?) -> Void

    @State private var selectedSessionID: String?
    @State private var selectedSessionJumpTarget: JumpTarget?

    var body: some View {
        let projection = projection
        let resolvedSelection = projection.resolvedSelection(current: selectedSessionID)

        HStack(spacing: 0) {
            sidebar(projection: projection, selectedSessionID: resolvedSelection)
            Divider().overlay(BubbleTheme.dashboardBorder)
            detailPane(selection: resolvedSelection, projection: projection)
        }
        .frame(width: 520, height: 300)
        .background(BubbleTheme.dashboardPanelTint)
        .onAppear {
            applyResolvedSelection(resolvedSelection)
        }
        .onChange(of: model.state.visibleSessions.map(\.id)) { _, _ in
            applyResolvedSelection(projection.resolvedSelection(current: selectedSessionID))
        }
        .onChange(of: model.contentVersion) { _, _ in
            applyResolvedSelection(projection.resolvedSelection(current: selectedSessionID))
        }
        .accessibilityElement(children: .contain)
    }

    private var projection: SessionDashboardProjection {
        SessionDashboardProjection(state: model.state, activePetName: model.activePetName)
    }

    private func sidebar(projection: SessionDashboardProjection, selectedSessionID: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sidebarHeader(projection: projection)
            if projection.isEmpty {
                emptyState
            } else {
                ThinDashboardScrollView {
                    VStack(spacing: 5) {
                        ForEach(projection.rows) { row in
                            sessionRow(row, isSelected: row.id == selectedSessionID)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(10)
        .frame(width: 178)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func sidebarHeader(projection: SessionDashboardProjection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(BubbleTheme.dashboardStatusColor(projection.attentionCount > 0 ? .attention : .running))
                    .frame(width: 7, height: 7)
                Text("Sessions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BubbleTheme.dashboardPrimaryText)
                Spacer(minLength: 0)
            }
            Text("\(projection.totalCount) total · \(projection.runningCount) running · \(projection.attentionCount) action")
                .font(.caption2)
                .foregroundStyle(BubbleTheme.dashboardSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Circle()
                .fill(BubbleTheme.dashboardStatusColor(.completed))
                .frame(width: 8, height: 8)
            Text(projection.emptyPetName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(BubbleTheme.dashboardPrimaryText)
                .lineLimit(1)
            Text("no running sessions")
                .font(.caption)
                .foregroundStyle(BubbleTheme.dashboardSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func sessionRow(_ row: SessionDashboardProjection.Row, isSelected: Bool) -> some View {
        Button {
            let jumpTarget = model.state.sessionsByID[row.id]?.jumpTarget
            selectedSessionID = row.id
            selectedSessionJumpTarget = jumpTarget
            onSelectedSessionChanged(row.id, jumpTarget)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(BubbleTheme.dashboardStatusColor(row.status))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(row.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(BubbleTheme.dashboardPrimaryText)
                        if row.status == .attention {
                            Text("!")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(BubbleTheme.dashboardPrimaryText)
                                .frame(width: 14, height: 14)
                                .background(BubbleTheme.dashboardStatusColor(.attention), in: Circle())
                        }
                    }
                    HStack(spacing: 4) {
                        Text(row.toolTag)
                            .lineLimit(1)
                        if let terminalTag = row.terminalTag {
                            Text(terminalTag)
                                .lineLimit(1)
                        }
                        Text(row.elapsed)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(BubbleTheme.dashboardSecondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? BubbleTheme.dashboardActivePillBackground : BubbleTheme.dashboardCardBackground,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7).stroke(
                    isSelected ? BubbleTheme.dashboardStatusColor(row.status).opacity(0.55) : BubbleTheme.dashboardBorder,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func detailPane(selection: String?, projection: SessionDashboardProjection) -> some View {
        if
            let selection,
            let session = model.state.sessionsByID[selection],
            let row = projection.rows.first(where: { $0.id == selection })
        {
            VStack(alignment: .leading, spacing: 9) {
                if let prompt = row.latestUserPrompt {
                    userPromptHeader(prompt)
                    Divider().overlay(BubbleTheme.dashboardBorder)
                }
                tabContent(session, detailSummary: row.detailSummary ?? row.emptyDetailSummary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(projection.emptyPetName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BubbleTheme.dashboardPrimaryText)
                Text("No active agent sessions")
                    .font(.callout)
                    .foregroundStyle(BubbleTheme.dashboardSecondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func userPromptHeader(_ prompt: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("You:")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BubbleTheme.dashboardSecondaryText)
                .lineLimit(1)
            Text(prompt)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BubbleTheme.dashboardPrimaryText.opacity(0.82))
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.top, 1)
    }

    @ViewBuilder
    private func tabContent(_ session: AgentSession, detailSummary: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let card = cardProvider(session.id) {
                card.view
                    .id(card.id)
            } else {
                DashboardTranscriptContent(session: session, detailSummary: detailSummary)
                    .id("\(session.id)-\(session.phase)-\(session.updatedAt.timeIntervalSince1970)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }


    private func applyResolvedSelection(_ selection: String?) {
        let jumpTarget = selection.flatMap { model.state.sessionsByID[$0]?.jumpTarget }
        guard selectedSessionID != selection || selectedSessionJumpTarget != jumpTarget else { return }
        selectedSessionID = selection
        selectedSessionJumpTarget = jumpTarget
        onSelectedSessionChanged(selection, jumpTarget)
    }
}
