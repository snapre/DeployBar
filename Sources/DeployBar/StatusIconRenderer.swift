import AppKit
import DeployBarCore

enum StatusIconRenderer {
    static func image(for severity: DeploymentSeverity, isRefreshing: Bool) -> NSImage {
        let size = NSSize(width: 28, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        defer {
            image.unlockFocus()
            image.isTemplate = false
        }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let baseColor = DeploymentSeverityStyle.nsColor(for: severity)

        let alpha = severity == .warning && !isRefreshing ? 0.82 : 1
        let color = baseColor.withAlphaComponent(alpha)
        color.setStroke()
        color.setFill()

        let line = NSBezierPath()
        line.lineWidth = 2.2
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: 5, y: 5))
        line.line(to: NSPoint(x: 10, y: 13))
        line.line(to: NSPoint(x: 15, y: 5))
        line.line(to: NSPoint(x: 23, y: 13))
        line.stroke()

        if severity >= .warning {
            let indicatorRect = NSRect(x: 20, y: 2, width: 6, height: 6)
            NSBezierPath(ovalIn: indicatorRect).fill()
        } else if isRefreshing || severity == .active {
            let indicatorRect = NSRect(x: 21, y: 3, width: 4, height: 4)
            NSBezierPath(ovalIn: indicatorRect).fill()
        }

        return image
    }
}
