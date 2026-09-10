import AppKit

final class StatusIconRenderer {
    private let size: NSSize

    init(size: NSSize) {
        self.size = size
    }

    func render(snapshot: StatusSnapshot) -> NSImage {
        let image = NSImage(size: size, flipped: false) { [weak self] rect in
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
                rect: rect,
                battery: snapshot.battery,
                bright: bright,
                dim: dim
            )

            self.drawLanguage(
                snapshot.languageCode,
                in: rect,
                color: bright
            )

            self.drawNetworkIndicator(
                snapshot.network,
                in: context,
                rect: rect,
                bright: bright,
                dim: dim
            )

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

        // Full dim arc is always visible.
        context.saveGState()
        context.setStrokeColor(dim.cgColor)
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

        let activeColor: NSColor
        if battery.isCharging {
            activeColor = .systemGreen
        } else if battery.isLowPowerModeEnabled {
            activeColor = .systemYellow
        } else if battery.hasLowBatteryWarning {
            activeColor = .systemRed
        } else {
            activeColor = bright
        }

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
