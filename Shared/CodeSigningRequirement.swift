import Foundation
import Security

enum CodeSigningRequirement {
    static func forCode(at executableURL: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else {
            return nil
        }

        var requirementText: CFString?
        guard SecRequirementCopyString(requirement, [], &requirementText) == errSecSuccess else {
            return nil
        }

        return requirementText as String?
    }
}
