import DeployBarCore
import Foundation
import Security

final class SecureTokenStore: MutableTokenStore, @unchecked Sendable {
    static let service = "com.deploybar.tokens"
    private static let vaultAccount = "deploybar-token-vault-v1"
    private let cache = TokenCache()

    func token(for account: ProviderAccount) throws -> String? {
        let accountKey = keychainAccount(for: account)
        try ensureVaultLoaded()
        if let cached = cache.token(for: accountKey) {
            return cached
        }

        let token = try Self.readLegacy(account: accountKey)
        if let token {
            cache.set(token, for: accountKey)
            try saveCachedVault()
            try? Self.deleteLegacy(account: accountKey)
        }
        return token
    }

    func save(token: String, for account: ProviderAccount) throws {
        let accountKey = keychainAccount(for: account)
        try ensureVaultLoaded()
        cache.set(token, for: accountKey)
        try saveCachedVault()
        try? Self.deleteLegacy(account: accountKey)
    }

    func deleteToken(for account: ProviderAccount) throws {
        let accountKey = keychainAccount(for: account)
        try ensureVaultLoaded()
        cache.removeToken(for: accountKey)
        try saveCachedVault()
        try? Self.deleteLegacy(account: accountKey)
    }

    private func keychainAccount(for account: ProviderAccount) -> String {
        "\(account.provider.rawValue):\(account.tokenReference)"
    }

    private func ensureVaultLoaded() throws {
        guard !cache.isLoaded else { return }
        let tokens = try Self.readVault()
        cache.replace(with: tokens)
    }

    private func saveCachedVault() throws {
        try Self.saveVault(tokens: cache.allTokens())
    }

    private static func readVault() throws -> [String: String] {
        guard let data = try read(account: vaultAccount, useDataProtectionKeychain: true)
            ?? read(account: vaultAccount, useDataProtectionKeychain: false)
        else {
            return [:]
        }

        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func saveVault(tokens: [String: String]) throws {
        let data = try JSONEncoder().encode(tokens)
        do {
            try save(data: data, account: vaultAccount, useDataProtectionKeychain: true)
        } catch {
            try save(data: data, account: vaultAccount, useDataProtectionKeychain: false)
        }
    }

    private static func readLegacy(account: String) throws -> String? {
        guard let data = try read(account: account, useDataProtectionKeychain: false) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func read(account: String, useDataProtectionKeychain: Bool) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ].withDataProtectionKeychain(useDataProtectionKeychain)

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return data
    }

    private static func save(data: Data, account: String, useDataProtectionKeychain: Bool) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ].withDataProtectionKeychain(useDataProtectionKeychain)
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            if useDataProtectionKeychain {
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }

    private static func deleteLegacy(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

struct KeychainError: Error {
    var status: OSStatus
}

private final class TokenCache: @unchecked Sendable {
    private var tokens: [String: String] = [:]
    private var loaded = false
    private let lock = NSLock()

    var isLoaded: Bool {
        lock.withLock {
            loaded
        }
    }

    func token(for account: String) -> String? {
        lock.withLock {
            tokens[account]
        }
    }

    func set(_ token: String, for account: String) {
        lock.withLock {
            loaded = true
            tokens[account] = token
        }
    }

    func removeToken(for account: String) {
        lock.withLock {
            loaded = true
            tokens.removeValue(forKey: account)
        }
    }

    func replace(with tokens: [String: String]) {
        lock.withLock {
            self.tokens = tokens
            loaded = true
        }
    }

    func allTokens() -> [String: String] {
        lock.withLock {
            tokens
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func withDataProtectionKeychain(_ enabled: Bool) -> [String: Any] {
        guard enabled else { return self }
        var copy = self
        copy[kSecUseDataProtectionKeychain as String] = true
        return copy
    }
}
