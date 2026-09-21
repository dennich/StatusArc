import AppKit
import CoreText

enum StatusIconNetworkActivity: Equatable {
    case idle
    case connecting
    case refreshing
}

final class StatusIconRenderer {
    // The Figma component and native status item share one fixed 22-point frame.
    static let baseItemWidth: CGFloat = 22
    private static let imageHeight: CGFloat = 22

    // Flattened directly from Figma's 14 × 4-point Union vector at 8×. It is
    // used only as an alpha mask, so the semantic foreground color still
    // follows the current menu-bar appearance without substituting a font.
    private static let vpnMarkImage: NSImage? = {
        let encoded = """
        iVBORw0KGgoAAAANSUhEUgAAAHAAAAAgCAYAAADKbvy8AAAACXBIWXMAAFiVAABYlQHZbTfTAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAOdEVYdFNvZnR3YXJlAEZpZ21hnrGWYwAABGZJREFUeAHtm41V2zAQxy95DEAnQExQukGYoHQC3AmACTATQCdImAA6QdwJUiaQmSBhgqsOy8UxtvXXhwn09feeXoJzJ50+TjpJZkIWZt43H5lJn+2jX5PJZEEjYMqamY+vJkmZG5NuTVm/HTpN+46srqAG1DY2CWXjmXx/tJ+lq2zArhNrV23Tg0n3Jt+SIjH5S11P6aWeP00qtvI2Qmcmrfk12iRFiZC8TFpyN9cDevsmrXg81taujDww8ifc3W41c646OLS9Lnvy1Vx17LNQxsPoGCNaBs0dZeWBeinRDAxa7m/cNksKgN39IgNnXwSRkZ1TJFx5n4vKqNe6Y3pfH6eRdWlyHdBeGsg3J8ZYUySMe5Hq0F3zbjiJrEuTU8/2QphP6WWRH0LWoIwC4apTMlC8y54kU3gAc+6eThX5c8P1upWOR+nAH6Cw1whqcQnKLUx0tdWBnDCICkAGTpftisLyuktdnwlXa44mbJQfmwYuyANrsAbFD9uht6f+PblnFGXSjPz41BxYMndROLIFOHYJgWVc1cKuiKfGO6JiPFqb9+j7BAyKQIxs7pHveUs3FmdQA+aTNxU0qDQjEK4aH81XDeSBosgDI78A850H2jPEucM2hHza0LkiDHQ9E5onCEMsUpxaBLAA5RSl55Ljg5qDvx1oj81KQGmGFMx+kSc6eFJTgnKK0pMkqJm2/r4ljDNA5r17n6BAuZLGQZl0RxG0O/CGsH2hnAH2Rq0fxPsEdGv0VH/xGGz1obmLIw44qbGorQ60oTKyL5TOG1qEk3nfGN7J1eG4BCYZqFKQP9KWx4Q5xLkrqOlj0n7A+L5QDDvs2XjLdkORG2hfKeEWYRSgXPM6CmFrfwraI9dUh1wdx6HT5Jf6agsto/Op0b1Bw9gO3UtQF95T8m6Zd9ijAT3dkEf3nJptUIPK9zXYEZjB1u0BV1OTBnUzwjsQzXMMVGwHWh10zyk3L/ugrJ52NZh144Lc1LfkNTJdKECvHOu2PzEXCddgWeNKQE6md3Sv3b8MmN6doaOgoaNBnYw84N3cB+YD9iwBfd2hJ6c4Sa/Gpn1G2uCiIDdilHR2RuN5HxLJpaKkKrjKKTHWm79RQqaO332O11C33+W+b4jCpAuqIsHCIftIgdi8LygRe+QozHhWQe7rF9fvNaFrH+qBpYecJNmgy3p/394OjYkpq77cjbljfWYPkBGPmVEaQr3vCZQ73uGxnC8S1NSvSAbjmkJ91kIXHyXyfBOsx8t6WFI4pbMDLSnWrfe69u0MO1t8p3A2UAcm8ML/3tdDZFCzQT2QKC5yihllwgH9w0hQQ/jLZU0evKQZPyNtklMkjB1DoS8+RWPKugPsWZEn7H9gocgXxs/0hAUlgLFToZzeCNAe7+sh9nuHKKdQ2O2Jaw683xooc+hEP+j/D0a054YC4eoiQfPYbcvVaBFvXDUyXtmK+dy1hZYplVxyxBvjCeyRxr6zdV+nsoer24jM5qcbdX3Vtn8AwcjDXfLWFBsAAAAASUVORK5CYII=
        """
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return NSImage(data: data)
    }()

