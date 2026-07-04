import AppKit
import DeployBarCore

@MainActor
enum StatusIconRenderer {
    static let iconSize = NSSize(width: 28, height: 18)
    static let badgeCutoutFrame = NSRect(x: 17, y: 2, width: 7, height: 7)
    static let badgeFrame = NSRect(x: 18, y: 3, width: 5, height: 5)

    static func templateImage() -> NSImage {
        let image = NSImage(size: iconSize)

        image.lockFocus()

        defer {
            image.unlockFocus()
            image.isTemplate = true
        }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: iconSize)).fill()

        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: 0, width: 18, height: 18)).fill()

        let glyph = NSBezierPath()
        glyph.lineWidth = 2
        glyph.lineCapStyle = .round
        glyph.lineJoinStyle = .round
        glyph.move(to: NSPoint(x: 8.7, y: 7))
        glyph.line(to: NSPoint(x: 11, y: 10.5))
        glyph.line(to: NSPoint(x: 13.3, y: 7))
        glyph.line(to: NSPoint(x: 16, y: 11))
        glyph.line(to: NSPoint(x: 19.3, y: 11))

        clearStroke(glyph)
        clearFill(NSBezierPath(ovalIn: badgeCutoutFrame))

        return image
    }

    static func badgeColor(for severity: DeploymentSeverity, isRefreshing: Bool) -> NSColor {
        let baseColor = DeploymentSeverityStyle.nsColor(for: severity)
        let alpha = severity == .warning && !isRefreshing ? 0.82 : 1
        return resolvedDeviceRGBColor(baseColor.withAlphaComponent(alpha))
    }

    private static func clearStroke(_ path: NSBezierPath) {
        guard let context = NSGraphicsContext.current else {
            NSColor.clear.setStroke()
            path.stroke()
            return
        }

        context.saveGraphicsState()
        context.compositingOperation = .clear
        path.stroke()
        context.restoreGraphicsState()
    }

    private static func clearFill(_ path: NSBezierPath) {
        guard let context = NSGraphicsContext.current else {
            NSColor.clear.setFill()
            path.fill()
            return
        }

        context.saveGraphicsState()
        context.compositingOperation = .clear
        path.fill()
        context.restoreGraphicsState()
    }

    private static func resolvedDeviceRGBColor(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.deviceRGB) ?? color
    }
}
