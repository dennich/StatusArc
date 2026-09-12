import AppKit
import Carbon
import CoreLocation
import CoreWLAN

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
                let found = try interface.scanForNetworks(withName: name)
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

    func savedPassword(for network: CWNetwork) -> String? {
        guard let ssidData = network.ssidData else {
            return nil
        }

        var password: NSString?

        if CWKeychainFindWiFiPassword(.user, ssidData, &password) == noErr,
           let password {
            return password as String
        }

        password = nil

        if CWKeychainFindWiFiPassword(.system, ssidData, &password) == noErr,
           let password {
            return password as String
        }

        return nil
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
            result.append("Channel: \(channel.channelNumber)")
        }

        let rate = interface.transmitRate()
        if rate > 0 {
            result.append(String(format: "Tx Rate: %.0f Mbps", rate))
        }

        if let country = interface.countryCode(), !country.isEmpty {
            result.append("Country: \(country)")
        }

        if let name = interface.interfaceName, !name.isEmpty {
            result.append("Interface: \(name)")
        }

        return result.isEmpty ? ["Wi-Fi connected"] : result
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
            boolProperty(
                source,
                key: kTISPropertyInputSourceIsSelectCapable
            )
        }
    }

    func currentInputSourceID() -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return inputSourceID(source)
    }

    func inputSourceName(_ source: TISInputSource) -> String {
        stringProperty(source, key: kTISPropertyLocalizedName)
            ?? inputSourceID(source)
            ?? "Input Source"
    }

    func inputSourceID(_ source: TISInputSource) -> String? {
        stringProperty(source, key: kTISPropertyInputSourceID)
    }

    func selectInputSource(_ source: TISInputSource) throws {
        let status = TISSelectInputSource(source)
        guard status == noErr else {
            throw StatusArcActionError.message(
                "macOS could not switch to that input source."
            )
        }
    }

    private func stringProperty(
        _ source: TISInputSource,
        key: CFString
    ) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<CFString>
            .fromOpaque(pointer)
            .takeUnretainedValue() as String
    }

    private func boolProperty(
        _ source: TISInputSource,
        key: CFString
    ) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return false
        }

        let value = Unmanaged<CFBoolean>
            .fromOpaque(pointer)
            .takeUnretainedValue()

        return CFBooleanGetValue(value)
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
