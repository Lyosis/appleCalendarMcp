import Foundation
import Security

public enum PinError: LocalizedError {
    case unreadable(String)
    case noRequirement(String)
    case notAnApplication(String)
    case keychain(OSStatus)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            "Cannot read a code signature at \(path)."
        case .noRequirement(let path):
            "\(path) has no designated requirement, so there is nothing to pin to. It is probably unsigned."
        case .notAnApplication(let path):
            "\(path) is not an application bundle."
        case .keychain(let status):
            "The keychain refused the operation (status \(status))."
        case .malformed(let text):
            "Not a usable code requirement: \(text)"
        }
    }
}

/// The one client allowed to reach the helper.
///
/// Stored in the keychain rather than a file on purpose: a file under the
/// person's home is writable by anything running as them, so an attacker could
/// simply replace the pin with their own identity and walk in. A keychain item
/// is bound to the code that created it.
public enum ClientPin {
    private static let service = "com.wilfrid.B.apple-calendar-mcp"
    private static let account = "pinned-client-requirement"

    // MARK: - Reading

    /// The pinned requirement, or nil when nothing is pinned.
    public static func requirementText() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    public static func compiled() -> SecRequirement? {
        guard let text = requirementText() else { return nil }
        return compile(text)
    }

    public static func compile(_ text: String) -> SecRequirement? {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess
        else {
            return nil
        }
        return requirement
    }

    // MARK: - Writing

    @discardableResult
    public static func pin(applicationAt path: String) throws -> String {
        let text = try designatedRequirement(ofBundleAt: path)
        guard compile(text) != nil else { throw PinError.malformed(text) }
        try store(text)
        return text
    }

    public static func unpin() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PinError.keychain(status)
        }
    }

    private static func store(_ text: String) throws {
        try unpin()  // replace rather than accumulate
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "apple-calendar-mcp — pinned client",
            kSecValueData as String: Data(text.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw PinError.keychain(status) }
    }

    /// The designated requirement Apple derives for a signed application.
    ///
    /// Taking the application's own requirement rather than composing one by
    /// hand means the pin says exactly what the system means by "this app",
    /// including its team, and stays right when certificates rotate.
    public static func designatedRequirement(ofBundleAt path: String) throws -> String {
        guard path.hasSuffix(".app") else { throw PinError.notAnApplication(path) }

        var staticCode: SecStaticCode?
        let url = URL(fileURLWithPath: path) as CFURL
        guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            throw PinError.unreadable(path)
        }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement
        else {
            throw PinError.noRequirement(path)
        }

        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else {
            throw PinError.noRequirement(path)
        }
        return text as String
    }
}
