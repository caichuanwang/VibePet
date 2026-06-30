import Foundation
import VibePetCore

struct AppLocalizer: Equatable {
    enum Key: CaseIterable, Hashable {
        case settingsWindowTitle
        case onboardingWindowTitle
        case importWindowTitle
        case toolsSection
        case hooksSection
        case behaviorSection
        case languageSection
        case languagePicker
        case launchAtLogin
        case petSection
        case noPetsSettingsHint
        case switchPet
        case importPet
        case install
        case uninstall
        case update
        case repair
        case noDetectedToolsOnboarding
        case noDetectedToolsSettings
        case repairableDriftHint
        case codexTrustGuidance
        case statusNotInstalled
        case statusInstalledNeedsTrust
        case statusEnabled
        case statusOutdated
        case hookProgramMissing
        case hookProgramNotExecutable
        case hookConfigJSONBroken
        case hookConfiguredPathInvalid
        case hookEntryMissing
        case hookManifestMissing
        case codexHooksFeatureDisabled
        case hookCoexistenceDetected
        case menuShowHidePet
        case menuImportPet
        case menuOpenSettings
        case menuQuit
        case menuSwitchPet
        case menuNoPets
        case sessionMenuSummary
        case onboardingWelcomeTitle
        case onboardingWelcomeBody
        case onboardingStart
        case onboardingChoosePetTitle
        case onboardingPetPicker
        case later
        case continueButton
        case onboardingNoPetsTitle
        case onboardingNoPetsBody
        case onboardingReadyTitle
        case onboardingReadyBody
        case finish
        case petPlaceholderChoosePet
        case importInProgress
        case importTitle
        case importDescription
        case choosePetFile
        case importSetCurrentPet
        case importAnother
        case importFailureTitle
        case chooseAnotherFile
        case dashboardSessionsTitle
        case dashboardSummary
        case dashboardNoRunningSessions
        case dashboardNoActiveSessions
        case dashboardUserPrefix
        case sessionWaitingForOutput
        case sessionWaitingForApproval
        case sessionWaitingForAnswer
        case sessionEndedWithError
        case sessionCompleted
        case riskHigh
        case riskMedium
        case riskLow
        case bubbleRunning
        case bubbleError
        case bubbleCompleted
        case approvalPending
        case backToTerminal
        case approvalTerminalRequired
        case handleInTerminal
        case pendingCount
        case questionSingleTitle
        case questionMultiTitle
        case questionUserSpeaker
        case questionIndex
        case questionIndexAccessibility
        case previousQuestion
        case nextQuestion
        case lastQuestion
        case multiSelect
        case singleSelect
        case customAnswerLabel
        case customAnswerPlaceholder
        case deferAnswer
        case deferAnswerHint
        case submitAnswersHint
        case answerCurrentQuestionHint
        case submitAllAnswers
        case submitAnswer
        case allAnsweredCanSubmit
        case remainingQuestions
        case answerRequired
        case notificationsAccessibility
        case handledInTerminal
        case sessionStarted
    }

    let language: AppLanguage

    init(language: AppLanguage) {
        self.language = language
    }

    func text(_ key: Key) -> String {
        Self.translations[key]?[language] ?? ""
    }

