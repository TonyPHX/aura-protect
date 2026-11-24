import SwiftUI

struct ScannerStatusView: View {
    let wide: Bool
    @Environment(ScanController.self) private var controller
    @State private var expanded = false

    private var workerLimit: Int {
        if controller.isBusy { return controller.scanWorkers }
        return controller.settings.parallelScanning ? controller.effectiveWorkerCount : 1
    }

    private var activeClients: Int {
        controller.isBusy ? controller.scanTelemetry.workers.filter { $0.exitCode == nil }.count : 0
    }
    private var readiness: (title: String, color: Color) {
        if controller.isUpdatingEngine { return ("Checking the scan engine", ConsoleStyle.amber) }
        if controller.isUpdating { return ("Updating definitions", ConsoleStyle.amber) }
        if !controller.scannerReady { return ("Scanner needs attention", .red) }
        if !controller.hasFullDiskAccess { return ("Ready for readable files", ConsoleStyle.amber) }
        if !controller.engineIsCurrent || !controller.definitionsAreCurrent {
            return ("Ready with installed definitions", ConsoleStyle.amber)
        }
        return ("Scanner ready", ConsoleStyle.cyan)
    }

    var body: some View {
        let readiness = readiness
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: wide ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible())] : [GridItem(.flexible())], spacing: 12) {
                    systemPanel("ENGINE", icon: "cpu", state: controller.isUpdatingEngine ? "UPDATING" : controller.engineIsCurrent ? "CURRENT" : controller.engineUsable ? "AVAILABLE" : "CHECK ENGINE",
                                detail: controller.engineUpdateStatus, color: controller.engineIsCurrent ? ConsoleStyle.cyan : controller.engineUsable ? ConsoleStyle.amber : .red,
                                action: "Check engine", working: controller.isUpdatingEngine) { controller.requestEngineUpdateCheck() }
                    systemPanel("DEFINITIONS", icon: "waveform.path.ecg", state: controller.isUpdating ? "UPDATING" : controller.definitionsAreCurrent ? "CURRENT" : "CHECK UPDATES",
                                detail: controller.definitionsStatus, color: controller.definitionsAreCurrent ? ConsoleStyle.cyan : ConsoleStyle.amber,
                                action: "Update definitions", working: controller.isUpdating) { controller.updateDefinitions() }
                    systemPanel("FILE ACCESS", icon: "internaldrive", state: controller.hasFullDiskAccess ? "FULL DISK ACCESS" : "READABLE FILES ONLY",
                                detail: controller.hasFullDiskAccess ? "Protected locations can be inspected." : "Protected locations may be skipped. Enable Full Disk Access for broader coverage.",
                                color: controller.hasFullDiskAccess ? ConsoleStyle.cyan : ConsoleStyle.amber,
                                action: controller.hasFullDiskAccess ? "Check access" : "Enable access…", working: false) {
                        controller.checkFullDiskAccess(showHelpWhenMissing: true)
                    }
                    systemPanel("SCAN CLIENTS", icon: "square.stack.3d.up", state: "\(activeClients) / \(workerLimit) ACTIVE",
                                detail: controller.settings.parallelScanning ? controller.parallelScannerStatus : "Single-process scanning selected in Settings.",
                                color: !controller.settings.parallelScanning || controller.parallelScannerAvailable ? ConsoleStyle.cyan : ConsoleStyle.amber,
                                action: "Check workers", working: controller.isCheckingParallelScanner) { controller.checkParallelScannerAvailability() }
                }
                signaturePanel
            }
            .padding(.top, 12)
        } label: {
            Label(readiness.title, systemImage: "shield.lefthalf.filled")
                .font(.callout.weight(.medium))
                .foregroundStyle(readiness.color)
        }
        .consolePanel()
    }

    @ViewBuilder private var signaturePanel: some View {
        if let snapshot = controller.signatureSnapshot {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    section("DETECTION DATABASE")
                    Spacer()
                    Text(controller.clamVersion).font(.system(size: 10, design: .monospaced)).foregroundStyle(ConsoleStyle.muted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(snapshot.total.formatted()).font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("installed signatures").font(.callout).foregroundStyle(ConsoleStyle.muted)
                }
                ForEach(snapshot.categories) { category in
                    HStack(spacing: 12) {
                        Text(category.name).font(.caption).foregroundStyle(ConsoleStyle.muted).frame(width: 70, alignment: .leading)
                        ProgressView(value: Double(category.count), total: Double(max(snapshot.total, 1))).tint(ConsoleStyle.blue)
                        Text(category.count.formatted()).font(.system(size: 10, design: .monospaced)).foregroundStyle(ConsoleStyle.muted)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(category.name): \(category.count) installed signatures")
                }
            }.padding(18).consolePanel()
        }
    }

    private func systemPanel(_ title: String, icon: String, state: String, detail: String, color: Color,
                             action: String, working: Bool, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(ConsoleStyle.muted)
                Spacer()
                if working { ProgressView().controlSize(.mini) }
                else { Circle().fill(color).frame(width: 5, height: 5) }
            }
            Text(state).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(color)
            Text(detail).font(.caption).foregroundStyle(ConsoleStyle.muted).lineLimit(3).frame(maxWidth: .infinity, minHeight: 43, alignment: .topLeading).help(detail)
            Button(action, action: perform).font(.caption).disabled(working || controller.isBusy || controller.isUpdating || controller.isUpdatingEngine)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).consolePanel()
    }

    private func section(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(ConsoleStyle.muted)
    }
}
