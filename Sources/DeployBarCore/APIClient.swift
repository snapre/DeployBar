import Foundation

public struct HTTPResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var data: Data

    public init(statusCode: Int, headers: [String: String] = [:], data: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public enum APIClientError: Error, Equatable, Sendable {
    case invalidResponse
    case transport
}

public final class APIClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession
    private let timeout: TimeInterval
    private let maxRetries: Int

    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = 20,
        maxRetries: Int = 1
    ) {
        self.session = session
        self.timeout = timeout
        self.maxRetries = max(0, maxRetries)
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        var request = request
        request.timeoutInterval = timeout

        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIClientError.invalidResponse
                }

                if shouldRetry(statusCode: httpResponse.statusCode), attempt < maxRetries {
                    try await sleepBeforeRetry(attempt: attempt)
                    continue
                }

                return HTTPResponse(
                    statusCode: httpResponse.statusCode,
                    headers: Self.headers(from: httpResponse),
                    data: data
                )
            } catch {
                if attempt < maxRetries {
                    try await sleepBeforeRetry(attempt: attempt)
                    continue
                }
                throw APIClientError.transport
            }
        }

        throw APIClientError.transport
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        (500...599).contains(statusCode)
    }

    private func sleepBeforeRetry(attempt: Int) async throws {
        let nanoseconds = UInt64(250_000_000 * max(1, attempt + 1))
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private static func headers(from response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [String: String]()) { partial, pair in
            guard let key = pair.key as? String else { return }
            partial[key] = String(describing: pair.value)
        }
    }
}

public extension ProviderIssue {
    static func fromHTTPStatus(provider: ProviderID, accountID: String?, statusCode: Int) -> ProviderIssue? {
        switch statusCode {
        case 200...299:
            return nil
        case 401, 403:
            return ProviderIssue(provider: provider, accountID: accountID, kind: .authentication, message: "\(provider.displayName) authentication failed.")
        case 429:
            return ProviderIssue(provider: provider, accountID: accountID, kind: .rateLimited, message: "\(provider.displayName) rate limit reached.")
        case 500...599:
            return ProviderIssue(provider: provider, accountID: accountID, kind: .network, message: "\(provider.displayName) API is temporarily unavailable.")
        default:
            return ProviderIssue(provider: provider, accountID: accountID, kind: .unknown, message: "\(provider.displayName) API returned HTTP \(statusCode).")
        }
    }
}
