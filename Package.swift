// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClamAVDesk",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ClamAVDesk", targets: ["ClamAVDesk"])],
    targets: [.executableTarget(name: "ClamAVDesk")]
)
