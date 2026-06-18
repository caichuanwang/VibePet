import AppKit
import VibePetCore

final class PetDragController {
    private weak var window: NSWindow?
    private let configStore: ConfigStore
    private var dragOffset: CGPoint?

    init(window: NSWindow, configStore: ConfigStore) {
        self.window = window
        self.configStore = configStore
    }

    func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }
        let location = event.locationInWindow
        dragOffset = CGPoint(x: location.x, y: location.y)
        window.ignoresMouseEvents = false
    }

    func mouseDragged(with event: NSEvent) {
        guard let window, let dragOffset, let screenFrame = NSScreen.main?.visibleFrame else {
            return
        }

        let mouse = NSEvent.mouseLocation
        let origin = CGPoint(x: mouse.x - dragOffset.x, y: mouse.y - dragOffset.y)
        let frame = ScreenSnap.clamp(CGRect(origin: origin, size: window.frame.size), in: screenFrame)
        window.setFrame(frame, display: true)
    }

    func mouseUp(with event: NSEvent) {
        guard let window, let screenFrame = NSScreen.main?.visibleFrame else {
            dragOffset = nil
            return
        }

        let frame = ScreenSnap.snap(window.frame, in: screenFrame)
        window.setFrame(frame, display: true, animate: true)
        persist(frame: frame, screenFrame: screenFrame)
        dragOffset = nil
    }

    private func persist(frame: CGRect, screenFrame: CGRect) {
        do {
            let current = try configStore.read()
            let updated = current.with(
                petPosition: PetPosition(
                    x: frame.origin.x,
                    y: frame.origin.y,
                    screenWidth: screenFrame.width,
                    screenHeight: screenFrame.height
                )
            )
            try configStore.write(updated)
        } catch {
            NSLog("VibePet failed to persist pet position: \(error)")
        }
    }
}

struct PetFrameResolver {
    static func initialFrame(config: AppConfig, visibleFrame: CGRect, spriteSize: CGSize) -> CGRect {
        guard config.petPosition.screenWidth > 0, config.petPosition.screenHeight > 0 else {
            return ScreenSnap.defaultFrame(spriteSize: spriteSize, in: visibleFrame)
        }

        let frame = CGRect(
            x: config.petPosition.x,
            y: config.petPosition.y,
            width: spriteSize.width,
            height: spriteSize.height
        )
        return ScreenSnap.clamp(frame, in: visibleFrame)
    }
}
