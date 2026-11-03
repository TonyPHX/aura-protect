import Charts
import SwiftUI

private enum Dash {
    static let background = Color(red: 0.025, green: 0.043, blue: 0.065)
    static let panel = Color(red: 0.045, green: 0.071, blue: 0.101)
    static let border = Color(red: 0.12, green: 0.21, blue: 0.28)
    static let cyan = Color(red: 0.22, green: 0.91, blue: 0.92)
    static let blue = Color(red: 0.35, green: 0.67, blue: 1)
    static let violet = Color(red: 0.72, green: 0.61, blue: 1)
    static let amber = Color(red: 1, green: 0.75, blue: 0.35)
    static let text = Color(red: 0.91, green: 0.96, blue: 0.99)
    static let muted = Color(red: 0.54, green: 0.66, blue: 0.75)

    static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
    }

    static func compact(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func duration(_ value: TimeInterval?) -> String {
        guard let value, value.isFinite else { return "—" }
        let seconds = max(Int(value), 0)
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
             : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct StatusDashboardView: View {
    var onScan: () -> Void = {}
    var onUpdates: () -> Void = {}
    var onResults: () -> Void = {}
    @Environment(ScanController.self) private var controller
    private var live: Bool { controller.state == .scanning }
    private var hasSession: Bool { !controller.scanHistoryTarget.isEmpty }
    private var scale: Double { ScanSpeedScale.maximum(for: controller.scanTelemetry.peakRate) }
    private var activeClients: Int {
        controller.isBusy ? controller.scanTelemetry.workers.filter { $0.exitCode == nil }.count : 0
    }
    private var readinessColor: Color {
        !controller.scannerReady ? .red : controller.engineIsCurrent && controller.definitionsAreCurrent && controller.hasFullDiskAccess
            ? Dash.cyan : Dash.amber
    }
    private var readinessTitle: String {
        if !controller.scannerReady { return "Scanner needs attention" }
        if !controller.hasFullDiskAccess { return "Ready for readable files" }
        return controller.engineIsCurrent && controller.definitionsAreCurrent ? "Scanner ready" : "Ready with installed definitions"
    }
    private var phase: String {
        if controller.state == .counting { return "BUILDING INVENTORY" }
        if controller.state == .cancelling { return "STOPPING SCAN" }
        if live && controller.scanTelemetry.workers.isEmpty { return "LOADING SCANNER" }
        if live { return "LIVE TELEMETRY" }
        return hasSession ? "LAST SCAN" : "STANDBY"
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if geometry.size.width >= 900 {
                        HStack(alignment: .top, spacing: 14) { speedPanel; averagePanel; completionPanel }
                    } else {
                        speedPanel
                        HStack(alignment: .top, spacing: 14) { averagePanel; completionPanel }
                    }
                    sessionStrip
                    throughputPanel
                    HStack(alignment: .top) {
                        section("SCANNER SYSTEMS")
                        Spacer()
                        Label(readinessTitle, systemImage: "shield.lefthalf.filled")
                            .font(.caption).foregroundStyle(readinessColor)
                    }.padding(.top, 8)
                    LazyVGrid(columns: geometry.size.width >= 600 ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible())] : [GridItem(.flexible())], spacing: 12) {
                        systemPanel("ENGINE", icon: "cpu", state: controller.isUpdatingEngine ? "UPDATING" : controller.engineIsCurrent ? "CURRENT" : controller.engineUsable ? "AVAILABLE" : "CHECK ENGINE",
                                    detail: controller.engineUpdateStatus, color: controller.engineIsCurrent ? Dash.cyan : controller.engineUsable ? Dash.amber : .red,
                                    action: "Check engine", working: controller.isUpdatingEngine) { controller.requestEngineUpdateCheck() }
                        systemPanel("DEFINITIONS", icon: "waveform.path.ecg", state: controller.isUpdating ? "UPDATING" : controller.definitionsAreCurrent ? "CURRENT" : "CHECK UPDATES",
                                    detail: controller.definitionsStatus, color: controller.definitionsAreCurrent ? Dash.cyan : Dash.amber,
                                    action: "Update definitions", working: controller.isUpdating) { controller.updateDefinitions() }
                        systemPanel("FILE ACCESS", icon: "internaldrive", state: controller.hasFullDiskAccess ? "FULL DISK ACCESS" : "READABLE FILES ONLY",
                                    detail: controller.hasFullDiskAccess ? "Protected locations can be inspected." : "Protected locations may be skipped. Enable Full Disk Access for broader coverage.",
                                    color: controller.hasFullDiskAccess ? Dash.cyan : Dash.amber,
                                    action: controller.hasFullDiskAccess ? "Check access" : "Enable access…", working: false) {
                            controller.checkFullDiskAccess(showHelpWhenMissing: true)
                        }
                        systemPanel("SCAN CLIENTS", icon: "square.stack.3d.up", state: "\(activeClients) / \(controller.isBusy ? controller.scanWorkers : controller.effectiveWorkerCount) ACTIVE",
                                    detail: controller.settings.parallelScanning ? controller.parallelScannerStatus : "Single-process scanning selected in Settings.",
                                    color: !controller.settings.parallelScanning || controller.parallelScannerAvailable ? Dash.cyan : Dash.amber,
                                    action: "Check workers", working: controller.isCheckingParallelScanner) { controller.checkParallelScannerAvailability() }
                    }
                    signaturePanel
                    Text("On-demand scanning · Local processing · User-controlled quarantine")
                        .font(.caption).foregroundStyle(Dash.muted).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .padding(24)
                .frame(maxWidth: 1400, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Dash.background)
        }
        .foregroundStyle(Dash.text)
        .tint(Dash.cyan)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2).fill(Dash.cyan).frame(width: 42, height: 4)
                Text("AURA PROTECT / SYSTEM OVERVIEW")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2)
                    .foregroundStyle(Dash.muted)
                Spacer()
                Text("01 — STATUS").font(.system(size: 9, design: .monospaced)).foregroundStyle(Dash.muted)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) { heading; Spacer(minLength: 20); actions }
                VStack(alignment: .leading, spacing: 12) { heading; actions }
            }
        }.padding(.bottom, 4)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Performance cockpit").font(.system(size: 30, weight: .semibold, design: .rounded))
            HStack(spacing: 7) {
                Circle().fill(readinessColor).frame(width: 6, height: 6)
                Text(readinessTitle).font(.callout).foregroundStyle(Dash.muted)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onUpdates) { Image(systemName: "arrow.triangle.2.circlepath").padding(3) }
                .help("Open engine and definition updates").accessibilityLabel("Open Updates")
            Button(action: onScan) {
                Label(controller.isBusy ? "Open scan" : "Choose a scan", systemImage: "arrow.up.right")
                    .font(.callout.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundStyle(Dash.background)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Dash.cyan))
            }.buttonStyle(.plain)
        }
    }

    private var speedPanel: some View {
        instrument(index: "01", name: "SCAN VELOCITY", color: Dash.cyan) {
            SpeedometerDial(value: live ? controller.scanTelemetry.currentRate : nil, maximum: scale,
                            display: live ? Dash.rate(controller.scanTelemetry.currentRate) : hasSession ? "Stopped" : "Standby",
                            unit: "FILES / SECOND", color: Dash.cyan)
            HStack {
                Label(phase, systemImage: live ? "waveform.path" : "pause.circle")
                Spacer()
                Text("AUTO · \(Dash.compact(scale)) F/S")
            }.font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Dash.muted)
        }
        .help("Measured completions per sampling interval, normally one second. The range adapts to the session peak and is shown explicitly. No active scan means no live rate.")
    }

    private var averagePanel: some View {
        instrument(index: "02", name: "SESSION AVERAGE", color: Dash.blue) {
            SpeedometerDial(value: controller.scanTelemetry.averageRate, maximum: scale,
                            display: Dash.rate(controller.scanTelemetry.averageRate), unit: "FILES / SECOND", color: Dash.blue)
            HStack {
                Text("PEAK INTERVAL")
                Spacer()
                Text("\(Dash.rate(controller.scanTelemetry.peakRate)) F/S").foregroundStyle(Dash.blue)
            }.font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Dash.muted)
        }.help("Average file completions since scan-client dispatch, through the last measured interval. Excludes inventory and scanner startup. Peak is the highest measured interval, not a hardware speed rating.")
    }

    private var completionPanel: some View {
        instrument(index: "03", name: "INVENTORY PROGRESS", color: Dash.violet) {
            SpeedometerDial(value: controller.totalFiles > 0 ? controller.scanFraction * 100 : nil, maximum: 100,
                            display: controller.state == .counting ? "Inventory" : controller.totalFiles > 0 ? "\(Int(controller.scanFraction * 100))%" : "—",
                            unit: controller.state == .counting ? "TOTAL NOT KNOWN YET" : "FILES COMPLETED", color: Dash.violet, isPercentage: true)
            HStack {
                Text(controller.processedFiles.formatted())
                Spacer()
                Text("OF \(controller.totalFiles.formatted()) FILES")
            }.font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Dash.muted)
        }.help("Completed files divided by the full eligible inventory. Skipped, reused and incompletely inspected files are reported separately. Inventory preparation has no invented percentage.")
    }

    private var sessionStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), alignment: .leading)], alignment: .leading, spacing: 16) {
            readout("ELAPSED", Dash.duration(hasSession ? controller.elapsed : nil), color: Dash.text)
            readout("EST. REMAINING", Dash.duration(controller.estimatedRemaining), color: Dash.text)
            readout("DETECTIONS", controller.detections.count.formatted(), color: controller.detections.isEmpty ? Dash.muted : .red)
            readout("SKIPPED / REUSED", "\(controller.liveSkippedFiles.formatted()) / \(controller.liveReusedFiles.formatted())", color: Dash.muted)
            readout("INCOMPLETE / ERRORS", "\(controller.incompletePaths.count.formatted()) / \(controller.liveScanErrors.formatted())",
                    color: controller.incompletePaths.isEmpty && controller.liveScanErrors == 0 ? Dash.muted : Dash.amber)
        }.padding(18).dashboardPanel()
    }

    private var throughputPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                section("THROUGHPUT TRACE")
                Spacer()
                Text("\(phase) · RECENT 60 SECONDS").font(.system(size: 8, design: .monospaced)).foregroundStyle(Dash.muted)
            }
            if controller.scanTelemetry.samples.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path").font(.title2).foregroundStyle(Dash.cyan.opacity(0.5))
                    Text(controller.isBusy ? "Waiting for measured file completions" : "Start a scan to see live throughput")
                        .font(.callout).foregroundStyle(Dash.muted)
                    Text("Measured data appears here. Preparation can take time before the first file completes.")
                        .font(.caption).foregroundStyle(Dash.muted)
                }.frame(maxWidth: .infinity).frame(height: 120)
            } else {
                Chart(controller.scanTelemetry.samples) { sample in
                    AreaMark(x: .value("Seconds since scanning began", sample.seconds), y: .value("Files per second", sample.filesPerSecond))
                        .foregroundStyle(LinearGradient(colors: [Dash.cyan.opacity(0.24), Dash.cyan.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Seconds since scanning began", sample.seconds), y: .value("Files per second", sample.filesPerSecond))
                        .foregroundStyle(Dash.cyan).lineStyle(StrokeStyle(lineWidth: 2))
                    if controller.scanTelemetry.samples.count == 1 {
                        PointMark(x: .value("Seconds since scanning began", sample.seconds), y: .value("Files per second", sample.filesPerSecond)).foregroundStyle(Dash.cyan)
                    }
                }
                .chartYScale(domain: 0...max((controller.scanTelemetry.samples.map(\.filesPerSecond).max() ?? 0) * 1.1, 10))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine().foregroundStyle(Dash.border); AxisValueLabel().foregroundStyle(Dash.muted) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(Dash.border); AxisValueLabel().foregroundStyle(Dash.muted) } }
                .frame(height: 120)
                .accessibilityLabel("Measured scan throughput, recent minute, in files per second")
            }
            Divider().overlay(Dash.border)
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(Dash.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.scanTelemetry.latestPathIsCurrent && live ? "CURRENT FILE" : "LAST REPORTED FILE")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(Dash.muted)
                    Text(controller.scanTelemetry.latestPath ?? "No file activity yet")
                        .font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        .help(controller.scanTelemetry.latestPath ?? "File paths appear when the scanner reports them.")
                }
                Spacer(minLength: 4)
                if hasSession { Button("Results", action: onResults).disabled(!controller.state.hasResults) }
            }
        }.padding(18).dashboardPanel()
    }

    @ViewBuilder private var signaturePanel: some View {
        if let snapshot = controller.signatureSnapshot {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    section("DETECTION DATABASE")
                    Spacer()
                    Text(controller.clamVersion).font(.system(size: 10, design: .monospaced)).foregroundStyle(Dash.muted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(snapshot.total.formatted()).font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("installed signatures").font(.callout).foregroundStyle(Dash.muted)
                }
                ForEach(snapshot.categories) { category in
                    HStack(spacing: 12) {
                        Text(category.name).font(.caption).foregroundStyle(Dash.muted).frame(width: 70, alignment: .leading)
                        ProgressView(value: Double(category.count), total: Double(max(snapshot.total, 1))).tint(Dash.blue)
                        Text(category.count.formatted()).font(.system(size: 10, design: .monospaced)).foregroundStyle(Dash.muted)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(category.name): \(category.count) installed signatures")
                }
            }.padding(18).dashboardPanel()
        }
    }

    private func systemPanel(_ title: String, icon: String, state: String, detail: String, color: Color,
                             action: String, working: Bool, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Dash.muted)
                Spacer()
                if working { ProgressView().controlSize(.mini) }
                else { Circle().fill(color).frame(width: 5, height: 5) }
            }
            Text(state).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(color)
            Text(detail).font(.caption).foregroundStyle(Dash.muted).lineLimit(3).frame(maxWidth: .infinity, minHeight: 43, alignment: .topLeading).help(detail)
            Button(action, action: perform).font(.caption).disabled(working || controller.isBusy || controller.isUpdating || controller.isUpdatingEngine)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).dashboardPanel()
    }

    private func instrument<Content: View>(index: String, name: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(index).foregroundStyle(color)
                Text(name).foregroundStyle(Dash.muted)
                Spacer(minLength: 0)
                Image(systemName: "scope").foregroundStyle(color.opacity(0.7))
            }.font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.6)
            content()
        }.padding(16).frame(maxWidth: .infinity).dashboardPanel()
    }

    private func readout(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Dash.muted)
            Text(value).font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(color)
        }
    }

    private func section(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(Dash.muted)
    }
}

