import SwiftUI

struct SettingsView: View {
    @Environment(ScanController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section("Performance") {
                Picker("Scan mode", selection: $controller.settings.scanMode) {
                    ForEach(ScanMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                Text("Quiet uses one worker. Balanced caps workers at four; Fast uses up to eight within CPU and memory limits. History records mode, workers, and duration for comparison on your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Scan behavior") {
                Toggle("Use faster parallel scanning", isOn: $controller.settings.parallelScanning)
                if controller.settings.parallelScanning {
                    Toggle("Automatically tune workers for this Mac", isOn: $controller.settings.automaticWorkerTuning)
                    HStack {
                        Text("Parallel workers")
                        Spacer()
                        if controller.settings.automaticWorkerTuning || controller.settings.scanMode == .quiet {
                            Text("Up to \(controller.effectiveWorkerCount)")
                        } else {
                            Stepper("\(controller.settings.workerCount)", value: $controller.settings.workerCount,
                                    in: 1...min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 12))
                        }
                    }
                    .disabled(controller.settings.automaticWorkerTuning || controller.settings.scanMode == .quiet)
                    Text(controller.settings.automaticWorkerTuning
                         ? "Aura Protect balances CPU and memory use automatically."
                         : "More workers use additional CPU and may not improve SSD-limited scans.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Reuse unchanged clean files", isOn: $controller.settings.incrementalScanning)
                Text("Optional incremental mode reuses clean results only while Aura Protect remains open, verifies file contents and resets whenever scan options, the engine, or any definition file changes. Turn it off for a fresh full scan.")
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
            Section("While Aura is open") {
                Toggle("Scan new completed Downloads", isOn: $controller.settings.monitorDownloads)
                Text("Checks new or changed files directly inside Downloads after they settle. Existing files are left for manual scans. This does not block files from opening.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Run a daily scheduled scan", isOn: $controller.settings.scheduledScan)
                if controller.settings.scheduledScan {
                    Stepper("Start after \(controller.settings.scheduledHour):00", value: $controller.settings.scheduledHour, in: 0...23)
                    Text(controller.settings.scheduledTarget).font(.caption).textSelection(.enabled)
                    Button("Choose Scheduled Target…") { controller.chooseScheduledTarget() }
                }
                Text("Aura must remain open. Scans wait while busy or while detections need review. Missed scans run after the scheduled hour when Aura is available.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(controller.backgroundStatus).font(.caption)
                if !controller.pendingScanURLs.isEmpty {
                    Button("Clear Waiting Requests") { controller.pendingScanURLs.removeAll() }
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
