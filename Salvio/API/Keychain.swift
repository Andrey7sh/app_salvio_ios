import Foundation
import Security

/// Токены в Keychain. AfterFirstUnlock: фоновая загрузка чанков идёт и при заблокированном экране.
enum Keychain {
    private static let service = "io.salvio.app.auth"

    static func get(_ key: String) -> String? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for key: String) {
        SecItemDelete(base(key) as CFDictionary)
        guard let value else { return }
        var query = base(key)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
}

enum TokenStore {
    static var access: String? {
        get { Keychain.get("access_token") }
        set { Keychain.set(newValue, for: "access_token") }
    }
    static var refresh: String? {
        get { Keychain.get("refresh_token") }
        set { Keychain.set(newValue, for: "refresh_token") }
    }
    static func save(_ pair: TokenPair) {
        access = pair.accessToken
        refresh = pair.refreshToken
    }
    static func clear() {
        access = nil
        refresh = nil
    }
}
