import Foundation
import Darwin

private final class PowerModeHelper: NSObject, PowerModeHelperProtocol {
    private let queue = DispatchQueue(label: "StatusArc.PowerModeHelper")

    func helperVersion(withReply reply: @escaping (Int) -> Void) {
        reply(PowerModeService.implementationVersion)
    }

    func setEnergyMode(
        _ mode: Int,
        for powerSource: Int,
        withReply reply: @escaping (Bool, String?) -> Void
    ) {
        guard let mode = EnergyMode(rawValue: mode),
              let powerSource = EnergyPowerSource(rawValue: powerSource) else {
            reply(false, "StatusArc received an unsupported Energy Mode request.")
            return
        }

        queue.async {
            do {
                try Self.apply(mode, to: powerSource)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func stopForUpdate(withReply reply: @escaping () -> Void) {
        reply()
        queue.asyncAfter(deadline: .now() + 0.1) {
            exit(EXIT_SUCCESS)
        }
    }

    private static func apply(
        _ mode: EnergyMode,
        to powerSource: EnergyPowerSource
    ) throws {
        guard geteuid() == 0 else {
            throw PowerModeHelperError.message(
                "The Energy Mode helper is not running with administrator privileges."
            )
        }

        let capabilities = try runPMSet(arguments: ["-g", "cap"])
        guard capabilities.split(whereSeparator: \Character.isWhitespace)
            .contains("lowpowermode") else {
            throw PowerModeHelperError.message(
                "Low Power Mode is not available on this Mac."
            )
        }

        let supportsHighPower = capabilities.split(whereSeparator: \Character.isWhitespace)
            .contains("highpowermode")
        if mode == .highPower, !supportsHighPower {
            throw PowerModeHelperError.message(
                "High Power Mode is not available on this Mac."
            )
        }

        let sourceFlag = powerSource == .battery ? "-b" : "-c"
        let modeValue = String(mode.rawValue)

        // Current macOS versions expose Energy Mode as one tri-state setting:
        // 0 = Automatic, 1 = Low Power, 2 = High Power. Keep the older key
        // pair as a fallback for systems predating that command-line form.
        do {
            _ = try runPMSet(arguments: [sourceFlag, "powermode", modeValue])
        } catch let error as PowerModeHelperError where error.isCommandFailure {
            _ = try runPMSet(
                arguments: [sourceFlag] + legacySettings(
                    for: mode,
                    supportsHighPower: supportsHighPower
                )
            )
        }

        let profiles = try runPMSet(arguments: ["-g", "custom"])
        guard currentMode(in: profiles, for: powerSource) == mode else {
            throw PowerModeHelperError.message(
                "macOS did not apply the selected Energy Mode."
            )
        }
    }

    private static func currentMode(
        in output: String,
        for powerSource: EnergyPowerSource
    ) -> EnergyMode? {
        let requestedHeading = powerSource == .battery ? "Battery Power:" : "AC Power:"
        var currentHeading: String?
        var profiles: [String: [String: Int]] = [:]

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix(":") {
                currentHeading = line
                profiles[line, default: [:]] = profiles[line, default: [:]]
                continue
            }

            let parts = line.split(whereSeparator: \Character.isWhitespace)
            guard parts.count == 2,
                  let value = Int(parts[1]),
                  let currentHeading else { continue }
            profiles[currentHeading, default: [:]][String(parts[0])] = value
        }

        // Newer systems may expose only one active power profile in `-g custom`.
        let values = profiles[requestedHeading] ?? profiles.values.first ?? [:]

        if let value = values["powermode"] {
            return EnergyMode(rawValue: value)
        }
        if values["highpowermode"] == 1 { return .highPower }
        if values["lowpowermode"] == 1 { return .lowPower }
        if values["lowpowermode"] != nil { return .automatic }
        return nil
    }

    private static func legacySettings(
        for mode: EnergyMode,
        supportsHighPower: Bool
    ) -> [String] {
        switch mode {
        case .automatic:
            return supportsHighPower
                ? ["lowpowermode", "0", "highpowermode", "0"]
                : ["lowpowermode", "0"]
        case .lowPower:
            return supportsHighPower
                ? ["lowpowermode", "1", "highpowermode", "0"]
                : ["lowpowermode", "1"]
        case .highPower:
            return ["lowpowermode", "0", "highpowermode", "1"]
        }
    }

    @discardableResult
    private static func runPMSet(arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        process.standardOutput = output
        process.standardError = errors

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            throw PowerModeHelperError.message("macOS could not start the Energy Mode command.")
        }

        guard completion.wait(timeout: .now() + 4) == .success else {
            process.terminate()
            if completion.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            throw PowerModeHelperError.message(
                "The Energy Mode command did not respond."
            )
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationReason == .exit,
              process.terminationStatus == 0 else {
            let standardError = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let standardOutput = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw PowerModeHelperError.commandFailed(
                status: process.terminationStatus,
                wasInterrupted: process.terminationReason == .uncaughtSignal,
                detail: standardError.isEmpty ? standardOutput : standardError
            )
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

private final class PowerModeListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let helper = PowerModeHelper()
    private let dynamicAppExecutableURL: URL?

    init(dynamicAppExecutableURL: URL? = nil) {
        self.dynamicAppExecutableURL = dynamicAppExecutableURL
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        if let dynamicAppExecutableURL {
            // Debug builds are ad-hoc signed, so their designated requirement
            // can change after every rebuild. Resolve it from the current app
            // for each connection. Release builds retain a requirement fixed
            // at helper launch so a mutable app path cannot change root trust.
            guard let appRequirement = CodeSigningRequirement.forCode(
                at: dynamicAppExecutableURL
            ) else {
                return false
            }
            connection.setCodeSigningRequirement(appRequirement)
        }
        connection.exportedInterface = NSXPCInterface(with: PowerModeHelperProtocol.self)
        connection.exportedObject = helper
        connection.resume()
        return true
    }
}

private enum PowerModeHelperError: LocalizedError {
    case message(String)
    case commandFailed(status: Int32, wasInterrupted: Bool, detail: String)

    var isCommandFailure: Bool {
        if case .commandFailed = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        case .commandFailed(let status, let wasInterrupted, let detail):
            if !detail.isEmpty { return detail }
            return wasInterrupted
                ? "The Energy Mode command was interrupted by signal \(status)."
                : "The Energy Mode command exited with status \(status)."
        }
    }
}

private func mainApplicationExecutableURL() -> URL? {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    var size = UInt32(buffer.count)
    guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }

    let helperURL = URL(fileURLWithPath: String(cString: buffer))
        .resolvingSymlinksInPath()
        .standardizedFileURL
    let appURL = helperURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return Bundle(url: appURL)?.executableURL
}

private let listener = NSXPCListener(machServiceName: PowerModeService.label)

#if DEBUG
guard let debugAppExecutableURL = mainApplicationExecutableURL() else {
    exit(EXIT_FAILURE)
}
private let delegate = PowerModeListenerDelegate(
    dynamicAppExecutableURL: debugAppExecutableURL
)
#else
guard let appExecutableURL = mainApplicationExecutableURL(),
      let appRequirement = CodeSigningRequirement.forCode(at: appExecutableURL) else {
    exit(EXIT_FAILURE)
}
listener.setConnectionCodeSigningRequirement(appRequirement)
private let delegate = PowerModeListenerDelegate()
#endif

listener.delegate = delegate
listener.resume()
RunLoop.current.run()
