import AppKit

final class StatusIconRenderer {
    // Trim only transparent outer margins; the artwork keeps its original geometry.
    static let baseItemWidth: CGFloat = 24
    private static let imageHeight: CGFloat = 22

    enum AccessoryState {
        case none, bolt, plug
    }

    private static func accessoryExtent(for state: AccessoryState) -> CGFloat {
        switch state {
        case .none: return 0
        case .bolt: return 10
        case .plug: return 12
        }
    }

    static func accessoryState(for battery: BatteryStatus?) -> AccessoryState {
        guard let battery else { return .none }
        switch battery.powerState {
        case .onBattery:
            return .none
        case .charging:
            return .bolt
        case .fullyCharged, .connectedNotCharging:
            return .plug
        }
    }

    func render(
        snapshot: StatusSnapshot,
        from previousSnapshot: StatusSnapshot? = nil,
        progress: CGFloat = 1
    ) -> NSImage {
        let bright = NSColor.labelColor
        let accessory = batteryAccessory(snapshot.battery, foreground: bright)
        let previousAccessory = batteryAccessory(
            (previousSnapshot ?? snapshot).battery, foreground: bright
        )
        let progress = min(max(progress, 0), 1)
        let oldWidth = previousAccessory?.size.width ?? 0
        let newWidth = accessory?.size.width ?? 0
        let accessoryWidth = oldWidth + (newWidth - oldWidth) * progress
        let oldExtent = Self.accessoryExtent(
            for: Self.accessoryState(for: (previousSnapshot ?? snapshot).battery)
        )
        let newExtent = Self.accessoryExtent(
            for: Self.accessoryState(for: snapshot.battery)
        )
        let imageSize = NSSize(
            width: Self.baseItemWidth + oldExtent + (newExtent - oldExtent) * progress,
            height: Self.imageHeight
        )
        let image = NSImage(size: imageSize, flipped: false) { [weak self] _ in
            guard
                let self,
                let context = NSGraphicsContext.current?.cgContext
            else {
                return false
            }

            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            let bright = NSColor.labelColor
            let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            let dim = NSColor.tertiaryLabelColor.withAlphaComponent(
                increaseContrast ? 0.78 : 0.55
            )
            let differentiateWithoutColor = NSWorkspace.shared
                .accessibilityDisplayShouldDifferentiateWithoutColor
            // The original arc has 3 points of transparent inset on its left.
            // Remove that inset without changing its radius or the bolt gap.
            let compositeRect = NSRect(
                x: -3,
                y: 0, width: 30, height: imageSize.height
            )

            self.drawBatteryArc(
                in: context,
                rect: compositeRect,
                battery: snapshot.battery,
                bright: bright,
                dim: dim,
                differentiateWithoutColor: differentiateWithoutColor
            )

            self.drawInputSourceLabel(
                snapshot.inputSourceLabel,
                in: compositeRect,
                color: bright
            )

            self.drawNetworkIndicator(
                snapshot.network,
                in: context,
                rect: compositeRect,
                bright: bright,
                dim: dim
            )

            let accessoryCenterX = compositeRect.maxX + accessoryWidth / 2
            func drawAccessory(_ image: NSImage?, opacity: CGFloat) {
                guard let image, opacity > 0 else { return }
                image.draw(
                    in: NSRect(
                        x: accessoryCenterX - image.size.width / 2,
                        y: (imageSize.height - image.size.height) / 2,
                        width: image.size.width, height: image.size.height
                    ),
                    from: .zero, operation: .sourceOver, fraction: opacity
                )
            }
            if Self.accessoryState(for: (previousSnapshot ?? snapshot).battery)
                == Self.accessoryState(for: snapshot.battery) {
                drawAccessory(accessory, opacity: 1)
            } else {
                drawAccessory(previousAccessory, opacity: 1 - progress)
                drawAccessory(accessory, opacity: progress)
            }

            return true
        }

        // Keep this false so battery state colors are preserved.
        image.isTemplate = false
        return image
    }

