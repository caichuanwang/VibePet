import Foundation
import VibePetCore

// Thin CLI over the installer logic in VibePetCore. Subcommands:
//   VibePetSetup install   [claude|codex|all]
//   VibePetSetup uninstall [claude|codex|all]
//   VibePetSetup status
//
// The hook binary is copied to the stable path (`bin/VibePetHooks`) and every tool
// config `command` points there, never at a path inside the .app bundle (§1.2).

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "status"
let toolArgument = arguments.dropFirst().first

let supportRoot = ProcessInfo.processInfo.environment["VIBEPET_SUPPORT_DIR"].map { URL(fileURLWithPath: $0) }
let stableBinaryPath = InstallPaths.hookBinaryURL(applicationSupportRoot: supportRoot).path

let writersByTool: [ToolKind: any ToolConfigWriter] = [
    .claudeCode: ClaudeCodeConfigWriter(hookBinaryPath: stableBinaryPath),
    .codex: CodexConfigWriter(hookBinaryPath: stableBinaryPath),
]
let installer = HookInstaller(applicationSupportRoot: supportRoot, writers: Array(writersByTool.values))

func out(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

/// The freshly built `VibePetHooks` sits next to this executable (dev build) or in
/// the app bundle; copy from there to the stable path. `HooksBinaryLocator` also
/// covers `Helpers/` and dev `.build` layouts, with the executable-adjacent path as
/// the fallback.
func hookBinarySource() -> URL {
    let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
    return HooksBinaryLocator.locate(executableDirectory: executableDirectory, applicationSupportRoot: supportRoot)
        ?? executableDirectory.appendingPathComponent("VibePetHooks", isDirectory: false)
}

func selectedTools() -> [ToolKind] {
    switch toolArgument {
    case "claude", "claudeCode": return [.claudeCode]
    case "codex": return [.codex]
    default: return [.claudeCode, .codex]
    }
}

switch command {
case "install":
    let source = hookBinarySource()
    // For an unscoped `install` (all), only touch tools that are actually present;
    // an explicit tool name installs regardless.
    let explicit = toolArgument != nil && toolArgument != "all"
    for tool in selectedTools() {
        if !explicit, writersByTool[tool]?.configExists() != true {
            out("\(tool.rawValue): not detected — skipped")
            continue
        }
        do {
            let record = try installer.install(tool: tool, hookBinarySource: source)
            out("\(tool.rawValue): installed (\(record.activationState.rawValue))")
            if tool == .codex, record.activationState == .installedNeedsTrust {
                out("  → trust the hook in Codex via /hooks to activate it")
            }
        } catch {
            out("\(tool.rawValue): install failed — \(error)")
        }
    }

case "uninstall":
    for tool in selectedTools() {
        do {
            try installer.uninstall(tool: tool)
            out("\(tool.rawValue): uninstalled")
        } catch {
            out("\(tool.rawValue): uninstall failed — \(error)")
        }
    }

case "status":
    for tool in [ToolKind.claudeCode, .codex] {
        out("\(tool.rawValue): \(installer.status(tool: tool))")
    }

case "doctor":
    // Deep config-drift diagnosis: moved binary, hand-edited JSON, removed hook,
    // disabled Codex feature flag, orphaned install. Read-only; suggests reinstall.
    for report in installer.healthReports() {
        if report.issues.isEmpty {
            out("\(report.tool.rawValue): OK")
            continue
        }
        out("\(report.tool.rawValue): \(report.isHealthy ? "OK (with notices)" : "PROBLEMS")")
        for issue in report.issues {
            out("  \(issue.severity == .error ? "✗" : "ℹ") \(issue)")
        }
        if !report.repairableIssues.isEmpty {
            out("  → run `VibePetSetup install \(report.tool == .claudeCode ? "claude" : "codex")` to repair")
        }
    }

default:
    out("usage: VibePetSetup <install|uninstall|status|doctor> [claude|codex|all]")
}
