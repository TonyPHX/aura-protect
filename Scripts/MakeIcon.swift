import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: MakeIcon <iconset directory> <output.icns>\n".utf8))
    exit(2)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let entries = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
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
for (type, filename) in entries {
    let image = try Data(contentsOf: directory.appendingPathComponent(filename))
    elements.append(Data(type.utf8))
    elements.append(bigEndian(UInt32(image.count + 8)))
    elements.append(image)
}

var icon = Data("icns".utf8)
icon.append(bigEndian(UInt32(elements.count + 8)))
icon.append(elements)
try icon.write(to: output, options: .atomic)
