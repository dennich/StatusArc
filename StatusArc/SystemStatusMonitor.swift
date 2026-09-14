import AppKit
import Carbon
import CoreWLAN
import IOKit.ps
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
    let isLowPowerModeEnabled: Bool
    let warningLevel: BatteryWarningLevel
    let powerSource: String
    let minutesRemaining: Int?

    var displayedPercentage: Int {
        Int((level * 100).rounded())
    }

    var isLowBattery: Bool {
        warningLevel != .none
    }
}

enum NetworkStatus {
    case wifi(strength: Int, rssi: Int?)
    case ethernet(interfaceName: String)
    case other(interfaceName: String)
    case disconnected

    var description: String {
        switch self {
        case .wifi(let strength, _):
            switch strength {
            case 3: return "Wi‑Fi • Strong"
            case 2: return "Wi‑Fi • Medium"
            case 1: return "Wi‑Fi • Weak"
            default: return "Wi‑Fi • Disconnected"
            }

        case .ethernet(let interfaceName):
            return "Ethernet • \(interfaceName)"

        case .other(let interfaceName):
            return "Network • \(interfaceName)"

        case .disconnected:
            return "Disconnected"
        }
    }
}

struct StatusSnapshot {
    let battery: BatteryStatus?
    let network: NetworkStatus
    let languageCode: String

    var tooltip: String {
        let batteryText: String

        if let battery {
            let percent = battery.displayedPercentage
            batteryText = battery.isCharging
                ? "Battery \(percent)% • Charging"
                : "Battery \(percent)%"
        } else {
            batteryText = "Battery unavailable"
        }

        return "\(batteryText) • \(network.description) • \(languageCode)"
    }
}

final class SystemStatusMonitor: NSObject, CWEventDelegate {
    private let wifiClient = CWWiFiClient.shared()
    private var onChange: (() -> Void)?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var networkDynamicStore: SCDynamicStore?
    private var refreshScheduled = false
    private var isMonitoring = false

    func startMonitoring(onChange: @escaping () -> Void) {
        self.onChange = onChange
        guard !isMonitoring else { return }
        isMonitoring = true

        startPowerSourceMonitoring()
        startWiFiMonitoring()
        startNetworkRouteMonitoring()
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
        StatusSnapshot(
            battery: readBattery(),
            network: readNetworkStatus(),
            languageCode: readLanguageCode()
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
            let powerSource = powerSourceState == kIOPSACPowerValue
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
                isLowPowerModeEnabled: isLowPowerModeEnabled,
                warningLevel: warningLevel,
                powerSource: powerSource,
                minutesRemaining: minutesRemaining
            )
        }

        return nil
    }

    private func readNetworkStatus() -> NetworkStatus {
        guard let primaryInterface = readPrimaryInterfaceName() else {
            return .disconnected
        }

        if let wifiInterface = wifiClient.interface(),
           let wifiName = wifiInterface.interfaceName,
           primaryInterface == wifiName {

            guard wifiInterface.powerOn() else {
                return .disconnected
            }

            let rssi = wifiInterface.rssiValue()

            // CoreWLAN normally returns a negative RSSI while associated.
            guard rssi < 0 else {
                return .wifi(strength: 0, rssi: nil)
            }

            let strength: Int
            if rssi >= -60 {
                strength = 3
            } else if rssi >= -72 {
                strength = 2
            } else {
                strength = 1
            }

            return .wifi(strength: strength, rssi: rssi)
        }

        if isEthernetLike(primaryInterface) {
            return .ethernet(interfaceName: primaryInterface)
        }

        // Covers interfaces such as VPN/tunnel adapters. The renderer uses
        // the same solid line because the active path is non-Wi‑Fi.
        return .other(interfaceName: primaryInterface)
    }

    private func readPrimaryInterfaceName() -> String? {
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

        for key in globalNetworkKeys {
            guard
                let value = SCDynamicStoreCopyValue(store, key as CFString)
                    as? [String: Any],
                let interfaceName = value["PrimaryInterface"] as? String,
                !interfaceName.isEmpty
            else {
                continue
            }

            return interfaceName
        }

        return nil
    }

    private func isEthernetLike(_ interfaceName: String) -> Bool {
        interfaceName.hasPrefix("en")
            || interfaceName.hasPrefix("bridge")
            || interfaceName.hasPrefix("bond")
    }

    private func readLanguageCode() -> String {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()

        if let pointer = TISGetInputSourceProperty(
            source,
            kTISPropertyInputSourceLanguages
        ) {
            let languages = Unmanaged<CFArray>
                .fromOpaque(pointer)
                .takeUnretainedValue() as? [String]

            if let language = languages?.first {
                return displayCode(for: language)
            }
        }

        if let pointer = TISGetInputSourceProperty(
            source,
            kTISPropertyLocalizedName
        ) {
            let name = Unmanaged<CFString>
                .fromOpaque(pointer)
                .takeUnretainedValue() as String

            return fallbackCode(from: name)
        }

        return "—"
    }

    private func displayCode(for identifier: String) -> String {
        let normalized = identifier.lowercased()

        // User-facing code. Ukrainian is intentionally shown as UA
        // rather than ISO language code "UK", matching the requested UI.
        if normalized.hasPrefix("uk") { return "UA" }
        if normalized.hasPrefix("en") { return "EN" }

        let pieces = normalized.split(whereSeparator: { $0 == "-" || $0 == "_" })
        if let first = pieces.first, first.count >= 2 {
            return String(first.prefix(2)).uppercased()
        }

        return String(normalized.prefix(2)).uppercased()
    }

    private func fallbackCode(from name: String) -> String {
        let upper = name.uppercased()

        if upper.contains("UKRAIN") { return "UA" }
        if upper.contains("ENGLISH") || upper.contains("U.S.") || upper == "ABC" {
            return "EN"
        }

        let letters = upper.filter(\.isLetter)
        if letters.count >= 2 {
            return String(letters.prefix(2))
        }

        return "—"
    }
}
