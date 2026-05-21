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

for icon in icons {
    let data = try renderDeployBarIcon(pixelSize: icon.pixels)
    try data.write(to: iconsetURL.appendingPathComponent(icon.name), options: .atomic)
}

try? fileManager.removeItem(at: icnsURL)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fputs("iconutil failed with status \(process.terminationStatus).\n", stderr)
    exit(process.terminationStatus)
}

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
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    context.clear(CGRect(x: 0, y: 0, width: side, height: side))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillEllipse(in: CGRect(
        x: side * 0.148,
        y: side * 0.148,
        width: side * 0.704,
        height: side * 0.704
    ))

    context.setBlendMode(.clear)
    context.setStrokeColor(CGColor(gray: 0, alpha: 1))
    context.setLineWidth(side * 0.084)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.beginPath()
    context.move(to: CGPoint(x: side * 0.295, y: side * 0.453))
    context.addLine(to: CGPoint(x: side * 0.386, y: side * 0.592))
    context.addLine(to: CGPoint(x: side * 0.477, y: side * 0.453))
    context.addLine(to: CGPoint(x: side * 0.584, y: side * 0.617))
    context.addLine(to: CGPoint(x: side * 0.715, y: side * 0.617))
    context.strokePath()
    context.setBlendMode(.normal)

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

private enum IconGenerationError: Error {
    case missingGraphicsContext
    case pngEncodingFailed
}
