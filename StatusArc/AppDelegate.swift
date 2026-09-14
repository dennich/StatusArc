import AppKit
import Carbon
import CoreWLAN

private enum EnergyModeVisual {
    case automatic, lowPower, highPower
}

private final class ControlCenterMenuSurface: NSView {
    let content = NSView()

    init(frame: NSRect, interactive: Bool) {
        super.init(frame: frame)

        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.cornerRadius = 10
            glass.style = .regular
            glass.tintColor = NSColor.controlAccentColor.withAlphaComponent(0.06)
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = interactive
            }
            content.frame = glass.bounds
            content.autoresizingMask = [.width, .height]
            glass.contentView = content
            background = glass
        } else {
            let visualEffect = NSVisualEffectView(frame: bounds)
            visualEffect.material = .menu
            visualEffect.blendingMode = .withinWindow
            visualEffect.state = .followsWindowActiveState
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = 10
            visualEffect.layer?.masksToBounds = true
            content.frame = visualEffect.bounds
            content.autoresizingMask = [.width, .height]
            visualEffect.addSubview(content)
            background = visualEffect
        }

        background.frame = bounds
        background.autoresizingMask = [.width, .height]
        addSubview(background)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class WiFiMenuControlView: NSView {
    let toggle = NSSwitch()
    private let label = NSTextField(labelWithString: "Wi-Fi")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 40))

        let surface = ControlCenterMenuSurface(
            frame: bounds.insetBy(dx: 4, dy: 2),
            interactive: true
        )
        surface.autoresizingMask = [.width, .height]
        addSubview(surface)

        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        toggle.translatesAutoresizingMaskIntoConstraints = false
        surface.content.addSubview(label)
        surface.content.addSubview(toggle)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: surface.content.leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: surface.content.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: surface.content.trailingAnchor, constant: -10),
            toggle.centerYAnchor.constraint(equalTo: surface.content.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(isOn: Bool, isEnabled: Bool, status: String? = nil) {
        toggle.state = isOn ? .on : .off
        toggle.isEnabled = isEnabled
        label.stringValue = status.map { "Wi-Fi — \($0)" } ?? "Wi-Fi"
        label.textColor = isEnabled ? .labelColor : .secondaryLabelColor
    }
}

