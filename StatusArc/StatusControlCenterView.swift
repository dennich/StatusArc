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
        .frame(width: 360, alignment: .top)
    }

    private var islandStack: some View {
        VStack(spacing: 10) {
            island(.battery) { batteryContent }
            island(.connectivity) { connectivityContent }
            island(.inputSource) { inputSourceContent }

            HStack(spacing: 8) {
                Button(model.updateTitle) { model.checkForUpdates?() }
                Spacer()
                Button("Quit") { model.quit?() }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func island<Content: View>(
        _ kind: StatusIsland,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if model.expandedIsland == kind {
            islandSurface(kind, expanded: true, content: content)
        } else {
            islandSurface(kind, expanded: false, content: content)
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
            .padding(expanded ? 18 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)

        if #available(macOS 26.0, *) {
            base
                .glassEffect(.regular.interactive(), in: shape)
                .glassEffectID(kind.rawValue, in: glassNamespace)
                .glassEffectTransition(.matchedGeometry)
        } else {
            base
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
                .matchedGeometryEffect(id: kind.rawValue, in: glassNamespace)
        }
    }

    private var batteryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            IslandHeader(
                symbol: "battery.100",
                title: "Battery",
                subtitle: model.batteryState,
                trailing: model.batteryPercentage.map { "\($0)%" } ?? "—",
                expanded: model.expandedIsland == .battery,
                action: { toggleIsland(.battery) }
            )

            if model.expandedIsland == .battery {
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
        }
    }

    private var connectivityContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            IslandHeader(
                symbol: "wifi",
                title: model.networkTitle,
                subtitle: model.networkDetail,
                expanded: model.expandedIsland == .connectivity,
                toggle: Binding(
                    get: { model.wifiOn },
                    set: { model.setWiFiPower?($0) }
                ),
                toggleDisabled: model.wifiBusy,
                action: { toggleIsland(.connectivity) }
            )

            if model.expandedIsland == .connectivity {
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
        }
    }

    private var inputSourceContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            IslandHeader(
                symbol: "keyboard",
                title: "Input Source",
                subtitle: model.inputSourceName,
                badge: model.inputSourceLabel,
                expanded: model.expandedIsland == .inputSource,
                action: { toggleIsland(.inputSource) }
            )

            if model.expandedIsland == .inputSource {
                Divider()
                VStack(spacing: 2) {
                    ForEach(model.inputSources) { source in
                        Button {
                            if !source.isCurrent { model.selectInputSource?(source.id) }
                        } label: {
                            HStack(spacing: 11) {
                                Text(source.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 28, height: 22)
                                    .background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                                Text(source.name)
                                Spacer()
                                if source.isCurrent {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
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
        }
    }

    private func toggleIsland(_ island: StatusIsland) {
        withAnimation(reduceMotion ? nil : StatusMotion.expansion) {
            model.toggle(island)
        }
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
    var toggleDisabled = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
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
                    .background(.primary.opacity(0.1), in: Circle())

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
                }
            }
            .buttonStyle(.plain)

            if let toggle {
                Toggle("", isOn: toggle)
                    .labelsHidden()
                    .disabled(toggleDisabled)
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
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(selected ? Color.accentColor : Color.primary.opacity(0.12))
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selected ? .white : .secondary)
                }
                .frame(width: 34, height: 34)
                Text(title)
                    .foregroundStyle(selected ? .primary : .secondary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
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
        .help("Change Energy Mode in Battery Settings")
        .accessibilityElement(children: .combine)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint("Opens Battery Settings to change Energy Mode")
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
                    .background(network.isCurrent ? Color.accentColor : Color.primary.opacity(0.1), in: Circle())
                    .foregroundStyle(network.isCurrent ? .white : .primary)
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
