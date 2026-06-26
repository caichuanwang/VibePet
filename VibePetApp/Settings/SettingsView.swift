import ServiceManagement
import SwiftUI
import VibePetCore

/// The settings page: enable tools, install/uninstall hooks, tune behavior,
/// and choose or import the active Codex pet. Preferences persist via `ConfigStore`.
struct SettingsView: View {
    @ObservedObject var hooks: HookInstallCoordinator
    let configStore: ConfigStore

    @State private var enabledClaude: Bool
    @State private var enabledCodex: Bool
    @State private var launchAtLogin: Bool
    @State private var pets: [PetAsset] = []
    @State private var selectedPetSlug: String
    @StateObject private var importViewModel = PetImportViewModel()
    private let assetStore = PetAssetStore()

    init(hooks: HookInstallCoordinator, configStore: ConfigStore) {
        self.hooks = hooks
        self.configStore = configStore
        let config = (try? configStore.read()) ?? .default
        _enabledClaude = State(initialValue: config.enabledTools.contains(.claudeCode))
        _enabledCodex = State(initialValue: config.enabledTools.contains(.codex))
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
        _selectedPetSlug = State(initialValue: config.activePetID ?? "")
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
                Toggle("开机自启", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
            }

            Section("宠物") {
                if pets.isEmpty {
                    Text("还没有可用宠物。可把宠物装进 ~/.codex/pets/，或在下方导入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("切换宠物", selection: $selectedPetSlug) {
                        ForEach(pets) { pet in
                            Text(pet.displayName).tag(pet.slug)
                        }
                    }
                    .onChange(of: selectedPetSlug) { _, newValue in
                        if newValue.isEmpty {
                            update { $0.with(activePetID: .some(nil)) }
                        } else {
                            update { $0.with(activePetID: newValue) }
                        }
                    }
                }
                Button("导入宠物…") {
                    importViewModel.choosePackage()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 520)
        .onAppear {
            hooks.refresh()
            refreshPets()
        }
        .onChange(of: importViewModel.selectedAsset) { _, asset in refreshPets(preferred: asset?.slug) }
    }

    // MARK: - Persistence

    private func persistTools() {
        var tools: [ToolKind] = []
        if enabledClaude { tools.append(.claudeCode) }
        if enabledCodex { tools.append(.codex) }
        update { $0.with(enabledTools: tools) }
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
            let current = try configStore.read()
            try configStore.write(transform(current))
        } catch {
            NSLog("VibePet failed to persist settings: \(error)")
        }
    }

    private func refreshPets(preferred: String? = nil) {
        pets = (try? assetStore.list()) ?? []
        selectedPetSlug = PetSelection.resolve(current: selectedPetSlug, pets: pets, preferred: preferred) ?? ""
    }
}

enum PetSelection {
    static func resolve(current: String?, pets: [PetAsset], preferred: String?) -> String? {
        let slugs = Set(pets.map(\.slug))
        if let preferred, slugs.contains(preferred) {
            return preferred
        }
        if let current, !current.isEmpty, slugs.contains(current) {
            return current
        }
        return pets.first?.slug
    }

    static func next(current: String?, pets: [PetAsset]) -> String? {
        guard pets.count >= 2 else {
            return nil
        }
        guard let current, let index = pets.firstIndex(where: { $0.slug == current }) else {
            return pets.first?.slug
        }
        let nextIndex = pets.index(after: index)
        return pets[nextIndex == pets.endIndex ? pets.startIndex : nextIndex].slug
    }
}