private struct SpeedometerDial: View {
    let value: Double?
    let maximum: Double
    let display: String
    let unit: String
    let color: Color
    var isPercentage = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var fraction: Double { ScanSpeedScale.fraction(rate: value, maximum: maximum) }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.44)
            let radius = min(geometry.size.width * 0.43, geometry.size.height * 0.37)
            ZStack {
                Canvas { context, _ in
                    var arc = Path()
                    arc.addArc(center: center, radius: radius * 0.78, startAngle: .degrees(135), endAngle: .degrees(405), clockwise: false)
                    context.stroke(arc, with: .color(color.opacity(0.12)), style: StrokeStyle(lineWidth: 13, lineCap: .butt))
                    if value != nil && fraction > 0 {
                        var illuminated = Path()
                        illuminated.addArc(center: center, radius: radius * 0.78, startAngle: .degrees(135),
                                           endAngle: .degrees(135 + fraction * 270), clockwise: false)
                        context.stroke(illuminated, with: .color(color.opacity(0.6)),
                                       style: StrokeStyle(lineWidth: 13, lineCap: .butt))
                    }
                    var inner = Path()
                    inner.addArc(center: center, radius: radius * 0.63, startAngle: .degrees(135), endAngle: .degrees(405), clockwise: false)
                    context.stroke(inner, with: .color(Dash.border), lineWidth: 1)
                    for index in 0...50 {
                        let angle = (135 + Double(index) * 5.4) * .pi / 180
                        let major = index % 10 == 0
                        let outer = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                        let inner = CGPoint(x: center.x + cos(angle) * radius * (major ? 0.9 : 0.95), y: center.y + sin(angle) * radius * (major ? 0.9 : 0.95))
                        var tick = Path(); tick.move(to: inner); tick.addLine(to: outer)
                        context.stroke(tick, with: .color(major ? color.opacity(0.9) : Dash.muted.opacity(0.45)), lineWidth: major ? 2 : 1)
                        if major {
                            let label = Dash.compact(Double(index) / 50 * maximum)
                            context.draw(Text(label).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(Dash.muted),
                                         at: CGPoint(x: center.x + cos(angle) * radius * 1.17, y: center.y + sin(angle) * radius * 1.17))
                        }
                    }
                }
                DialNeedle(fraction: fraction).stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .shadow(color: color.opacity(0.65), radius: 5)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: fraction)
                Circle().fill(Dash.panel).frame(width: 17, height: 17).overlay(Circle().stroke(color.opacity(0.6), lineWidth: 1)).position(center)
                Circle().fill(color).frame(width: 5, height: 5).position(center)
                VStack(spacing: 5) {
                    Text(display).font(.system(size: display.count > 7 ? 25 : 34, weight: .medium, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.65)
                    Text(unit).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Dash.muted)
                }.position(x: center.x, y: geometry.size.height * 0.84)
            }
        }
        .frame(height: 205)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit)
        .accessibilityValue(value == nil ? display : "\(display)\(isPercentage ? "" : " files per second"). Scale zero to \(Dash.rate(maximum)).")
    }
}

private struct DialNeedle: Shape {
    var fraction: Double
    var animatableData: Double { get { fraction } set { fraction = newValue } }
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.width / 2, y: rect.height * 0.44)
        let radius = min(rect.width * 0.43, rect.height * 0.37)
        let angle = (135 + min(max(fraction, 0), 1) * 270) * .pi / 180
        var path = Path()
        path.move(to: CGPoint(x: center.x - cos(angle) * radius * 0.12, y: center.y - sin(angle) * radius * 0.12))
        path.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.78, y: center.y + sin(angle) * radius * 0.78))
        return path
    }
}

private extension View {
    func dashboardPanel() -> some View {
        self.background(RoundedRectangle(cornerRadius: 14).fill(Dash.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Dash.border, lineWidth: 1))
    }
}
