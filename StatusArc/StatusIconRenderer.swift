import AppKit

final class StatusIconRenderer {
    // Preserve the original 30 × 22 composite and reserve 8 points on its right.
    static let imageSize = NSSize(width: 38, height: 22)
    static let statusItemWidth: CGFloat = imageSize.width + 2
    private let compositeRect = NSRect(x: 0, y: 0, width: 30, height: 22)
    private let accessoryRect = NSRect(x: 30, y: 5, width: 8, height: 12)

    func render(snapshot: StatusSnapshot) -> NSImage {
        let image = NSImage(size: Self.imageSize, flipped: false) { [weak self] _ in
            guard
                let self,
                let context = NSGraphicsContext.current?.cgContext
            else {
                return false
            }

            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            let bright = NSColor.labelColor
            let dim = NSColor.tertiaryLabelColor.withAlphaComponent(0.55)

            self.drawBatteryArc(
                in: context,
                rect: self.compositeRect,
                battery: snapshot.battery,
                bright: bright,
                dim: dim
            )

            self.drawLanguage(
                snapshot.languageCode,
                in: self.compositeRect,
                color: bright
            )

            self.drawNetworkIndicator(
                snapshot.network,
                in: context,
                rect: self.compositeRect,
                bright: bright,
                dim: dim
            )

            self.drawBatteryAccessory(snapshot.battery, foreground: bright)

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
        dim: NSColor
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
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
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
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
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

    private func drawBatteryAccessory(_ battery: BatteryStatus?, foreground: NSColor) {
        guard let battery else { return }

        let symbolName: String
        let color: NSColor
        if battery.isCharging {
            symbolName = "bolt.fill"
            color = foreground
        } else if battery.isLowBattery {
            symbolName = "exclamationmark"
            color = .systemRed
        } else {
            return
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            .applying(.init(paletteColors: [color]))
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }

        // Fit without stretching; both accessories share the same fixed slot.
        let scale = min(accessoryRect.width / symbol.size.width, accessoryRect.height / symbol.size.height)
        let symbolSize = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let symbolRect = NSRect(
            x: accessoryRect.midX - symbolSize.width / 2,
            y: accessoryRect.midY - symbolSize.height / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        symbol.draw(in: symbolRect)
    }

    private func drawLanguage(
        _ code: String,
        in rect: NSRect,
        color: NSColor
    ) {
        let font = NSFont.monospacedSystemFont(
            ofSize: 8.2,
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
            x: 4,
            y: 6.1,
            width: rect.width - 8,
            height: 10
        )

        (code as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func drawNetworkIndicator(
        _ network: NetworkStatus,
        in context: CGContext,
        rect: NSRect,
        bright: NSColor,
        dim: NSColor
    ) {
        switch network {
        case .wifi(let strength, _):
            drawWiFiDots(
                count: strength,
                in: context,
                rect: rect,
                bright: bright,
                dim: dim
            )

        case .ethernet, .other:
            drawLANLine(
                in: context,
                rect: rect,
                color: bright
            )

        case .disconnected:
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
