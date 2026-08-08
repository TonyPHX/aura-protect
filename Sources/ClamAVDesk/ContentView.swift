import AppKit
import Charts
import SwiftUI

struct ContentView: View {
    @Environment(ScanController.self) private var controller
    @State private var tab = 0

    var body: some View {
        NavigationSplitView {
            List(selection: $tab) {
                Label("Status", systemImage: "checkmark.shield").tag(0)
                Label("Scan", systemImage: "shield.checkered").tag(1)
                Label("Results", systemImage: "doc.text.magnifyingglass").tag(2)
                Label("Updates", systemImage: "arrow.triangle.2.circlepath").tag(3)
                Label("About & Licenses", systemImage: "info.circle").tag(4)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch tab {
                case 1: ScanView()
                case 2: ResultsView()
                case 3: DefinitionsView()
                case 4: LicensesView()
                default: StatusView()
                }
            }
            .padding(28)
        }
        .sheet(isPresented: Binding(
            get: { controller.showFullDiskAccessHelp },
            set: { controller.showFullDiskAccessHelp = $0 }
        )) {
            FullDiskAccessView()
                .environment(controller)
        }
    }
}

private struct LicensesView: View {
    @Environment(ScanController.self) private var controller

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    if let image = NSImage(named: "AuraProtectIcon") ?? bundledIcon {
                        Image(nsImage: image).resizable().frame(width: 72, height: 72)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Aura Protect").font(.largeTitle.bold())
                        Text("Open-source malware scanning for macOS")
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Aura Protect license") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: copyrightNotice)
                        Text("Aura Protect is free and open-source software distributed under the GNU General Public License, version 2 only (GPL-2.0-only). It comes with no warranty.")
                        HStack {
                            Link("View source code", destination: URL(string: "https://github.com/TonyPHX/aura-protect")!)
                            Button("Read full license") { openResource("AuraProtect-License", extension: "txt") }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }

                GroupBox("ClamAV attribution") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Aura Protect is powered by ClamAV, the open-source antivirus engine created and maintained by the ClamAV Team and Cisco Systems, Inc.")
                        Text(engineAttributionText)
                        HStack {
                            Link("ClamAV project", destination: URL(string: "https://www.clamav.net")!)
                            if let sourceURL = clamAVSourceURL {
                                Link("ClamAV \(installedEngineVersion) source", destination: sourceURL)
                            }
                            Button("Read ClamAV license") { openClamAVLicense() }
                        }
                        Text("Aura Protect is an independent community project and is not affiliated with, sponsored by, or endorsed by Cisco Systems or the ClamAV project. Product names and trademarks belong to their respective owners.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }

                GroupBox("Third-party components") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ClamAV includes components maintained by other open-source projects. Their notices are preserved in the application bundle and in the Aura Protect source repository.")
                        Button("Show bundled license notices") { revealLicenseFolder() }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bundledIcon: NSImage? {
        Bundle.main.url(forResource: "AuraProtectIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }

    private var copyrightYear: Int {
        max(Calendar.current.component(.year, from: Date()), 2026)
    }

    private var copyrightNotice: String {
        "Copyright © \(String(copyrightYear)) Tony Simek and Aura Protect contributors."
    }

    private var installedEngineVersion: String {
        EngineUpdater.version(from: controller.clamVersion) ?? "version unavailable"
    }

    private var engineAttributionText: String {
        let license = "is distributed under the GNU General Public License, version 2. Its corresponding source code and third-party license notices are available below and are also included with this application."
        guard let version = EngineUpdater.version(from: controller.clamVersion) else {
            return "The installed ClamAV engine version is currently unavailable. ClamAV \(license)"
        }
        return "The installed ClamAV \(version) runtime \(license)"
    }

    private var clamAVSourceURL: URL? {
        guard let version = EngineUpdater.version(from: controller.clamVersion) else { return nil }
        return URL(string: "https://github.com/Cisco-Talos/clamav/tree/clamav-\(version)")
    }

    private func openResource(_ name: String, extension fileExtension: String) {
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openClamAVLicense() {
        if let executable = ScanController.findExecutable("clamscan") {
            let license = executable.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("licenses/ClamAV-License.txt")
            if FileManager.default.fileExists(atPath: license.path) {
                NSWorkspace.shared.open(license)
                return
            }
        }
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("ClamAV/licenses/ClamAV-License.txt"),
           FileManager.default.fileExists(atPath: bundled.path) {
            NSWorkspace.shared.open(bundled)
        }
    }

    private func revealLicenseFolder() {
        guard let resources = Bundle.main.resourceURL else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: resources.appendingPathComponent("ClamAV/licenses").path)
    }
}

private struct StatusView: View {
    @Environment(ScanController.self) private var controller

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(systemName: controller.dashboardReady ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(controller.dashboardReady ? .green : .red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(controller.dashboardReady ? "Aura Protect Ready" : (controller.scannerReady ? "Performance Attention" : "Action Needed"))
                        .font(.largeTitle.bold())
                    Text(controller.dashboardReady
                         ? "Your scanner is ready to provide its highest level of protection."
                         : (controller.scannerReady
                            ? "Core scanning is ready, but parallel acceleration needs attention. Safe single-process scanning remains available."
                            : "Resolve the core readiness items below before starting a scan."))
                        .foregroundStyle(.secondary)
                }
            }

            readinessRow(title: "Full Disk Access",
                         detail: controller.hasFullDiskAccess ? "Access to protected files is enabled." : "Protected locations cannot be scanned yet.",
                         good: controller.hasFullDiskAccess,
                         working: false,
                         button: controller.hasFullDiskAccess ? "Check Again" : "Enable…") {
                if controller.hasFullDiskAccess { controller.checkFullDiskAccess(showHelpWhenMissing: true) }
                else { controller.showFullDiskAccessHelp = true }
            }

            readinessRow(title: "ClamAV Engine",
                         detail: controller.engineUpdateStatus,
                         good: controller.engineIsCurrent,
                         working: controller.isUpdatingEngine,
                         button: "Check Now") {
                controller.requestEngineUpdateCheck()
            }

            readinessRow(title: "Virus Definitions",
                         detail: controller.definitionsStatus,
                         good: controller.definitionsAreCurrent,
                         working: controller.isUpdating,
                         button: "Update Now") {
                controller.updateDefinitions()
            }

            readinessRow(title: "Parallel Scan Workers",
                         detail: controller.settings.parallelScanning
                            ? controller.parallelScannerStatus
                            : "Parallel scanning is turned off in Settings; scans use reliable single-process mode.",
                         good: !controller.settings.parallelScanning || controller.parallelScannerAvailable,
                         working: controller.isCheckingParallelScanner,
                         button: "Check Now") {
                controller.checkParallelScannerAvailability()
            }

            if let snapshot = controller.signatureSnapshot {
                GroupBox("Detection coverage") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(snapshot.total.formatted()).font(.title.bold())
                            Text("signatures covering viruses, trojans, ransomware, and other malware")
                                .foregroundStyle(.secondary)
                            Spacer()
                            comparison(snapshot)
                        }
                        Chart(snapshot.categories) { category in
                            BarMark(x: .value("Signatures", category.count),
                                    y: .value("Database", category.name))
                                .foregroundStyle(by: .value("Database", category.name))
                                .annotation(position: .trailing) {
                                    Text(category.count.formatted()).font(.caption).foregroundStyle(.secondary)
                                }
                        }
                        .chartLegend(.hidden)
                        .chartXAxis { AxisMarks(format: Decimal.FormatStyle().notation(.compactName)) }
                        .frame(height: 145)
                        Text("ClamAV groups signatures by database rather than reliably classifying each one as a virus, trojan, or other malware type.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
            }

            if controller.scannerReady {
                Label("Engine, definitions, and protected-file access are all ready.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.headline)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func comparison(_ current: SignatureSnapshot) -> some View {
        if let previous = controller.previousSignatureSnapshot {
            let change = current.total - previous.total
            Text("\(change >= 0 ? "+" : "")\(change.formatted()) since previous update")
                .font(.caption.bold()).foregroundStyle(change >= 0 ? .green : .orange)
        } else {
            Text("Baseline recorded").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func readinessRow(title: String, detail: String, good: Bool, working: Bool,
                              button: String, action: @escaping () -> Void) -> some View {
        GroupBox {
            HStack(spacing: 16) {
                if working {
                    ProgressView().controlSize(.small).frame(width: 32, height: 32)
                } else {
                    Image(systemName: good ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title).foregroundStyle(good ? .green : .red)
                        .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button(button, action: action).disabled(working || controller.isBusy)
            }.padding(10)
        }
    }
}

private struct FullDiskAccessView: View {
    @Environment(ScanController.self) private var controller

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "internaldrive.fill.badge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            Text("Allow Full Disk Access")
                .font(.title.bold())
            Text("Aura Protect needs Full Disk Access to scan protected locations such as Mail, Messages, browser data, and other users’ files.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480)

            VStack(alignment: .leading, spacing: 10) {
                instruction(1, "Open Full Disk Access settings.")
                instruction(2, "Find Aura Protect and turn its switch on. If it is not listed, use the + button to add this app.")
                instruction(3, "Return here and choose Check Again.")
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Button("Continue Without Access") { controller.showFullDiskAccessHelp = false }
                Spacer()
                Button("Check Again") { controller.checkFullDiskAccess() }
                Button("Open System Settings") { controller.openFullDiskAccessSettings() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 580)
        .interactiveDismissDisabled()
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(.blue, in: Circle())
                .foregroundStyle(.white)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ScanView: View {
    @Environment(ScanController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Malware Scan").font(.largeTitle.bold())
            HStack {
                Text(controller.clamVersion).foregroundStyle(.secondary)
                Spacer()
                Button {
                    controller.checkFullDiskAccess(showHelpWhenMissing: true)
                } label: {
                    Label(controller.hasFullDiskAccess ? "Full Disk Access enabled" : "Full Disk Access needed",
                          systemImage: controller.hasFullDiskAccess ? "checkmark.shield.fill" : "lock.trianglebadge.exclamationmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(controller.hasFullDiskAccess ? .green : .orange)
                .help("Check Full Disk Access")
            }

            GroupBox("Scan target") {
                HStack {
                    Image(systemName: controller.selectedURL == nil ? "folder.badge.questionmark" : "folder.fill")
                        .font(.title2).foregroundStyle(.blue)
                    Text(controller.selectedURL?.path(percentEncoded: false) ?? "No file or folder selected")
                        .lineLimit(2).textSelection(.enabled)
                    Spacer()
                    Button("Choose…") { controller.chooseTarget() }.disabled(controller.isBusy)
                }.padding(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(controller.state.label).font(.headline)
                    Spacer()
                    if controller.state == .scanning {
                        Group {
                            if controller.totalFiles > 0 {
                                Text("\(controller.processedFiles) of \(controller.totalFiles) files")
                            } else {
                                Text("Discovering files…")
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                if controller.state == .scanning && controller.totalFiles == 0 {
                    ProgressView()
                } else {
                    ProgressView(value: controller.progress)
                }
                HStack {
                    Text("Elapsed: \(format(controller.elapsed))")
                    Spacer()
                    if let eta = controller.estimatedRemaining { Text("About \(format(eta)) remaining") }
                }.font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button("Start Scan") { controller.startScan() }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!controller.canScan)
                if controller.isBusy {
                    Button("Cancel") { controller.cancelScan() }.controlSize(.large)
                }
                Spacer()
                SettingsLink { Label("Scan Settings", systemImage: "gearshape") }
            }

            if !controller.scannerReady {
                Label("Complete the red readiness checks on the Status screen before scanning.",
                      systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }

            if !controller.detections.isEmpty {
                Label("\(controller.detections.count) threat\(controller.detections.count == 1 ? "" : "s") detected", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.headline)
            }
            if controller.state == .finishedWithIssues {
                Label("The scan completed, but ClamAV reported \(controller.summary.errors) error\(controller.summary.errors == 1 ? "" : "s"). Open Results for the affected paths and details.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
    }

    private func format(_ value: TimeInterval) -> String {
        let seconds = max(Int(value.rounded()), 0)
        return seconds >= 3600 ? String(format: "%dh %02dm", seconds / 3600, seconds / 60 % 60)
             : seconds >= 60 ? String(format: "%dm %02ds", seconds / 60, seconds % 60)
             : "\(seconds)s"
    }
}

private struct ResultsView: View {
    @Environment(ScanController.self) private var controller
    @State private var showQuarantineConfirmation = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Scan Results").font(.largeTitle.bold())
                Spacer()
                if controller.state.hasResults {
                    Button { controller.exportReport() } label: {
                        Label("Save Report…", systemImage: "square.and.arrow.down")
                    }
                }
            }
            if controller.state.hasResults {
                HStack(spacing: 28) {
                    metric("Files scanned", "\(controller.summary.scannedFiles)", .blue)
                    metric("Threats", "\(controller.summary.infectedFiles)", controller.summary.infectedFiles == 0 ? .green : .red)
                    metric("Duration", String(format: "%.1fs", controller.summary.duration), .secondary)
                }
                GroupBox("Scan overview") {
                    HStack(spacing: 28) {
                        Chart(scanChartItems) { item in
                            SectorMark(angle: .value("Files", item.count), innerRadius: .ratio(0.58),
                                       angularInset: 1.5)
                                .foregroundStyle(by: .value("Result", item.name))
                        }
                        .chartForegroundStyleScale([
                            "Clean": Color.green, "Detections": Color.red, "Errors": Color.orange
                        ])
                        .frame(width: 180, height: 180)

                        VStack(alignment: .leading, spacing: 12) {
                            reportLine("Clean files", cleanFiles.formatted(), .green)
                            reportLine("Concerning detections", controller.summary.infectedFiles.formatted(), .red)
                            reportLine("Scan errors", controller.summary.errors.formatted(), .orange)
                            reportLine("Skipped by limits or access", controller.summary.skippedFiles.formatted(), .orange)
                            reportLine("Unchanged files reused", controller.summary.reusedFiles.formatted(), .blue)
                            Divider()
                            reportLine("Average throughput", throughput, .blue)
                            reportLine("Protection signatures",
                                       controller.signatureSnapshot?.total.formatted() ?? "—", .purple)
                        }
                        Spacer()
                    }.padding(8)
                    Text("Target: \(controller.selectedURL?.path(percentEncoded: false) ?? "Unknown")  •  Engine: \(controller.clamVersion)")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.horizontal, 8)
                }
            }
            if !controller.detections.isEmpty {
                GroupBox("Detected files") {
                    VStack(alignment: .leading, spacing: 10) {
                        List {
                            ForEach(controller.detections, id: \.self) { path in
                                detectionRow(path)
                            }
                        }.frame(minHeight: 100, maxHeight: 180)

                        HStack {
                            if !controller.unquarantinedDetections.isEmpty {
                                Button {
                                    showQuarantineConfirmation = true
                                } label: {
                                    Label("Quarantine Detected Files…", systemImage: "shield.lefthalf.filled")
                                }
                            }
                            Button { controller.revealQuarantine() } label: {
                                Label("Show Quarantine Folder", systemImage: "folder")
                            }
                        }
                        if let status = controller.quarantineStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(status.contains("could not") || status.hasPrefix("Could not") ? .red : .green)
                                .textSelection(.enabled)
                        }
                        Text("Nothing is removed automatically. Quarantine only occurs after you confirm it, and files are moved—not deleted—with recovery information saved alongside them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }.padding(8)
                }
            }
            if !controller.skippedFileDetails.isEmpty {
                GroupBox("Files not scanned") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("These files were outside the configured size limit or could not be read. The saved report includes the total.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(controller.skippedFileDetails, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
                        if controller.summary.skippedFiles > controller.skippedFileDetails.count {
                            Text("…and \(controller.summary.skippedFiles - controller.skippedFileDetails.count) more")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(8)
                }
            }
            GroupBox("Concerning findings and scan errors") {
                Text(controller.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading).padding(8)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Quarantine detected files?", isPresented: $showQuarantineConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Quarantine \(controller.unquarantinedDetections.count) File\(controller.unquarantinedDetections.count == 1 ? "" : "s")") {
                controller.quarantineDetectedFiles()
            }
        } message: {
            Text("The selected detections will be moved into Aura Protect’s private quarantine. They will not be deleted. Because false positives are possible, review the detected paths before continuing.")
        }
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading) { Text(value).font(.title.bold()).foregroundStyle(color); Text(title).foregroundStyle(.secondary) }
    }

    private func detectionRow(_ path: String) -> some View {
        let quarantined = controller.quarantinedPaths.contains(path)
        return Label(path, systemImage: quarantined ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(quarantined ? Color.secondary : Color.red)
            .textSelection(.enabled)
    }

    private var cleanFiles: Int {
        max(controller.summary.scannedFiles - controller.summary.infectedFiles - controller.summary.errors, 0)
    }

    private var scanChartItems: [ScanChartItem] {
        [ScanChartItem(name: "Clean", count: cleanFiles, colorName: "green"),
         ScanChartItem(name: "Detections", count: controller.summary.infectedFiles, colorName: "red"),
         ScanChartItem(name: "Errors", count: controller.summary.errors, colorName: "orange")]
            .filter { $0.count > 0 }
    }

    private var throughput: String {
        guard controller.summary.duration > 0 else { return "—" }
        return "\(Int(Double(controller.summary.scannedFiles) / controller.summary.duration).formatted()) files/sec"
    }

    private func reportLine(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack { Circle().fill(color).frame(width: 9, height: 9); Text(title); Spacer(); Text(value).font(.headline.monospacedDigit()) }
    }
}

private struct DefinitionsView: View {
    @Environment(ScanController.self) private var controller
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Virus Definitions").font(.largeTitle.bold())
            Text("Fresh definitions help ClamAV recognize recently discovered threats.").foregroundStyle(.secondary)
            GroupBox {
                HStack(spacing: 16) {
                    Image(systemName: controller.isUpdating ? "arrow.triangle.2.circlepath" :
                            (controller.definitionsAreCurrent ? "checkmark.shield.fill" : "xmark.shield.fill"))
                        .font(.largeTitle)
                        .foregroundStyle(controller.isUpdating ? Color.blue :
                            (controller.definitionsAreCurrent ? Color.green : Color.red))
                    VStack(alignment: .leading) {
                        Text(controller.definitionsStatus).font(.headline)
                        Text("Uses the bundled ClamAV updater").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Update Now") { controller.updateDefinitions() }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.isUpdating || controller.isBusy || controller.isUpdatingEngine)
                }.padding(12)
            }
            GroupBox("Definition database") {
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 8) {
                    GridRow { Text("Daily database version").foregroundStyle(.secondary); Text(controller.definitionDatabaseVersion).font(.headline.monospacedDigit()) }
                    GridRow { Text("Database release").foregroundStyle(.secondary); Text(controller.definitionRelease) }
                    GridRow { Text("Last attempt").foregroundStyle(.secondary); Text(formatted(controller.lastDefinitionsAttempt)) }
                    GridRow { Text("Last successful update").foregroundStyle(.secondary); Text(formatted(controller.lastDefinitionsSuccess)) }
                    GridRow { Text("Automatic checks").foregroundStyle(.secondary); Text("Every 4 hours while Aura Protect is open") }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("Definition update log") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent update milestones, warnings, and errors. Repeated transport chatter is omitted.")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        Text(controller.definitionUpdateLog)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(8)
                    }.frame(minHeight: 120, maxHeight: 220)
                }
            }
            GroupBox("ClamAV engine") {
                HStack(spacing: 12) {
                    if controller.isUpdatingEngine { ProgressView().controlSize(.small) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(controller.clamVersion).font(.headline)
                        Text(controller.engineUpdateStatus).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Now") { controller.requestEngineUpdateCheck() }
                        .disabled(controller.isUpdatingEngine || controller.isBusy)
                }.padding(8)
            }
            Text("Definitions are stored privately in your user Library. Administrator access is not required.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func formatted(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }
}