    func render(
        snapshot: StatusSnapshot,
        networkActivity: StatusIconNetworkActivity = .idle,
        animationPhase: Int = 0,
        reduceMotion: Bool = false,
        appearance: NSAppearance? = nil
    ) -> NSImage {
        let imageSize = NSSize(width: Self.baseItemWidth, height: Self.imageHeight)
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let differentiateWithoutColor = NSWorkspace.shared
            .accessibilityDisplayShouldDifferentiateWithoutColor
        let dimAlpha: CGFloat = increaseContrast ? 0.48 : 0.28

        // Resolve semantic colors for the status button's effective appearance.
        // The resulting non-template image keeps state colors while still
        // producing the correct white-on-dark and black-on-light variants.
        let bright = resolved(.labelColor, appearance: appearance)
        let red = resolved(.systemRed, appearance: appearance)
        let yellow = resolved(.systemYellow, appearance: appearance)
        let amber = resolved(.systemOrange, appearance: appearance)
        let green = resolved(.systemGreen, appearance: appearance)

        let image = NSImage(size: imageSize, flipped: false) { [weak self] _ in
            guard
                let self,
                let context = NSGraphicsContext.current?.cgContext
            else {
                return false
            }

            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            let rect = NSRect(origin: .zero, size: imageSize)

            self.drawBatteryArc(
                in: context,
                rect: rect,
                battery: snapshot.battery,
                bright: bright,
                red: red,
                yellow: yellow,
                amber: amber,
                green: green,
                dimAlpha: dimAlpha,
                differentiateWithoutColor: differentiateWithoutColor
            )

            self.drawInputSourceLabel(
                snapshot.inputSourceLabel,
                in: context,
                rect: rect,
                color: bright
            )

            self.drawNetworkIndicator(
                snapshot.network,
                vpn: snapshot.vpn,
                activity: networkActivity,
                animationPhase: animationPhase,
                reduceMotion: reduceMotion,
                in: context,
                rect: rect,
                bright: bright,
                dim: bright.withAlphaComponent(dimAlpha)
            )

            return true
        }

        // Template rendering would discard the battery and power-state colors.
        image.isTemplate = false
        return image
    }

    private func resolved(_ color: NSColor, appearance: NSAppearance?) -> NSColor {
        var result = color
        let resolve = {
            result = color.usingColorSpace(.deviceRGB) ?? color
        }

        if let appearance {
            appearance.performAsCurrentDrawingAppearance(resolve)
        } else {
            resolve()
        }
        return result
    }

    private func drawBatteryArc(
        in context: CGContext,
        rect: NSRect,
        battery: BatteryStatus?,
        bright: NSColor,
        red: NSColor,
        yellow: NSColor,
        amber: NSColor,
        green: NSColor,
        dimAlpha: CGFloat,
        differentiateWithoutColor: Bool
    ) {
        // Figma uses an inside-aligned 1.5-point stroke on the 20-point ellipse.
        // A 9.25-point centerline radius reproduces its 10-point outer radius.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius: CGFloat = 9.25
        let lineWidth: CGFloat = 1.5
        let leftBottom = radians(210)
        let leftTop = radians(120)
        let rightTop = radians(60)
        let rightBottom = radians(-30)
        let externalPower = battery.map {
            $0.isConnectedToExternalPower || $0.isCharging
        } ?? false

        // Figma joins the two upper arc sections while the Mac is draining.
        // External-power states retain the top opening for their power dot.
        let arcSegments: [(start: CGFloat, end: CGFloat)] = externalPower
            ? [(leftBottom, leftTop), (rightTop, rightBottom)]
            : [(leftBottom, rightBottom)]
        let totalSweep = arcSegments.reduce(CGFloat.zero) {
            $0 + ($1.start - $1.end)
        }

        let activeColor: NSColor
        if battery?.isLowBattery == true {
            activeColor = red
        } else if battery?.isLowPowerModeEnabled == true {
            activeColor = yellow
        } else {
            activeColor = bright
        }
        let remainderColor = activeColor.withAlphaComponent(dimAlpha)

        let accessibleLineWidth = differentiateWithoutColor && battery?.isLowBattery == true
            ? lineWidth + 0.65
            : lineWidth

        func strokeArc(from start: CGFloat, to end: CGFloat, color: NSColor) {
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
                startAngle: start,
                endAngle: end,
                clockwise: true
            )
            context.strokePath()
            context.restoreGState()
        }

        for segment in arcSegments {
            strokeArc(from: segment.start, to: segment.end, color: remainderColor)
        }

