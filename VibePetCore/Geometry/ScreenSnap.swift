import CoreGraphics

public enum ScreenSnap {
    public static let defaultRightInset: CGFloat = 24
    public static let snapThreshold: CGFloat = 40
    public static let snappedEdgeInset: CGFloat = 8
    public static let dragThreshold: CGFloat = 6

    public enum DragIntent: Equatable, Sendable {
        case click
        case drag
    }

    public static func defaultFrame(spriteSize: CGSize, in visibleFrame: CGRect) -> CGRect {
        let origin = CGPoint(
            x: visibleFrame.maxX - spriteSize.width - defaultRightInset,
            y: visibleFrame.minY
        )
        return clamp(CGRect(origin: origin, size: spriteSize), in: visibleFrame)
    }

    public static func snap(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        let distances = EdgeDistances(frame: frame, visibleFrame: visibleFrame)
        guard distances.nearest < snapThreshold else {
            return clamp(frame, in: visibleFrame)
        }

        var origin = frame.origin
        if distances.left < snapThreshold {
            origin.x = visibleFrame.minX + snappedEdgeInset
        }
        if distances.right < snapThreshold {
            origin.x = visibleFrame.maxX - frame.width - snappedEdgeInset
        }
        if distances.bottom < snapThreshold {
            origin.y = visibleFrame.minY + snappedEdgeInset
        }
        if distances.top < snapThreshold {
            origin.y = visibleFrame.maxY - frame.height - snappedEdgeInset
        }

        return clamp(CGRect(origin: origin, size: frame.size), in: visibleFrame)
    }

    public static func clamp(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        let x = clamped(
            frame.origin.x,
            minimum: visibleFrame.minX,
            maximum: visibleFrame.maxX - frame.width,
            fallback: visibleFrame.minX
        )
        let y = clamped(
            frame.origin.y,
            minimum: visibleFrame.minY,
            maximum: visibleFrame.maxY - frame.height,
            fallback: visibleFrame.minY
        )
        return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
    }

    public static func dragIntent(
        from pressOrigin: CGPoint,
        to currentPoint: CGPoint,
        threshold: CGFloat = dragThreshold
    ) -> DragIntent {
        let dx = currentPoint.x - pressOrigin.x
        let dy = currentPoint.y - pressOrigin.y
        let distanceSquared = dx * dx + dy * dy
        return distanceSquared >= threshold * threshold ? .drag : .click
    }

    private static func clamped(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat, fallback: CGFloat) -> CGFloat {
        guard minimum <= maximum else {
            return fallback
        }
        return min(max(value, minimum), maximum)
    }
}

private struct EdgeDistances {
    let left: CGFloat
    let right: CGFloat
    let bottom: CGFloat
    let top: CGFloat

    var nearest: CGFloat {
        min(left, right, bottom, top)
    }

    init(frame: CGRect, visibleFrame: CGRect) {
        left = abs(frame.minX - visibleFrame.minX)
        right = abs(visibleFrame.maxX - frame.maxX)
        bottom = abs(frame.minY - visibleFrame.minY)
        top = abs(visibleFrame.maxY - frame.maxY)
    }
}
