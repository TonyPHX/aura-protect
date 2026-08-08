import SwiftUI

struct SettingsView: View {
    @Environment(ScanController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section("Scan behavior") {
                Toggle("Use faster parallel scanning", isOn: $controller.settings.parallelScanning)
                if controller.settings.parallelScanning {
                    Toggle("Automatically tune workers for this Mac", isOn: $controller.settings.automaticWorkerTuning)
                    HStack {
                        Text("Parallel workers")
                        Spacer()
                        Stepper("\(controller.settings.workerCount)", value: $controller.settings.workerCount,
                                in: 2...min(max(ProcessInfo.processInfo.activeProcessorCount, 2), 12))
                    }
                    .disabled(controller.settings.automaticWorkerTuning)
                    Text(controller.settings.automaticWorkerTuning
                         ? "Aura Protect balances CPU and memory use automatically."
                         : "More workers use additional CPU and may not improve SSD-limited scans.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Reuse unchanged clean files", isOn: $controller.settings.incrementalScanning)
                Text("Optional incremental mode reuses clean results only while Aura Protect remains open, and resets whenever the engine or definitions change. Turn it off for a fresh full scan.")
                    .font(.caption).foregroundStyle(.secondary)
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
