import SwiftUI

struct RecoveryView: View {
    @Environment(ScanController.self) private var controller
    @State private var pending: QuarantineRecord?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Quarantine").font(.largeTitle.bold())
                    Spacer()
                    Button("Refresh") { controller.refreshQuarantine() }
                }
                Text("Files are moved only after your confirmation. Restore returns a file to its original location without overwriting another file.")
                    .foregroundStyle(.secondary)
                if controller.quarantineRecords.isEmpty { Text("No quarantined files.") }
                ForEach(controller.quarantineRecords, id: \.quarantinedPath) { item in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.originalPath).font(.headline).textSelection(.enabled)
                            Text(item.detectionName ?? "Detection details unavailable for this older item")
                            Text("Quarantined \(item.quarantinedAt.formatted()) • \(item.engineVersion)")
                                .font(.caption).foregroundStyle(.secondary)
                            if let restored = item.restoredAt {
                                Text("Restored \(restored.formatted())").foregroundStyle(.secondary)
                            } else {
                                Button("Restore…") { pending = item }.disabled(controller.isBusy)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                Text(controller.recoveryStatus).textSelection(.enabled)
            }
        }
        .alert("Restore this detected file?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Cancel", role: .cancel) { pending = nil }
            Button("Restore", role: .destructive) {
                if let pending { controller.restoreQuarantine(pending) }
                pending = nil
            }
        } message: { Text("Restoring a file makes it available again. Only restore a file you trust.\n\(pending?.originalPath ?? "")") }
    }
}

struct HistoryView: View {
    @Environment(ScanController.self) private var controller
    @State private var confirmClearHistory = false

    var body: some View {
        @Bindable var controller = controller
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Scan History").font(.largeTitle.bold())
                    Spacer()
                    Button("Clear All History…") { confirmClearHistory = true }
                        .disabled(controller.history.isEmpty && controller.historyError == nil)
                }
                Toggle("Save scan history", isOn: $controller.settings.saveScanHistory)
                Text("Keep up to 100 scan results on this Mac. Turning off saving keeps your existing history until you clear it.")
                    .foregroundStyle(.secondary)
                if let error = controller.historyError {
                    Text(error).foregroundStyle(.red)
                } else if controller.history.isEmpty {
                    Text(controller.settings.saveScanHistory ? "No saved scans yet." : "Scan history is off.")
                        .foregroundStyle(.secondary)
                }
                ForEach(controller.history) { item in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.target).font(.headline).textSelection(.enabled)
                            Text(item.date.formatted()).foregroundStyle(.secondary)
                            if let outcome = item.outcome {
                                Text(outcome).font(.subheadline.weight(.medium))
                            }
                            Text("Scanned: \(item.scanned) • Reused: \(item.reused) • Skipped: \(item.skipped) • Incomplete: \(item.incomplete)")
                            Text("\(item.mode.rawValue) • \(item.workers) worker(s) • \(String(format: "%.1f", item.duration)) seconds • \(item.engine)")
                                .font(.caption).foregroundStyle(.secondary)
                            if let preparation = item.preparationDuration, let startup = item.startupDuration,
                               let matching = item.matchingDuration {
                                Text(String(format: "Preparation %.1fs · Startup %.1fs · Scanning %.1fs", preparation, startup, matching))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let delivery = item.inputDeliveryDuration {
                                Text(String(format: "Input delivery (including waits) %.2fs", delivery))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let firstResult = item.firstResultDuration {
                                Text(String(format: "First file result %.2fs", firstResult))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(item.detections, id: \.self) { path in
                                Text(path + (item.detectionDetails?[path].map { " — " + $0 } ?? "")).foregroundStyle(.red).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
            }
        }
        .confirmationDialog("Clear all scan history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Clear All History", role: .destructive) { controller.clearScanHistory() }
        } message: {
            Text("This permanently deletes the saved scan results on this Mac.")
        }
    }
}
