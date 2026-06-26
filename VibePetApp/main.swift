import AppKit
import SwiftUI
import VibePetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = ConfigStore()
    private let assetStore = PetAssetStore()

    private var statusItemController: StatusItemController?
    private var petWindowController: PetWindowController?
    private var onboardingWindow: NSWindow?
    private var importWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var dashboardWindowController: SessionDashboardWindowController?
    private var petVisible = false

    private let petWindowSurface = PetWindowSurface()
    private lazy var petController = PetController(
        surface: petWindowSurface,
        openDashboard: { [weak self] in self?.toggleDashboard() }
    )
    private var bridgeHost: BridgeServerHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        let config = (try? configStore.read()) ?? .default
        if config.hasCompletedOnboarding {
            showPet(config: config, greet: true)
        } else {
            presentOnboarding()
        }

        startBridge()

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridgeHost?.stop()
    }

    // MARK: - Bridge

    /// Starts the notification bridge so hook events surface as pet bubbles via
    /// `PetController`. The controller anchors bubbles to wherever the (visible)
    /// pet currently sits through `PetWindowSurface`; when hidden, the event drops.
    private func startBridge() {
        let host = BridgeServerHost(
            petController: petController,
            onSessionStateChange: { [weak self] state in
                self?.statusItemController?.rebuild()
                self?.dashboardWindowController?.update(
                    state: state,
                    activePetName: self?.currentPetName() ?? "VibePet"
                )
            }
        )
        bridgeHost = host
        host.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let actions = StatusItemController.Actions(
            togglePetVisibility: { [weak self] in self?.togglePetVisibility() },
            switchPet: { [weak self] id in self?.switchPet(to: id) },
            importNewPhoto: { [weak self] in self?.presentImport() },
            openSettings: { [weak self] in self?.presentSettings() },
            quit: { NSApp.terminate(nil) }
        )
        statusItemController = StatusItemController(
            actions: actions,
            petsProvider: { [weak self] in self?.petMenuEntries() ?? [] },
            sessionSummaryProvider: { [weak self] in
                guard let state = self?.bridgeHost?.sessionStateSnapshot else {
                    return SessionMenuSummary(activeCount: 0, attentionCount: 0)
                }
                return SessionMenuSummary.derive(from: state)
            }
        )
    }

    private func petMenuEntries() -> [PetMenuEntry] {
        let activeID = (try? configStore.read())?.activePetID
        let assets = (try? assetStore.list()) ?? []
        return assets.map { asset in
            return PetMenuEntry(
                id: asset.slug,
                title: asset.displayName,
                isActive: asset.slug == activeID
            )
        }
    }

    // MARK: - Pet window

    private func showPet(config: AppConfig, greet: Bool) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let frame = PetFrameResolver.initialFrame(
            config: config,
            visibleFrame: visibleFrame,
            spriteSize: PetWindow.defaultSpriteSize
        )

        let controller = petWindowController ?? PetWindowController(frame: frame, configStore: configStore)
        controller.onOpenDashboard = { [weak self] in self?.petController.openDashboardFromPetClick() }
        controller.onCyclePet = { [weak self] in self?.cyclePet() }
        controller.setFrame(frame, display: true, animate: false)
        controller.showWindow(nil)
        petWindowController = controller
        petVisible = true

        // PetController is the single source of truth for sprite + state; the
        // surface renders into this window.
        petWindowSurface.bind(windowController: controller)
        petWindowSurface.setPetVisible(true)
        petController.setActiveAsset(activeAsset(config: config))
        if greet {
            petController.greet()
        }
    }

    private func refreshPet() {
        let config = (try? configStore.read()) ?? .default
        guard petWindowController != nil else {
            showPet(config: config, greet: false)
            return
        }
        petController.setActiveAsset(activeAsset(config: config))
        statusItemController?.rebuild()
    }

    private func togglePetVisibility() {
        guard let window = petWindowController?.window else {
            refreshPet()
            return
        }
        if petVisible {
            window.orderOut(nil)
        } else {
            window.orderFront(nil)
        }
        petVisible.toggle()
        petWindowSurface.setPetVisible(petVisible)
    }

    private func switchPet(to id: String) {
        update { $0.with(activePetID: id) }
        refreshPet()
    }

    private func cyclePet() {
        let config = (try? configStore.read()) ?? .default
        let assets = (try? assetStore.list()) ?? []
        guard let nextSlug = PetSelection.next(current: config.activePetID, pets: assets) else {
            return
        }
        switchPet(to: nextSlug)
        if let asset = assets.first(where: { $0.slug == nextSlug }) {
            petWindowSurface.showPetSwitchTooltip(name: asset.displayName)
        }
    }

    private func activeAsset(config: AppConfig) -> PetAsset? {
        guard let slug = config.activePetID else {
            return nil
        }
        return (try? assetStore.read(slug: slug)) ?? nil
    }

    private func currentPetName() -> String {
        let config = (try? configStore.read()) ?? .default
        return activeAsset(config: config)?.displayName ?? "VibePet"
    }

    private func toggleDashboard() {
        if let dashboardWindowController, dashboardWindowController.window?.isVisible == true {
            dashboardWindowController.close()
            return
        }
        openDashboard()
    }

    private func openDashboard() {
        guard let petFrame = petWindowSurface.petFrame else {
            return
        }

        let controller = SessionDashboardWindowController(
            state: bridgeHost?.sessionStateSnapshot ?? SessionState(),
            activePetName: currentPetName(),
            petFrame: petFrame,
            visibleFrame: petWindowSurface.visibleFrame,
            cardProvider: { [weak self] sessionID in
                self?.petController.dashboardCard(for: sessionID)
            },
            onJump: { target in
                try? TerminalJumpService().jump(to: target)
            },
            onSelectedSessionChanged: { [weak self] sessionID, jumpTarget in
                self?.petController.dashboardSelectionChanged(sessionID: sessionID, jumpTarget: jumpTarget)
            }
        )
        controller.onClose = { [weak self, weak controller] in
            guard self?.dashboardWindowController === controller else { return }
            self?.dashboardWindowController = nil
            self?.petWindowSurface.dashboardController = nil
            self?.petController.dashboardSelectionChanged(sessionID: nil, jumpTarget: nil)
        }
        dashboardWindowController = controller
        petWindowSurface.dashboardController = controller
        controller.show()
    }

    // MARK: - Onboarding

    private func presentOnboarding() {
        let viewModel = PetImportViewModel()
        let flow = OnboardingFlow(importViewModel: viewModel, hooks: HookInstallCoordinator()) { [weak self] in
            self?.finishOnboarding()
        }
        let window = makeHostingWindow(title: "欢迎使用 VibePet", view: flow)
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding() {
        update { $0.with(hasCompletedOnboarding: true) }
        onboardingWindow?.close()
        onboardingWindow = nil
        let config = (try? configStore.read()) ?? .default
        showPet(config: config, greet: true)
        statusItemController?.rebuild()
    }

    // MARK: - Import

    private func presentImport() {
        let viewModel = PetImportViewModel()
        viewModel.onPlaced = { [weak self] _ in
            self?.importWindow?.close()
            self?.importWindow = nil
            self?.refreshPet()
        }
        let window = makeHostingWindow(title: "导入宠物", view: PetImportPanel(viewModel: viewModel))
        importWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Settings (entry only in M2; full page lands in M6)

    private func presentSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(hooks: HookInstallCoordinator(), configStore: configStore)
        let window = makeHostingWindow(title: "VibePet 设置", view: view)
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Helpers

    private func update(_ transform: (AppConfig) -> AppConfig) {
        do {
            let current = try configStore.read()
            try configStore.write(transform(current))
        } catch {
            NSLog("VibePet failed to update config: \(error)")
        }
    }

    private func makeHostingWindow<V: View>(title: String, view: V) -> NSWindow {
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