private final class BatterySummaryMenuView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Battery")
    private let percentageLabel = NSTextField(labelWithString: "—")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 38))

        let surface = ControlCenterMenuSurface(
            frame: bounds.insetBy(dx: 4, dy: 2),
            interactive: false
        )
        surface.autoresizingMask = [.width, .height]
        addSubview(surface)

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        percentageLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        percentageLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        percentageLabel.translatesAutoresizingMaskIntoConstraints = false
        surface.content.addSubview(titleLabel)
        surface.content.addSubview(percentageLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: surface.content.leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: surface.content.centerYAnchor),
            percentageLabel.trailingAnchor.constraint(equalTo: surface.content.trailingAnchor, constant: -10),
            percentageLabel.centerYAnchor.constraint(equalTo: surface.content.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(percentage: Int?) {
        percentageLabel.stringValue = percentage.map { "\($0)%" } ?? "—"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private enum WiFiOperation: Equatable {
        case idle
        case changingPower(enabled: Bool)
        case scanning
        case connecting(ssid: String)
        case disconnecting(ssid: String?)
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: StatusIconRenderer.baseItemWidth)
    private let monitor = SystemStatusMonitor()
    private let actions = SystemActions()
    private let renderer = StatusIconRenderer()
    private let updateManager = UpdateManager()
    private let controlCenterModel = StatusControlCenterModel()
    private var panelController: StatusPanelController?
    private var expandedInterfaceDelegate: AnyObject?

    private var fallbackRefreshTimer: Timer?
    private var appearanceObservation: NSKeyValueObservation?
    private var lastIconSnapshot: StatusSnapshot?
    private var iconAnimation: StatusIconAnimation?
    private var inputSources: [TISInputSource] = []
    private var scannedNetworks: [CWNetwork] = []
    private var wifiOperation: WiFiOperation = .idle

    private let batteryMenuItem = NSMenuItem(title: "Battery", action: nil, keyEquivalent: "")
    private let batteryMenu = NSMenu(title: "Battery")
    private let batterySummaryItem = NSMenuItem()
    private let batterySummaryView = BatterySummaryMenuView()
    private let batteryItem = NSMenuItem(title: "Battery", action: nil, keyEquivalent: "")
    private let batteryPowerItem = NSMenuItem(title: "Power Source", action: nil, keyEquivalent: "")
    private let automaticEnergyModeItem = NSMenuItem(title: "Automatic", action: nil, keyEquivalent: "")
    private let lowPowerEnergyModeItem = NSMenuItem(title: "Low Power", action: nil, keyEquivalent: "")
    private let highPowerEnergyModeItem = NSMenuItem(title: "High Power", action: nil, keyEquivalent: "")

    private let connectivityMenuItem = NSMenuItem(title: "Connectivity", action: nil, keyEquivalent: "")
    private let connectivityMenu = NSMenu(title: "Connectivity")
    private let networkItem = NSMenuItem(title: "Network", action: nil, keyEquivalent: "")
    private let wifiToggleItem = NSMenuItem(title: "Wi-Fi", action: nil, keyEquivalent: "")
    private let wifiControlView = WiFiMenuControlView()
    private let disconnectWiFiItem = NSMenuItem(title: "Disconnect Wi-Fi", action: nil, keyEquivalent: "")
    private let wifiNetworksItem = NSMenuItem(title: "Other Networks", action: nil, keyEquivalent: "")
    private let wifiNetworksMenu = NSMenu(title: "Other Networks")
    private let wifiDetailsItem = NSMenuItem(title: "Connection Details", action: nil, keyEquivalent: "")
    private let wifiDetailsMenu = NSMenu(title: "Connection Details")

    private let inputItem = NSMenuItem(title: "Input Source", action: nil, keyEquivalent: "")
    private let inputSourcesMenu = NSMenu(title: "Input Sources")
    private let keyboardViewerItem = NSMenuItem(title: "Show Keyboard Viewer", action: nil, keyEquivalent: "")

    private let versionItem = NSMenuItem(title: "StatusArc", action: nil, keyEquivalent: "")
    private let checkForUpdatesItem = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureMenu()
        configureControlCenter()

        updateManager.onUpdateAvailabilityChanged = { [weak self] _ in
            self?.updateApplicationMenu()
            self?.refresh()
        }
        updateManager.start()

        monitor.startMonitoring { [weak self] in
            self?.refresh()
        }
        refresh()

        fallbackRefreshTimer = Timer.scheduledTimer(
            timeInterval: 60.0,
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )

        if let fallbackRefreshTimer {
            RunLoop.main.add(fallbackRefreshTimer, forMode: .common)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        fallbackRefreshTimer?.invalidate()
        appearanceObservation?.invalidate()
        monitor.stopMonitoring()
        iconAnimation?.stop()
        panelController?.hide(animated: false)
        updateManager.stop()
    }

    // MARK: - Setup

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.toolTip = "StatusArc"
            button.setAccessibilityLabel("StatusArc")
            appearanceObservation = button.observe(
                \.effectiveAppearance,
                options: [.new]
            ) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.refresh()
                }
            }
        }
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.delegate = self
        wifiNetworksMenu.autoenablesItems = false
        wifiDetailsMenu.autoenablesItems = false
        inputSourcesMenu.autoenablesItems = false
        batteryMenu.autoenablesItems = false

        batteryItem.isEnabled = false
        batteryPowerItem.isEnabled = false
        networkItem.isEnabled = false
        versionItem.isEnabled = false

        // Apple does not expose its Control Center panels to third-party apps.
        // Standard AppKit submenus preserve native menu behavior. Small
        // standard AppKit views provide the public controls macOS exposes.
        batteryMenuItem.submenu = batteryMenu
        batterySummaryItem.view = batterySummaryView
        batteryMenu.addItem(batterySummaryItem)
        batteryMenu.addItem(batteryItem)
        batteryMenu.addItem(batteryPowerItem)
        batteryMenu.addItem(.separator())
        batteryMenu.addItem(sectionItem("Energy Mode"))
        for item in [
            automaticEnergyModeItem,
            lowPowerEnergyModeItem,
            highPowerEnergyModeItem
        ] {
            item.isEnabled = false
            item.toolTip = "macOS does not expose a public API for changing Energy Mode."
            batteryMenu.addItem(item)
        }
        batteryMenu.addItem(.separator())
        batteryMenu.addItem(actionItem(
            "Energy Usage in Activity Monitor…",
            #selector(openActivityMonitor)
        ))
        batteryMenu.addItem(actionItem(
            "Battery Settings…",
            #selector(openBatterySettings)
        ))
        menu.addItem(batteryMenuItem)

        connectivityMenuItem.submenu = connectivityMenu
        wifiToggleItem.view = wifiControlView
        wifiControlView.toggle.target = self
        wifiControlView.toggle.action = #selector(wifiSwitchChanged(_:))

        disconnectWiFiItem.target = self
        disconnectWiFiItem.action = #selector(disconnectWiFi)

        wifiNetworksItem.submenu = wifiNetworksMenu

        wifiDetailsItem.submenu = wifiDetailsMenu
        rebuildWiFiNetworksMenu(using: actions.cachedWiFiNetworks())
        menu.addItem(connectivityMenuItem)

        inputItem.submenu = inputSourcesMenu
        menu.addItem(inputItem)

        menu.addItem(.separator())

        updateManager.configure(checkForUpdatesMenuItem: checkForUpdatesItem)
        updateApplicationMenu()
        menu.addItem(versionItem)
        menu.addItem(checkForUpdatesItem)

        menu.addItem(.separator())

        let quitItem = actionItem(
            "Quit StatusArc",
            #selector(quit),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func configureControlCenter() {
        // The status item remains AppKit-owned so its custom drawing and width
        // follow the system menu bar. SwiftUI owns only the expanded surface.
        statusItem.menu = nil

        let controller = StatusPanelController(
            statusItem: statusItem,
            model: controlCenterModel
        )
        controller.onWillShow = { [weak self] in
            guard let self else { return }
            self.inputSources = self.actions.enabledInputSources()
            if self.scannedNetworks.isEmpty {
                self.scannedNetworks = self.actions.cachedWiFiNetworks()
            }
            self.refresh()
        }
        panelController = controller

        controlCenterModel.setWiFiPower = { [weak self] enabled in
            self?.setWiFiPower(enabled)
        }
        controlCenterModel.disconnectWiFi = { [weak self] in self?.disconnectWiFi() }
        controlCenterModel.scanNetworks = { [weak self] in self?.scanNetworksWithPermission() }
        controlCenterModel.connectNetwork = { [weak self] index in
            self?.connectToWiFiNetwork(at: index)
        }
        controlCenterModel.joinOtherNetwork = { [weak self] in self?.joinOtherNetwork() }
        controlCenterModel.selectInputSource = { [weak self] index in
            guard let self else { return }
            self.selectInputSource(at: index)
        }
        controlCenterModel.showEmojiAndSymbols = { [weak self] in
            self?.performPanelAction { $0.showEmojiAndSymbols() }
        }
        controlCenterModel.showKeyboardViewer = { [weak self] in
            self?.performPanelAction { $0.showKeyboardViewer() }
        }
        controlCenterModel.openBatterySettings = { [weak self] in
            self?.performPanelAction { $0.openBatterySettings() }
        }
        controlCenterModel.openActivityMonitor = { [weak self] in
            self?.performPanelAction { $0.openActivityMonitor() }
        }
        controlCenterModel.openWiFiSettings = { [weak self] in
            self?.performPanelAction { $0.openWiFiSettings() }
        }
        controlCenterModel.openNetworkSettings = { [weak self] in
            self?.performPanelAction { $0.openNetworkSettings() }
        }
        controlCenterModel.openWirelessDiagnostics = { [weak self] in
            self?.performPanelAction { $0.openWirelessDiagnostics() }
        }
        controlCenterModel.openKeyboardSettings = { [weak self] in
            self?.performPanelAction { $0.openKeyboardSettings() }
        }
        controlCenterModel.checkForUpdates = { [weak self] in
            self?.performPanelAction { $0.updateManager.checkForUpdates() }
        }
        controlCenterModel.quit = { [weak self] in self?.quit() }

        if #available(macOS 27.0, *) {
            let delegate = StatusExpandedInterfaceDelegate(panelController: controller)
            expandedInterfaceDelegate = delegate
            statusItem.expandedInterfaceDelegate = delegate
        } else if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggleControlCenter)
            button.sendAction(on: [.leftMouseUp])
        }
    }

    @objc private func toggleControlCenter() {
        panelController?.toggle()
    }

    private func performPanelAction(_ action: (AppDelegate) -> Void) {
        panelController?.requestClose()
        action(self)
    }

    private func sectionItem(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
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
        let optionPressed = NSApp.currentEvent?.modifierFlags.contains(.option) == true
        wifiDetailsItem.isHidden = !optionPressed
        refresh()
        updateApplicationMenu()
        rebuildInputSourcesMenu()
        if optionPressed {
            rebuildWiFiDetailsMenu()
        }

        // Do not start scans or rebuild tracked Connectivity submenus here.
        // Mutating a menu during pointer tracking makes moving between sibling
        // submenus lag. Nearby-network scans remain explicit user actions.
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === wifiToggleItem || menuItem === disconnectWiFiItem {
            return wifiOperation == .idle
        }
        if menuItem === wifiNetworksItem {
            return actions.wifiPowerOn
        }
        if menuItem === wifiDetailsItem {
            return actions.wifiPowerOn
                && (actions.currentSSID != nil
                    || (actions.wifiInterface?.rssiValue() ?? 0) < 0)
        }
        return true
    }

    @objc private func refreshTimerFired() {
        refresh()
    }

    // MARK: - Status refresh

    private func refresh() {
        reconcileWiFiOperation()
        let snapshot = monitor.snapshot()

        updateStatusIcon(snapshot)
        statusItem.button?.toolTip = snapshot.tooltip
        statusItem.button?.setAccessibilityValue(snapshot.tooltip)

        updateBatteryMenu(snapshot)
        updateNetworkMenu(snapshot)
        updateInputMenu(snapshot)
        updateControlCenter(snapshot)
    }

    private func updateControlCenter(_ snapshot: StatusSnapshot) {
        if inputSources.isEmpty {
            inputSources = actions.enabledInputSources()
        }

        let currentInputID = actions.currentInputSourceID()
        let inputRows = inputSources.enumerated().map { index, source in
            let identity = InputSourceIdentityResolver.resolve(source)
            return StatusInputSourceRow(
                id: index,
                name: identity.localizedName,
                label: identity.compactLabel,
                isCurrent: actions.inputSourceID(source) == currentInputID
            )
        }

        let knownNames = actions.knownWiFiNetworkNames()
        let currentSSID = actions.currentSSID
        var networkRows = scannedNetworks.enumerated().compactMap { index, network -> StatusNetworkRow? in
            guard let name = network.ssid, !name.isEmpty else { return nil }
            return StatusNetworkRow(
                id: index,
                name: name,
                strength: actions.signalStrength(for: network),
                isSecured: !actions.isOpenNetwork(network),
                isCurrent: name == currentSSID,
                isKnown: knownNames.contains(name)
            )
        }

        if let currentSSID, !networkRows.contains(where: { $0.name == currentSSID }) {
            networkRows.insert(StatusNetworkRow(
                id: -1,
                name: currentSSID,
                strength: 3,
                isSecured: true,
                isCurrent: true,
                isKnown: true
            ), at: 0)
        }
        networkRows.sort {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            if $0.isKnown != $1.isKnown { return $0.isKnown }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        controlCenterModel.update(
            snapshot: snapshot,
            wifiOn: actions.wifiPowerOn,
            wifiBusy: wifiOperation != .idle,
            currentSSID: currentSSID,
            networks: networkRows,
            inputSources: inputRows,
            keyboardViewerAvailable: actions.keyboardViewerSource() != nil,
            availableUpdate: updateManager.availableVersion
        )
    }

    private func updateStatusIcon(_ snapshot: StatusSnapshot) {
        let previous = lastIconSnapshot
        lastIconSnapshot = snapshot
        let accessoryChanged = previous.map {
            StatusIconRenderer.accessoryState(for: $0.battery)
                != StatusIconRenderer.accessoryState(for: snapshot.battery)
        } ?? false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if !accessoryChanged, iconAnimation?.isAnimating == true, !reduceMotion {
            return
        }
        iconAnimation?.stop()
        iconAnimation = nil

        guard let previous, accessoryChanged, !reduceMotion else {
            applyStatusIcon(renderer.render(snapshot: snapshot))
            return
        }

        let animation = StatusIconAnimation(duration: 0.18, animationCurve: .easeInOut)
        animation.animationBlockingMode = .nonblocking
        animation.frameRate = 60
        animation.onFrame = { [weak self] progress in
            guard let self else { return }
            self.applyStatusIcon(self.renderer.render(
                snapshot: snapshot, from: previous, progress: progress
            ))
        }
        iconAnimation = animation
        animation.start()
    }

    private func applyStatusIcon(_ image: NSImage) {
        // Resize the native item with the rendered frame, never scale its artwork.
        statusItem.length = image.size.width
        statusItem.button?.image = image
    }

    private func updateBatteryMenu(_ snapshot: StatusSnapshot) {
        if let battery = snapshot.battery {
            let percent = battery.displayedPercentage

            var stateText: String
            switch battery.powerState {
            case .fullyCharged:
                stateText = "Fully Charged"
            case .charging:
                stateText = "Charging"
            case .connectedNotCharging:
                stateText = "Not Charging"
            case .onBattery:
                stateText = "Battery"
            }

            if let minutes = battery.minutesRemaining {
                stateText += " • \(formattedDuration(minutes))"
            }

            if battery.isLowPowerModeEnabled {
                stateText += " • Low Power Mode"
            }

            batteryItem.title = stateText
            batteryPowerItem.title = "Power Source: \(battery.powerSource)"
            batteryMenuItem.title = "Battery: \(percent)%"
            batterySummaryView.update(percentage: percent)
            updateEnergyModeVisuals(lowPowerModeEnabled: battery.isLowPowerModeEnabled)
        } else {
            batteryItem.title = "Battery: Not available"
            batteryPowerItem.title = "Power Source: —"
            batteryMenuItem.title = "Battery"
            batterySummaryView.update(percentage: nil)
            updateEnergyModeVisuals(lowPowerModeEnabled: nil)
        }
    }

    private func updateEnergyModeVisuals(lowPowerModeEnabled: Bool?) {
        let modes: [(NSMenuItem, EnergyModeVisual, Bool)] = [
            (automaticEnergyModeItem, .automatic, lowPowerModeEnabled == false),
            (lowPowerEnergyModeItem, .lowPower, lowPowerModeEnabled == true),
            (highPowerEnergyModeItem, .highPower, false)
        ]

        for (item, mode, selected) in modes {
            item.image = energyModeImage(mode, selected: selected)
            item.state = .off
            item.setAccessibilityValue(selected ? "Selected" : "Not selected")
        }
    }

    private func energyModeImage(
        _ mode: EnergyModeVisual,
        selected: Bool
    ) -> NSImage {
        let symbolNames: [String]
        switch mode {
        case .automatic:
            symbolNames = ["battery.100percent", "battery.100"]
        case .lowPower:
            symbolNames = ["battery.25percent", "battery.25"]
        case .highPower:
            symbolNames = ["battery.100percent.bolt", "battery.100.bolt"]
        }

        let size = NSSize(width: 28, height: 28)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = rect.insetBy(dx: 2, dy: 2)
            let fill = selected
                ? NSColor.controlAccentColor
                : NSColor.tertiaryLabelColor.withAlphaComponent(0.42)
            fill.setFill()
            NSBezierPath(ovalIn: circle).fill()

            guard let baseSymbol = symbolNames.lazy.compactMap({
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)
            }).first else {
                return true
            }

            let foreground = selected ? NSColor.white : NSColor.secondaryLabelColor
            let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                .applying(.init(paletteColors: [foreground]))
            guard let symbol = baseSymbol.withSymbolConfiguration(configuration),
                  symbol.size.width > 0, symbol.size.height > 0 else {
                return true
            }

            let maximum = NSSize(width: 16, height: 11)
            let scale = min(
                maximum.width / symbol.size.width,
                maximum.height / symbol.size.height
            )
            let symbolSize = NSSize(
                width: symbol.size.width * scale,
                height: symbol.size.height * scale
            )
            symbol.draw(
                in: NSRect(
                    x: rect.midX - symbolSize.width / 2,
                    y: rect.midY - symbolSize.height / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    private func updateNetworkMenu(_ snapshot: StatusSnapshot) {
        switch snapshot.network {
        case .wifi(let strength, let rssi, let connectivity):
            let label: String
            switch strength {
            case 3: label = "Strong"
            case 2: label = "Medium"
            case 1: label = "Weak"
            default: label = "Disconnected"
            }

            let ssidText = actions.currentSSID.map { " • \($0)" } ?? ""

            let connectivityText = connectivity == .localOnly
                ? " • No Internet Connection"
                : ""

            if let rssi, strength > 0 {
                networkItem.title = "Network: Wi-Fi\(ssidText) • \(label) (\(rssi) dBm)\(connectivityText)"
            } else {
                networkItem.title = "Network: Wi-Fi\(ssidText) • \(label)\(connectivityText)"
            }

        case .wifiDisconnected:
            networkItem.title = "Network: Wi-Fi • Disconnected"

        case .wifiOff:
            networkItem.title = "Network: Wi-Fi • Off"

        case .ethernet(let interfaceName, let connectivity):
            networkItem.title = connectivity == .internet
                ? "Network: Ethernet • \(interfaceName)"
                : "Network: Ethernet • No Internet Connection"

        case .other(let interfaceName, let connectivity):
            networkItem.title = connectivity == .internet
                ? "Network: \(interfaceName)"
                : "Network: \(interfaceName) • No Internet Connection"

        case .disconnected:
            networkItem.title = "Network: Disconnected"
        }

        switch wifiOperation {
        case .scanning:
            networkItem.title += " • Scanning…"
        case .connecting(let ssid):
            networkItem.title = "Network: Connecting to “\(ssid)”…"
        case .disconnecting(let ssid):
            networkItem.title = ssid.map {
                "Network: Disconnecting from “\($0)”…"
            } ?? "Network: Disconnecting…"
        case .changingPower, .idle:
            break
        }

        connectivityMenuItem.title = networkItem.title.replacingOccurrences(
            of: "Network:",
            with: "Connectivity:",
            options: [.anchored]
        )

        switch wifiOperation {
        case .changingPower(true):
            wifiControlView.update(isOn: true, isEnabled: false, status: "Turning On…")
        case .changingPower(false):
            wifiControlView.update(isOn: false, isEnabled: false, status: "Turning Off…")
        default:
            wifiControlView.update(
                isOn: actions.wifiPowerOn,
                isEnabled: wifiOperation == .idle
            )
        }
        wifiToggleItem.isEnabled = wifiOperation == .idle

        let hasWiFiAssociation = actions.wifiPowerOn
            && (actions.currentSSID != nil || (actions.wifiInterface?.rssiValue() ?? 0) < 0)

        disconnectWiFiItem.isHidden = !hasWiFiAssociation
        if let ssid = actions.currentSSID {
            disconnectWiFiItem.title = "Disconnect from “\(ssid)”"
        } else {
            disconnectWiFiItem.title = "Disconnect Wi-Fi"
        }

        disconnectWiFiItem.isEnabled = wifiOperation == .idle

        wifiNetworksItem.isEnabled = actions.wifiPowerOn
        wifiDetailsItem.isEnabled = hasWiFiAssociation
    }

    private func updateInputMenu(_ snapshot: StatusSnapshot) {
        inputItem.title = "Input Source: \(snapshot.inputSourceName)"
    }

    private func updateApplicationMenu() {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"

        versionItem.title = "StatusArc \(version)"

        if let availableVersion = updateManager.availableVersion {
            checkForUpdatesItem.title = "Update to \(availableVersion)…"
        } else {
            checkForUpdatesItem.title = "Check for Updates…"
        }
    }

    private func formattedDuration(_ minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes)m"
    }

    // MARK: - Wi-Fi controls

    @objc private func wifiSwitchChanged(_ sender: NSSwitch) {
        setWiFiPower(sender.state == .on)
    }

    private func setWiFiPower(_ enabled: Bool) {
        guard wifiOperation == .idle else { return }
        wifiOperation = .changingPower(enabled: enabled)
        refresh()

        do {
            try actions.setWiFiPower(enabled)
            refresh()
            rebuildWiFiNetworksMenu(using: [])
            clearWiFiOperationAfterDelay()
        } catch {
            wifiOperation = .idle
            refresh()
            showError(error, title: "Couldn’t Change Wi-Fi")
        }
    }

    @objc private func disconnectWiFi() {
        guard wifiOperation == .idle else { return }
        wifiOperation = .disconnecting(ssid: actions.currentSSID)
        actions.disconnectWiFi()
        refresh()
        clearWiFiOperationAfterDelay()
    }

    private func reconcileWiFiOperation() {
        switch wifiOperation {
        case .changingPower(let enabled) where actions.wifiPowerOn == enabled:
            wifiOperation = .idle
        case .connecting(let ssid) where actions.currentSSID == ssid:
            wifiOperation = .idle
        case .disconnecting where actions.currentSSID == nil:
            wifiOperation = .idle
        default:
            break
        }
    }

    private func clearWiFiOperationAfterDelay() {
        let operation = wifiOperation
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.wifiOperation == operation else { return }
            self.wifiOperation = .idle
            self.refresh()
        }
    }

    private func addKnownWiFiNetworkItems(to menu: NSMenu) {
        let currentSSID = actions.currentSSID
        let knownNames = actions.knownWiFiNetworkNames()
        let indexed = scannedNetworks.enumerated().compactMap { index, network in
            network.ssid.map { (index: index, network: network, ssid: $0) }
        }

        let known = indexed.filter {
            knownNames.contains($0.ssid) || $0.ssid == currentSSID
        }

        guard !known.isEmpty || currentSSID != nil else {
            return
        }

        menu.addItem(sectionItem("Known Networks"))

        if let currentSSID,
           !known.contains(where: { $0.ssid == currentSSID }) {
            let currentItem = NSMenuItem(
                title: currentSSID,
                action: nil,
                keyEquivalent: ""
            )
            currentItem.state = .on
            currentItem.isEnabled = false
            menu.addItem(currentItem)
        }

        for entry in known.sorted(by: {
            if $0.ssid == currentSSID { return true }
            if $1.ssid == currentSSID { return false }
            return $0.ssid.localizedStandardCompare($1.ssid) == .orderedAscending
        }) {
            menu.addItem(networkItem(
                for: entry,
                isCurrent: entry.ssid == currentSSID
            ))
        }
    }

    private func rebuildConnectivityMenu() {
        connectivityMenu.removeAllItems()
        connectivityMenu.addItem(wifiToggleItem)
        connectivityMenu.addItem(networkItem)
        connectivityMenu.addItem(.separator())

        if actions.wifiPowerOn {
            addKnownWiFiNetworkItems(to: connectivityMenu)

            if connectivityMenu.items.last?.isSeparatorItem == false,
               connectivityMenu.items.last !== networkItem {
                connectivityMenu.addItem(.separator())
            }

            connectivityMenu.addItem(wifiNetworksItem)
            connectivityMenu.addItem(disconnectWiFiItem)
            connectivityMenu.addItem(wifiDetailsItem)
        }

        connectivityMenu.addItem(.separator())
        connectivityMenu.addItem(actionItem(
            "Network Settings…",
            #selector(openNetworkSettings)
        ))
        connectivityMenu.addItem(actionItem(
            "Wi-Fi Settings…",
            #selector(openWiFiSettings)
        ))
    }

    private func networkItem(
        for entry: (index: Int, network: CWNetwork, ssid: String),
        isCurrent: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: entry.ssid,
            action: isCurrent ? nil : #selector(connectToWiFiNetwork(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = entry.index
        item.state = isCurrent ? .on : .off
        item.isEnabled = !isCurrent && wifiOperation == .idle

        let secured = !actions.isOpenNetwork(entry.network)
        if secured {
            item.image = NSImage(
                systemSymbolName: "lock.fill",
                accessibilityDescription: "Secured network"
            )
        }

        let strength = actions.signalStrength(for: entry.network)
        let signalDescription: String
        switch strength {
        case 3: signalDescription = "strong signal"
        case 2: signalDescription = "medium signal"
        case 1: signalDescription = "weak signal"
        default: signalDescription = "unavailable signal"
        }
        item.setAccessibilityLabel(
            "\(entry.ssid), \(signalDescription)\(secured ? ", secured" : "")"
        )

        if case .connecting(let ssid) = wifiOperation, ssid == entry.ssid {
            item.title = "\(entry.ssid) — Connecting…"
        }

        return item
    }

    private func rebuildWiFiNetworksMenu(using networks: [CWNetwork]) {
        scannedNetworks = networks

        wifiNetworksMenu.removeAllItems()

        if !actions.wifiPowerOn {
            let item = NSMenuItem(title: "Wi-Fi is off", action: nil, keyEquivalent: "")
            item.isEnabled = false
            wifiNetworksMenu.addItem(item)
            rebuildConnectivityMenu()
            return
        }

        if case .scanning = wifiOperation {
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
            let knownNames = actions.knownWiFiNetworkNames()
            let other: [(index: Int, network: CWNetwork, ssid: String)] =
                scannedNetworks.enumerated().compactMap { index, network in
                guard let ssid = network.ssid,
                      ssid != currentSSID,
                      !knownNames.contains(ssid) else {
                    return nil
                }
                return (index: index, network: network, ssid: ssid)
            }

            if other.isEmpty {
                let empty = NSMenuItem(
                    title: "No Other Networks Found",
                    action: nil,
                    keyEquivalent: ""
                )
                empty.isEnabled = false
                wifiNetworksMenu.addItem(empty)
            } else {
                other.forEach {
                    wifiNetworksMenu.addItem(networkItem(for: $0, isCurrent: false))
                }
            }
        }

        wifiNetworksMenu.addItem(.separator())

        let refreshNetworks = NSMenuItem(
            title: wifiOperation == .scanning ? "Scanning…" : "Refresh Nearby Networks",
            action: #selector(scanNetworksWithPermission),
            keyEquivalent: ""
        )
        refreshNetworks.target = self
        refreshNetworks.isEnabled = wifiOperation == .idle
        wifiNetworksMenu.addItem(refreshNetworks)

        let otherNetwork = NSMenuItem(
            title: "Other Network…",
            action: #selector(joinOtherNetwork),
            keyEquivalent: ""
        )
        otherNetwork.target = self
        otherNetwork.isEnabled = wifiOperation == .idle
        wifiNetworksMenu.addItem(otherNetwork)

        wifiNetworksMenu.addItem(.separator())
        wifiNetworksMenu.addItem(actionItem(
            "Wi-Fi Settings…",
            #selector(openWiFiSettings)
        ))

        if actions.locationAccess == .denied {
            let privacy = NSMenuItem(
                title: "Open Location Privacy Settings…",
                action: #selector(openLocationPrivacySettings),
                keyEquivalent: ""
            )
            privacy.target = self
            wifiNetworksMenu.addItem(privacy)
        }

        rebuildConnectivityMenu()
    }

    @objc private func scanNetworksWithPermission() {
        scanNearbyNetworks(requestPermission: true, showErrors: true)
    }

    private func scanNearbyNetworks(
        requestPermission: Bool,
        showErrors: Bool
    ) {
        guard wifiOperation == .idle, actions.wifiPowerOn else {
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

            self.wifiOperation = .scanning
            self.rebuildWiFiNetworksMenu(using: [])

            self.actions.scanWiFiNetworks { [weak self] result in
                guard let self else { return }

                self.wifiOperation = .idle

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
        connectToWiFiNetwork(at: sender.tag)
    }

    private func connectToWiFiNetwork(at index: Int) {
        guard wifiOperation == .idle,
              scannedNetworks.indices.contains(index) else {
            return
        }

        let network = scannedNetworks[index]

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
            password = actions.savedUserPassword(for: network)

            if password == nil {
                guard let ssid = network.ssid else { return }
                password = askForPassword(networkName: ssid)
                if password == nil {
                    return
                }
            }
        }

        let ssid = network.ssid ?? "Wi-Fi"
        wifiOperation = .connecting(ssid: ssid)
        rebuildWiFiNetworksMenu(using: scannedNetworks)

        actions.connect(to: network, password: password) { [weak self] error in
            guard let self else { return }

            self.wifiOperation = .idle

            if let error {
                self.showError(error, title: "Couldn’t Join Wi-Fi Network")
            } else {
                self.refresh()
            }
        }
    }

    @objc private func joinOtherNetwork() {
        guard wifiOperation == .idle else { return }
        guard let credentials = WiFiDialogs.requestHiddenNetwork() else { return }
        let name = credentials.networkName
        let suppliedPassword = credentials.password

        actions.requestWiFiNameAccessIfNeeded { [weak self] in
            guard let self else { return }

            guard self.actions.locationAccess != .denied else {
                self.showMessage(
                    title: "Location Access Is Required",
                    message: "macOS requires Location access before an app can find a hidden Wi-Fi network by name. You can enable access for StatusArc or join it in Wi-Fi Settings."
                )
                return
            }

            self.wifiOperation = .scanning
            self.actions.findWiFiNetwork(named: name) { [weak self] result in
                guard let self else { return }
                self.wifiOperation = .idle

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

                    let isOpenNetwork = self.actions.isOpenNetwork(network)
                    var password = isOpenNetwork ? nil : suppliedPassword
                    if !isOpenNetwork, password == nil {
                        guard let resolvedPassword = self.actions.savedUserPassword(for: network)
                            ?? self.askForPassword(networkName: name) else {
                            return
                        }
                        password = resolvedPassword
                    }

                    self.wifiOperation = .connecting(ssid: name)
                    self.actions.connect(to: network, password: password) { [weak self] error in
                        guard let self else { return }

                        self.wifiOperation = .idle

                        if let error {
                            self.showError(error, title: "Couldn’t Join Wi-Fi Network")
                        } else {
                            self.refresh()
                        }
                    }

                case .failure(let error):
                    self.showError(error, title: "Wi-Fi Scan Failed")
                }
            }
        }
    }

    private func askForPassword(networkName: String) -> String? {
        WiFiDialogs.requestPassword(networkName: networkName)
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
            let identity = InputSourceIdentityResolver.resolve(source)
            let item = NSMenuItem(
                title: identity.localizedName,
                action: #selector(selectInputSource(_:)),
                keyEquivalent: ""
            )

            item.target = self
            item.tag = index

            if actions.inputSourceID(source) == currentID {
                item.state = .on
            }

            item.image = inputSourceMenuImage(label: identity.compactLabel)

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

        inputSourcesMenu.addItem(.separator())
        let emojiItem = actionItem(
            "Show Emoji & Symbols",
            #selector(showEmojiAndSymbols)
        )
        emojiItem.image = NSImage(
            systemSymbolName: "character.book.closed",
            accessibilityDescription: nil
        )
        inputSourcesMenu.addItem(emojiItem)

        keyboardViewerItem.target = self
        keyboardViewerItem.action = #selector(showKeyboardViewer)
        keyboardViewerItem.image = NSImage(
            systemSymbolName: "keyboard",
            accessibilityDescription: nil
        )
        keyboardViewerItem.isEnabled = actions.keyboardViewerSource() != nil
        keyboardViewerItem.toolTip = keyboardViewerItem.isEnabled
            ? nil
            : "Keyboard Viewer is not exposed through the public API on this macOS version."
        inputSourcesMenu.addItem(keyboardViewerItem)

        inputSourcesMenu.addItem(.separator())
        inputSourcesMenu.addItem(actionItem(
            "Input Source Name in Menu Bar…",
            #selector(openKeyboardSettings)
        ))
        inputSourcesMenu.addItem(.separator())
        inputSourcesMenu.addItem(actionItem(
            "Keyboard Settings…",
            #selector(openKeyboardSettings)
        ))
    }

    private func inputSourceMenuImage(label: String) -> NSImage {
        let size = NSSize(width: 26, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.labelColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(
                roundedRect: rect.insetBy(dx: 1, dy: 1),
                xRadius: 4,
                yRadius: 4
            ).fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(
                    ofSize: label.count == 1 ? 12 : 10,
                    weight: .semibold
                ),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
            (label as NSString).draw(
                in: NSRect(x: 1, y: 2, width: size.width - 2, height: 14),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    @objc private func selectInputSource(_ sender: NSMenuItem) {
        selectInputSource(at: sender.tag)
    }

    private func selectInputSource(at index: Int) {
        guard inputSources.indices.contains(index) else {
            return
        }

        do {
            try actions.selectInputSource(inputSources[index])
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
        do {
            try actions.showKeyboardViewer()
        } catch {
            showError(error, title: "Couldn’t Show Keyboard Viewer")
        }
    }

    // MARK: - System destinations

    @objc private func openNetworkSettings() {
        openSettings(
            deepLink: "x-apple.systempreferences:com.apple.Network-Settings.extension"
        )
    }

    @objc private func openWiFiSettings() {
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

    @objc private func openActivityMonitor() {
        let path = "/System/Applications/Utilities/Activity Monitor.app"
        let url = URL(fileURLWithPath: path)

        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(url)
        }
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

// AppKit schedules frames only during a short accessory transition.
private final class StatusIconAnimation: NSAnimation {
    var onFrame: ((CGFloat) -> Void)?

    override var currentProgress: NSAnimation.Progress {
        get { super.currentProgress }
        set {
            super.currentProgress = newValue
            onFrame?(CGFloat(currentValue))
        }
    }

    override var runLoopModesForAnimating: [RunLoop.Mode]? { [.common] }
}
