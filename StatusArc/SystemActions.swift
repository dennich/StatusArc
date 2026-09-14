import AppKit
import Carbon
import CoreLocation
import CoreWLAN
import SystemConfiguration

enum WiFiLocationAccess: Equatable {
    case notDetermined
    case allowed
    case denied
}

final class SystemActions: NSObject, CLLocationManagerDelegate {
    private let wifiClient = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()

    private var locationCompletion: (() -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Wi-Fi

    var wifiInterface: CWInterface? {
        wifiClient.interface()
    }

    var wifiPowerOn: Bool {
        wifiInterface?.powerOn() ?? false
    }

    var currentSSID: String? {
        guard let ssid = wifiInterface?.ssid(), !ssid.isEmpty else {
            return nil
        }
        return ssid
    }

    var locationAccess: WiFiLocationAccess {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return .notDetermined

        case .authorizedAlways, .authorizedWhenInUse:
            return .allowed

        case .denied, .restricted:
            return .denied

        @unknown default:
            return .denied
        }
    }

    func requestWiFiNameAccessIfNeeded(completion: @escaping () -> Void) {
        switch locationAccess {
        case .allowed, .denied:
            completion()

        case .notDetermined:
            locationCompletion = completion
            NSApp.activate(ignoringOtherApps: true)
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else {
            return
        }

        let completion = locationCompletion
        locationCompletion = nil
        completion?()
    }

    func setWiFiPower(_ enabled: Bool) throws {
        guard let interface = wifiInterface else {
            throw StatusArcActionError.message("No Wi-Fi interface was found.")
        }

        try interface.setPower(enabled)
    }

    func disconnectWiFi() {
        wifiInterface?.disassociate()
    }

    func cachedWiFiNetworks() -> [CWNetwork] {
        guard let networks = wifiInterface?.cachedScanResults() else {
            return []
        }

        return cleanAndSort(networks: Array(networks))
    }

    func scanWiFiNetworks(
        completion: @escaping (Result<[CWNetwork], Error>) -> Void
    ) {
        guard let interface = wifiInterface else {
            completion(.failure(StatusArcActionError.message("No Wi-Fi interface was found.")))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let found = try interface.scanForNetworks(withName: nil)
                let networks = self.cleanAndSort(networks: Array(found))

                DispatchQueue.main.async {
                    completion(.success(networks))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func findWiFiNetwork(
        named name: String,
        completion: @escaping (Result<CWNetwork?, Error>) -> Void
    ) {
        guard let interface = wifiInterface else {
            completion(.failure(StatusArcActionError.message("No Wi-Fi interface was found.")))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // A named scan is directed and can locate a network that isn't
                // present in the ordinary nearby-network list.
                let found = try interface.scanForNetworks(
                    withName: name,
                    includeHidden: true
                )
                let best = found.max { $0.rssiValue < $1.rssiValue }

                DispatchQueue.main.async {
                    completion(.success(best))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func connect(
        to network: CWNetwork,
        password: String?,
        completion: @escaping (Error?) -> Void
    ) {
        guard let interface = wifiInterface else {
            completion(StatusArcActionError.message("No Wi-Fi interface was found."))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result: Error?
            do {
                try interface.associate(to: network, password: password)
                result = nil
            } catch {
                result = error
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func savedUserPassword(for network: CWNetwork) -> String? {
        guard let ssidData = network.ssidData else {
            return nil
        }

        var password: NSString?

        guard CWKeychainFindWiFiPassword(.user, ssidData, &password) == noErr,
              let password else {
            return nil
        }

        return password as String
    }

    func isOpenNetwork(_ network: CWNetwork) -> Bool {
        network.supportsSecurity(.none)
    }

    func isEnterpriseNetwork(_ network: CWNetwork) -> Bool {
        network.supportsSecurity(.enterprise)
            || network.supportsSecurity(.wpaEnterprise)
            || network.supportsSecurity(.wpaEnterpriseMixed)
            || network.supportsSecurity(.wpa2Enterprise)
            || network.supportsSecurity(.wpa3Enterprise)
    }

    func knownWiFiNetworkNames() -> Set<String> {
        guard let profiles = wifiInterface?.configuration()?.networkProfiles else {
            return []
        }

        return Set(profiles.array.compactMap {
            ($0 as? CWNetworkProfile)?.ssid
        })
    }

    func wiFiConnectionDetails() -> [String] {
        guard let interface = wifiInterface, interface.powerOn() else {
            return ["Wi-Fi is off"]
        }

        var result: [String] = []

        if let ssid = interface.ssid(), !ssid.isEmpty {
            result.append("Network: \(ssid)")
        }

        if let bssid = interface.bssid(), !bssid.isEmpty {
            result.append("BSSID: \(bssid)")
        }

        let rssi = interface.rssiValue()
        if rssi < 0 {
            result.append("RSSI: \(rssi) dBm")
        }

        let noise = interface.noiseMeasurement()
        if noise < 0 {
            result.append("Noise: \(noise) dBm")
        }

        if let channel = interface.wlanChannel() {
            let band: String
            switch channel.channelBand {
            case .band2GHz: band = "2.4 GHz"
            case .band5GHz: band = "5 GHz"
            case .band6GHz: band = "6 GHz"
            default: band = "Unknown band"
            }
            result.append("Channel: \(channel.channelNumber) (\(band))")
        }

        let rate = interface.transmitRate()
        if rate > 0 {
            result.append(String(format: "Tx Rate: %.0f Mbps", rate))
        }

        if let country = interface.countryCode(), !country.isEmpty {
            result.append("Country: \(country)")
        }

        if let network = currentScannedNetwork(for: interface) {
            if let protocolName = protocolName(for: network) {
                result.append("Protocol: \(protocolName)")
            }
            result.append("Security: \(securityName(for: network))")
        }

        let addressing = networkAddressing(for: interface.interfaceName)
        for address in addressing.addresses {
            result.append("IP Address: \(address)")
        }
        if let router = addressing.router {
            result.append("Router: \(router)")
        }

        if let name = interface.interfaceName, !name.isEmpty {
            result.append("Interface: \(name)")
        }

        return result.isEmpty ? ["Wi-Fi connected"] : result
    }

    func signalStrength(for network: CWNetwork) -> Int {
        let rssi = network.rssiValue
        if rssi >= -60 { return 3 }
        if rssi >= -72 { return 2 }
        return rssi < 0 ? 1 : 0
    }

    private func currentScannedNetwork(for interface: CWInterface) -> CWNetwork? {
        let currentSSID = interface.ssid()
        let currentBSSID = interface.bssid()
        return interface.cachedScanResults()?.first(where: { network in
            if let currentBSSID, network.bssid == currentBSSID { return true }
            return network.ssid == currentSSID
        })
    }

    private func protocolName(for network: CWNetwork) -> String? {
        let modes: [(CWPHYMode, String)] = [
            (.mode11ax, "802.11ax"),
            (.mode11ac, "802.11ac"),
            (.mode11n, "802.11n"),
            (.mode11g, "802.11g"),
            (.mode11a, "802.11a"),
            (.mode11b, "802.11b")
        ]
        return modes.first(where: { network.supportsPHYMode($0.0) })?.1
    }

    private func securityName(for network: CWNetwork) -> String {
        if network.supportsSecurity(.wpa3Enterprise) { return "WPA3 Enterprise" }
        if network.supportsSecurity(.wpa3Personal) { return "WPA3 Personal" }
        if network.supportsSecurity(.wpa2Enterprise) { return "WPA2 Enterprise" }
        if network.supportsSecurity(.wpa2Personal) { return "WPA2 Personal" }
        if network.supportsSecurity(.wpaEnterprise) { return "WPA Enterprise" }
        if network.supportsSecurity(.wpaPersonal) { return "WPA Personal" }
        if network.supportsSecurity(.dynamicWEP) { return "Dynamic WEP" }
        if network.supportsSecurity(.WEP) { return "WEP" }
        if network.supportsSecurity(.none) { return "None" }
        return "Unknown"
    }

    private func networkAddressing(
        for interfaceName: String?
    ) -> (addresses: [String], router: String?) {
        guard let interfaceName,
              let store = SCDynamicStoreCreate(
                nil, "StatusArc.ConnectionDetails" as CFString, nil, nil
              ) else {
            return ([], nil)
        }

        var addresses: [String] = []
        var router: String?

        for family in ["IPv4", "IPv6"] {
            let key = "State:/Network/Interface/\(interfaceName)/\(family)"
            guard let values = SCDynamicStoreCopyValue(store, key as CFString)
                    as? [String: Any] else {
                continue
            }

            addresses.append(contentsOf: values["Addresses"] as? [String] ?? [])
            if router == nil {
                router = values["Router"] as? String
            }
        }

        return (addresses, router)
    }

    private func cleanAndSort(networks: [CWNetwork]) -> [CWNetwork] {
        // Keep the strongest BSSID for each visible SSID.
        var bestBySSID: [String: CWNetwork] = [:]

        for network in networks {
            guard let ssid = network.ssid, !ssid.isEmpty else {
                continue
            }

            if let existing = bestBySSID[ssid] {
                if network.rssiValue > existing.rssiValue {
                    bestBySSID[ssid] = network
                }
            } else {
                bestBySSID[ssid] = network
            }
        }

        return bestBySSID.values.sorted {
            if $0.rssiValue == $1.rssiValue {
                return ($0.ssid ?? "") < ($1.ssid ?? "")
            }
            return $0.rssiValue > $1.rssiValue
        }
    }

    // MARK: - Input Sources

    func enabledInputSources() -> [TISInputSource] {
        guard let unmanaged = TISCreateInputSourceList(nil, false) else {
            return []
        }

        let array = unmanaged.takeRetainedValue() as NSArray
        let sources = array as? [TISInputSource] ?? []

        return sources.filter { source in
            InputSourceIdentityResolver.boolProperty(
                source, key: kTISPropertyInputSourceIsSelectCapable
            )
                && InputSourceIdentityResolver.boolProperty(
                    source, key: kTISPropertyInputSourceIsEnabled
                )
                && InputSourceIdentityResolver.stringProperty(
                    source, key: kTISPropertyInputSourceCategory
                ) == kTISCategoryKeyboardInputSource as String
        }
    }

    func currentInputSourceID() -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return inputSourceID(source)
    }

    func inputSourceName(_ source: TISInputSource) -> String {
        InputSourceIdentityResolver.resolve(source).localizedName
    }

    func inputSourceID(_ source: TISInputSource) -> String? {
        InputSourceIdentityResolver.stringProperty(source, key: kTISPropertyInputSourceID)
    }

    func selectInputSource(_ source: TISInputSource) throws {
        let status = TISSelectInputSource(source)
        guard status == noErr else {
            throw StatusArcActionError.message(
                "macOS could not switch to that input source."
            )
        }
    }

    func keyboardViewerSource() -> TISInputSource? {
        let properties = [
            kTISPropertyInputSourceType as String: kTISTypeKeyboardViewer
        ] as CFDictionary

        guard let unmanaged = TISCreateInputSourceList(properties, true) else {
            return nil
        }

        let array = unmanaged.takeRetainedValue() as NSArray
        let sources = array as? [TISInputSource] ?? []

        return sources.first(where: {
            InputSourceIdentityResolver.boolProperty(
                $0,
                key: kTISPropertyInputSourceIsSelectCapable
            )
        })
    }

    func showKeyboardViewer() throws {
        guard let source = keyboardViewerSource() else {
            throw StatusArcActionError.message(
                "This macOS version does not expose Keyboard Viewer through the public Text Input Source API."
            )
        }

        if !InputSourceIdentityResolver.boolProperty(
            source,
            key: kTISPropertyInputSourceIsEnabled
        ) {
            let enableStatus = TISEnableInputSource(source)
            guard enableStatus == noErr else {
                throw StatusArcActionError.message(
                    "macOS could not enable Keyboard Viewer."
                )
            }
        }

        let selectStatus = TISSelectInputSource(source)
        guard selectStatus == noErr else {
            throw StatusArcActionError.message(
                "macOS could not show Keyboard Viewer."
            )
        }
    }

}

enum StatusArcActionError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text):
            return text
        }
    }
}
