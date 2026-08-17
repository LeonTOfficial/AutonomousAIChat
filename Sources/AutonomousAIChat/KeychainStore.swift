import Foundation
import Security

struct KeychainStore {
    static let service = "com.leon.autonomous-ai-chat"
    static let geminiAccount = "gemini-api-key"
    static let ollamaWebSearchAccount = "ollama-web-search-api-key"

    private static var isDisabledForLocalQA: Bool {
        ProcessInfo.processInfo.environment["AUTONOMOUS_AI_CHAT_QA_NO_KEYCHAIN"] == "1"
    }

    static func save(_ value: String, account: String = geminiAccount) throws {
        guard !isDisabledForLocalQA else { return }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var create = query
            create[kSecValueData as String] = data
            let addStatus = SecItemAdd(create as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.status(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    static func read(account: String = geminiAccount) -> String? {
        guard !isDisabledForLocalQA else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func delete(account: String = geminiAccount) {
        guard !isDisabledForLocalQA else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return "Keychain-Fehler (\(status))"
            }
        }
    }
}
