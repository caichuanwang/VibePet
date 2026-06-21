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
    private var petVisible = false

    private let petWindowSurface = PetWindowSurface()
    private lazy var petController = PetController(
        surface: petWindowSurface,
        decisionTimeout: ((try? configStore.read()) ?? .default).decisionTimeoutSeconds
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
        let host = BridgeServerHost(petController: petController)
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
        statusItemController = StatusItemController(actions: actions) { [weak self] in
            self?.petMenuEntries() ?? []
        }
    }

    private func petMenuEntries() -> [PetMenuEntry] {
        let activeID = (try? configStore.read())?.activePetID
        let assets = (try? assetStore.list()) ?? []
        return assets.map { asset in
            let name = asset.metadata["name"].flatMap { $0.isEmpty ? nil : $0 }
            return PetMenuEntry(
                id: asset.id.uuidString,
                title: name ?? String(asset.id.uuidString.prefix(8)),
                isActive: asset.id.uuidString == activeID
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

    private func activeAsset(config: AppConfig) -> PetAsset? {
        guard let idString = config.activePetID, let id = UUID(uuidString: idString) else {
            return nil
        }
        return (try? assetStore.read(id: id)) ?? nil
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
        let window = makeHostingWindow(title: "导入新照片", view: PetImportPanel(viewModel: viewModel))
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
