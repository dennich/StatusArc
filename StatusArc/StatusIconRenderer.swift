import AppKit
import CoreText

final class StatusIconRenderer {
    // Trim only transparent outer margins; the artwork keeps its original geometry.
    static let baseItemWidth: CGFloat = 24
    private static let imageHeight: CGFloat = 22

    func render(snapshot: StatusSnapshot) -> NSImage {
        let imageSize = NSSize(width: Self.baseItemWidth, height: Self.imageHeight)
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
            // Remove that inset without changing its radius.
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
                in: context,
                rect: compositeRect,
                color: bright
            )

            self.drawNetworkIndicator(
                snapshot.network,
                vpn: snapshot.vpn,
                in: context,
                rect: compositeRect,
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
        dim: NSColor,
        differentiateWithoutColor: Bool
    ) {
        let center = CGPoint(x: rect.midX, y: 11)
        let radius: CGFloat = 10
        let lineWidth: CGFloat = 1.75
        let startAngle = CGFloat.pi * (10.0 / 9.0)
        let endAngle = -CGFloat.pi / 9.0
        let leftGapAngle = CGFloat.pi * (7.0 / 9.0)
        let rightGapAngle = CGFloat.pi * (2.0 / 9.0)
        let hasTopIndicator = battery != nil

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

        let accessibleLineWidth = differentiateWithoutColor && battery?.isLowBattery == true
            ? lineWidth + 0.65
            : lineWidth

        func strokeArc(from arcStart: CGFloat, to arcEnd: CGFloat, color: NSColor) {
            context.saveGState()
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(accessibleLineWidth)
            context.setLineCap(.round)
            if differentiateWithoutColor && battery?.isLowPowerModeEnabled == true
                && battery?.isLowBattery != true {
                context.setLineDash(phase: 0, lengths: [2.4, 1.5])
            }
            context.addArc(
                center: center,
                radius: radius,
                startAngle: arcStart,
                endAngle: arcEnd,
                clockwise: true
            )
            context.strokePath()
            context.restoreGState()
        }

        // Every available battery state reserves a wide top gap for its power
        // indicator. The wider opening keeps round arc caps clear of numbers.
        if hasTopIndicator {
            strokeArc(from: startAngle, to: leftGapAngle, color: remainderColor)
            strokeArc(from: rightGapAngle, to: endAngle, color: remainderColor)
        } else {
            strokeArc(from: startAngle, to: endAngle, color: remainderColor)
        }

        guard let battery else { return }

        let fraction = min(max(battery.level, 0.0), 1.0)
        if fraction > 0 {
            if hasTopIndicator {
                // The two 60-degree segments together represent 100%.
                let segmentSweep = startAngle - leftGapAngle
                let activeSweep = segmentSweep * 2 * CGFloat(fraction)
                let leftSweep = min(activeSweep, segmentSweep)
                strokeArc(from: startAngle, to: startAngle - leftSweep, color: activeColor)

                let rightSweep = max(activeSweep - segmentSweep, 0)
                if rightSweep > 0 {
                    strokeArc(
                        from: rightGapAngle,
                        to: rightGapAngle - rightSweep,
                        color: activeColor
                    )
                }
            } else {
                // The highlighted segment length is the exact battery percentage.
                let sweep = CGFloat.pi * (11.0 / 9.0)
                strokeArc(
                    from: startAngle,
                    to: startAngle - (sweep * CGFloat(fraction)),
                    color: activeColor
                )
            }
        }

        drawTopPowerIndicator(battery, in: context, rect: rect, color: bright)
    }

