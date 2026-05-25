import Foundation

enum ProviderUtilities {
    static func normalizedURL(from rawValue: String?) -> URL? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
            return nil
        }
        if rawValue.hasPrefix("http://") || rawValue.hasPrefix("https://") {
            return URL(string: rawValue)
        }
        return URL(string: "https://\(rawValue)")
    }

    static func duration(startedAt: Date?, finishedAt: Date?) -> TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    static func deduplicated(_ snapshots: [DeploymentSnapshot]) -> [DeploymentSnapshot] {
        var seen = Set<String>()
        return snapshots.filter { snapshot in
            seen.insert(snapshot.id).inserted
        }
    }

    static func issue(for error: APIClientError, provider: ProviderID, accountID: String?) -> ProviderIssue {
        switch error {
        case .invalidResponse:
            ProviderIssue(provider: provider, accountID: accountID, kind: .apiChanged, message: "\(provider.displayName) API returned an invalid response.")
        case .transport:
            ProviderIssue(provider: provider, accountID: accountID, kind: .network, message: localNetworkIssueMessage(provider: provider))
        }
    }

    static func localNetworkIssueMessage(provider: ProviderID) -> String {
        "Network connection issue: could not reach \(provider.displayName) API. Check your internet, VPN, or proxy connection."
    }
}

struct ProviderLossyStringDictionary: Decodable {
    var values: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: LossyDynamicCodingKey.self)
        var values: [String: String] = [:]

        for key in container.allKeys {
            if let value = try? container.decode(String.self, forKey: key) {
                values[key.stringValue] = value
            } else if let value = try? container.decode(Int.self, forKey: key) {
                values[key.stringValue] = String(value)
            } else if let value = try? container.decode(Double.self, forKey: key) {
                values[key.stringValue] = String(value)
            } else if let value = try? container.decode(Bool.self, forKey: key) {
                values[key.stringValue] = String(value)
            }
        }

        self.values = values
    }
}

private struct LossyDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
