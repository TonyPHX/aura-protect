import Charts
import SwiftUI

private enum ConsoleStyle {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.075)
    static let panel = Color(red: 0.055, green: 0.083, blue: 0.108)
    static let cyan = Color(red: 0.20, green: 0.83, blue: 0.95)
    static let blue = Color(red: 0.43, green: 0.65, blue: 0.87)
    static let amber = Color(red: 1.0, green: 0.74, blue: 0.31)
    static let violet = Color(red: 0.69, green: 0.58, blue: 0.85)
    static let text = Color(red: 0.92, green: 0.95, blue: 0.98)
    static let muted = Color(red: 0.63, green: 0.72, blue: 0.80)
    static let border = Color(red: 0.16, green: 0.26, blue: 0.32)
}

struct ScanConsoleView: View {
    var onShowResults: (() -> Void)? = nil
    @Environment(ScanController.self) private var controller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selectedMode: ScanMode { controller.isBusy || hasSession ? controller.scanMode : controller.settings.scanMode }
    private var hasSession: Bool { !controller.scanHistoryTarget.isEmpty }
    private var heading: String {
        if controller.state == .failed { return "Scan could not finish" }
        if controller.state == .counting { return "Preparing inventory" }
        if controller.state == .cancelling { return "Stopping scan" }
        if controller.state == .scanning { return "Scanning \(URL(fileURLWithPath: controller.scanHistoryTarget).lastPathComponent)" }
        return controller.scanWasCancelled ? "Scan stopped" : controller.state.hasResults ? "Scan results ready" : "Ready to explore"
    }
    private var status: String {
        if controller.state == .counting { return "Building the file inventory. Progress appears when the total is known." }
        if controller.state == .scanning && controller.scanTelemetry.workers.isEmpty { return "Preparing the scanner and loading definitions…" }
        if controller.scanWasCancelled { return "Stopped by you. Completed files remain visible below." }
        return controller.state == .idle ? "Choose a target and start a local malware scan." : controller.state.label
    }
    private var accent: Color { controller.detections.isEmpty ? ConsoleStyle.cyan : .red }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    consoleRail
                    header
                    if geometry.size.width >= 760 {
                        HStack(alignment: .center, spacing: 26) {
                            progressInstrument.frame(width: 270)
                            telemetryPanel.frame(maxWidth: .infinity)
                        }
                    } else {
                        progressInstrument.frame(maxWidth: .infinity)
                        telemetryPanel
                    }
                    if geometry.size.width >= 760 && !controller.scanTelemetry.workers.isEmpty {
                        HStack(alignment: .top, spacing: 16) {
                            workersPanel.frame(maxWidth: .infinity)
                            resultCounters.frame(width: 280)
                        }
                    } else {
                        if !controller.scanTelemetry.workers.isEmpty { workersPanel }
                        resultCounters
                    }
                    filePanel
                    if !controller.isBusy { controls }
                    if controller.state == .failed {
                        Label(controller.log, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(ConsoleStyle.amber).lineLimit(5).consolePanel()
                    }
                    Text(controller.backgroundStatus)
                        .font(.caption).foregroundStyle(ConsoleStyle.muted)
                    if !controller.scannerReady && !controller.isBusy {
                        Label("A working engine and installed definitions are required. Open Status or Updates for details.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(ConsoleStyle.amber)
                    } else if !controller.hasFullDiskAccess {
                        Label("Readable files can be scanned. Protected locations may be skipped until Full Disk Access is enabled.", systemImage: "lock")
                            .font(.caption).foregroundStyle(ConsoleStyle.muted)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .background(ConsoleStyle.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Text(controller.isBusy ? "Results update as files complete." : "Local scanning · user-controlled remediation")
                        .font(.caption).foregroundStyle(ConsoleStyle.muted)
                    Spacer(minLength: 12)
                    if controller.state.hasResults, let onShowResults {
                        Button("View Results", action: onShowResults)
                    }
                    scanActions
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(ConsoleStyle.background)
                .overlay(alignment: .top) { Rectangle().fill(ConsoleStyle.border).frame(height: 1) }
            }
        }
        .foregroundStyle(ConsoleStyle.text)
        .tint(ConsoleStyle.cyan)
        .environment(\.colorScheme, .dark)
    }

    private var consoleRail: some View {
        HStack(spacing: 5) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 0)
                .fill(ConsoleStyle.blue).frame(width: 26)
            Rectangle().fill(ConsoleStyle.blue)
            Rectangle().fill(ConsoleStyle.amber).frame(width: 55)
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 16)
                .fill(ConsoleStyle.violet).frame(width: 65)
        }.frame(height: 9).accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("AURA / SCAN CONSOLE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2.3)
                .foregroundStyle(ConsoleStyle.blue)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { title; Spacer(minLength: 12); modeBadge }
                VStack(alignment: .leading, spacing: 10) { title; modeBadge }
            }
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(controller.isBusy ? accent : ConsoleStyle.muted).frame(width: 6, height: 6).padding(.top, 5)
                Text(status).font(.callout).foregroundStyle(ConsoleStyle.muted)
            }
        }
    }

    private var title: some View {
        Text(heading).font(.system(size: 30, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }

    private var workerBadge: String {
        if !controller.scanTelemetry.workers.isEmpty { return "\(controller.scanTelemetry.workers.count) WORKER \(controller.scanTelemetry.workers.count == 1 ? "QUEUE" : "QUEUES")" }
        if controller.state.hasResults && controller.scanWorkers == 0 { return "NO FILES SUBMITTED" }
        let count = controller.isBusy ? controller.scanWorkers : (controller.settings.parallelScanning ? controller.effectiveWorkerCount : 1)
        return "UP TO \(count) WORKERS"
    }

    private var modeBadge: some View {
        Text("\(selectedMode.rawValue.uppercased()) · \(workerBadge)")
            .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(0.8)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().stroke(ConsoleStyle.cyan.opacity(0.8), lineWidth: 1))
            .fixedSize()
    }

    private var progressInstrument: some View {
        ZStack {
            SegmentedScanRing(fraction: controller.scanFraction, color: accent)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: controller.scanFraction)
            VStack(spacing: 7) {
                if controller.state == .counting {
                    ProgressView().controlSize(.small).padding(6)
                    Text("Inventory").font(.title2.weight(.medium))
                } else if controller.totalFiles > 0 {
                    Text("\(Int(controller.scanFraction * 100))%")
                        .font(.system(size: 57, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("\(controller.processedFiles.formatted()) / \(controller.totalFiles.formatted()) files")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(ConsoleStyle.muted)
                } else {
                    Image(systemName: controller.state.hasResults ? "checkmark.circle" : "shield.lefthalf.filled")
                        .font(.system(size: 35, weight: .light)).foregroundStyle(accent)
                    Text(controller.state.hasResults ? "Finished" : "Standby").font(.title2.weight(.medium))
                    Text(controller.state.hasResults ? (controller.liveSkippedFiles > 0 ? "No eligible files were scanned" : controller.liveReusedFiles > 0 ? "Clean results reused" : "No eligible files") : "Local file inspection")
                        .font(.caption).foregroundStyle(ConsoleStyle.muted)
                }
                Text(controller.state == .scanning ? "FILES COMPLETED" : controller.state == .counting ? "ESTABLISHING TOTAL" : "SCAN PROGRESS")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(ConsoleStyle.blue)
            }
        }
        .frame(width: 250, height: 250)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan progress")
        .accessibilityValue(controller.state == .counting ? "Preparing inventory; total unknown" : "\(controller.processedFiles) of \(controller.totalFiles) files completed. \(controller.state.label)")
    }

    private var telemetryPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                instrument(controller.state == .scanning ? "FILES / SEC" : "LAST RATE", value: controller.scanTelemetry.currentRate.map { Int($0.rounded()).formatted() } ?? "—")
                Divider().overlay(ConsoleStyle.border)
                instrument("ELAPSED", value: duration(controller.elapsed))
                Divider().overlay(ConsoleStyle.border)
                instrument("ABOUT REMAINING", value: (controller.state == .scanning ? controller.estimatedRemaining : nil).map(duration) ?? "—")
            }.frame(height: 66)
            ThroughputChart(samples: controller.scanTelemetry.samples)
        }.consolePanel()
    }

    private func instrument(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(0.6)
                .foregroundStyle(ConsoleStyle.muted).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var workersPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("WORKER QUEUES")
                Spacer()
                Text("Observed file completions").font(.caption2).foregroundStyle(ConsoleStyle.muted)
            }
            ScrollView {
                VStack(spacing: 9) {
                    ForEach(controller.scanTelemetry.workers) { worker in
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", worker.id + 1))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(workerColor(worker.id)).frame(width: 28)
                            Text("Worker \(worker.id + 1)").font(.caption.weight(.medium)).frame(width: 66, alignment: .leading)
                            GeometryReader { bar in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(ConsoleStyle.border.opacity(0.55))
                                    Capsule().fill(workerColor(worker.id)).frame(width: bar.size.width * worker.fraction)
                                }
                            }
                            .frame(height: 5)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: worker.fraction)
                            .help(worker.latestPath ?? "Waiting for a file result")
                            Text(controller.scanWasCancelled ? "Stopped" : controller.state == .cancelling ? "Stopping" : worker.exitCode.map { $0 > 1 ? "Issue" : "Done" } ?? "Scanning")
                                .font(.caption2).foregroundStyle(worker.exitCode.map { $0 > 1 } == true ? ConsoleStyle.amber : ConsoleStyle.muted)
                                .frame(width: 48, alignment: .trailing)
                            Text("\(worker.completed.formatted()) / \(worker.queued.formatted())")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(ConsoleStyle.muted)
                                .frame(minWidth: 75, alignment: .trailing)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ConsoleStyle.background))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Worker \(worker.id + 1), \(worker.completed) of \(worker.queued) files completed")
                    }
                }
            }
            .frame(height: min(CGFloat(controller.scanTelemetry.workers.count) * 43, 215))
            .scrollIndicators(.visible)
        }.consolePanel()
    }

    private var resultCounters: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 16)], alignment: .leading, spacing: 16) {
            counter("Detections", controller.detections.count, symbol: "exclamationmark.shield", color: controller.detections.isEmpty ? ConsoleStyle.text : .red)
            counter("Skipped", controller.liveSkippedFiles, symbol: "doc.badge.ellipsis", color: controller.liveSkippedFiles == 0 ? ConsoleStyle.muted : ConsoleStyle.amber)
            counter("Incomplete", controller.incompletePaths.count, symbol: "circle.lefthalf.filled", color: controller.incompletePaths.isEmpty ? ConsoleStyle.muted : ConsoleStyle.amber)
            counter("Errors", controller.liveScanErrors, symbol: "exclamationmark.triangle", color: controller.liveScanErrors == 0 ? ConsoleStyle.muted : ConsoleStyle.amber)
            counter("Reused", controller.liveReusedFiles, symbol: "arrow.triangle.2.circlepath", color: ConsoleStyle.violet)
        }.consolePanel()
    }

    private func counter(_ label: String, _ count: Int, symbol: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(ConsoleStyle.muted)
                Text(count.formatted()).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)
            }
        }.accessibilityElement(children: .combine)
    }

    private var filePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel(controller.scanTelemetry.latestPathIsCurrent ? "CURRENT FILE" : "LAST REPORTED FILE")
            HStack(spacing: 10) {
                Image(systemName: "doc.text").foregroundStyle(ConsoleStyle.blue)
                Text(controller.scanTelemetry.latestPath ?? "File activity appears as the scanner reports it.")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(ConsoleStyle.muted)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .help(controller.scanTelemetry.latestPath ?? "Waiting for scanner output")
            }
            Text(controller.isBusy ? controller.scanHistoryTarget : controller.selectedURL?.path ?? "Choose a scan target")
                .font(.caption2).foregroundStyle(ConsoleStyle.muted).lineLimit(1).truncationMode(.middle)
        }.frame(maxWidth: .infinity, alignment: .leading).consolePanel()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { targetPresets; Spacer(); SettingsLink { Label("Scan Settings", systemImage: "gearshape") } }
                VStack(alignment: .leading, spacing: 12) { targetPresets; SettingsLink { Label("Scan Settings", systemImage: "gearshape") } }
            }
            HStack {
                Text(controller.clamVersion).lineLimit(1).truncationMode(.tail)
                Spacer()
            }.font(.caption).foregroundStyle(ConsoleStyle.muted)
        }
    }

    private var targetPresets: some View {
        HStack(spacing: 8) {
            Menu("Quick targets") {
                ForEach(controller.scanPresets, id: \.0) { preset in
                    Button("Scan \(preset.0)") { controller.scanPreset(preset.1) }.disabled(!controller.canScan)
                }
            }.fixedSize().disabled(controller.isBusy)
            Button("Choose Target…") { controller.chooseTarget() }.disabled(controller.isBusy)
        }
    }

    private var scanActions: some View {
        Group {
            if controller.isBusy {
                Button(controller.state == .cancelling ? "Stopping…" : "Cancel Scan") { controller.cancelScan() }
                    .disabled(controller.state == .cancelling).controlSize(.large)
                    .buttonStyle(ConsoleActionStyle(color: ConsoleStyle.amber)).keyboardShortcut(.cancelAction)
            } else {
                Button("Start Scan") { controller.startScan() }
                    .buttonStyle(ConsoleActionStyle(color: ConsoleStyle.cyan, filled: true)).controlSize(.large).disabled(!controller.canScan)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.7).foregroundStyle(ConsoleStyle.blue)
    }
    private func workerColor(_ index: Int) -> Color { [ConsoleStyle.cyan, ConsoleStyle.blue, ConsoleStyle.violet][index % 3] }
    private func duration(_ seconds: TimeInterval) -> String {
        let value = max(Int(seconds.rounded()), 0)
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private struct SegmentedScanRing: View {
    let fraction: Double
    let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(ConsoleStyle.border, lineWidth: 1).padding(1)
            ForEach(0..<40) { index in
                Circle().trim(from: Double(index) / 40 + 0.004, to: Double(index + 1) / 40 - 0.004)
                    .stroke(Double(index) / 40 < fraction ? color : ConsoleStyle.border, lineWidth: 12)
                    .rotationEffect(.degrees(-90)).padding(12)
            }
            Circle().stroke(ConsoleStyle.blue.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [1, 6])).padding(27)
        }.accessibilityHidden(true)
    }
}

