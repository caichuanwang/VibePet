import SwiftUI
import VibePetCore

/// First-launch onboarding: ① welcome → ② generate pet (reusing `PetImportPanel`)
/// → ③ install hooks (only the detected tools, skippable). Wired up in M6
/// (technical design §5.4, PRD US-0①②③).
struct OnboardingFlow: View {
    @ObservedObject var importViewModel: PetImportViewModel
    @ObservedObject var hooks: HookInstallCoordinator
    /// Called when the user finishes onboarding (after the pet is placed and the
    /// step-③ hooks step is dismissed/skipped).
    var onFinished: () -> Void

    @State private var started = false

    var body: some View {
        VStack(spacing: 20) {
            if !started {
                welcomeView
            } else if importViewModel.phase == .placed {
                installHooksStep
            } else {
                generateView
            }
        }
        .padding(28)
        .frame(minWidth: 420)
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Text("🐾").font(.system(size: 56))
            Text("欢迎来到 VibePet").font(.title2.bold())
            Text("把一张照片变成桌面宠物，它会在你写代码时陪着你，并在需要决策时叫你。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            Button("开始") { started = true }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }

    private var generateView: some View {
        VStack(spacing: 10) {
            Text("生成你的宠物").font(.headline)
            Text("导入一张照片，VibePet 会自动抠出主体。")
                .font(.caption)
                .foregroundStyle(.secondary)
            PetImportPanel(viewModel: importViewModel)
        }
    }

    private var installHooksStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("宠物准备好了！").font(.title3.bold())
            Text("给检测到的工具安装提醒 hooks，宠物就能在审批/完成时叫你。也可以以后再说。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            // Only when a detected tool has a pre-existing, repairable broken install.
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
        // Refresh on arrival: the coordinator was built at launch, but the user only
        // reaches this step after generating a pet, so detection/health may be stale.
        .onAppear { hooks.refresh() }
    }
}
