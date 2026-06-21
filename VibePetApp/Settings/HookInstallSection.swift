import SwiftUI
import VibePetCore

/// Reusable hooks install/uninstall list, shown in the settings page and onboarding
/// step ③. `detectedOnly` (onboarding) lists only tools present on the machine and
/// shows a readable hint when none are detected (technical design §5.4, US-0③/US-5).
struct HookInstallSection: View {
    @ObservedObject var coordinator: HookInstallCoordinator
    var detectedOnly: Bool = false

    private var visibleRows: [ToolInstallStatus] {
        detectedOnly ? coordinator.rows.filter(\.detected) : coordinator.rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if visibleRows.isEmpty {
                Text(detectedOnly
                    ? "未检测到 Claude Code 或 Codex —— 之后可在设置里安装提醒 hooks。"
                    : "未检测到支持的工具（Claude Code / Codex）。")
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
                    Text(row.status.label).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if row.status == .notInstalled {
                    Button("安装") { coordinator.install(row.tool) }
                } else {
                    Button("卸载") { coordinator.uninstall(row.tool) }
                    if row.status == .outdated {
                        Button("更新") { coordinator.install(row.tool) }
                    }
                }
            }
            // Codex `/hooks` trust guidance (and any other status notice).
            if let notice = coordinator.notice(for: row) {
                Text(notice.suggestedAction ?? notice.message)
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
                Label(issue.zhLabel, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(BubbleTheme.errorAccent)
            }
            ForEach(Array(report.notices.enumerated()), id: \.offset) { _, issue in
                Label(issue.zhLabel, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !report.repairableIssues.isEmpty {
                Button("修复") { coordinator.repair(tool) }
                    .controlSize(.small)
            }
        }
        .padding(.top, 2)
    }
}
