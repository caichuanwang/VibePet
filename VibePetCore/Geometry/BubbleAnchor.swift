import CoreGraphics

/// Quadrant-aware bubble placement (technical design §5.3 通用). Pure geometry in
/// `VibePetCore` so the anchoring / tail-tracking / boundary-avoidance rules are
/// unit testable; the SwiftUI bubble only consumes the result. All coordinates
/// are in the AppKit screen space (y-up) of `visibleFrame`.
public enum BubbleAnchor {
    /// Gap kept between the bubble edge and the visible frame edge.
    public static let edgeInset: CGFloat = 12
    /// Gap between the pet body and the bubble.
    public static let petGap: CGFloat = 8
    /// Horizontal offset of the bubble's near corner from the pet center.
    public static let tailInset: CGFloat = 24
    /// Keeps the tail away from the bubble's rounded corners.
    public static let cornerInset: CGFloat = 16

    public enum VerticalOpening: Equatable, Sendable {
        case up
        case down
    }

    public enum HorizontalOpening: Equatable, Sendable {
        case left
        case right
    }

    public struct Placement: Equatable, Sendable {
        public let frame: CGRect
        public let vertical: VerticalOpening
        public let horizontal: HorizontalOpening
        /// Point on the bubble's pet-facing edge that the tail should point from.
        public let tail: CGPoint
    }

    public static func place(
        petFrame: CGRect,
        bubbleSize: CGSize,
        in visibleFrame: CGRect
    ) -> Placement {
        let petCenter = CGPoint(x: petFrame.midX, y: petFrame.midY)

        // Quadrant: lower half opens up, upper half opens down; right half opens
        // left, left half opens right (so the bubble grows toward screen center).
        let horizontal: HorizontalOpening = petCenter.x >= visibleFrame.midX ? .left : .right
        var vertical: VerticalOpening = petCenter.y < visibleFrame.midY ? .up : .down

        let minY = visibleFrame.minY + edgeInset
        let maxY = visibleFrame.maxY - edgeInset - bubbleSize.height

        func originY(for opening: VerticalOpening) -> CGFloat {
            switch opening {
            case .up:
                return petFrame.maxY + petGap
            case .down:
                return petFrame.minY - petGap - bubbleSize.height
            }
        }

        // Flip vertically only when the chosen side overflows and the other fits
        // (e.g. pet pinned to the top edge can't open down).
        var y = originY(for: vertical)
        if y < minY || y > maxY {
            let flipped: VerticalOpening = vertical == .up ? .down : .up
            let flippedY = originY(for: flipped)
            if flippedY >= minY, flippedY <= maxY {
                vertical = flipped
                y = flippedY
            }
        }

        var x: CGFloat
        switch horizontal {
        case .right:
            x = petCenter.x - tailInset
        case .left:
            x = petCenter.x + tailInset - bubbleSize.width
        }

        // Clamp the whole bubble into the visible frame (12pt from edges).
        x = clamp(x, minimum: visibleFrame.minX + edgeInset, maximum: visibleFrame.maxX - edgeInset - bubbleSize.width)
        y = clamp(y, minimum: minY, maximum: maxY)

        let frame = CGRect(x: x, y: y, width: bubbleSize.width, height: bubbleSize.height)

        // The tail keeps pointing at the pet even after the bubble is clamped.
        let tailX = clamp(petCenter.x, minimum: frame.minX + cornerInset, maximum: frame.maxX - cornerInset)
        let tailY = vertical == .up ? frame.minY : frame.maxY

        return Placement(
            frame: frame,
            vertical: vertical,
            horizontal: horizontal,
            tail: CGPoint(x: tailX, y: tailY)
        )
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else {
            return minimum
        }
        return min(max(value, minimum), maximum)
    }
}