        if let battery {
            let fraction = min(max(battery.level, 0), 1)
            var remainingActiveSweep = totalSweep * CGFloat(fraction)

            for segment in arcSegments where remainingActiveSweep > 0 {
                let segmentSweep = segment.start - segment.end
                let sweep = min(remainingActiveSweep, segmentSweep)
                strokeArc(
                    from: segment.start,
                    to: segment.start - sweep,
                    color: activeColor
                )
                remainingActiveSweep -= sweep
            }
        }

        drawPowerStateDot(
            battery,
            in: context,
            rect: rect,
            amber: amber,
            green: green
        )
    }

    private func drawPowerStateDot(
        _ battery: BatteryStatus?,
        in context: CGContext,
        rect: NSRect,
        amber: NSColor,
        green: NSColor
    ) {
        guard let battery else { return }
        let externalPower = battery.isConnectedToExternalPower || battery.isCharging
        guard externalPower else { return }

        let color = battery.isFullyCharged || battery.displayedPercentage >= 100
            ? green
            : amber

        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(
            x: rect.midX - 2,
            y: 18,
            width: 4,
            height: 4
        ))
    }

    private func drawInputSourceLabel(
        _ label: String,
        in context: CGContext,
        rect: NSRect,
        color: NSColor
    ) {
        let line = textLine(label, size: 8.5, weight: .bold, color: color)
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

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
        activity: StatusIconNetworkActivity,
        animationPhase: Int,
        reduceMotion: Bool,
        in context: CGContext,
        rect: NSRect,
        bright: NSColor,
        dim: NSColor
    ) {
        if activity != .idle {
            drawWiFiActivityDots(
                activity,
                phase: animationPhase,
                reduceMotion: reduceMotion,
                in: context,
                rect: rect,
                bright: bright,
                dim: dim
            )
            return
        }

        if vpn != nil {
            drawVPNMark(in: context, rect: rect, color: bright)
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
            drawLANLine(in: context, rect: rect, color: bright)

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

    private func drawVPNMark(
        in context: CGContext,
        rect: NSRect,
        color: NSColor
    ) {
        guard let mark = Self.vpnMarkImage else { return }
        let target = NSRect(x: rect.midX - 7, y: 1, width: 14, height: 4)

        context.saveGState()
        context.clip(to: target)
        mark.draw(
            in: target,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.setBlendMode(.sourceIn)
        context.setFillColor(color.cgColor)
        context.fill(target)
        context.restoreGState()
    }

    private func textLine(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor
    ) -> CTLine {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
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
        for index in 0..<3 {
            drawNetworkDot(
                index: index,
                in: context,
                rect: rect,
                color: index < clamped ? bright : dim
            )
        }
    }

    private func drawWiFiActivityDots(
        _ activity: StatusIconNetworkActivity,
        phase: Int,
        reduceMotion: Bool,
        in context: CGContext,
        rect: NSRect,
        bright: NSColor,
        dim: NSColor
    ) {
        if reduceMotion {
            let steady = bright.withAlphaComponent(0.58)
            for index in 0..<3 {
                drawNetworkDot(index: index, in: context, rect: rect, color: steady)
            }
            return
        }

        let normalizedPhase = ((phase % 3) + 3) % 3
        let activeIndex: Int
        switch activity {
        case .connecting:
            activeIndex = normalizedPhase
        case .refreshing:
            activeIndex = 2 - normalizedPhase
        case .idle:
            return
        }

        for index in 0..<3 {
            let color = index == activeIndex ? bright : dim
            drawNetworkDot(index: index, in: context, rect: rect, color: color)
        }
    }

    private func drawNetworkDot(
        index: Int,
        in context: CGContext,
        rect: NSRect,
        color: NSColor
    ) {
        // Figma positions the 3-point dots 4.5 points center-to-center. Their
        // top-down centers are x = 6.5/11/15.5 and y = 19.5.
        let x = rect.midX - 4.5 + CGFloat(index) * 4.5
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: x - 1.5, y: 1, width: 3, height: 3))
    }

    private func drawLANLine(
        in context: CGContext,
        rect: NSRect,
        color: NSColor
    ) {
        let lineWidth: CGFloat = 2
        let centerlineWidth: CGFloat = 9
        let halfCenterlineWidth = centerlineWidth / 2

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: rect.midX - halfCenterlineWidth, y: 2.5))
        context.addLine(to: CGPoint(x: rect.midX + halfCenterlineWidth, y: 2.5))
        context.strokePath()
        context.restoreGState()
    }

    private func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }
}
