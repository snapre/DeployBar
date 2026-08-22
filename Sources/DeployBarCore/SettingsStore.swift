import Foundation

public struct DeployBarSettings: Codable, Equatable, Sendable {
    public var refreshCadence: RefreshCadence
    public var accounts: [ProviderAccount]
    public var showMockProvider: Bool

    public init(
        refreshCadence: RefreshCadence = .minute1,
        accounts: [ProviderAccount] = [],
        showMockProvider: Bool = true
    ) {
        self.refreshCadence = refreshCadence
        self.accounts = accounts
        self.showMockProvider = showMockProvider
    }

    public mutating func addAccount(_ account: ProviderAccount) {
        accounts.append(account)
        if account.provider != .mock {
            showMockProvider = false
        }
    }
}

public final class SettingsStore: @unchecked Sendable {
    private let settingsURL: URL
    private let queue = DispatchQueue(label: "com.deploybar.settings")

    public init(settingsURL: URL? = nil) {
        self.settingsURL = settingsURL ?? Self.defaultSettingsURL()
    }

    public func load() -> DeployBarSettings {
        queue.sync {
            guard let data = try? Data(contentsOf: settingsURL) else {
                return DeployBarSettings()
            }

            do {
                let decoder = JSONDecoder.deployBar
                return try decoder.decode(DeployBarSettings.self, from: data)
            } catch {
                return DeployBarSettings()
            }
        }
    }

    public func save(_ settings: DeployBarSettings) throws {
        try queue.sync {
            let directory = settingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder.deployBar
            let data = try encoder.encode(settings)
            try data.write(to: settingsURL, options: [.atomic])
        }
    }

    public static func defaultSettingsURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("DeployBar", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}

public extension JSONDecoder {
    static var deployBar: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = DateParsers.parse(string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date.")
        }
        return decoder
    }
}

public extension JSONEncoder {
    static var deployBar: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private enum DateParsers {
    static func parse(_ string: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
