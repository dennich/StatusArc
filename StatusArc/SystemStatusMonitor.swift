import AppKit
import Carbon
import CoreWLAN
import IOKit.ps
import Network
import SystemConfiguration

enum BatteryWarningLevel {
    case none
    case early
    case final

    init(systemLevel: IOPSLowBatteryWarningLevel) {
        switch systemLevel {
        case kIOPSLowBatteryWarningNone: self = .none
        case kIOPSLowBatteryWarningEarly: self = .early
        case kIOPSLowBatteryWarningFinal: self = .final
        default: self = .none
        }
    }
}

struct BatteryStatus {
    let level: Double
    let isCharging: Bool
    let isFullyCharged: Bool
    let isConnectedToExternalPower: Bool
    let isLowPowerModeEnabled: Bool
    let warningLevel: BatteryWarningLevel
    let powerSource: String
    let minutesRemaining: Int?

    enum PowerState {
        case onBattery
        case charging
        case fullyCharged
        case connectedNotCharging
    }

    var powerState: PowerState {
        if isCharging { return .charging }
        if isFullyCharged { return .fullyCharged }
        if isConnectedToExternalPower { return .connectedNotCharging }
        return .onBattery
    }

    var displayedPercentage: Int {
        Int((level * 100).rounded())
    }

    var isLowBattery: Bool {
        warningLevel != .none
    }
}

enum NetworkConnectivity: Equatable {
    case internet
    case localOnly
}

enum NetworkStatus {
    case wifi(strength: Int, rssi: Int?, connectivity: NetworkConnectivity)
    case wifiDisconnected
    case wifiOff
    case ethernet(interfaceName: String, connectivity: NetworkConnectivity)
    case other(interfaceName: String, connectivity: NetworkConnectivity)
    case disconnected

    var description: String {
        switch self {
        case .wifi(let strength, _, let connectivity):
            if connectivity == .localOnly {
                return "Wi‑Fi • No Internet Connection"
            }
            switch strength {
            case 3: return "Wi‑Fi • Strong"
            case 2: return "Wi‑Fi • Medium"
            case 1: return "Wi‑Fi • Weak"
            default: return "Wi‑Fi • Disconnected"
            }

        case .wifiDisconnected:
            return "Wi‑Fi • Disconnected"

        case .wifiOff:
            return "Wi‑Fi • Off"

        case .ethernet(let interfaceName, let connectivity):
            return connectivity == .internet
                ? "Ethernet • \(interfaceName)"
                : "Ethernet • No Internet Connection"

        case .other(let interfaceName, let connectivity):
            return connectivity == .internet
                ? "Network • \(interfaceName)"
                : "Network • \(interfaceName) • No Internet Connection"

        case .disconnected:
            return "Disconnected"
        }
    }
}

struct StatusSnapshot {
    let battery: BatteryStatus?
    let network: NetworkStatus
    let inputSourceLabel: String
    let inputSourceName: String

    var tooltip: String {
        let batteryText: String

        if let battery {
            let percent = battery.displayedPercentage
            switch battery.powerState {
            case .onBattery:
                batteryText = "Battery \(percent)%"
            case .charging:
                batteryText = "Battery \(percent)% • Charging"
            case .fullyCharged:
                batteryText = "Battery \(percent)% • Fully Charged"
            case .connectedNotCharging:
                batteryText = "Battery \(percent)% • Power Adapter"
            }
        } else {
            batteryText = "Battery unavailable"
        }

        return "\(batteryText) • \(network.description) • \(inputSourceName)"
    }
}

