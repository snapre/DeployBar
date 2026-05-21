import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView(
            "No providers configured",
            systemImage: "key",
            description: Text("Open Settings to add a Vercel or Railway API token.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
