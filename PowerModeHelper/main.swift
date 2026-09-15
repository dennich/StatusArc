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
        var arguments = [sourceFlag]

        switch mode {
        case .automatic:
            arguments += ["lowpowermode", "0"]
            if supportsHighPower {
                arguments += ["highpowermode", "0"]
            }

        case .lowPower:
            arguments += ["lowpowermode", "1"]
            if supportsHighPower {
                arguments += ["highpowermode", "0"]
            }

        case .highPower:
            arguments += ["lowpowermode", "0", "highpowermode", "1"]
        }

        _ = try runPMSet(arguments: arguments)

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
        var values: [String: Int] = [:]

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix(":") {
                currentHeading = line
                continue
            }
            guard currentHeading == requestedHeading else { continue }

            let parts = line.split(whereSeparator: \Character.isWhitespace)
            guard parts.count == 2, let value = Int(parts[1]) else { continue }
            values[String(parts[0])] = value
        }

        if values["highpowermode"] == 1 { return .highPower }
        if values["lowpowermode"] == 1 { return .lowPower }
        if values["lowpowermode"] != nil { return .automatic }
        return nil
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
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let statusDetail = process.terminationReason == .uncaughtSignal
                ? "The Energy Mode command was interrupted by signal \(process.terminationStatus)."
                : "The Energy Mode command exited with status \(process.terminationStatus)."
            throw PowerModeHelperError.message(
                detail?.isEmpty == false
                    ? detail!
                    : statusDetail
            )
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

private final class PowerModeListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let helper = PowerModeHelper()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: PowerModeHelperProtocol.self)
        connection.exportedObject = helper
        connection.resume()
        return true
    }
}

private enum PowerModeHelperError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
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
private let delegate = PowerModeListenerDelegate()

guard let appExecutableURL = mainApplicationExecutableURL(),
      let appRequirement = CodeSigningRequirement.forCode(at: appExecutableURL) else {
    exit(EXIT_FAILURE)
}

listener.setConnectionCodeSigningRequirement(appRequirement)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
