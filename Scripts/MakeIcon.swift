#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write(Data("Usage: MakeIcon <source.png> <corrected.png> <output.icns>\n".utf8))
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let correctedURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

guard let source = NSImage(contentsOf: sourceURL),
      let sourceRepresentation = source.representations.max(by: { $0.pixelsWide < $1.pixelsWide }) else {
    FileHandle.standardError.write(Data("Could not read the source icon.\n".utf8))
    exit(1)
}

func pngData(size: Int, roundedCorners: Bool) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "AuraProtectIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        throw NSError(domain: "AuraProtectIcon", code: 2)
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    if roundedCorners {
        let radius = CGFloat(size) * 0.20
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
    }
    source.draw(
        in: bounds,
        from: NSRect(
            x: 0,
            y: 0,
            width: sourceRepresentation.pixelsWide,
            height: sourceRepresentation.pixelsHigh
        ),
        operation: .copy,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AuraProtectIcon", code: 3)
    }
    return data
}

let iconsetURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("AuraProtect-\(UUID().uuidString).iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconsetURL) }

let files = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

let master = try pngData(size: 1024, roundedCorners: true)
try master.write(to: correctedURL, options: .atomic)
for (size, name) in files {
    let resize = Process()
    resize.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    resize.arguments = [
        "--resampleHeightWidth", String(size), String(size),
        correctedURL.path,
        "--out", iconsetURL.appendingPathComponent(name).path
    ]
    resize.standardOutput = FileHandle.nullDevice
    try resize.run()
    resize.waitUntilExit()
    guard resize.terminationStatus == 0 else { exit(resize.terminationStatus) }
}

let chunks = [
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func bigEndian(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
}

var elements = Data()
for (type, filename) in chunks {
    let image = try Data(contentsOf: iconsetURL.appendingPathComponent(filename))
    elements.append(Data(type.utf8))
    elements.append(bigEndian(UInt32(image.count + 8)))
    elements.append(image)
}

var icon = Data("icns".utf8)
icon.append(bigEndian(UInt32(elements.count + 8)))
icon.append(elements)
try icon.write(to: outputURL, options: .atomic)
