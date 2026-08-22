import AppKit
import SwiftUI

@main
struct ClamAVDeskApp: App {
    @State private var controller = ScanController()

    init() {
        if let url = Bundle.main.url(forResource: "AuraProtectIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controller)
                .frame(minWidth: 820, minHeight: 620)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    controller.shutdown()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        Settings {
            SettingsView()
                .environment(controller)
                .frame(width: 520, height: 380)
        }
    }
}
