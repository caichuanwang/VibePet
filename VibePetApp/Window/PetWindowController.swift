import AppKit
import SwiftUI
import VibePetCore

final class PetWindowController: NSWindowController {
    private let hitTestView: PetHitTestHostingView
    private let dragController: PetDragController

    /// Opaque-pixel mask of the current sprite, used both to maintain mouse
    /// passthrough and to reject clicks on transparent pixels.
    private var hitMask: SpriteHitMask?
    private var hitMasksByFrame: [ObjectIdentifier: SpriteHitMask] = [:]
    private var mouseMonitors: [Any] = []

    init(frame: CGRect, configStore: ConfigStore) {
        let window = PetWindow(frame: frame)
        let dragController = PetDragController(window: window, configStore: configStore)
        self.dragController = dragController
        self.hitTestView = PetHitTestHostingView(rootView: EmptyView(), dragController: dragController)
        super.init(window: window)
        hitTestView.frame = NSRect(origin: .zero, size: frame.size)
        hitTestView.autoresizingMask = [.width, .height]
        window.contentView = hitTestView
        startMousePassthroughTracking()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent<Content: View>(_ content: Content) {
        hitTestView.rootView = AnyView(content)
    }

    /// Sets the sprite whose opaque pixels define the clickable pet body; pass
    /// nil only when the whole frame should be interactive.
    func setHitSprite(_ cgImage: CGImage?) {
        let mask = cgImage.flatMap { image in
            let key = ObjectIdentifier(image)
            if let cached = hitMasksByFrame[key] {
                return cached
            }
            guard let created = SpriteHitMask(cgImage: image, sampleStep: 4) else {
                return nil
            }
            hitMasksByFrame[key] = created
            return created
        }
        hitMask = mask
        hitTestView.hitMask = mask
        updateMousePassthrough()
    }

    func setFrame(_ frame: CGRect, display: Bool, animate: Bool) {
        window?.setFrame(frame, display: display, animate: animate)
    }

    // MARK: - Mouse passthrough

    /// Drives `ignoresMouseEvents` from the cursor position so transparent
    /// pixels click through to the app beneath (technical design §5.1).
    ///
    /// This must be done OUTSIDE `hitTest`: once `ignoresMouseEvents` becomes
    /// true the window stops receiving any mouse events — including the hit-test
    /// that would flip it back — so a hitTest-driven toggle deadlocks the pet
    /// into permanent passthrough. A global monitor keeps firing even while the
    /// window ignores events, so it can always recover; the local monitor covers
    /// the cursor-over-body case.
    private func startMousePassthroughTracking() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.updateMousePassthrough()
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.updateMousePassthrough()
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func updateMousePassthrough() {
        guard let window else { return }
        guard let hitMask else {
            window.ignoresMouseEvents = false
            return
        }
        let mouse = NSEvent.mouseLocation
        let frame = window.frame
        guard frame.contains(mouse) else {
            // Cursor isn't over the pet window; keep it interactive so the next
            // click that lands on the body is delivered.
            window.ignoresMouseEvents = false
            return
        }
        let local = CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
        let overBody = hitMask.isOpaque(at: local, in: CGRect(origin: .zero, size: frame.size))
        window.ignoresMouseEvents = !overBody
    }
}

private final class PetHitTestHostingView: NSHostingView<AnyView> {
    var hitMask: SpriteHitMask?
    private let dragController: PetDragController

    init(rootView: some View, dragController: PetDragController) {
        self.dragController = dragController
        super.init(rootView: AnyView(rootView))
    }

    @available(*, unavailable)
    required init(rootView: AnyView) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Reject clicks on transparent pixels (no side effects here — passthrough
        // is driven by the controller's mouse monitors). With no mask the whole
        // frame is interactive (e.g. the onboarding placeholder).
        if let hitMask, !hitMask.isOpaque(at: point, in: bounds) {
            return nil
        }
        return super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {
        dragController.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        dragController.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        dragController.mouseUp(with: event)
    }
}
