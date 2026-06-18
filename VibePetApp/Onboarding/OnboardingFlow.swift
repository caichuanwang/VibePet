import SwiftUI
import VibePetCore

/// First-launch onboarding: ① welcome → ② generate pet (reusing `PetImportPanel`).
/// Step ③ (install hooks) is only a placeholder in M2 and is wired up in M6
/// (technical design §5.4, PRD US-0①②).
struct OnboardingFlow: View {
    @ObservedObject var importViewModel: PetImportViewModel
    /// Called when the user finishes onboarding (after the pet is placed and the
    /// step-③ placeholder is dismissed).
    var onFinished: () -> Void

    @State private var started = false

    var body: some View {
        VStack(spacing: 20) {
            if !started {
                welcomeView
            } else if importViewModel.phase == .placed {
                installHooksPlaceholder
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

    private var installHooksPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("宠物准备好了！").font(.title3.bold())
            Text("下一步可以安装 Claude Code / Codex 的提醒 hooks —— 这一步将在后续版本接入，现在可以先跳过。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            Button("完成") { onFinished() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }
}
