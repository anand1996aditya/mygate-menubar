import Foundation
import Security

/// Storage for the MyGate access key.
///
/// The production implementation keeps the key in the macOS Keychain. The
/// in-memory implementation exists so the self-test can exercise migration and
/// save/load behaviour without touching the real Keychain.
protocol SecureTokenStore {
    func read(service: String, account: String) throws -> String?
    func write(_ token: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

enum KeychainStoreError: LocalizedError {
    case status(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .status(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "Keychain error \(status): \(message)"
        case .invalidData:
            return "Keychain item is not valid text"
        }
    }
}

/// Generic-password Keychain storage for a single service/account pair.
struct KeychainTokenStore: SecureTokenStore {
    static let shared = KeychainTokenStore()

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func read(service: String, account: String) throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let token = String(data: data, encoding: .utf8),
                  !token.isEmpty else {
                throw KeychainStoreError.invalidData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.status(status)
        }
    }

    func write(_ token: String, service: String, account: String) throws {
        let data = Data(token.utf8)
        let query = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.status(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw KeychainStoreError.status(retryStatus)
            }
            return
        }
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.status(addStatus)
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.status(status)
        }
    }
}

/// Test double for `SecureTokenStore`. Never used by the app at runtime.
final class InMemoryTokenStore: SecureTokenStore {
    private(set) var values: [String: String] = [:]
    var failRead = false
    var failWrite = false
    var failDelete = false

    private func key(_ service: String, _ account: String) -> String { "\(service)/\(account)" }

    func value(service: String, account: String) -> String? {
        values[key(service, account)]
    }

    func seed(_ token: String, service: String, account: String) {
        values[key(service, account)] = token
    }

    func read(service: String, account: String) throws -> String? {
        if failRead { throw KeychainStoreError.status(errSecInteractionNotAllowed) }
        return values[key(service, account)]
    }

    func write(_ token: String, service: String, account: String) throws {
        if failWrite { throw KeychainStoreError.status(errSecInteractionNotAllowed) }
        values[key(service, account)] = token
    }

    func delete(service: String, account: String) throws {
        if failDelete { throw KeychainStoreError.status(errSecInteractionNotAllowed) }
        values.removeValue(forKey: key(service, account))
    }
}
