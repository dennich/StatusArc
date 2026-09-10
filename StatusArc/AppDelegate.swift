import AppKit
import Carbon
import CoreWLAN

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 32)
    private let monitor = SystemStatusMonitor()
    private let actions = SystemActions()
    private let renderer = StatusIconRenderer(size: NSSize(width: 30, height: 22))

    private var timer: Timer?
    private var inputSources: [TISInputSource] = []
    private var scannedNetworks: [CWNetwork] = []
    private var isScanningNetworks = false

    private let batteryItem = NSMenuItem(title: "Battery", action: nil, keyEquivalent: "")
    private let batteryPowerItem = NSMenuItem(title: "Power Source", action: nil, keyEquivalent: "")

    private let networkItem = NSMenuItem(title: "Network", action: nil, keyEquivalent: "")
    private let wifiToggleItem = NSMenuItem(title: "Wi-Fi", action: nil, keyEquivalent: "")
    private let disconnectWiFiItem = NSMenuItem(title: "Disconnect Wi-Fi", action: nil, keyEquivalent: "")
    private let wifiNetworksItem = NSMenuItem(title: "Wi-Fi Networks", action: nil, keyEquivalent: "")
    private let wifiNetworksMenu = NSMenu(title: "Wi-Fi Networks")
    private let wifiDetailsItem = NSMenuItem(title: "Connection Details", action: nil, keyEquivalent: "")
    private let wifiDetailsMenu = NSMenu(title: "Connection Details")

    private let inputItem = NSMenuItem(title: "Input", action: nil, keyEquivalent: "")
    private let inputSourcesItem = NSMenuItem(title: "Input Sources", action: nil, keyEquivalent: "")
    private let inputSourcesMenu = NSMenu(title: "Input Sources")

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureMenu()
        refresh()

        timer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    // MARK: - Setup

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.toolTip = "StatusArc"
        }
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.delegate = self

        batteryItem.isEnabled = false
        batteryPowerItem.isEnabled = false
        networkItem.isEnabled = false
        inputItem.isEnabled = false

        // Battery — mirrors the actionable part of Apple's Battery menu.
        menu.addItem(sectionItem("Battery"))
        menu.addItem(batteryItem)
        menu.addItem(batteryPowerItem)

        let batterySettings = actionItem(
            "Battery Settings…",
            #selector(openBatterySettings)
        )
        menu.addItem(batterySettings)

        menu.addItem(.separator())

        // Network / Wi-Fi.
        menu.addItem(sectionItem("Network"))
        menu.addItem(networkItem)

        wifiToggleItem.target = self
        wifiToggleItem.action = #selector(toggleWiFi)
        menu.addItem(wifiToggleItem)

        disconnectWiFiItem.target = self
        disconnectWiFiItem.action = #selector(disconnectWiFi)
        menu.addItem(disconnectWiFiItem)

        wifiNetworksItem.submenu = wifiNetworksMenu
        menu.addItem(wifiNetworksItem)

        wifiDetailsItem.submenu = wifiDetailsMenu
        menu.addItem(wifiDetailsItem)

        menu.addItem(actionItem(
            "Network Settings…",
            #selector(openNetworkSettings)
        ))

        menu.addItem(.separator())

        // Input menu.
        menu.addItem(sectionItem("Input"))
        menu.addItem(inputItem)

        inputSourcesItem.submenu = inputSourcesMenu
        menu.addItem(inputSourcesItem)

        menu.addItem(actionItem(
            "Emoji & Symbols…",
            #selector(showEmojiAndSymbols)
        ))

        menu.addItem(actionItem(
            "Keyboard Viewer…",
            #selector(showKeyboardViewer)
        ))

        menu.addItem(actionItem(
            "Keyboard Settings…",
            #selector(openKeyboardSettings)
        ))

        menu.addItem(.separator())

        let quitItem = actionItem(
            "Quit StatusArc",
            #selector(quit),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func sectionItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: attributes
        )

        return item
    }

    private func actionItem(
        _ title: String,
        _ selector: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: selector,
            keyEquivalent: keyEquivalent
        )
        item.target = self
        return item
    }

    // MARK: - Menu lifecycle

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        rebuildInputSourcesMenu()
        rebuildWiFiDetailsMenu()
        rebuildWiFiNetworksMenu(using: actions.cachedWiFiNetworks())

        // Once Location access has been granted, behave more like Apple's
        // Wi-Fi menu and refresh the nearby list automatically.
        if actions.locationAccess == .allowed && actions.wifiPowerOn {
            scanNearbyNetworks(requestPermission: false, showErrors: false)
        }
    }

    @objc private func refreshTimerFired() {
        refresh()
    }

    // MARK: - Status refresh

    private func refresh() {
        let snapshot = monitor.snapshot()

        statusItem.button?.image = renderer.render(snapshot: snapshot)
        statusItem.button?.toolTip = snapshot.tooltip

        updateBatteryMenu(snapshot)
        updateNetworkMenu(snapshot)
        updateInputMenu(snapshot)
    }

    private func updateBatteryMenu(_ snapshot: StatusSnapshot) {
        if let battery = snapshot.battery {
            let percent = Int((battery.level * 100).rounded())

            var stateText: String
            if battery.isFullyCharged {
                stateText = "Fully Charged"
            } else if battery.isCharging {
                stateText = "Charging"
            } else {
                stateText = "Battery"
            }

            if let minutes = battery.minutesRemaining {
                stateText += " • \(formattedDuration(minutes))"
            }

            batteryItem.title = "Battery: \(percent)% • \(stateText)"
            batteryPowerItem.title = "Power Source: \(battery.powerSource)"
        } else {
            batteryItem.title = "Battery: Not available"
            batteryPowerItem.title = "Power Source: —"
        }
    }

    private func updateNetworkMenu(_ snapshot: StatusSnapshot) {
        switch snapshot.network {
        case .wifi(let strength, let rssi):
            let label: String
            switch strength {
            case 3: label = "Strong"
            case 2: label = "Medium"
            case 1: label = "Weak"
            default: label = "Disconnected"
            }

            let ssidText = actions.currentSSID.map { " • \($0)" } ?? ""

            if let rssi, strength > 0 {
                networkItem.title = "Network: Wi-Fi\(ssidText) • \(label) (\(rssi) dBm)"
            } else {
                networkItem.title = "Network: Wi-Fi\(ssidText) • \(label)"
            }

        case .ethernet(let interfaceName):
            networkItem.title = "Network: Ethernet • \(interfaceName)"

        case .other(let interfaceName):
            networkItem.title = "Network: \(interfaceName)"

        case .disconnected:
            networkItem.title = "Network: Disconnected"
        }

        wifiToggleItem.title = actions.wifiPowerOn ? "Wi-Fi: On" : "Wi-Fi: Off"
        wifiToggleItem.state = actions.wifiPowerOn ? .on : .off

        let hasWiFiAssociation = actions.wifiPowerOn
            && (actions.currentSSID != nil || (actions.wifiInterface?.rssiValue() ?? 0) < 0)

        disconnectWiFiItem.isHidden = !hasWiFiAssociation
        if let ssid = actions.currentSSID {
            disconnectWiFiItem.title = "Disconnect from “\(ssid)”"
        } else {
            disconnectWiFiItem.title = "Disconnect Wi-Fi"
        }

        wifiNetworksItem.isEnabled = actions.wifiPowerOn
        wifiDetailsItem.isEnabled = actions.wifiPowerOn
    }

    private func updateInputMenu(_ snapshot: StatusSnapshot) {
        inputItem.title = "Input: \(snapshot.languageCode)"
    }

    private func formattedDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours > 0 && remainder > 0 {
            return "\(hours)h \(remainder)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(remainder)m"
        }
    }

    // MARK: - Wi-Fi controls

    @objc private func toggleWiFi() {
        do {
            try actions.setWiFiPower(!actions.wifiPowerOn)
            refresh()
            rebuildWiFiNetworksMenu(using: [])
        } catch {
            showError(error, title: "Couldn’t Change Wi-Fi")
        }
    }

    @objc private func disconnectWiFi() {
        actions.disconnectWiFi()
        refresh()
    }

    private func rebuildWiFiNetworksMenu(using networks: [CWNetwork]) {
        if !networks.isEmpty {
            scannedNetworks = networks
        }

        wifiNetworksMenu.removeAllItems()

        if !actions.wifiPowerOn {
            let item = NSMenuItem(title: "Wi-Fi is off", action: nil, keyEquivalent: "")
            item.isEnabled = false
            wifiNetworksMenu.addItem(item)
            return
        }

        if isScanningNetworks {
            let scanning = NSMenuItem(title: "Scanning…", action: nil, keyEquivalent: "")
            scanning.isEnabled = false
            wifiNetworksMenu.addItem(scanning)
        } else if scannedNetworks.isEmpty {
            let empty: NSMenuItem

            switch actions.locationAccess {
            case .notDetermined:
                empty = NSMenuItem(
                    title: "Scan Nearby Networks…",
                    action: #selector(scanNetworksWithPermission),
                    keyEquivalent: ""
                )
                empty.target = self

            case .denied:
                empty = NSMenuItem(
                    title: "Location Access Needed for Network Names",
                    action: nil,
                    keyEquivalent: ""
                )
                empty.isEnabled = false

            case .allowed:
                empty = NSMenuItem(
                    title: "No Nearby Networks Found",
                    action: nil,
                    keyEquivalent: ""
                )
                empty.isEnabled = false
            }

            wifiNetworksMenu.addItem(empty)
        } else {
            let currentSSID = actions.currentSSID

            for (index, network) in scannedNetworks.prefix(15).enumerated() {
                guard let ssid = network.ssid, !ssid.isEmpty else {
                    continue
                }

                let item = NSMenuItem(
                    title: ssid,
                    action: #selector(connectToWiFiNetwork(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index

                if ssid == currentSSID {
                    item.state = .on
                }

                if !actions.isOpenNetwork(network) {
                    item.image = NSImage(
                        systemSymbolName: "lock.fill",
                        accessibilityDescription: "Secured network"
                    )
                }

                wifiNetworksMenu.addItem(item)
            }
        }

        wifiNetworksMenu.addItem(.separator())

        let refreshNetworks = NSMenuItem(
            title: isScanningNetworks ? "Scanning…" : "Refresh Nearby Networks",
            action: #selector(scanNetworksWithPermission),
            keyEquivalent: "r"
        )
        refreshNetworks.target = self
        refreshNetworks.isEnabled = !isScanningNetworks
        wifiNetworksMenu.addItem(refreshNetworks)

        let otherNetwork = NSMenuItem(
            title: "Other Network…",
            action: #selector(joinOtherNetwork),
            keyEquivalent: ""
        )
        otherNetwork.target = self
        wifiNetworksMenu.addItem(otherNetwork)

        if actions.locationAccess == .denied {
            wifiNetworksMenu.addItem(.separator())

            let privacy = NSMenuItem(
                title: "Open Location Privacy Settings…",
                action: #selector(openLocationPrivacySettings),
                keyEquivalent: ""
            )
            privacy.target = self
            wifiNetworksMenu.addItem(privacy)
        }
    }

    @objc private func scanNetworksWithPermission() {
        scanNearbyNetworks(requestPermission: true, showErrors: true)
    }

    private func scanNearbyNetworks(
        requestPermission: Bool,
        showErrors: Bool
    ) {
        guard !isScanningNetworks, actions.wifiPowerOn else {
            return
        }

        let beginScan = { [weak self] in
            guard let self else { return }

            if self.actions.locationAccess == .denied {
                self.rebuildWiFiNetworksMenu(using: [])
                if showErrors {
                    self.showMessage(
                        title: "Location Access Is Required",
                        message: "macOS requires Location access before an app can read Wi-Fi network names. StatusArc only uses it to display nearby SSIDs."
                    )
                }
                return
            }

            self.isScanningNetworks = true
            self.rebuildWiFiNetworksMenu(using: [])

            self.actions.scanWiFiNetworks { [weak self] result in
                guard let self else { return }

                self.isScanningNetworks = false

                switch result {
                case .success(let networks):
                    self.scannedNetworks = networks
                    self.rebuildWiFiNetworksMenu(using: networks)

                case .failure(let error):
                    self.rebuildWiFiNetworksMenu(using: [])
                    if showErrors {
                        self.showError(error, title: "Wi-Fi Scan Failed")
                    }
                }
            }
        }

        if requestPermission {
            actions.requestWiFiNameAccessIfNeeded(completion: beginScan)
        } else {
            beginScan()
        }
    }

    @objc private func connectToWiFiNetwork(_ sender: NSMenuItem) {
        guard scannedNetworks.indices.contains(sender.tag) else {
            return
        }

        let network = scannedNetworks[sender.tag]

        if actions.isEnterpriseNetwork(network) {
            showMessage(
                title: "Enterprise Wi-Fi",
                message: "Enterprise/802.1X networks need credentials and certificates managed by macOS. Opening Wi-Fi Settings is the safest equivalent."
            )
            openWiFiSettings()
            return
        }

        var password: String?

        if !actions.isOpenNetwork(network) {
            password = actions.savedPassword(for: network)

            if password == nil {
                guard let ssid = network.ssid else { return }
                password = askForPassword(networkName: ssid)
                if password == nil {
                    return
                }
            }
        }

        do {
            try actions.connect(to: network, password: password)
            refresh()
        } catch {
            showError(error, title: "Couldn’t Join Wi-Fi Network")
        }
    }

    @objc private func joinOtherNetwork() {
        let alert = NSAlert()
        alert.messageText = "Join Other Wi-Fi Network"
        alert.informativeText = "Enter a hidden or unlisted network name. Leave the password blank for an open network."
        alert.addButton(withTitle: "Join")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 58))

        let nameField = NSTextField(frame: NSRect(x: 0, y: 32, width: 300, height: 24))
        nameField.placeholderString = "Network name (SSID)"

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 2, width: 300, height: 24))
        passwordField.placeholderString = "Password (optional)"

        container.addSubview(nameField)
        container.addSubview(passwordField)
        alert.accessoryView = container

        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }

        let suppliedPassword = passwordField.stringValue.isEmpty
            ? nil
            : passwordField.stringValue

        actions.requestWiFiNameAccessIfNeeded { [weak self] in
            guard let self else { return }

            self.isScanningNetworks = true
            self.actions.findWiFiNetwork(named: name) { [weak self] result in
                guard let self else { return }
                self.isScanningNetworks = false

                switch result {
                case .success(let network):
                    guard let network else {
                        self.showMessage(
                            title: "Network Not Found",
                            message: "StatusArc couldn’t find “\(name)”. For enterprise/802.1X networks, use Wi-Fi Settings."
                        )
                        return
                    }

                    if self.actions.isEnterpriseNetwork(network) {
                        self.showMessage(
                            title: "Enterprise Wi-Fi",
                            message: "Enterprise/802.1X networks need credentials and certificates managed by macOS. Opening Wi-Fi Settings is the safest equivalent."
                        )
                        self.openWiFiSettings()
                        return
                    }

                    var password = suppliedPassword
                    if !self.actions.isOpenNetwork(network), password == nil {
                        password = self.actions.savedPassword(for: network)
                            ?? self.askForPassword(networkName: name)
                    }

                    do {
                        try self.actions.connect(to: network, password: password)
                        self.refresh()
                    } catch {
                        self.showError(error, title: "Couldn’t Join Wi-Fi Network")
                    }

                case .failure(let error):
                    self.showError(error, title: "Wi-Fi Scan Failed")
                }
            }
        }
    }

    private func askForPassword(networkName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Password for “\(networkName)”"
        alert.informativeText = "Enter the Wi-Fi password."
        alert.addButton(withTitle: "Join")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(
            frame: NSRect(x: 0, y: 0, width: 280, height: 24)
        )
        field.placeholderString = "Password"
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return field.stringValue
    }

    private func rebuildWiFiDetailsMenu() {
        wifiDetailsMenu.removeAllItems()

        let details = actions.wiFiConnectionDetails()
        for detail in details {
            let item = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
            item.isEnabled = false
            wifiDetailsMenu.addItem(item)
        }

        wifiDetailsMenu.addItem(.separator())

        let diagnostics = NSMenuItem(
            title: "Open Wireless Diagnostics…",
            action: #selector(openWirelessDiagnostics),
            keyEquivalent: ""
        )
        diagnostics.target = self
        wifiDetailsMenu.addItem(diagnostics)
    }

    // MARK: - Input source controls

    private func rebuildInputSourcesMenu() {
        inputSourcesMenu.removeAllItems()
        inputSources = actions.enabledInputSources()

        let currentID = actions.currentInputSourceID()

        for (index, source) in inputSources.enumerated() {
            let item = NSMenuItem(
                title: actions.inputSourceName(source),
                action: #selector(selectInputSource(_:)),
                keyEquivalent: ""
            )

            item.target = self
            item.tag = index

            if actions.inputSourceID(source) == currentID {
                item.state = .on
            }

            inputSourcesMenu.addItem(item)
        }

        if inputSources.isEmpty {
            let empty = NSMenuItem(
                title: "No selectable input sources",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            inputSourcesMenu.addItem(empty)
        }
    }

    @objc private func selectInputSource(_ sender: NSMenuItem) {
        guard inputSources.indices.contains(sender.tag) else {
            return
        }

        do {
            try actions.selectInputSource(inputSources[sender.tag])
            refresh()
        } catch {
            showError(error, title: "Couldn’t Change Input Source")
        }
    }

    @objc private func showEmojiAndSymbols() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontCharacterPalette(nil)
    }

    @objc private func showKeyboardViewer() {
        // Apple does not provide a public API for directly opening Keyboard
        // Viewer. Its own Input menu calls a private TextInputMenuAgent action.
        // Avoiding Accessibility/UI scripting keeps StatusArc permission-light
        // and reliable, so take the user to the exact setting instead.
        showMessage(
            title: "Keyboard Viewer",
            message: "macOS doesn’t expose a public API for opening Keyboard Viewer directly. StatusArc can switch input sources and open Emoji & Symbols itself; Keyboard Viewer still has to be enabled from Apple’s Input menu."
        )
        openKeyboardSettings()
    }

    // MARK: - System destinations

    @objc private func openNetworkSettings() {
        openSettings(
            deepLink: "x-apple.systempreferences:com.apple.Network-Settings.extension"
        )
    }

    private func openWiFiSettings() {
        openSettings(
            deepLink: "x-apple.systempreferences:com.apple.wifi-settings-extension"
        )
    }

    @objc private func openKeyboardSettings() {
        openSettings(
            deepLink: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources"
        )
    }

    @objc private func openBatterySettings() {
        openSettings(
            deepLink: "x-apple.systempreferences:com.apple.Battery-Settings.extension"
        )
    }

    @objc private func openLocationPrivacySettings() {
        openSettings(
            deepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        )
    }

    @objc private func openWirelessDiagnostics() {
        let path = "/System/Library/CoreServices/Applications/Wireless Diagnostics.app"
        let url = URL(fileURLWithPath: path)

        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(url)
        } else {
            openWiFiSettings()
        }
    }

    private func openSettings(deepLink: String) {
        if let url = URL(string: deepLink), NSWorkspace.shared.open(url) {
            return
        }

        if let fallback = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(fallback)
        }
    }

    // MARK: - Alerts

    private func showError(_ error: Error, title: String) {
        showMessage(
            title: title,
            message: error.localizedDescription
        )
    }

    private func showMessage(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