    private func drawTopPowerIndicator(
        _ battery: BatteryStatus,
        in context: CGContext,
        rect: NSRect,
        color: NSColor
    ) {
        switch battery.powerState {
        case .onBattery:
            let text = String(battery.displayedPercentage)
            let fontSize: CGFloat = text.count >= 3 ? 7 : 8
            let line = roundedTextLine(
                text,
                size: fontSize,
                weight: .heavy,
                color: color,
                kern: 0
            )
            let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let maximumWidth: CGFloat = 8.5
            let horizontalScale = min(maximumWidth / glyphBounds.width, 1)

            context.saveGState()
            context.textMatrix = CGAffineTransform(scaleX: horizontalScale, y: 1)
            context.textPosition = CGPoint(
                // A small optical correction balances the rounded numerals
                // within the arc gap while retaining their original height.
                x: rect.midX - glyphBounds.midX * horizontalScale - 0.5,
                y: 19 - glyphBounds.midY
            )
            CTLineDraw(line, context)
            context.restoreGState()

        case .charging:
            // SF Symbols include generous alignment padding. Use a larger
            // symbol frame so the visible bolt matches Figma's 2 × 4-point
            // vector rather than inheriting the tiny padded glyph size.
            drawTopSymbol(
                "bolt.fill",
                pointSize: 9.5,
                weight: .bold,
                maximumSize: NSSize(width: 6, height: 9.5),
                in: rect,
                color: color
            )

        case .fullyCharged, .connectedNotCharging:
            let symbolName = NSImage(
                systemSymbolName: "powerplug.portrait.fill",
                accessibilityDescription: nil
            ) == nil ? "powerplug.fill" : "powerplug.portrait.fill"
            drawTopSymbol(
                symbolName,
                pointSize: 9.5,
                weight: .semibold,
                maximumSize: NSSize(width: 4.5, height: 6.5),
                in: rect,
                color: color
            )
        }
    }

    private func drawTopSymbol(
        _ name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        maximumSize: NSSize,
        in rect: NSRect,
        color: NSColor
    ) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(.init(paletteColors: [color]))
        guard let symbol = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration) else { return }

        let scale = min(
            maximumSize.width / symbol.size.width,
            maximumSize.height / symbol.size.height
        )
        let size = NSSize(
            width: symbol.size.width * scale,
            height: symbol.size.height * scale
        )
        symbol.draw(
            in: NSRect(
                x: rect.midX - size.width / 2,
                y: 19 - size.height / 2,
                width: size.width,
                height: size.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    private func drawInputSourceLabel(
        _ label: String,
        in context: CGContext,
        rect: NSRect,
        color: NSColor
    ) {
        let font = NSFont.systemFont(
            ofSize: 9.5,
            weight: .bold
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: label, attributes: attributes)
        )
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

        // Center the visible glyph outlines rather than the font's line box.
        // This keeps one- and two-letter identities on the same optical axis.
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: rect.midX - glyphBounds.midX,
            y: rect.midY - glyphBounds.midY
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawNetworkIndicator(
        _ network: NetworkStatus,
        vpn: VPNStatus?,
        in context: CGContext,
        rect: NSRect,
        bright: NSColor,
        dim: NSColor
    ) {
        if vpn != nil {
            drawVPNLabel(in: context, rect: rect, color: bright)
            return
        }

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

    private func drawVPNLabel(
        in context: CGContext,
        rect: NSRect,
        color: NSColor
    ) {
        let line = roundedTextLine(
            "VPN",
            size: 5,
            weight: .bold,
            color: color,
            kern: 0.5
        )
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: rect.midX - glyphBounds.midX,
            y: 4 - glyphBounds.midY
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func roundedTextLine(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        kern: CGFloat? = nil
    ) -> CTLine {
        let baseFont = NSFont.systemFont(ofSize: size, weight: weight)
        let descriptor = baseFont.fontDescriptor.withDesign(.rounded)
            ?? baseFont.fontDescriptor
        let font = NSFont(descriptor: descriptor, size: size) ?? baseFont
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        if let kern {
            attributes[.kern] = kern
        }
        return CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
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
        let y: CGFloat = 2.25

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
        let y: CGFloat = 2.25
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
