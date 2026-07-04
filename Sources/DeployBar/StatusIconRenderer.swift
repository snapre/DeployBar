import AppKit
import DeployBarCore

@MainActor
enum StatusIconRenderer {
    static func image(
        for severity: DeploymentSeverity,
        isRefreshing: Bool,
        appearance: NSAppearance? = nil
    ) -> NSImage {
        let size = NSSize(width: 28, height: 18)
        let image = NSImage(size: size)
        let colors = statusBarColors(for: appearance)

        image.lockFocus()

        defer {
            image.unlockFocus()
            image.isTemplate = false
        }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        colors.body.setFill()
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

        if let context = NSGraphicsContext.current {
            context.compositingOperation = .clear
            glyph.stroke()
            context.compositingOperation = .sourceOver
        } else {
            NSColor.clear.setStroke()
            glyph.stroke()
        }

        let baseColor = DeploymentSeverityStyle.nsColor(for: severity)
        let alpha = severity == .warning && !isRefreshing ? 0.82 : 1
        colors.badgeBorder.setFill()
        NSBezierPath(ovalIn: NSRect(x: 17, y: 2, width: 7, height: 7)).fill()

        baseColor.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: 18, y: 3, width: 5, height: 5)).fill()

        return image
    }

    private static func statusBarColors(for appearance: NSAppearance?) -> StatusBarColors {
        StatusBarColors(
            body: resolvedSystemColor(.labelColor, for: appearance),
            badgeBorder: resolvedSystemColor(.controlBackgroundColor, for: appearance)
        )
    }

    private static func resolvedSystemColor(_ color: NSColor, for appearance: NSAppearance?) -> NSColor {
        let appearance = appearance ?? NSApplication.shared.effectiveAppearance
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolved
    }

    private struct StatusBarColors {
        let body: NSColor
        let badgeBorder: NSColor
    }
}