    private func drawBatteryArc(
        in context: CGContext,
        rect: NSRect,
        battery: BatteryStatus?,
        bright: NSColor,
        dim: NSColor,
        differentiateWithoutColor: Bool
    ) {
        let center = CGPoint(x: rect.midX, y: 9.6)
        let radius: CGFloat = 11.1
        let lineWidth: CGFloat = 1.75

        let activeColor: NSColor
        let remainderColor: NSColor
        if battery?.isLowBattery == true {
            activeColor = .systemRed
            remainderColor = activeColor.withAlphaComponent(0.25)
        } else if battery?.isLowPowerModeEnabled == true {
            activeColor = .systemYellow
            remainderColor = activeColor.withAlphaComponent(0.25)
        } else {
            activeColor = bright
            remainderColor = dim
        }

        // Full dim arc is always visible.
        context.saveGState()
        context.setStrokeColor(remainderColor.cgColor)
        let accessibleLineWidth = differentiateWithoutColor && battery?.isLowBattery == true
            ? lineWidth + 0.65
            : lineWidth
        context.setLineWidth(accessibleLineWidth)
        context.setLineCap(.round)
        if differentiateWithoutColor && battery?.isLowPowerModeEnabled == true
            && battery?.isLowBattery != true {
            context.setLineDash(phase: 0, lengths: [2.4, 1.5])
        }
        context.addArc(
            center: center,
            radius: radius,
            startAngle: .pi,
            endAngle: 0,
            clockwise: true
        )
        context.strokePath()
        context.restoreGState()

        guard let battery else { return }

        let fraction = min(max(battery.level, 0.0), 1.0)
        guard fraction > 0 else { return }

        // The highlighted segment length is the exact battery percentage.
        let startAngle = CGFloat.pi
        let endAngle = CGFloat.pi - (CGFloat.pi * CGFloat(fraction))

        context.saveGState()
        context.setStrokeColor(activeColor.cgColor)
        context.setLineWidth(accessibleLineWidth)
        context.setLineCap(.round)
        if differentiateWithoutColor && battery.isLowPowerModeEnabled
            && !battery.isLowBattery {
            context.setLineDash(phase: 0, lengths: [2.4, 1.5])
        }
        context.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        context.strokePath()
        context.restoreGState()
    }

    private func batteryAccessory(_ battery: BatteryStatus?, foreground: NSColor) -> NSImage? {
        let symbolName: String
        let pointSize: CGFloat
        let maximumSize: NSSize
        let weight: NSFont.Weight
        switch Self.accessoryState(for: battery) {
        case .none:
            return nil
        case .bolt:
            symbolName = "bolt.fill"
            pointSize = 10
            maximumSize = NSSize(width: 8, height: 12)
            weight = .regular
        case .plug:
            symbolName = NSImage(systemSymbolName: "powerplug.portrait.fill", accessibilityDescription: nil) == nil
                ? "powerplug.fill"
                : "powerplug.portrait.fill"
            pointSize = 11.5
            // The plug receives two extra item-width points so it can grow
            // without clipping or moving toward the arc.
            maximumSize = NSSize(width: 9, height: 13)
            weight = .semibold
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(.init(paletteColors: [foreground]))
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }

        // Preserve each symbol's aspect ratio and the original arc/accessory gap.
        let scale = min(
            maximumSize.width / symbol.size.width,
            maximumSize.height / symbol.size.height
        )
        symbol.size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        return symbol
    }

    private func drawInputSourceLabel(
        _ label: String,
        in rect: NSRect,
        color: NSColor
    ) {
        let font = NSFont.monospacedSystemFont(
            ofSize: label.count == 1 ? 9 : 8.2,
            weight: .semibold
        )

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let textRect = NSRect(
            x: rect.minX + 4,
            y: 6.1,
            width: rect.width - 8,
            height: 10
        )

        (label as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func drawNetworkIndicator(
        _ network: NetworkStatus,
        in context: CGContext,
        rect: NSRect,
        bright: NSColor,
        dim: NSColor
    ) {
        switch network {
        case .wifi(let strength, _, _):
            drawWiFiDots(
                count: strength,
                in: context,
                rect: rect,
                bright: bright,
                dim: dim
            )

        case .ethernet:
            drawLANLine(
                in: context,
                rect: rect,
                color: bright
            )

        case .other, .wifiDisconnected, .wifiOff, .disconnected:
            drawWiFiDots(
                count: 0,
                in: context,
                rect: rect,
                bright: bright,
                dim: dim
            )
        }
    }

    private func drawWiFiDots(
        count: Int,
        in context: CGContext,
        rect: NSRect,
        bright: NSColor,
        dim: NSColor
    ) {
        let clamped = min(max(count, 0), 3)
        let radius: CGFloat = 1.15
        let spacing: CGFloat = 5.2
        let totalWidth = spacing * 2
        let startX = rect.midX - totalWidth / 2
        let y: CGFloat = 3.0

        for index in 0..<3 {
            let x = startX + CGFloat(index) * spacing
            let dotRect = CGRect(
                x: x - radius,
                y: y - radius,
                width: radius * 2,
                height: radius * 2
            )

            let color = index < clamped ? bright : dim
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: dotRect)
        }
    }

    private func drawLANLine(
        in context: CGContext,
        rect: NSRect,
        color: NSColor
    ) {
        let y: CGFloat = 3.0
        let halfWidth: CGFloat = 6.35

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2.3)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: rect.midX - halfWidth, y: y))
        context.addLine(to: CGPoint(x: rect.midX + halfWidth, y: y))
        context.strokePath()
        context.restoreGState()
    }
}
