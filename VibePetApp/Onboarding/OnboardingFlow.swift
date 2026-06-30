import SwiftUI
import VibePetCore

struct OnboardingFlow: View {
    @ObservedObject var importViewModel: PetImportViewModel
    @ObservedObject var hooks: HookInstallCoordinator
    var localizer: AppLocalizer = AppLocalizer(language: .simplifiedChinese)
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
            Text(localizer.text(.onboardingWelcomeTitle)).font(.title2.bold())
            Text(localizer.text(.onboardingWelcomeBody))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            Button(localizer.text(.onboardingStart)) { step = .pet }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }

    private var petStep: some View {
        VStack(spacing: 14) {
            Text(localizer.text(.onboardingChoosePetTitle)).font(.headline)
            if pets.isEmpty {
                emptyPetView
            } else {
                Picker(localizer.text(.onboardingPetPicker), selection: Binding(
                    get: { selectedSlug ?? pets.first?.slug ?? "" },
                    set: { selectedSlug = $0 }
                )) {
                    ForEach(pets) { pet in
                        Text(pet.displayName).tag(pet.slug)
                    }
                }
                .pickerStyle(.menu)
            }

            PetImportPanel(viewModel: importViewModel, localizer: localizer)
                .onChange(of: importViewModel.selectedAsset) { _, asset in refreshPets(preferred: asset?.slug) }

            HStack {
                Button(localizer.text(.later)) { step = .hooks }
                Button(localizer.text(.continueButton)) {
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
            Text(localizer.text(.onboardingNoPetsTitle))
                .font(.subheadline.bold())
            Text(localizer.text(.onboardingNoPetsBody))
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
            Text(localizer.text(.onboardingReadyTitle)).font(.title3.bold())
            Text(localizer.text(.onboardingReadyBody))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            if hooks.hasRepairableDriftAmongDetected() {
                Label(localizer.text(.repairableDriftHint), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(BubbleTheme.errorAccent)
                    .frame(maxWidth: 360)
            }

            HookInstallSection(coordinator: hooks, detectedOnly: true, localizer: localizer)
                .frame(maxWidth: 360)

            HStack {
                Button(localizer.text(.later)) { onFinished() }
                Button(localizer.text(.finish)) { onFinished() }
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
