import Foundation
import Security

public enum KeychainPasswordStoreError: LocalizedError {
    case invalidPasswordData
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidPasswordData:
            return L10n.text("error.keychain_invalid_data")
        case .unexpectedStatus(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String?
                ?? L10n.format("error.code", status)
            return L10n.format("error.keychain_status", detail)
        }
    }
}

public struct KeychainPasswordStore: Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "nl.eikeldal.OpenConnectVPN",
        account: String = "globalprotect-password"
    ) {
        self.service = service
        self.account = account
    }

    public func load() throws -> String? {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainPasswordStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainPasswordStoreError.invalidPasswordData
        }
        return password
    }

    public func save(_ password: String) throws {
        guard !password.isEmpty else {
            try delete()
            return
        }
        guard let data = password.data(using: .utf8) else {
            throw KeychainPasswordStoreError.invalidPasswordData
        }

        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainPasswordStoreError.unexpectedStatus(updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainPasswordStoreError.unexpectedStatus(addStatus)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainPasswordStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
