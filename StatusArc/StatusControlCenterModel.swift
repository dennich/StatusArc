import Combine
import Foundation

enum StatusIsland: String, Hashable {
    case battery
    case connectivity
    case inputSource
}

struct StatusNetworkRow: Identifiable, Equatable {
    let id: Int
    let name: String
    let strength: Int
    let isSecured: Bool
    let isCurrent: Bool
    let isKnown: Bool
}

struct StatusInputSourceRow: Identifiable, Equatable {
    let id: Int
    let name: String
    let label: String
    let isCurrent: Bool
}

@MainActor
final class StatusControlCenterModel: ObservableObject {
    @Published var expandedIsland: StatusIsland?

    var requestIslandToggle: ((StatusIsland) -> Void)?

    @Published private(set) var batteryPercentage: Int?
    @Published private(set) var batteryState = "Not available"

    @Published private(set) var networkTitle = "Connectivity"
    @Published private(set) var networkDetail = "Disconnected"
    @Published private(set) var wifiOn = false
    @Published private(set) var wifiBusy = false
    @Published private(set) var currentSSID: String?
    @Published private(set) var networks: [StatusNetworkRow] = []

    @Published private(set) var inputSourceName = "Input Source"
    @Published private(set) var inputSourceLabel = "—"
    @Published private(set) var inputSources: [StatusInputSourceRow] = []
    @Published private(set) var keyboardViewerAvailable = false

    @Published private(set) var updateTitle = "Check for Updates…"

    var setWiFiPower: ((Bool) -> Void)?
    var disconnectWiFi: (() -> Void)?
    var scanNetworks: (() -> Void)?
    var connectNetwork: ((Int) -> Void)?
    var joinOtherNetwork: (() -> Void)?
    var selectInputSource: ((Int) -> Void)?
    var showEmojiAndSymbols: (() -> Void)?
    var showKeyboardViewer: (() -> Void)?
    var openWiFiSettings: (() -> Void)?
    var openNetworkSettings: (() -> Void)?
    var openWirelessDiagnostics: (() -> Void)?
    var openKeyboardSettings: (() -> Void)?
    var checkForUpdates: (() -> Void)?
    var quit: (() -> Void)?

    var panelHeight: CGFloat {
        switch expandedIsland {
        case .battery: return 286
        case .connectivity: return 620
        case .inputSource: return 560
        case nil: return 286
        }
    }

    func toggle(_ island: StatusIsland) {
        guard island != .battery else { return }
        if let requestIslandToggle {
            requestIslandToggle(island)
        } else {
            expandedIsland = expandedIsland == island ? nil : island
        }
    }

    func update(
        snapshot: StatusSnapshot,
        wifiOn: Bool,
        wifiBusy: Bool,
        currentSSID: String?,
        networks: [StatusNetworkRow],
        inputSources: [StatusInputSourceRow],
        keyboardViewerAvailable: Bool,
        availableUpdate: String?
    ) {
        if let battery = snapshot.battery {
            batteryPercentage = battery.displayedPercentage

            switch battery.powerState {
            case .onBattery: batteryState = "On Battery"
            case .charging: batteryState = "Charging"
            case .fullyCharged: batteryState = "Fully Charged"
            case .connectedNotCharging: batteryState = "On Hold"
            }

            if let minutes = battery.minutesRemaining {
                batteryState += " • " + Self.duration(minutes)
            }
        } else {
            batteryPercentage = nil
            batteryState = "Not available"
        }

        networkTitle = Self.networkTitle(for: snapshot.network)
        networkDetail = currentSSID ?? snapshot.network.description
        self.wifiOn = wifiOn
        self.wifiBusy = wifiBusy
        self.currentSSID = currentSSID
        self.networks = networks
        inputSourceName = snapshot.inputSourceName
        inputSourceLabel = snapshot.inputSourceLabel
        self.inputSources = inputSources
        self.keyboardViewerAvailable = keyboardViewerAvailable
        updateTitle = availableUpdate.map { "Update to \($0)…" } ?? "Check for Updates…"
    }

    private static func networkTitle(for status: NetworkStatus) -> String {
        switch status {
        case .wifi, .wifiDisconnected, .wifiOff: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .other: return "Network"
        case .disconnected: return "Connectivity"
        }
    }

    private static func duration(_ minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes)m"
    }
}
