import AppKit
import SwiftUI

struct StatusControlCenterView: View {
    @ObservedObject var model: StatusControlCenterModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    islandStack
                }
            } else {
                islandStack
            }
        }
        .padding(12)
        .frame(width: 360)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var islandStack: some View {
        VStack(spacing: 10) {
            if let expandedIsland = model.expandedIsland {
                expandedIslandView(expandedIsland)
            } else {
                compactIsland(.battery)
                compactIsland(.connectivity)
                compactIsland(.inputSource)

                HStack(spacing: 8) {
                    Button(model.updateTitle) { model.checkForUpdates?() }
                    Spacer()
                    Button("Quit") { model.quit?() }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func compactIsland(_ kind: StatusIsland) -> some View {
        islandSurface(kind, expanded: false) {
            compactHeader(for: kind)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
        }
        .overlay {
            FirstMouseButton(
                accessibilityLabel: "Open \(kind.accessibilityName) controls"
            ) {
                toggleIsland(kind)
            }
        }
    }

    @ViewBuilder
    private func compactHeader(for kind: StatusIsland) -> some View {
        switch kind {
        case .battery:
            CompactIslandHeader(
                symbol: "battery.100",
                title: "Battery",
                subtitle: model.batteryState,
                trailing: model.batteryPercentage.map { "\($0)%" } ?? "—"
            )
        case .connectivity:
            CompactIslandHeader(
                symbol: "wifi",
                title: model.networkTitle,
                subtitle: model.networkDetail
            )
        case .inputSource:
            CompactIslandHeader(
                symbol: "keyboard",
                title: "Input Source",
                subtitle: model.inputSourceName,
                badge: model.inputSourceLabel
            )
        }
    }

    @ViewBuilder
    private func expandedIslandView(_ kind: StatusIsland) -> some View {
        switch kind {
        case .battery:
            islandSurface(kind, expanded: true) { batteryContent }
        case .connectivity:
            islandSurface(kind, expanded: true) { connectivityContent }
        case .inputSource:
            islandSurface(kind, expanded: true) { inputSourceContent }
        }
    }

    @ViewBuilder
    private func islandSurface<Content: View>(
        _ kind: StatusIsland,
        expanded: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: expanded ? 24 : 30, style: .continuous)
        let base = content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)

        if #available(macOS 26.0, *) {
            base
                .glassEffect(.regular, in: shape)
                .glassEffectID(kind.rawValue, in: glassNamespace)
                .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        } else {
            base
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
                .transition(
                    reduceMotion
                        ? .identity
                        : .scale(scale: 0.96).combined(with: .opacity)
                )
        }
    }

    private var batteryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            IslandHeader(
                symbol: "battery.100",
                title: "Battery",
                subtitle: model.batteryState,
                trailing: model.batteryPercentage.map { "\($0)%" } ?? "—",
                expanded: model.expandedIsland == .battery,
                action: { toggleIsland(.battery) }
            )

            if model.expandedIsland == .battery {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()
                    LabeledContent("Power Source", value: model.powerSource)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Energy Mode")
                            .font(.headline)
                        EnergyModeRow(
                            title: "Automatic",
                            symbol: "battery.100",
                            selected: model.lowPowerModeEnabled == false,
                            action: { model.openBatterySettings?() }
                        )
                        EnergyModeRow(
                            title: "Low Power",
                            symbol: "battery.25",
                            selected: model.lowPowerModeEnabled == true,
                            action: { model.openBatterySettings?() }
                        )
                        EnergyModeRow(
                            title: "High Power",
                            symbol: "battery.100.bolt",
                            selected: false,
                            action: { model.openBatterySettings?() }
                        )
                    }

                    Divider()
                    ActionRow(title: "Energy Usage in Activity Monitor…", symbol: "gauge.with.dots.needle.67percent") {
                        model.openActivityMonitor?()
                    }
                    ActionRow(title: "Battery Settings…", symbol: "gear") {
                        model.openBatterySettings?()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
    }

    private var connectivityContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            IslandHeader(
                symbol: "wifi",
                title: model.networkTitle,
                subtitle: model.networkDetail,
                expanded: model.expandedIsland == .connectivity,
                toggle: Binding(
                    get: { model.wifiOn },
                    set: { model.setWiFiPower?($0) }
                ),
                showsToggle: model.expandedIsland == .connectivity,
                toggleDisabled: model.wifiBusy,
                action: { toggleIsland(.connectivity) }
            )

            if model.expandedIsland == .connectivity {
                VStack(alignment: .leading, spacing: 13) {
                    Divider()

                    if model.networks.isEmpty {
                        Text(model.wifiBusy ? "Scanning…" : "No nearby networks")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 46)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                NetworkSection(
                                    title: "Known Networks",
                                    networks: model.networks.filter { $0.isKnown || $0.isCurrent },
                                    connect: model.connectNetwork
                                )
                                NetworkSection(
                                    title: "Other Networks",
                                    networks: model.networks.filter { !$0.isKnown && !$0.isCurrent },
                                    connect: model.connectNetwork
                                )
                            }
                        }
                        .frame(maxHeight: 226)
                    }

                    HStack {
                        Button("Refresh") { model.scanNetworks?() }
                            .disabled(model.wifiBusy || !model.wifiOn)
                        Button("Other Network…") { model.joinOtherNetwork?() }
                            .disabled(model.wifiBusy || !model.wifiOn)
                        Spacer()
                        if model.currentSSID != nil {
                            Button("Disconnect") { model.disconnectWiFi?() }
                                .disabled(model.wifiBusy)
                        }
                    }
                    .controlSize(.small)

                    Divider()
                    ActionRow(title: "Network Settings…", symbol: "network") {
                        model.openNetworkSettings?()
                    }
                    ActionRow(title: "Wi-Fi Settings…", symbol: "wifi") {
                        model.openWiFiSettings?()
                    }
                    ActionRow(title: "Wireless Diagnostics…", symbol: "wave.3.right.circle") {
                        model.openWirelessDiagnostics?()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
    }

    private var inputSourceContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            IslandHeader(
                symbol: "keyboard",
                title: "Input Source",
                subtitle: model.inputSourceName,
                badge: model.inputSourceLabel,
                expanded: model.expandedIsland == .inputSource,
                action: { toggleIsland(.inputSource) }
            )

            if model.expandedIsland == .inputSource {
                VStack(alignment: .leading, spacing: 13) {
                    Divider()
                    VStack(spacing: 2) {
                        ForEach(model.inputSources) { source in
                            InputSourceSelectionRow(source: source) {
                                if !source.isCurrent { model.selectInputSource?(source.id) }
                            }
                        }
                    }

                    Divider()
                    ActionRow(title: "Show Emoji & Symbols", symbol: "character.book.closed") {
                        model.showEmojiAndSymbols?()
                    }
                    ActionRow(title: "Show Keyboard Viewer", symbol: "keyboard") {
                        model.showKeyboardViewer?()
                    }
                    .disabled(!model.keyboardViewerAvailable)
                    Divider()
                    ActionRow(title: "Keyboard Settings…", symbol: "gear") {
                        model.openKeyboardSettings?()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
    }

    private func toggleIsland(_ island: StatusIsland) {
        withAnimation(reduceMotion ? nil : StatusMotion.expansion) {
            model.toggle(island)
        }
    }
}

private struct FirstMouseButton: NSViewRepresentable {
    let accessibilityLabel: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = FirstMouseNSButton()
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(accessibilityLabel)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.setAccessibilityLabel(accessibilityLabel)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private final class FirstMouseNSButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private extension StatusIsland {
    var accessibilityName: String {
        switch self {
        case .battery: return "battery"
        case .connectivity: return "connectivity"
        case .inputSource: return "input source"
        }
    }
}

private struct CompactIslandHeader: View {
    let symbol: String
    let title: String
    let subtitle: String
    var trailing: String? = nil
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let badge {
                    Text(badge)
                        .font(.system(size: 15, weight: .bold))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .foregroundStyle(.tint)
            .frame(width: 42, height: 42)
            .background(.white, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct InputSourceSelectionRow: View {
    let source: StatusInputSourceRow
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Text(source.label)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .background(.white, in: RoundedRectangle(cornerRadius: 5))
                Text(source.name)
                Spacer()
                if source.isCurrent {
                    Image(systemName: "checkmark")
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(
            isHovered ? Color.primary.opacity(0.085) : .clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            if isHovered {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.12), lineWidth: 0.7)
            }
        }
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : StatusMotion.hover) {
                isHovered = hovered
            }
        }
        .accessibilityValue(source.isCurrent ? "Selected" : "Not selected")
    }
}

private struct IslandHeader: View {
    let symbol: String
    let title: String
    let subtitle: String
    var trailing: String? = nil
    var badge: String? = nil
    let expanded: Bool
    var toggle: Binding<Bool>?
    var showsToggle = true
    var toggleDisabled = false
    let action: () -> Void

    var body: some View {
        let inset: CGFloat = expanded ? 18 : 14
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 15, weight: .bold))
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .foregroundStyle(.tint)
                .frame(width: 42, height: 42)
                .background(.white, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? 2 : 1)
                }

                Spacer(minLength: 8)

                if toggle == nil, let trailing {
                    Text(trailing)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)

                if showsToggle, toggle != nil {
                    Color.clear.frame(width: 48, height: 1)
                }
            }
            .padding(inset)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            if showsToggle, let toggle {
                Toggle("", isOn: toggle)
                    .labelsHidden()
                    .disabled(toggleDisabled)
                    .padding(.trailing, inset)
            }
        }
    }
}

