import SwiftUI
import VibePetCore

/// Reusable hooks install/uninstall list, shown in the settings page and onboarding
/// step ③. `detectedOnly` (onboarding) lists only tools present on the machine and
/// shows a readable hint when none are detected (technical design §5.4, US-0③/US-5).
struct HookInstallSection: View {
    @ObservedObject var coordinator: HookInstallCoordinator
    var detectedOnly: Bool = false
    var localizer: AppLocalizer = AppLocalizer(language: .simplifiedChinese)

    private var visibleRows: [ToolInstallStatus] {
        detectedOnly ? coordinator.rows.filter(\.detected) : coordinator.rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if visibleRows.isEmpty {
                Text(localizer.text(detectedOnly ? .noDetectedToolsOnboarding : .noDetectedToolsSettings))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleRows, id: \.tool) { row in
                    toolRow(row)
                }
            }

            if let error = coordinator.lastError {
                Text(error.message + (error.suggestedAction.map { "\n" + $0 } ?? ""))
                    .font(.caption)
                    .foregroundStyle(BubbleTheme.errorAccent)
            }
        }
    }

    @ViewBuilder
    private func toolRow(_ row: ToolInstallStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.tool.displayName).font(.callout.weight(.semibold))
                    Text(row.status.localizedLabel(localizer)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if row.status == .notInstalled {
                    Button(localizer.text(.install)) { coordinator.install(row.tool) }
                } else {
                    Button(localizer.text(.uninstall)) { coordinator.uninstall(row.tool) }
                    if row.status == .outdated {
                        Button(localizer.text(.update)) { coordinator.install(row.tool) }
                    }
                }
            }
            // Codex `/hooks` trust guidance (and any other status notice).
            if let notice = coordinator.notice(for: row) {
                Text(localizedNotice(notice))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            // Deep diagnostics: surface config drift and offer a one-click repair.
            if let report = coordinator.healthReport(for: row.tool) {
                diagnostics(report, tool: row.tool)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func diagnostics(_ report: HookHealthReport, tool: ToolKind) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(report.errors.enumerated()), id: \.offset) { _, issue in
                Label(issue.localizedLabel(localizer), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(BubbleTheme.errorAccent)
            }
            ForEach(Array(report.notices.enumerated()), id: \.offset) { _, issue in
                Label(issue.localizedLabel(localizer), systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !report.repairableIssues.isEmpty {
                Button(localizer.text(.repair)) { coordinator.repair(tool) }
                    .controlSize(.small)
            }
        }
        .padding(.top, 2)
    }

    private func localizedNotice(_ notice: PresentedError) -> String {
        let text = notice.suggestedAction ?? notice.message
        if text.contains("Codex"), text.contains("/hooks") {
            return localizer.text(.codexTrustGuidance)
        }
        return text
    }
}
