#!/usr/bin/env xcrun swift

import AppKit
import CoreGraphics
import Foundation

private struct IconVariant {
    let filename: String
    let pixels: Int
}

private let variants = [
    IconVariant(filename: "AppIcon-16.png", pixels: 16),
    IconVariant(filename: "AppIcon-16@2x.png", pixels: 32),
    IconVariant(filename: "AppIcon-32.png", pixels: 32),
    IconVariant(filename: "AppIcon-32@2x.png", pixels: 64),
    IconVariant(filename: "AppIcon-128.png", pixels: 128),
    IconVariant(filename: "AppIcon-128@2x.png", pixels: 256),
    IconVariant(filename: "AppIcon-256.png", pixels: 256),
    IconVariant(filename: "AppIcon-256@2x.png", pixels: 512),
    IconVariant(filename: "AppIcon-512.png", pixels: 512),
    IconVariant(filename: "AppIcon-512@2x.png", pixels: 1024),
]

private let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("StatusArc/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        components: [red, green, blue, alpha]
    )!
}

private func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
}

private func addStatusArcs(
    to context: CGContext,
    center: CGPoint,
    radius: CGFloat
) {
    context.move(to: CGPoint(
        x: center.x + radius * cos(210 * .pi / 180),
        y: center.y + radius * sin(210 * .pi / 180)
    ))
    context.addArc(
        center: center,
        radius: radius,
        startAngle: 210 * .pi / 180,
        endAngle: 120 * .pi / 180,
        clockwise: true
    )
    context.move(to: CGPoint(
        x: center.x + radius * cos(60 * .pi / 180),
        y: center.y + radius * sin(60 * .pi / 180)
    ))
    context.addArc(
        center: center,
        radius: radius,
        startAngle: 60 * .pi / 180,
        endAngle: -30 * .pi / 180,
        clockwise: true
    )
}

private func renderIcon(pixels: Int) throws -> Data {
    let size = CGFloat(pixels)
    let compact = pixels <= 64
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "StatusArcIcon", code: 1)
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // The transparent canvas and centered rounded tile preserve the macOS icon
    // silhouette on Ventura while remaining safe for newer system treatments.
    let tileInset = size * (compact ? 0.0625 : 0.09765625)
    let tileRect = CGRect(
        x: tileInset,
        y: tileInset,
        width: size - tileInset * 2,
        height: size - tileInset * 2
    )
    let tileRadius = tileRect.width * 0.225
    let tilePath = roundedRectPath(tileRect, radius: tileRadius)

    if !compact {
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -size * 0.022),
            blur: size * 0.035,
            color: color(0, 0, 0, 0.34)
        )
        context.addPath(tilePath)
        context.setFillColor(color(0.035, 0.043, 0.058, 1))
        context.fillPath()
        context.restoreGState()
    }

    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            color(0.18, 0.205, 0.25, 1),
            color(0.075, 0.09, 0.12, 1),
            color(0.028, 0.033, 0.047, 1),
        ] as CFArray,
        locations: [0, 0.48, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: tileRect.midX - size * 0.14, y: tileRect.maxY),
        end: CGPoint(x: tileRect.midX + size * 0.16, y: tileRect.minY),
        options: []
    )

    if !compact {
        let topGlow = CGGradient(
            colorsSpace: colorSpace,
            colors: [color(0.32, 0.58, 0.78, 0.16), color(0.12, 0.22, 0.34, 0)] as CFArray,
            locations: [0, 1]
        )!
        context.drawRadialGradient(
            topGlow,
            startCenter: CGPoint(x: tileRect.minX + tileRect.width * 0.28, y: tileRect.maxY),
            startRadius: 0,
            endCenter: CGPoint(x: tileRect.minX + tileRect.width * 0.28, y: tileRect.maxY),
            endRadius: tileRect.width * 0.78,
            options: []
        )
    }
    context.restoreGState()

    if !compact {
        context.saveGState()
        context.addPath(roundedRectPath(tileRect.insetBy(dx: size * 0.002, dy: size * 0.002), radius: tileRadius))
        context.setStrokeColor(color(1, 1, 1, 0.12))
        context.setLineWidth(size * 0.003)
        context.strokePath()
        context.restoreGState()
    }

    let glyphCenter = CGPoint(x: size * 0.5, y: size * 0.505)
    let arcRadius = size * (compact ? 0.27 : 0.255)
    let arcWidth = max(size * (compact ? 0.074 : 0.064), compact ? 1.15 : 2)

    if !compact {
        context.saveGState()
        context.setStrokeColor(color(0.35, 0.76, 1, 0.14))
        context.setLineWidth(arcWidth + size * 0.018)
        context.setLineCap(.round)
        context.setShadow(
            offset: .zero,
            blur: size * 0.022,
            color: color(0.18, 0.67, 1, 0.22)
        )
        addStatusArcs(to: context, center: glyphCenter, radius: arcRadius)
        context.strokePath()
        context.restoreGState()
    }

    context.saveGState()
    context.setStrokeColor(color(0.97, 0.98, 1, 1))
    context.setLineWidth(arcWidth)
    context.setLineCap(.round)
    addStatusArcs(to: context, center: glyphCenter, radius: arcRadius)
    context.strokePath()
    context.restoreGState()

    let powerDotRadius = max(size * 0.041, compact ? 1.05 : 2)
    let powerDotCenter = CGPoint(x: size * 0.5, y: size * 0.80)
    if !compact {
        context.saveGState()
        context.setShadow(
            offset: .zero,
            blur: size * 0.027,
            color: color(0.19, 0.82, 0.35, 0.55)
        )
        context.setFillColor(color(0.19, 0.82, 0.35, 1))
        context.fillEllipse(in: CGRect(
            x: powerDotCenter.x - powerDotRadius,
            y: powerDotCenter.y - powerDotRadius,
            width: powerDotRadius * 2,
            height: powerDotRadius * 2
        ))
        context.restoreGState()
    } else {
        context.setFillColor(color(0.19, 0.82, 0.35, 1))
        context.fillEllipse(in: CGRect(
            x: powerDotCenter.x - powerDotRadius,
            y: powerDotCenter.y - powerDotRadius,
            width: powerDotRadius * 2,
            height: powerDotRadius * 2
        ))
    }

    let networkRadius = max(size * 0.031, compact ? 0.72 : 1)
    let networkSpacing = size * 0.105
    let networkY = size * 0.22
    for index in 0..<3 {
        let x = size * 0.5 + CGFloat(index - 1) * networkSpacing
        context.setFillColor(color(0.97, 0.98, 1, 1))
        context.fillEllipse(in: CGRect(
            x: x - networkRadius,
            y: networkY - networkRadius,
            width: networkRadius * 2,
            height: networkRadius * 2
        ))
    }

    guard let image = context.makeImage() else {
        throw NSError(domain: "StatusArcIcon", code: 2)
    }
    let representation = NSBitmapImageRep(cgImage: image)
    guard let png = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "StatusArcIcon", code: 3)
    }
    return png
}

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

for variant in variants {
    let data = try renderIcon(pixels: variant.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(variant.filename))
    print("Generated \(variant.filename) (\(variant.pixels) × \(variant.pixels))")
}
