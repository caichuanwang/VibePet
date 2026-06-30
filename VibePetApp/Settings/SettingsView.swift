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
    @State private var selectedLanguage: AppLanguage
    @State private var pets: [PetAsset] = []
    @State private var selectedPetSlug: String
    @StateObject private var importViewModel = PetImportViewModel()
    private let assetStore = PetAssetStore()

    private var localizer: AppLocalizer { AppLocalizer(language: selectedLanguage) }

    init(hooks: HookInstallCoordinator, configStore: ConfigStore) {
        self.hooks = hooks
        self.configStore = configStore
        let config = (try? configStore.read()) ?? .default
        _enabledClaude = State(initialValue: config.enabledTools.contains(.claudeCode))
        _enabledCodex = State(initialValue: config.enabledTools.contains(.codex))
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
        _selectedLanguage = State(initialValue: SettingsLanguageModel(config: config).selectedLanguage)
        _selectedPetSlug = State(initialValue: config.activePetID ?? "")
    }

    var body: some View {
        Form {
            Section(localizer.text(.toolsSection)) {
                Toggle("Claude Code", isOn: $enabledClaude).onChange(of: enabledClaude) { _, _ in persistTools() }
                Toggle("Codex", isOn: $enabledCodex).onChange(of: enabledCodex) { _, _ in persistTools() }
            }

            Section(localizer.text(.hooksSection)) {
                HookInstallSection(coordinator: hooks, localizer: localizer)
            }

            Section(localizer.text(.behaviorSection)) {
                Toggle(localizer.text(.launchAtLogin), isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
            }

            Section(localizer.text(.languageSection)) {
                Picker(localizer.text(.languagePicker), selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(localizer.languageDisplayName(language)).tag(language)
                    }
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    update { SettingsLanguageModel(config: $0).configAfterSelecting(newValue, from: $0) }
                }
            }

            Section(localizer.text(.petSection)) {
                if pets.isEmpty {
                    Text(localizer.text(.noPetsSettingsHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(localizer.text(.switchPet), selection: $selectedPetSlug) {
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
                Button(localizer.text(.importPet)) {
                    importViewModel.choosePackage()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 560)
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