private struct ThroughputChart: View {
    let samples: [ScanRateSample]
    private var last: Double { samples.last?.seconds ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SCAN THROUGHPUT").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.3)
                Spacer()
                Text("Files / second").font(.caption2)
            }.foregroundStyle(ConsoleStyle.blue)
            if samples.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).stroke(ConsoleStyle.border, lineWidth: 1)
                    Text("Measured throughput appears as files complete.")
                        .font(.caption).foregroundStyle(ConsoleStyle.muted).multilineTextAlignment(.center).padding()
                }.frame(height: 120)
            } else {
                Chart(samples) { sample in
                    AreaMark(x: .value("Seconds", sample.seconds), y: .value("Files per second", sample.filesPerSecond))
                        .foregroundStyle(LinearGradient(colors: [ConsoleStyle.cyan.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Seconds", sample.seconds), y: .value("Files per second", sample.filesPerSecond))
                        .foregroundStyle(ConsoleStyle.cyan).lineStyle(.init(lineWidth: 1.5))
                    if samples.count == 1 {
                        PointMark(x: .value("Seconds", sample.seconds), y: .value("Files per second", sample.filesPerSecond))
                            .foregroundStyle(ConsoleStyle.cyan)
                    }
                }
                .chartXScale(domain: max(0, last - 60)...max(5, last))
                .chartYScale(domain: 0...max(1, (samples.map(\.filesPerSecond).max() ?? 1) * 1.15))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(ConsoleStyle.border.opacity(0.5))
                        AxisValueLabel(anchor: .top).foregroundStyle(ConsoleStyle.muted).font(.system(size: 9, design: .monospaced))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(ConsoleStyle.border.opacity(0.5))
                        AxisValueLabel(anchor: .trailing).foregroundStyle(ConsoleStyle.muted).font(.system(size: 9, design: .monospaced))
                    }
                }
                .frame(height: 120)
                .accessibilityLabel("Measured file completions per second, most recent minute")
            }
            Text("Recent minute · seconds since scanning began")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(ConsoleStyle.muted)
        }
    }
}

private extension View {
    func consolePanel() -> some View {
        padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(ConsoleStyle.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ConsoleStyle.border, lineWidth: 1))
    }
}

private struct ConsoleActionStyle: ButtonStyle {
    let color: Color
    var filled = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(filled ? ConsoleStyle.background : ConsoleStyle.text)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(filled ? color : color.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.8), lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
