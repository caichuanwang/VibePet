import Foundation

/// A readable error/notice plus an optional suggested next action, decoupled from any
/// UI framework so it can be unit-tested and reused by the import panel, settings
/// page, and bubbles.
public struct PresentedError: Equatable, Sendable {
    public let message: String
    public let suggestedAction: String?

    public init(message: String, suggestedAction: String? = nil) {
        self.message = message
        self.suggestedAction = suggestedAction
    }
}

/// Maps generation, install, and trust conditions to user-facing copy per the
/// technical design §7 error table. Pure: no AppKit/SwiftUI, so it lives in
/// `VibePetCore` and is shared across the App's surfaces.
public enum ErrorPresenter {
    /// Generation failures (e.g. cutout produced no subject).
    public static func present(generationError error: GenError) -> PresentedError {
        switch error {
        case .noSubject:
            return PresentedError(
                message: "没有在照片里找到清晰的主体。",
                suggestedAction: "换一张主体更清楚的照片，或重试。"
            )
        case .encodingFailed:
            return PresentedError(
                message: "生成精灵图失败（图像编码出错）。",
                suggestedAction: "换一张照片重试。"
            )
        case let .writeFailed(reason):
            return PresentedError(
                message: "保存宠物素材失败：\(reason)",
                suggestedAction: "检查磁盘空间后重试。"
            )
        case let .defaultGeneratorUnavailable(reason):
            return PresentedError(
                message: "生成器不可用：\(reason)",
                suggestedAction: nil
            )
        }
    }

    /// A notice for a tool's install status, or nil when nothing needs surfacing.
    public static func present(installStatus status: InstallStatus, tool: ToolKind) -> PresentedError? {
        let name = Self.toolName(tool)
        switch status {
        case .installedNeedsTrust:
            return PresentedError(
                message: "\(name) 的 hooks 已写入，但尚未在 Codex 生效。",
                suggestedAction: "在 Codex 里运行 /hooks 信任该 hook 后即可启用。"
            )
        case .outdated:
            return PresentedError(
                message: "\(name) 的 hook 程序版本落后。",
                suggestedAction: "重新安装以更新到最新版本。"
            )
        case .enabled, .notInstalled:
            return nil
        }
    }

    /// An install/uninstall failure, with a rollback hint (the original config was
    /// backed up before writing).
    public static func presentInstallFailure(_ error: Error, tool: ToolKind) -> PresentedError {
        PresentedError(
            message: "\(Self.toolName(tool)) hooks 安装失败：\(error.localizedDescription)",
            suggestedAction: "原配置已备份，可在 VibePet 支持目录的 backups/ 中找回；修复后可重试。"
        )
    }

    private static func toolName(_ tool: ToolKind) -> String {
        switch tool {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}
