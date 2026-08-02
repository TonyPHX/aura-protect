import SwiftUI

@main
struct ClamAVDeskApp: App {
    @State private var controller = ScanController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controller)
                .frame(minWidth: 820, minHeight: 620)
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