private struct NetworkSection: View {
    let title: String
    let networks: [StatusNetworkRow]
    let connect: ((Int) -> Void)?

    var body: some View {
        if !networks.isEmpty {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            ForEach(networks) { network in
                NetworkRow(network: network) {
                    if !network.isCurrent { connect?(network.id) }
                }
            }
        }
    }
}

private struct EnergyModeRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(selected ? Color.accentColor : Color.white)
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selected ? .white : .secondary)
                }
                .frame(width: 34, height: 34)
                Text(title)
                    .foregroundStyle(selected ? .primary : .secondary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .background(
            isHovered ? Color.primary.opacity(0.085) : .clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            if isHovered {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.12), lineWidth: 0.7)
            }
        }
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : StatusMotion.hover) {
                isHovered = hovered
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

private struct NetworkRow: View {
    let network: StatusNetworkRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: wifiSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.white, in: Circle())
                    .foregroundStyle(network.isCurrent ? Color.accentColor : Color.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(network.name)
                    if network.isKnown && !network.isCurrent {
                        Text("Known Network").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if network.isSecured { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                if network.isCurrent { Image(systemName: "checkmark").foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .accessibilityLabel("\(network.name), signal \(network.strength) of 3\(network.isSecured ? ", secured" : "")")
    }

    private var wifiSymbol: String {
        switch network.strength {
        case 3: return "wifi"
        case 2: return "wifi"
        default: return "wifi.exclamationmark"
        }
    }
}

private struct ActionRow: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }
}
