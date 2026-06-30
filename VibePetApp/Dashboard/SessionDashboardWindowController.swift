import AppKit
import SwiftUI
import VibePetCore

@MainActor
final class SessionDashboardWindowController: NSWindowController, NSWindowDelegate {
    static let size = CGSize(width: 520, height: 300)

    private let model: SessionDashboardModel
    private let hostingController: NSHostingController<SessionDashboardView>
    private let cardProvider: (String) -> SessionDashboardCard?
    private let onJump: (JumpTarget) -> Void
    private let onSelectedSessionChanged: (String?, JumpTarget?) -> Void
    private var localizer: AppLocalizer
    private var mouseMonitors: [Any] = []
    var onClose: () -> Void = {}

    init(
        state: SessionState,
        activePetName: String,
        petFrame: CGRect,
        visibleFrame: CGRect,
        cardProvider: @escaping (String) -> SessionDashboardCard?,
        localizer: AppLocalizer = AppLocalizer(language: .simplifiedChinese),
        onJump: @escaping (JumpTarget) -> Void = { _ in },
        onSelectedSessionChanged: @escaping (String?, JumpTarget?) -> Void
    ) {
        model = SessionDashboardModel(state: state, activePetName: activePetName)
        self.cardProvider = cardProvider
        self.onJump = onJump
        self.onSelectedSessionChanged = onSelectedSessionChanged
        self.localizer = localizer
        let view = SessionDashboardView(
            model: model,
            cardProvider: cardProvider,
            onJump: onJump,
            onSelectedSessionChanged: onSelectedSessionChanged,
            localizer: localizer
        )
        hostingController = NSHostingController(rootView: view)

        let placement = BubbleAnchor.place(
            petFrame: petFrame,
            bubbleSize: Self.size,
            in: visibleFrame
        )
        let panel = SessionDashboardPanel(contentRect: placement.frame)
        let effectView = NSVisualEffectView(frame: CGRect(origin: .zero, size: placement.frame.size))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .vibrantDark)
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = BubbleTheme.dashboardCornerRadius
        effectView.layer?.masksToBounds = true

        let hosted = hostingController.view
        hosted.translatesAutoresizingMaskIntoConstraints = false
        hosted.wantsLayer = true
        hosted.layer?.backgroundColor = NSColor.clear.cgColor
        hosted.layer?.cornerRadius = BubbleTheme.dashboardCornerRadius
        hosted.layer?.masksToBounds = true
        effectView.addSubview(hosted)
        NSLayoutConstraint.activate([
            hosted.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosted.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosted.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosted.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        panel.contentView = effectView
        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.orderFront(nil)
        startOutsideClickMonitor()
    }

    func update(state: SessionState, activePetName: String) {
        model.update(state: state, activePetName: activePetName)
    }

    func refreshContent() {
        model.refreshContent()
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        hostingController.rootView = SessionDashboardView(
            model: model,
            cardProvider: cardProvider,
            onJump: onJump,
            onSelectedSessionChanged: onSelectedSessionChanged,
            localizer: localizer
        )
        model.refreshContent()
    }

    func windowWillClose(_ notification: Notification) {
        tearDownOutsideClickMonitor()
        onClose()
    }

    private func startOutsideClickMonitor() {
        tearDownOutsideClickMonitor()
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.closeIfOutsideClick()
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.closeIfOutsideClick()
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func closeIfOutsideClick() {
        guard let window else { return }
        if !window.frame.contains(NSEvent.mouseLocation) {
            window.close()
        }
    }

    private func tearDownOutsideClickMonitor() {
        for monitor in mouseMonitors {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitors.removeAll()
    }
}

private final class SessionDashboardPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = PetWindow.overlayCollectionBehavior
        hasShadow = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
