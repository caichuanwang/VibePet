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

struct SessionDashboardView: View {
    @ObservedObject var model: SessionDashboardModel
    let cardProvider: (String) -> SessionDashboardCard?
    let onJump: (JumpTarget) -> Void
    let onSelectedSessionChanged: (String?) -> Void

    @State private var selectedSessionID: String?

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
        VStack(alignment: .leading, spacing: 10) {
            sidebarHeader(projection: projection)
            if projection.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(projection.rows) { row in
                            sessionRow(row, isSelected: row.id == selectedSessionID)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(12)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func sidebarHeader(projection: SessionDashboardProjection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Circle()
                    .fill(BubbleTheme.dashboardStatusColor(projection.attentionCount > 0 ? .attention : .running))
                    .frame(width: 7, height: 7)
                Text("Sessions")
                    .font(.callout.weight(.semibold))
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
            selectedSessionID = row.id
            onSelectedSessionChanged(row.id)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(BubbleTheme.dashboardStatusColor(row.status))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
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
                    HStack(spacing: 5) {
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
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? BubbleTheme.dashboardActivePillBackground : BubbleTheme.dashboardCardBackground,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(
                    isSelected ? BubbleTheme.dashboardStatusColor(row.status).opacity(0.55) : BubbleTheme.dashboardBorder,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func detailPane(selection: String?, projection: SessionDashboardProjection) -> some View {
        if let selection, let session = model.state.sessionsByID[selection] {
            VStack(alignment: .leading, spacing: 10) {
                detailHeader(session, projection: projection)
                tabContent(session)
            }
            .padding(12)
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

    private func detailHeader(_ session: AgentSession, projection: SessionDashboardProjection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(BubbleTheme.dashboardStatusColor(SessionDashboardProjection.status(for: session)))
                    .frame(width: 8, height: 8)
                Text(session.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(BubbleTheme.dashboardPrimaryText)
                Spacer(minLength: 0)
                if projection.attentionCount > 0, !session.phase.requiresAttention {
                    Text("\(projection.attentionCount) action")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BubbleTheme.dashboardPrimaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(BubbleTheme.dashboardStatusColor(.attention).opacity(0.24), in: Capsule())
                }
            }
            HStack(spacing: 6) {
                tag(SessionDashboardProjection.toolTag(for: session.tool))
                if let terminalTag = session.jumpTarget?.terminalApp {
                    tag(terminalTag)
                }
                Text(session.phase.requiresAttention ? "needs user decision" : session.phase.rawValue)
                    .font(.caption2)
                    .foregroundStyle(BubbleTheme.dashboardSecondaryText)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let card = cardProvider(session.id) {
                card.view
                    .id(card.id)
            } else {
                SpeechBubble(
                    content: dashboardContent(for: session),
                    source: sourceInfo(for: session),
                    tailEdge: .bottom,
                    tailOffsetX: 40,
                    autoDismiss: false,
                    onJump: onJump,
                    onDismiss: {}
                )
                .id("\(session.id)-\(session.phase)-\(session.updatedAt.timeIntervalSince1970)")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BubbleTheme.dashboardCardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(BubbleTheme.dashboardBorder, lineWidth: 1)
        )
        .clipped()
    }

    private func dashboardContent(for session: AgentSession) -> BubbleContent {
        if session.phase == .completed {
            return .completion(CompletionContent(markdownSummary: session.summary, isError: session.isError))
        }
        return .status(StatusContent(text: session.summary))
    }

    private func sourceInfo(for session: AgentSession) -> SourceInfo {
        SourceInfo(
            tool: session.tool,
            projectName: session.title,
            sessionID: session.id,
            sessionShortId: String(session.id.prefix(6)),
            cwd: session.jumpTarget?.workingDirectory,
            jumpTarget: session.jumpTarget
        )
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(BubbleTheme.dashboardPrimaryText)
            .background(BubbleTheme.dashboardPillBackground, in: Capsule())
    }

    private func applyResolvedSelection(_ selection: String?) {
        guard selectedSessionID != selection else { return }
        selectedSessionID = selection
        onSelectedSessionChanged(selection)
    }
}
