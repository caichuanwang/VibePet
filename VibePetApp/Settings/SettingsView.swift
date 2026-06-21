import ServiceManagement
import SwiftUI
import VibePetCore

/// The settings page (technical design §5.4): enable tools, install/uninstall hooks
/// (with per-tool status), decision timeout, launch-at-login, and generator selection
/// (MVP: local only). Preferences persist via `ConfigStore`.
struct SettingsView: View {
    @ObservedObject var hooks: HookInstallCoordinator
    let configStore: ConfigStore

    @State private var enabledClaude: Bool
    @State private var enabledCodex: Bool
    @State private var decisionTimeout: Double
    @State private var launchAtLogin: Bool

    init(hooks: HookInstallCoordinator, configStore: ConfigStore) {
        self.hooks = hooks
        self.configStore = configStore
        let config = (try? configStore.read()) ?? .default
        _enabledClaude = State(initialValue: config.enabledTools.contains(.claudeCode))
        _enabledCodex = State(initialValue: config.enabledTools.contains(.codex))
        _decisionTimeout = State(initialValue: config.decisionTimeoutSeconds)
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
    }

    var body: some View {
        Form {
            Section("启用工具") {
                Toggle("Claude Code", isOn: $enabledClaude).onChange(of: enabledClaude) { _, _ in persistTools() }
                Toggle("Codex", isOn: $enabledCodex).onChange(of: enabledCodex) { _, _ in persistTools() }
            }

            Section("提醒 Hooks") {
                HookInstallSection(coordinator: hooks)
            }

            Section("行为") {
                VStack(alignment: .leading) {
                    Text("决策超时：\(Int(decisionTimeout)) 秒")
                    Slider(value: $decisionTimeout, in: 5...60, step: 1) { editing in
                        if !editing { persistTimeout() }
                    }
                }
                Toggle("开机自启", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
            }

            Section("生成器") {
                Picker("生成器", selection: .constant("local-cutout")) {
                    Text("本地抠图（Vision）").tag("local-cutout")
                }
                .disabled(true) // MVP: local only
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 520)
        .onAppear { hooks.refresh() }
    }

    // MARK: - Persistence

    private func persistTools() {
        var tools: [ToolKind] = []
        if enabledClaude { tools.append(.claudeCode) }
        if enabledCodex { tools.append(.codex) }
        update { $0.with(enabledTools: tools) }
    }

    private func persistTimeout() {
        update { $0.with(decisionTimeoutSeconds: decisionTimeout) }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("VibePet failed to set launch-at-login: \(error)")
            // Reflect the real OS state if the change didn't take.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func update(_ transform: (AppConfig) -> AppConfig) {
        do {
            let current = (try? configStore.read()) ?? .default
            try configStore.write(transform(current))
        } catch {
            NSLog("VibePet failed to persist settings: \(error)")
        }
    }
}
