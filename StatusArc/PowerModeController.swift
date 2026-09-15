import Foundation
import ServiceManagement

enum PowerModeControlState: Equatable {
    case notConfigured
    case requiresApproval
    case ready
    case unavailable(String)
}

struct PowerModeStatus: Equatable {
    var currentMode: EnergyMode?
    var capabilitiesKnown: Bool
    var supportsLowPowerMode: Bool
    var supportsHighPowerMode: Bool
    var isChanging: Bool
    var controlState: PowerModeControlState

    static let initial = PowerModeStatus(
        currentMode: nil,
        capabilitiesKnown: false,
        supportsLowPowerMode: false,
        supportsHighPowerMode: false,
        isChanging: false,
        controlState: .notConfigured
    )
}

@MainActor
final class PowerModeController {
    var onStatusChange: ((PowerModeStatus) -> Void)?
    var onError: ((Error) -> Void)?

    private let service = SMAppService.daemon(plistName: PowerModeService.plistName)
    private let readQueue = DispatchQueue(label: "StatusArc.PowerModeReader", qos: .utility)

    private(set) var status = PowerModeStatus.initial {
        didSet {
            guard status != oldValue else { return }
            onStatusChange?(status)
        }
    }

    private var connection: NSXPCConnection?
    private var approvalTimer: Timer?
    private var currentPowerSource: EnergyPowerSource = .powerAdapter
    private var pendingMode: EnergyMode?
    private var readInProgress = false
    private var needsAnotherRead = false
    private var lastReadDate = Date.distantPast
    private var scheduledRead: DispatchWorkItem?
    private var helperRestartAttempts = 0

    func start() {
        updateServiceState()
        refresh()
    }

    func stop() {
        approvalTimer?.invalidate()
        approvalTimer = nil
        scheduledRead?.cancel()
        scheduledRead = nil
        connection?.invalidate()
        connection = nil
    }

    func setPowerSource(_ powerSource: EnergyPowerSource) {
        guard currentPowerSource != powerSource else { return }
        currentPowerSource = powerSource
        refresh(force: true)
    }

