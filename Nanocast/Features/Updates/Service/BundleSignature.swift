import Foundation
import Security

enum BundleSignature {
    /// Returned so the swap at quit can pin the exact bytes that were verified.
    static func trustedHash(of bundleURL: URL) -> Data? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode,
            let requirement = runningRequirement,
            SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
        else { return nil }
        return uniqueHash(of: staticCode)
    }

    /// An unsealed bundle can claim any identity, and a nested helper is where one hides.
    private static let flags = SecCSFlags(
        rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)

    private static var runningRequirement: SecRequirement? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess
        else { return nil }
        return requirement
    }

    private static func uniqueHash(of staticCode: SecStaticCode) -> Data? {
        var information: CFDictionary?
        let options = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, options, &information) == errSecSuccess
        else { return nil }
        return (information as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
    }
}