final class SystemStatusMonitor: NSObject, CWEventDelegate {
    private let wifiClient = CWWiFiClient.shared()
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "StatusArc.NetworkPath")
    private var onChange: (() -> Void)?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var networkDynamicStore: SCDynamicStore?
    private var refreshScheduled = false
    private var isMonitoring = false
    private var networkPathStatus: NWPath.Status = .requiresConnection

    func startMonitoring(onChange: @escaping () -> Void) {
        self.onChange = onChange
        guard !isMonitoring else { return }
        isMonitoring = true

        startPowerSourceMonitoring()
        startWiFiMonitoring()
        startNetworkRouteMonitoring()
        startNetworkPathMonitoring()
        startInputSourceMonitoring()

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(
            self,
            selector: #selector(observedSystemStateDidChange),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(observedSystemStateDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .commonModes)
        }
        powerSourceRunLoopSource = nil

        if let networkDynamicStore {
            SCDynamicStoreSetDispatchQueue(networkDynamicStore, nil)
        }
        networkDynamicStore = nil
        pathMonitor.cancel()

        _ = try? wifiClient.stopMonitoringAllEvents()
        wifiClient.delegate = nil

        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        onChange = nil
    }

    private func startPowerSourceMonitoring() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<SystemStatusMonitor>
                .fromOpaque(context)
                .takeUnretainedValue()
            monitor.systemStateDidChange()
        }, context)?.takeRetainedValue() else {
            return
        }

        powerSourceRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func startWiFiMonitoring() {
        wifiClient.delegate = self

        let events: [CWEventType] = [
            .powerDidChange,
            .ssidDidChange,
            .linkDidChange,
            .linkQualityDidChange,
            .scanCacheUpdated
        ]

        for event in events {
            _ = try? wifiClient.startMonitoringEvent(with: event)
        }
    }

    private func startNetworkRouteMonitoring() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let store = SCDynamicStoreCreate(
            nil,
            "StatusArc.NetworkMonitor" as CFString,
            { _, _, context in
                guard let context else { return }
                let monitor = Unmanaged<SystemStatusMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                monitor.systemStateDidChange()
            },
            &context
        ) else {
            return
        }

        let keys = [
            "State:/Network/Global/IPv4",
            "State:/Network/Global/IPv6"
        ] as CFArray

        guard SCDynamicStoreSetNotificationKeys(store, keys, nil),
              SCDynamicStoreSetDispatchQueue(store, .main) else {
            return
        }

        networkDynamicStore = store
    }

    private func startInputSourceMonitoring() {
        let notifications = DistributedNotificationCenter.default()
        notifications.addObserver(
            self,
            selector: #selector(observedSystemStateDidChange),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        notifications.addObserver(
            self,
            selector: #selector(observedSystemStateDidChange),
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil
        )
    }

    private func startNetworkPathMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                self.networkPathStatus = path.status
                self.systemStateDidChange()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    @objc private func observedSystemStateDidChange() {
        systemStateDidChange()
    }

    private func systemStateDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isMonitoring, !self.refreshScheduled else { return }
            self.refreshScheduled = true

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshScheduled = false
                self.onChange?()
            }
        }
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        systemStateDidChange()
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        systemStateDidChange()
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        systemStateDidChange()
    }

    func linkQualityDidChangeForWiFiInterface(
        withName interfaceName: String,
        rssi: Int,
        transmitRate: Double
    ) {
        systemStateDidChange()
    }

    func scanCacheUpdatedForWiFiInterface(withName interfaceName: String) {
        systemStateDidChange()
    }

    func snapshot() -> StatusSnapshot {
        let inputSource = readInputSource()
        return StatusSnapshot(
            battery: readBattery(),
            network: readNetworkStatus(),
            inputSourceLabel: inputSource.compactLabel,
            inputSourceName: inputSource.localizedName
        )
    }

    private func readBattery() -> BatteryStatus? {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
                maximum > 0
            else {
                continue
            }

            let rawLevel = Double(current) / Double(maximum)
            let level = min(max(rawLevel, 0.0), 1.0)
            let isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
            let isFullyCharged = description[kIOPSIsChargedKey as String] as? Bool ?? false
            let isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

            let warningLevel = BatteryWarningLevel(systemLevel: IOPSGetBatteryWarningLevel())

            let powerSourceState = description[kIOPSPowerSourceStateKey as String] as? String
            let isConnectedToExternalPower = powerSourceState == kIOPSACPowerValue
            let powerSource = isConnectedToExternalPower
                ? "Power Adapter"
                : "Battery"

            let timeKey = isCharging
                ? kIOPSTimeToFullChargeKey as String
                : kIOPSTimeToEmptyKey as String

            let rawMinutes = description[timeKey] as? Int
            let minutesRemaining = (rawMinutes ?? 0) > 0 ? rawMinutes : nil

            return BatteryStatus(
                level: level,
                isCharging: isCharging,
                isFullyCharged: isFullyCharged,
                isConnectedToExternalPower: isConnectedToExternalPower,
                isLowPowerModeEnabled: isLowPowerModeEnabled,
                warningLevel: warningLevel,
                powerSource: powerSource,
                minutesRemaining: minutesRemaining
            )
        }

        return nil
    }

    private func readNetworkStatus() -> NetworkStatus {
        let connectivity: NetworkConnectivity = networkPathStatus == .satisfied
            ? .internet
            : .localOnly
        let wifiInterfaces = wifiClient.interfaces() ?? []
        let wifiNames = Set(wifiInterfaces.compactMap(\.interfaceName))
        let defaultWiFi = wifiClient.interface()

        guard let primaryInterface = readPrimaryInterfaceName(wifiNames: wifiNames) else {
            guard let defaultWiFi else { return .disconnected }
            if defaultWiFi.powerOn(), defaultWiFi.rssiValue() < 0 {
                return .wifi(
                    strength: strength(for: defaultWiFi.rssiValue()),
                    rssi: defaultWiFi.rssiValue(),
                    connectivity: .localOnly
                )
            }
            return defaultWiFi.powerOn() ? .wifiDisconnected : .wifiOff
        }

        if wifiNames.contains(primaryInterface),
           let wifiInterface = wifiInterfaces.first(where: {
               $0.interfaceName == primaryInterface
           }) {

            guard wifiInterface.powerOn() else {
                return .wifiOff
            }

            let rssi = wifiInterface.rssiValue()

            // CoreWLAN normally returns a negative RSSI while associated.
            guard rssi < 0 else {
                return .wifi(
                    strength: 0,
                    rssi: nil,
                    connectivity: connectivity
                )
            }

            return .wifi(
                strength: strength(for: rssi),
                rssi: rssi,
                connectivity: connectivity
            )
        }

        if isEthernetLike(primaryInterface, wifiNames: wifiNames) {
            return .ethernet(
                interfaceName: primaryInterface,
                connectivity: connectivity
            )
        }

        // Covers interfaces such as VPN/tunnel adapters. The renderer uses a
        // neutral disconnected-style indicator instead of claiming Ethernet.
        return .other(
            interfaceName: primaryInterface,
            connectivity: connectivity
        )
    }

    private func strength(for rssi: Int) -> Int {
        if rssi >= -60 { return 3 }
        if rssi >= -72 { return 2 }
        return 1
    }

    private func readPrimaryInterfaceName(wifiNames: Set<String>) -> String? {
        guard let store = SCDynamicStoreCreate(
            nil,
            "StatusArc" as CFString,
            nil,
            nil
        ) else {
            return nil
        }

        let globalNetworkKeys = [
            "State:/Network/Global/IPv4",
            "State:/Network/Global/IPv6"
        ]

        var routedInterface: String?
        for key in globalNetworkKeys {
            guard
                let value = SCDynamicStoreCopyValue(store, key as CFString)
                    as? [String: Any],
                let interfaceName = value["PrimaryInterface"] as? String,
                !interfaceName.isEmpty
            else {
                continue
            }

            routedInterface = interfaceName
            break
        }

        if let routedInterface,
           wifiNames.contains(routedInterface)
            || isEthernetLike(routedInterface, wifiNames: wifiNames) {
            return routedInterface
        }

        // A VPN or tunnel can own the default route even though Wi-Fi or
        // Ethernet remains the physical link carrying it. Use macOS's service
        // order to select the first active physical interface in that case.
        return readActivePhysicalInterfaceName(from: store, wifiNames: wifiNames)
            ?? routedInterface
    }

    private func readActivePhysicalInterfaceName(
        from store: SCDynamicStore,
        wifiNames: Set<String>
    ) -> String? {
        guard
            let globalSetup = SCDynamicStoreCopyValue(
                store,
                "Setup:/Network/Global/IPv4" as CFString
            ) as? [String: Any],
            let serviceOrder = globalSetup["ServiceOrder"] as? [String]
        else {
            return nil
        }

        for serviceID in serviceOrder {
            let interfaceKey = "Setup:/Network/Service/\(serviceID)/Interface"
            guard
                let interface = SCDynamicStoreCopyValue(store, interfaceKey as CFString)
                    as? [String: Any],
                let interfaceName = interface["DeviceName"] as? String,
                wifiNames.contains(interfaceName)
                    || isEthernetLike(interfaceName, wifiNames: wifiNames)
            else {
                continue
            }

            let addressFamilies = ["IPv4", "IPv6"]
            let hasAddress = addressFamilies.contains { family in
                let stateKey = "State:/Network/Service/\(serviceID)/\(family)"
                guard
                    let state = SCDynamicStoreCopyValue(store, stateKey as CFString)
                        as? [String: Any],
                    let addresses = state["Addresses"] as? [String]
                else {
                    return false
                }
                return !addresses.isEmpty
            }

            if hasAddress {
                return interfaceName
            }
        }

        return nil
    }

    private func isEthernetLike(
        _ interfaceName: String,
        wifiNames: Set<String>
    ) -> Bool {
        guard !wifiNames.contains(interfaceName) else { return false }

        return interfaceName.hasPrefix("en")
            || interfaceName.hasPrefix("bridge")
            || interfaceName.hasPrefix("bond")
    }

    private func readInputSource() -> InputSourceIdentity {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return InputSourceIdentityResolver.resolve(source)
    }
}
