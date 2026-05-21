import AppKit
import DeployBarCore
import SwiftUI

enum DeploymentSeverityStyle {
    static func color(for severity: DeploymentSeverity) -> Color {
        switch severity {
        case .healthy:
            .green
        case .pending:
            .cyan
        case .active:
            .blue
        case .warning:
            .orange
        case .critical:
            .red
        }
    }

    static func nsColor(for severity: DeploymentSeverity) -> NSColor {
        NSColor(color(for: severity))
    }
}
