import SwiftUI
import VibePetCore

struct OnboardingFlow: View {
    @ObservedObject var importViewModel: PetImportViewModel
    @ObservedObject var hooks: HookInstallCoordinator
    var onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var pets: [PetAsset] = []
    @State private var selectedSlug: String?

    private let store = PetAssetStore()
    private let configStore = ConfigStore()

    var body: some View {
        VStack(spacing: 20) {
            switch step {
            case .welcome:
                welcomeView
            case .pet:
                petStep
            case .hooks:
                installHooksStep
            }
        }
        .padding(28)
        .frame(minWidth: 420)
        .onAppear { refreshPets() }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint.fill").font(.system(size: 48))
            Text("欢迎来到 VibePet").font(.title2.bold())
            Text("选择一个 Codex 宠物，它会在你写代码时陪着你，并在需要决策时叫你。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            Button("开始") { step = .pet }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }

    private var petStep: some View {
        VStack(spacing: 14) {
            Text("挑一个宠物").font(.headline)
            if pets.isEmpty {
                emptyPetView
            } else {
                Picker("宠物", selection: Binding(
                    get: { selectedSlug ?? pets.first?.slug ?? "" },
                    set: { selectedSlug = $0 }
                )) {
                    ForEach(pets) { pet in
                        Text(pet.displayName).tag(pet.slug)
                    }
                }
                .pickerStyle(.menu)
            }

            PetImportPanel(viewModel: importViewModel)
                .onChange(of: importViewModel.selectedAsset) { _, asset in refreshPets(preferred: asset?.slug) }

            HStack {
                Button("以后再说") { step = .hooks }
                Button("继续") {
                    persistSelectionIfNeeded()
                    step = .hooks
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var emptyPetView: some View {
        VStack(spacing: 8) {
            Text("还没有可用宠物")
                .font(.subheadline.bold())
            Text("可以用任意方式把宠物装进 ~/.codex/pets/，也可以直接拖入一个 Codex 宠物 zip 或文件夹。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
    }

    private var installHooksStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("准备好了").font(.title3.bold())
            Text("给检测到的工具安装提醒 hooks，宠物就能在审批/完成时叫你。也可以以后再说。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            if hooks.hasRepairableDriftAmongDetected() {
                Label("检测到既有配置异常，点下方「修复」即可一键修正。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(BubbleTheme.errorAccent)
                    .frame(maxWidth: 360)
            }

            HookInstallSection(coordinator: hooks, detectedOnly: true)
                .frame(maxWidth: 360)

            HStack {
                Button("以后再说") { onFinished() }
                Button("完成") { onFinished() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { hooks.refresh() }
    }

    private func refreshPets(preferred: String? = nil) {
        pets = (try? store.list()) ?? []
        selectedSlug = PetSelection.resolve(current: selectedSlug, pets: pets, preferred: preferred)
    }

    private func persistSelectionIfNeeded() {
        guard let selectedSlug else { return }
        do {
            let current = try configStore.read()
            try configStore.write(current.with(activePetID: selectedSlug))
        } catch {
            NSLog("VibePet failed to persist selected pet: \(error)")
        }
    }

    private enum Step {
        case welcome
        case pet
        case hooks
    }
}
