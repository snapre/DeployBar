import Foundation

public struct Redactor: Sendable {
    private let secrets: [String]

    public init(secrets: [String]) {
        self.secrets = secrets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func redact(_ text: String) -> String {
        secrets.reduce(text) { partial, secret in
            partial.replacingOccurrences(of: secret, with: "<redacted>")
        }
    }
}
