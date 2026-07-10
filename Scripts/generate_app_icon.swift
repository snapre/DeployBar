#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let packageManifestURL = rootURL.appendingPathComponent("Package.swift")

guard fileManager.fileExists(atPath: packageManifestURL.path) else {
    fputs("Run this script from the DeployBar repository root.\n", stderr)
    exit(1)
}

let resourcesURL = rootURL.appendingPathComponent("Sources/DeployBar/Resources")
let iconsetURL = resourcesURL.appendingPathComponent("DeployBar.iconset")
let icnsURL = resourcesURL.appendingPathComponent("DeployBar.icns")

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let icons: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

var pngDataByName: [String: Data] = [:]
for icon in icons {
    let data = try renderDeployBarIcon(pixelSize: icon.pixels)
    pngDataByName[icon.name] = data
    try data.write(to: iconsetURL.appendingPathComponent(icon.name), options: .atomic)
}

try? fileManager.removeItem(at: icnsURL)
try writeICNS(
    entries: [
        ("icp4", pngDataByName["icon_16x16.png"]),
        ("ic11", pngDataByName["icon_16x16@2x.png"]),
        ("icp5", pngDataByName["icon_32x32.png"]),
        ("ic12", pngDataByName["icon_32x32@2x.png"]),
        ("ic07", pngDataByName["icon_128x128.png"]),
        ("ic13", pngDataByName["icon_128x128@2x.png"]),
        ("ic08", pngDataByName["icon_256x256.png"]),
        ("ic14", pngDataByName["icon_256x256@2x.png"]),
        ("ic09", pngDataByName["icon_512x512.png"]),
        ("ic10", pngDataByName["icon_512x512@2x.png"])
    ].compactMap { type, data in
        data.map { (type, $0) }
    },
    to: icnsURL
)

try? fileManager.removeItem(at: iconsetURL)
print("Generated \(icnsURL.path)")

private func renderDeployBarIcon(pixelSize: Int) throws -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw IconGenerationError.missingGraphicsContext
    }

    let side = CGFloat(pixelSize)
    let badgeColor = CGColor(red: 244.0 / 255.0, green: 250.0 / 255.0, blue: 246.0 / 255.0, alpha: 1)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    context.clear(CGRect(x: 0, y: 0, width: side, height: side))
    // Scale the complete mark as one unit so the app icon fills its canvas.
    // This preserves the proportions between the stripes, badge, and glyph.
    let artworkScale: CGFloat = 1.0 / 0.781
    context.translateBy(x: side / 2, y: side / 2)
    context.scaleBy(x: artworkScale, y: artworkScale)
    context.translateBy(x: -side / 2, y: -side / 2)
    let statusColors = statusColorsTopToBottom()

    let outerRect = CGRect(x: side * 0.109, y: side * 0.109, width: side * 0.781, height: side * 0.781)
    let outerRadius = side * 0.191
    context.saveGState()
    context.addPath(roundedPath(in: outerRect, radius: outerRadius))
    context.clip()
    drawStatusStripes(in: outerRect, colors: statusColors, context: context)
    context.restoreGState()

    context.setStrokeColor(CGColor(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 20.0 / 255.0, alpha: 0.12))
    context.setLineWidth(side * 0.008)
    context.addPath(roundedPath(in: outerRect.insetBy(dx: side * 0.004, dy: side * 0.004), radius: outerRadius - side * 0.004))
    context.strokePath()

    let badgeDiameter = side * 0.586
    let badgeRect = CGRect(
        x: (side - badgeDiameter) / 2,
        y: (side - badgeDiameter) / 2,
        width: badgeDiameter,
        height: badgeDiameter
    )
    context.setFillColor(badgeColor)
    context.fillEllipse(in: badgeRect)

    let markDiameter = side * 0.434
    let markRect = CGRect(
        x: (side - markDiameter) / 2,
        y: (side - markDiameter) / 2,
        width: markDiameter,
        height: markDiameter
    )

    context.saveGState()
    context.addEllipse(in: markRect)
    context.clip()
    context.setFillColor(CGColor(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 20.0 / 255.0, alpha: 1))
    context.fillEllipse(in: markRect)
    context.setStrokeColor(badgeColor)
    context.setLineWidth(side * 0.072)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let glyphRect = CGRect(
        x: side * 0.31,
        y: side * 0.31,
        width: side * 0.38,
        height: side * 0.38
    )
    context.beginPath()
    context.move(to: glyphPoint(x: 0.08, y: 0.65, in: glyphRect))
    context.addLine(to: glyphPoint(x: 0.29, y: 0.34, in: glyphRect))
    context.addLine(to: glyphPoint(x: 0.50, y: 0.65, in: glyphRect))
    context.addLine(to: glyphPoint(x: 0.74, y: 0.29, in: glyphRect))
    context.addLine(to: glyphPoint(x: 0.92, y: 0.29, in: glyphRect))
    context.strokePath()
    context.restoreGState()

    guard let image = context.makeImage() else {
        throw IconGenerationError.pngEncodingFailed
    }

    let pngData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(pngData, "public.png" as CFString, 1, nil) else {
        throw IconGenerationError.pngEncodingFailed
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconGenerationError.pngEncodingFailed
    }

    return pngData as Data
}

private func statusColorsTopToBottom() -> [CGColor] {
    [
        CGColor(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1),
        CGColor(red: 0.0 / 255.0, green: 192.0 / 255.0, blue: 232.0 / 255.0, alpha: 1),
        CGColor(red: 0.0 / 255.0, green: 136.0 / 255.0, blue: 255.0 / 255.0, alpha: 1),
        CGColor(red: 255.0 / 255.0, green: 141.0 / 255.0, blue: 40.0 / 255.0, alpha: 1),
        CGColor(red: 255.0 / 255.0, green: 56.0 / 255.0, blue: 60.0 / 255.0, alpha: 1)
    ]
}

private func drawStatusStripes(in rect: CGRect, colors: [CGColor], context: CGContext) {
    let stripeHeight = rect.height / CGFloat(colors.count)
    for (index, color) in colors.enumerated() {
        let y = rect.maxY - stripeHeight * CGFloat(index + 1)
        context.setFillColor(color)
        context.fill(CGRect(x: rect.minX, y: y, width: rect.width, height: stripeHeight))
    }
}

private func roundedPath(in rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func glyphPoint(x: CGFloat, y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * (1 - y))
}

private func writeICNS(entries: [(type: String, data: Data)], to url: URL) throws {
    var body = Data()
    for entry in entries {
        appendFourCC(entry.type, to: &body)
        appendUInt32(UInt32(entry.data.count + 8), to: &body)
        body.append(entry.data)
    }

    var file = Data()
    appendFourCC("icns", to: &file)
    appendUInt32(UInt32(body.count + 8), to: &file)
    file.append(body)
    try file.write(to: url, options: .atomic)
}

private func appendFourCC(_ value: String, to data: inout Data) {
    precondition(value.utf8.count == 4)
    data.append(contentsOf: value.utf8)
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { bytes in
        data.append(contentsOf: bytes)
    }
}

private enum IconGenerationError: Error {
    case missingGraphicsContext
    case pngEncodingFailed
}