    func text(_ key: Key, _ values: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language.localeIdentifier), arguments: values)
    }

    func languageDisplayName(_ language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            "简体中文"
        case .english:
            "English"
        }
    }

    static func missingTranslations() -> [(Key, AppLanguage)] {
        Key.allCases.flatMap { key in
            AppLanguage.allCases.compactMap { language in
                let value = translations[key]?[language]
                return value?.isEmpty == false ? nil : (key, language)
            }
        }
    }

    private static let translations: [Key: [AppLanguage: String]] = [
        .settingsWindowTitle: [.simplifiedChinese: "VibePet 设置", .english: "VibePet Settings"],
        .onboardingWindowTitle: [.simplifiedChinese: "欢迎使用 VibePet", .english: "Welcome to VibePet"],
        .importWindowTitle: [.simplifiedChinese: "导入宠物", .english: "Import Pet"],
        .toolsSection: [.simplifiedChinese: "启用工具", .english: "Enabled Tools"],
        .hooksSection: [.simplifiedChinese: "提醒 Hooks", .english: "Notification Hooks"],
        .behaviorSection: [.simplifiedChinese: "行为", .english: "Behavior"],
        .languageSection: [.simplifiedChinese: "语言", .english: "Language"],
        .languagePicker: [.simplifiedChinese: "界面语言", .english: "Interface Language"],
        .launchAtLogin: [.simplifiedChinese: "开机自启", .english: "Launch at Login"],
        .petSection: [.simplifiedChinese: "宠物", .english: "Pet"],
        .noPetsSettingsHint: [.simplifiedChinese: "还没有可用宠物。可把宠物装进 ~/.codex/pets/，或在下方导入。", .english: "No pets are available yet. Add pets to ~/.codex/pets/ or import one below."],
        .switchPet: [.simplifiedChinese: "切换宠物", .english: "Switch Pet"],
        .importPet: [.simplifiedChinese: "导入宠物…", .english: "Import Pet..."],
        .install: [.simplifiedChinese: "安装", .english: "Install"],
        .uninstall: [.simplifiedChinese: "卸载", .english: "Uninstall"],
        .update: [.simplifiedChinese: "更新", .english: "Update"],
        .repair: [.simplifiedChinese: "修复", .english: "Repair"],
        .noDetectedToolsOnboarding: [.simplifiedChinese: "未检测到 Claude Code 或 Codex —— 之后可在设置里安装提醒 hooks。", .english: "Claude Code or Codex was not detected. You can install notification hooks later in settings."],
        .noDetectedToolsSettings: [.simplifiedChinese: "未检测到支持的工具（Claude Code / Codex）。", .english: "No supported tools detected (Claude Code / Codex)."],
        .repairableDriftHint: [.simplifiedChinese: "检测到既有配置异常，点下方「修复」即可一键修正。", .english: "Existing configuration needs repair. Use Repair below to fix it."],
        .codexTrustGuidance: [.simplifiedChinese: "已写入 Codex hooks；请在 Codex /hooks 中确认信任。", .english: "Codex hooks are written. Confirm trust in Codex /hooks."],
        .statusNotInstalled: [.simplifiedChinese: "未安装", .english: "Not installed"],
        .statusInstalledNeedsTrust: [.simplifiedChinese: "已写入，待信任", .english: "Written, trust pending"],
        .statusEnabled: [.simplifiedChinese: "已启用", .english: "Enabled"],
        .statusOutdated: [.simplifiedChinese: "版本落后", .english: "Outdated"],
        .hookProgramMissing: [.simplifiedChinese: "Hook 程序缺失", .english: "Hook program missing"],
        .hookProgramNotExecutable: [.simplifiedChinese: "Hook 程序无法执行", .english: "Hook program is not executable"],
        .hookConfigJSONBroken: [.simplifiedChinese: "配置文件 JSON 损坏（需手动修复）", .english: "Configuration JSON is invalid and needs manual repair"],
        .hookConfiguredPathInvalid: [.simplifiedChinese: "配置指向的程序路径已失效", .english: "Configured hook program path is invalid"],
        .hookEntryMissing: [.simplifiedChinese: "配置中缺少 VibePet 的 hook 条目", .english: "Configuration is missing VibePet hook entries"],
        .hookManifestMissing: [.simplifiedChinese: "配置残留 VibePet hook，但安装记录已丢失", .english: "VibePet hooks remain, but the install manifest is missing"],
        .codexHooksFeatureDisabled: [.simplifiedChinese: "Codex [features] hooks 开关被关闭", .english: "Codex [features] hooks is disabled"],
        .hookCoexistenceDetected: [.simplifiedChinese: "检测到其它 hook 共存：%@", .english: "Other hooks detected: %@"],
        .menuShowHidePet: [.simplifiedChinese: "显示 / 隐藏宠物", .english: "Show / Hide Pet"],
        .menuImportPet: [.simplifiedChinese: "导入宠物…", .english: "Import Pet..."],
        .menuOpenSettings: [.simplifiedChinese: "打开设置…", .english: "Open Settings..."],
        .menuQuit: [.simplifiedChinese: "退出 VibePet", .english: "Quit VibePet"],
        .menuSwitchPet: [.simplifiedChinese: "切换宠物", .english: "Switch Pet"],
        .menuNoPets: [.simplifiedChinese: "（还没有可用宠物）", .english: "(No pets available)"],
        .sessionMenuSummary: [.simplifiedChinese: "会话：%d 个活跃，%d 个待处理", .english: "Sessions: %d active, %d need attention"],
        .onboardingWelcomeTitle: [.simplifiedChinese: "欢迎来到 VibePet", .english: "Welcome to VibePet"],
        .onboardingWelcomeBody: [.simplifiedChinese: "选择一个 Codex 宠物，它会在你写代码时陪着你，并在需要决策时叫你。", .english: "Choose a Codex pet to keep you company while you code and alert you when decisions need attention."],
        .onboardingStart: [.simplifiedChinese: "开始", .english: "Start"],
        .onboardingChoosePetTitle: [.simplifiedChinese: "挑一个宠物", .english: "Choose a Pet"],
        .onboardingPetPicker: [.simplifiedChinese: "宠物", .english: "Pet"],
        .later: [.simplifiedChinese: "以后再说", .english: "Later"],
        .continueButton: [.simplifiedChinese: "继续", .english: "Continue"],
        .onboardingNoPetsTitle: [.simplifiedChinese: "还没有可用宠物", .english: "No Pets Available"],
        .onboardingNoPetsBody: [.simplifiedChinese: "可以用任意方式把宠物装进 ~/.codex/pets/，也可以直接拖入一个 Codex 宠物 zip 或文件夹。", .english: "Add pets to ~/.codex/pets/ or drag in a Codex pet zip or folder."],
        .onboardingReadyTitle: [.simplifiedChinese: "准备好了", .english: "Ready"],
        .onboardingReadyBody: [.simplifiedChinese: "给检测到的工具安装提醒 hooks，宠物就能在审批/完成时叫你。也可以以后再说。", .english: "Install notification hooks for detected tools so your pet can alert you for approvals and completions. You can also do this later."],
        .finish: [.simplifiedChinese: "完成", .english: "Finish"],
        .petPlaceholderChoosePet: [.simplifiedChinese: "选择宠物", .english: "Choose Pet"],
        .importInProgress: [.simplifiedChinese: "正在导入宠物…", .english: "Importing pet..."],
        .importTitle: [.simplifiedChinese: "导入 Codex 宠物", .english: "Import Codex Pet"],
        .importDescription: [.simplifiedChinese: "拖入包含 pet.json 和 spritesheet 的 zip 或文件夹。", .english: "Drop a zip or folder that contains pet.json and a spritesheet."],
        .choosePetFile: [.simplifiedChinese: "选择宠物…", .english: "Choose Pet..."],
        .importSetCurrentPet: [.simplifiedChinese: "已设为当前宠物。", .english: "Set as the current pet."],
        .importAnother: [.simplifiedChinese: "再导入一个", .english: "Import Another"],
        .importFailureTitle: [.simplifiedChinese: "无法导入", .english: "Import Failed"],
        .chooseAnotherFile: [.simplifiedChinese: "换一个文件…", .english: "Choose Another File..."],
        .dashboardSessionsTitle: [.simplifiedChinese: "会话", .english: "Sessions"],
        .dashboardSummary: [.simplifiedChinese: "%d 个总计 · %d 个运行中 · %d 个待处理", .english: "%d total · %d running · %d action"],
        .dashboardNoRunningSessions: [.simplifiedChinese: "没有运行中的会话", .english: "no running sessions"],
        .dashboardNoActiveSessions: [.simplifiedChinese: "没有活跃的 Agent 会话", .english: "No active agent sessions"],
        .dashboardUserPrefix: [.simplifiedChinese: "你：", .english: "You:"],
        .sessionWaitingForOutput: [.simplifiedChinese: "等待 Agent 输出…", .english: "Waiting for agent output..."],
        .sessionWaitingForApproval: [.simplifiedChinese: "等待审批…", .english: "Waiting for approval..."],
        .sessionWaitingForAnswer: [.simplifiedChinese: "等待你的回答…", .english: "Waiting for your answer..."],
        .sessionEndedWithError: [.simplifiedChinese: "会话已结束，但出现错误。", .english: "Session ended with an error."],
        .sessionCompleted: [.simplifiedChinese: "会话已完成。", .english: "Session completed."],
        .riskHigh: [.simplifiedChinese: "高风险", .english: "High risk"],
        .riskMedium: [.simplifiedChinese: "中风险", .english: "Medium risk"],
        .riskLow: [.simplifiedChinese: "低风险", .english: "Low risk"],
        .bubbleRunning: [.simplifiedChinese: "运行中", .english: "Running"],
        .bubbleError: [.simplifiedChinese: "错误", .english: "Error"],
        .bubbleCompleted: [.simplifiedChinese: "完成", .english: "Completed"],
        .approvalPending: [.simplifiedChinese: "待审批", .english: "Approval"],
        .backToTerminal: [.simplifiedChinese: "回终端", .english: "Back to Terminal"],
        .approvalTerminalRequired: [.simplifiedChinese: "此请求需在终端继续处理", .english: "This request must be handled in the terminal"],
        .handleInTerminal: [.simplifiedChinese: "回终端处理", .english: "Handle in Terminal"],
        .pendingCount: [.simplifiedChinese: "还有 %d 个待处理", .english: "%d more pending"],
        .questionSingleTitle: [.simplifiedChinese: "Question", .english: "Question"],
        .questionMultiTitle: [.simplifiedChinese: "Questions · %d", .english: "Questions · %d"],
        .questionUserSpeaker: [.simplifiedChinese: "用户", .english: "User"],
        .questionIndex: [.simplifiedChinese: "问题 %d / %d", .english: "Question %d / %d"],
        .questionIndexAccessibility: [.simplifiedChinese: "问题 %d，共 %d 题", .english: "Question %d of %d"],
        .previousQuestion: [.simplifiedChinese: "上一题", .english: "Previous Question"],
        .nextQuestion: [.simplifiedChinese: "下一题", .english: "Next Question"],
        .lastQuestion: [.simplifiedChinese: "最后一题", .english: "Last Question"],
        .multiSelect: [.simplifiedChinese: "多选", .english: "Multiple choice"],
        .singleSelect: [.simplifiedChinese: "单选", .english: "Single choice"],
        .customAnswerLabel: [.simplifiedChinese: "我的回答", .english: "My Answer"],
        .customAnswerPlaceholder: [.simplifiedChinese: "填写你的回答…", .english: "Write your answer..."],
        .deferAnswer: [.simplifiedChinese: "稍后", .english: "Later"],
        .deferAnswerHint: [.simplifiedChinese: "交还终端原生流程", .english: "Return to the terminal's native flow"],
        .submitAnswersHint: [.simplifiedChinese: "提交所有问题的答案", .english: "Submit answers to all questions"],
        .answerCurrentQuestionHint: [.simplifiedChinese: "请先回答当前问题", .english: "Answer the current question first"],
        .submitAllAnswers: [.simplifiedChinese: "提交全部回答", .english: "Submit All Answers"],
        .submitAnswer: [.simplifiedChinese: "提交回答", .english: "Submit Answer"],
        .allAnsweredCanSubmit: [.simplifiedChinese: "全部已回答，可提交", .english: "All answered, ready to submit"],
        .remainingQuestions: [.simplifiedChinese: "%d 个问题待回答", .english: "%d questions remaining"],
        .answerRequired: [.simplifiedChinese: "需要回答后继续", .english: "Answer required to continue"],
        .notificationsAccessibility: [.simplifiedChinese: "%d 条待查看通知", .english: "%d notifications to review"],
        .handledInTerminal: [.simplifiedChinese: "已在终端处理", .english: "Handled in terminal"],
        .sessionStarted: [.simplifiedChinese: "会话已开始", .english: "Session started"]
    ]
}

private extension AppLanguage {
    var localeIdentifier: String {
        switch self {
        case .simplifiedChinese:
            "zh-Hans"
        case .english:
            "en"
        }
    }
}