    func refresh(force: Bool = false) {
        let elapsed = Date().timeIntervalSince(lastReadDate)
        if !force, elapsed < 1 {
            guard scheduledRead == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.scheduledRead = nil
                self?.refresh(force: true)
            }
            scheduledRead = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (1 - elapsed), execute: work)
            return
        }

        guard !readInProgress else {
            needsAnotherRead = true
            return
        }

        scheduledRead?.cancel()
        scheduledRead = nil
        readInProgress = true
        lastReadDate = Date()
        let powerSource = currentPowerSource
        readQueue.async { [weak self] in
            let reading = Self.readStatus(for: powerSource)
            DispatchQueue.main.async {
                guard let self else { return }
                self.readInProgress = false
                self.status.currentMode = reading.mode
                self.status.capabilitiesKnown = true
                self.status.supportsLowPowerMode = reading.supportsLowPowerMode
                self.status.supportsHighPowerMode = reading.supportsHighPowerMode

                if self.needsAnotherRead {
                    self.needsAnotherRead = false
                    self.refresh()
                }
            }
        }
    }

    func select(_ mode: EnergyMode) {
        guard !status.isChanging else { return }
        guard status.currentMode != mode else { return }
        guard status.supportsLowPowerMode else {
            onError?(PowerModeControllerError.message(
                "Energy Mode is not available on this Mac."
            ))
            return
        }
        guard mode != .highPower || status.supportsHighPowerMode else {
            onError?(PowerModeControllerError.message(
                "High Power Mode is not available on this Mac."
            ))
            return
        }

        pendingMode = mode
        switch service.status {
        case .enabled:
            status.controlState = .ready
            applyPendingMode()

        case .notRegistered:
            registerService()

        case .requiresApproval:
            requestApproval()

        case .notFound:
            fail(PowerModeControllerError.message(
                "The Energy Mode helper is missing from this copy of StatusArc."
            ))

        @unknown default:
            fail(PowerModeControllerError.message(
                "macOS returned an unknown Energy Mode helper state."
            ))
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
        startApprovalMonitoring()
    }

    private func registerService() {
        status.isChanging = true

        do {
            try service.register()
            updateServiceState()

            if service.status == .enabled {
                applyPendingMode()
            } else {
                status.isChanging = false
                requestApproval()
            }
        } catch {
            updateServiceState()
            if service.status == .requiresApproval {
                status.isChanging = false
                requestApproval()
            } else {
                fail(error)
            }
        }
    }

    private func requestApproval() {
        status.controlState = .requiresApproval
        status.isChanging = false
        SMAppService.openSystemSettingsLoginItems()
        startApprovalMonitoring()
    }

    private func startApprovalMonitoring() {
        approvalTimer?.invalidate()
        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(checkApprovalStatus),
            userInfo: nil,
            repeats: true
        )
        approvalTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func checkApprovalStatus() {
        updateServiceState()
        guard service.status == .enabled else { return }

        approvalTimer?.invalidate()
        approvalTimer = nil
        prepareRunningHelperIfNeeded {
            self.applyPendingMode()
        }
    }

    private func updateServiceState() {
        switch service.status {
        case .enabled:
            status.controlState = .ready
        case .notRegistered:
            status.controlState = .notConfigured
        case .requiresApproval:
            status.controlState = .requiresApproval
        case .notFound:
            status.controlState = .unavailable(
                "The Energy Mode helper is missing from this copy of StatusArc."
            )
        @unknown default:
            status.controlState = .unavailable(
                "macOS returned an unknown Energy Mode helper state."
            )
        }
    }

    private func prepareRunningHelperIfNeeded(completion: (() -> Void)? = nil) {
        guard service.status == .enabled else {
            completion?()
            return
        }

        helperProxy { [weak self] proxy in
            guard let self else { return }
            proxy.helperVersion { [weak self] version in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if version == PowerModeService.implementationVersion {
                        self.helperRestartAttempts = 0
                        completion?()
                    } else {
                        self.restartOutdatedHelper(completion: completion)
                    }
                }
            }
        }
    }

    private func restartOutdatedHelper(completion: (() -> Void)?) {
        guard helperRestartAttempts < 2 else {
            fail(PowerModeControllerError.message(
                "StatusArc could not start the updated Energy Mode helper."
            ))
            return
        }

        helperRestartAttempts += 1
        helperProxy { [weak self] proxy in
            proxy.stopForUpdate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard let self else { return }
                    self.connection?.invalidate()
                    self.connection = nil
                    self.prepareRunningHelperIfNeeded(completion: completion)
                }
            }
        }
    }

    private func applyPendingMode() {
        guard let mode = pendingMode else { return }
        status.isChanging = true

        prepareRunningHelperIfNeeded { [weak self] in
            guard let self else { return }
            self.helperProxy { [weak self] proxy in
                guard let self else { return }
                proxy.setEnergyMode(
                    mode.rawValue,
                    for: self.currentPowerSource.rawValue
                ) { [weak self] succeeded, message in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.status.isChanging = false

                        if succeeded {
                            self.pendingMode = nil
                            self.status.currentMode = mode
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                self.refresh(force: true)
                            }
                        } else {
                            self.fail(PowerModeControllerError.message(
                                message ?? "macOS did not apply the selected Energy Mode."
                            ))
                        }
                    }
                }
            }
        }
    }

    private func helperProxy(
        completion: @escaping (PowerModeHelperProtocol) -> Void
    ) {
        do {
            let connection = try activeConnection()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
                DispatchQueue.main.async {
                    self?.connection?.invalidate()
                    self?.connection = nil
                    self?.fail(error)
                }
            }) as? PowerModeHelperProtocol else {
                throw PowerModeControllerError.message(
                    "StatusArc could not communicate with its Energy Mode helper."
                )
            }
            completion(proxy)
        } catch {
            fail(error)
        }
    }

    private func activeConnection() throws -> NSXPCConnection {
        if let connection {
            return connection
        }

        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/StatusArcPowerHelper")
        guard let helperRequirement = CodeSigningRequirement.forCode(at: helperURL) else {
            throw PowerModeControllerError.message(
                "StatusArc could not verify its Energy Mode helper."
            )
        }

        let connection = NSXPCConnection(
            machServiceName: PowerModeService.label,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: PowerModeHelperProtocol.self)
        connection.setCodeSigningRequirement(helperRequirement)
        connection.invalidationHandler = { [weak self, weak connection] in
            DispatchQueue.main.async {
                guard self?.connection === connection else { return }
                self?.connection = nil
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func fail(_ error: Error) {
        pendingMode = nil
        status.isChanging = false
        onError?(error)
    }

    private nonisolated static func readStatus(for powerSource: EnergyPowerSource) -> (
        mode: EnergyMode?,
        supportsLowPowerMode: Bool,
        supportsHighPowerMode: Bool
    ) {
        let capabilities = runPMSet(arguments: ["-g", "cap"]) ?? ""
        let profiles = runPMSet(arguments: ["-g", "custom"]) ?? ""
        let capabilityNames = Set(
            capabilities.split(whereSeparator: \Character.isWhitespace).map(String.init)
        )
        let values = profileValues(in: profiles, for: powerSource)
        let supportsLow = capabilityNames.contains("lowpowermode")
            || values["lowpowermode"] != nil
        let supportsHigh = capabilityNames.contains("highpowermode")
            || values["highpowermode"] != nil

        let mode: EnergyMode?
        if values["highpowermode"] == 1 {
            mode = .highPower
        } else if values["lowpowermode"] == 1 {
            mode = .lowPower
        } else if supportsLow {
            mode = .automatic
        } else {
            mode = nil
        }

        return (mode, supportsLow, supportsHigh)
    }

    private nonisolated static func profileValues(
        in output: String,
        for powerSource: EnergyPowerSource
    ) -> [String: Int] {
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
                  let currentHeading else {
                continue
            }
            profiles[currentHeading, default: [:]][String(parts[0])] = value
        }

        return profiles[requestedHeading] ?? profiles.values.first ?? [:]
    }

    private nonisolated static func runPMSet(arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

private enum PowerModeControllerError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}
