import SwiftUI

struct SettingsView: View {
    @Environment(ScanController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section("Scan behavior") {
                Toggle("Use faster parallel scanning", isOn: $controller.settings.parallelScanning)
                if controller.settings.parallelScanning {
                    HStack {
                        Text("Parallel workers")
                        Spacer()
                        Stepper("\(controller.settings.workerCount)", value: $controller.settings.workerCount,
                                in: 2...min(max(ProcessInfo.processInfo.activeProcessorCount, 2), 12))
                    }
                    Text("Four workers is a good balance for most Macs. More workers use additional CPU and may not improve SSD-limited scans.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Scan folders recursively", isOn: $controller.settings.recursive)
                Toggle("Inspect archives", isOn: $controller.settings.scanArchives)
                Toggle("Include hidden files", isOn: $controller.settings.scanHidden)
                Toggle("Detect potentially unwanted applications", isOn: $controller.settings.detectPUA)
                Toggle("Follow symbolic links", isOn: $controller.settings.followSymlinks)
            }
            Section("Limits") {
                HStack {
                    Text("Maximum file size")
                    Spacer()
                    Stepper("\(controller.settings.maxFileSizeMB) MB", value: $controller.settings.maxFileSizeMB, in: 1...2048, step: 25)
                }
            }
            Section("Alerts") {
                Toggle("Play a sound when threats are detected", isOn: $controller.settings.bellOnDetection)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
