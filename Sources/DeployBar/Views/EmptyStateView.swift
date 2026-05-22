import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "key")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("No providers configured")
                .font(.headline)

            Text("Open Settings to add a Vercel or Railway API token.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
