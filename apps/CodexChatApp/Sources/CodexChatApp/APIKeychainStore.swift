import Foundation
import Security

enum APIKeychainStoreError: LocalizedError {
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .osStatus(status):
            let text = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown OSStatus"
            return "Keychain operation failed (\(status)): \(text)"
        }
    }
}

final class APIKeychainStore: @unchecked Sendable {
    static let runtimeAPIKeyAccount = "codexchat.runtime.openai_api_key"

    private let service = "app.codexchat.credentials"

    func saveSecret(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw APIKeychainStoreError.osStatus(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeychainStoreError.osStatus(addStatus)
        }
    }

    func deleteSecret(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }

        throw APIKeychainStoreError.osStatus(status)
    }

    func readSecret(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw APIKeychainStoreError.osStatus(status)
        }

        guard let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
