## 1. Window Behavior Contract

- [x] 1.1 Add a shared AppKit collection-behavior helper or constant for VibePet overlay windows that includes `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`, and `.ignoresCycle`
- [x] 1.2 Update `PetWindow` to use a nonactivating stationary all-Spaces `NSPanel` overlay while preserving its current transparency, level, shadow, and mouse behavior
- [x] 1.3 Update `BubbleWindow` so notification bubbles, approval/question bubbles, and pending-count badges use the same stationary all-Spaces overlay behavior while preserving current interactive key-window behavior

## 2. Automated Verification

- [x] 2.1 Add or update AppKit-level tests that assert the pet window collection behavior includes `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`, and `.ignoresCycle`
- [x] 2.2 Add or update AppKit-level tests that assert the pet window uses a nonactivating `NSPanel`, and that bubble windows use the same stationary all-Spaces collection behavior or expose a testable helper if the private window class cannot be instantiated directly
- [x] 2.3 Run the focused affected tests, then run `swift test`

## 3. Manual macOS Spaces Verification

- [x] 3.1 Run `swift run VibePetApp` and verify the pet remains visible at the same screen-coordinate position when switching between two normal desktop Spaces
- [x] 3.2 Verify the pet remains visible when switching into and out of a full-screen app Space
- [x] 3.3 Verify Mission Control and Show Desktop / click-wallpaper-to-reveal-desktop do not leave the pet behind on the old Space
- [x] 3.4 Verify at least one visible bubble or pending-count badge follows the pet across Space switches
- [x] 3.5 If `.floating` level is insufficient in manual verification, evaluate `.statusBar` for pet overlay surfaces and document the result before changing level

## 4. Final Validation

- [x] 4.1 Run `swift build`
- [x] 4.2 Run `openspec validate keep-pet-across-spaces --strict`
- [x] 4.3 Update implementation notes or task evidence with any macOS-version-specific behavior observed during manual verification

Manual verification note: user confirmed the nonactivating floating `NSPanel` implementation follows macOS Space switches successfully; `.statusBar` escalation was not needed.
