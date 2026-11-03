// Native layout QA only. Illustrative data stays in this separate renderer.
// Compile with Sources/ClamAVDesk/*.swift excluding ClamAVDeskApp.swift.
import AppKit
import SwiftUI

@main
struct RenderStatusDashboard {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/private/tmp/aura-status-previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, width, height, active, partial) in [
            ("status-live-wide", 1040.0, 1400.0, true, false),
            ("status-live-compact", 620.0, 1750.0, true, true),
            ("status-idle", 1040.0, 1400.0, false, true)
        ] {
            let controller = ScanController(startServices: false, recordsHistory: false)
            controller.engineUsable = true
            controller.engineIsCurrent = true
            controller.definitionsAreCurrent = !partial
            controller.hasFullDiskAccess = !partial
            controller.clamVersion = "ClamAV 1.5.4"
            controller.engineUpdateStatus = "ClamAV 1.5.4 is the latest available engine."
            controller.definitionsStatus = partial ? "Installed definitions available. Last online check unavailable." : "Definitions are current. Last checked today."
            controller.parallelScannerAvailable = true
            controller.parallelScannerStatus = "Warm scanner ready. Workers take another batch when available."
            controller.signatureSnapshot = .init(capturedAt: .now, categories: [.init(name: "Main", count: 3287027), .init(name: "Daily", count: 355841), .init(name: "Bytecode", count: 80)])
            if active {
                controller.state = .scanning
                controller.scanHistoryTarget = "/Users/example/Documents"
                controller.totalFiles = 64000
                controller.scanWorkers = 4
                controller.elapsed = 142
                controller.estimatedRemaining = 96
                controller.scanTelemetry.start(queues: [16000, 16000, 16000, 16000], now: 0)
                var completed = 0
                for second in 1...60 {
                    completed += Int(590 + 330 * sin(Double(second) / 7))
                    controller.scanTelemetry.sample(completed: completed, now: Double(second))
                }
                controller.processedFiles = completed
                controller.scanTelemetry.report(path: "/Users/example/Documents/Projects/Design assets.zip", worker: 0, completed: false)
            }
            let root = VStack(spacing: 0) {
                Text("INTERFACE PREVIEW · ILLUSTRATIVE READINGS")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.6)).padding(8)
                    .frame(maxWidth: .infinity).background(Color.black)
                StatusDashboardView().environment(controller)
            }.frame(width: width, height: height)
            let hosting = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("Could not render preview") }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode preview") }
            let destination = output.appendingPathComponent(name + ".png")
            try data.write(to: destination)
            print(destination.path)
            window.orderOut(nil)
        }
    }
}
