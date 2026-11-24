import AppKit
import os

@MainActor
final class ScanDiagnosticsDelegate: NSObject, NSApplicationDelegate {
    weak var controller: ScanController?
    private var diagnostics: ScanDiagnostics?
    private var heartbeat: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let diagnostics = ScanDiagnostics()
        self.diagnostics = diagnostics
        let heartbeat = DispatchSource.makeTimerSource(queue: .main)
        heartbeat.schedule(deadline: .now(), repeating: .seconds(2))
        heartbeat.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                let controller = self?.controller
                diagnostics.beat(phase: controller?.scanPaused == true ? "Paused" : controller?.state.label,
                                 discovering: controller?.discoveringFiles, processed: controller?.processedFiles)
            }
        }
        self.heartbeat = heartbeat
        heartbeat.resume()
    }

    func applicationWillTerminate(_ notification: Notification) {
        heartbeat?.cancel()
        diagnostics?.finish()
    }

    func reveal() {
        let folder = ScanDiagnostics.directory
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        NSWorkspace.shared.open(folder)
    }
}

private final class ScanDiagnostics: Sendable {
    private struct Session: Codable, Sendable {
        var launchedAt = Date()
        var processID = ProcessInfo.processInfo.processIdentifier
        var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        var lastResponsiveAt = Date()
        var phase: String? = "Launching"
        var discovering: Bool?
        var filesProcessed: Int?
        var unresponsiveSince: Date?
        var lastStallStartedAt: Date?
        var longestObservedStallSeconds = 0
        var exit: String?
        var macOSTermination: String?
    }

    private struct State: Sendable {
        var session = Session()
        var lastBeat = ProcessInfo.processInfo.systemUptime
        var lastWrite = -Double.infinity
        var monitorTick = ProcessInfo.processInfo.systemUptime
    }

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Aura Protect/Diagnostics", isDirectory: true)
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "Aura Protect diagnostics", qos: .utility)
    private let monitor: DispatchSourceTimer

    init() {
        monitor = DispatchSource.makeTimerSource(queue: queue)
        queue.async { [self] in
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true,
                                                      attributes: [.posixPermissions: 0o700])
            let current = Self.directory.appendingPathComponent("current-session.json")
            if let data = try? Data(contentsOf: current),
               var previous = Self.decode(data),
               previous.exit == nil || previous.longestObservedStallSeconds > 0 {
                if previous.exit == nil {
                    previous.macOSTermination = Self.crashReason(for: previous)
                    previous.exit = previous.macOSTermination == nil ? "Unexpected exit (cause unavailable)" : "macOS reported a crash"
                }
                save(previous, as: "last-issue.json")
            }
            checkpoint(force: true)
        }
        monitor.schedule(deadline: .now() + .seconds(2), repeating: .seconds(2), leeway: .milliseconds(500))
        monitor.setEventHandler { [weak self] in self?.checkpoint() }
        monitor.resume()
    }

    deinit { monitor.cancel() }

    func beat(phase: String?, discovering: Bool?, processed: Int?) {
        state.withLock { value in
            value.lastBeat = ProcessInfo.processInfo.systemUptime
            value.session.lastResponsiveAt = .now
            value.session.phase = phase ?? "Launching"
            value.session.discovering = discovering
            value.session.filesProcessed = processed
            value.session.unresponsiveSince = nil
        }
    }

    func finish() {
        monitor.cancel()
        queue.sync {
            let session = state.withLock { value in
                value.session.exit = "Normal quit"
                return value.session
            }
            save(session, as: "current-session.json")
        }
    }

    private func checkpoint(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        let session = state.withLock { value -> Session? in
            guard value.session.exit == nil else { return nil }
            // A stalled monitor cannot distinguish a main-thread stall from a process-wide suspension.
            if now - value.monitorTick > 8 {
                value.lastBeat = now
                value.session.unresponsiveSince = nil
            }
            value.monitorTick = now
            let stalledFor = Int(now - value.lastBeat)
            let beganStall = stalledFor >= 10 && value.session.unresponsiveSince == nil
            if stalledFor >= 10 {
                value.session.unresponsiveSince = value.session.lastResponsiveAt
                value.session.lastStallStartedAt = value.session.lastResponsiveAt
                value.session.longestObservedStallSeconds = max(value.session.longestObservedStallSeconds, stalledFor)
            }
            guard force || beganStall || now - value.lastWrite >= (stalledFor >= 10 ? 4 : 10) else { return nil }
            value.lastWrite = now
            return value.session
        }
        if let session { save(session, as: "current-session.json") }
    }

    private func save(_ session: Session, as name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = Self.directory.appendingPathComponent(name)
        do {
            try encoder.encode(session).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Logger(subsystem: "com.local.AuraProtect", category: "Diagnostics")
                .error("Could not save a diagnostic checkpoint: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func decode(_ data: Data) -> Session? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Session.self, from: data)
    }

    private static func crashReason(for session: Session) -> String? {
        let reportDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let reports = try? FileManager.default.contentsOfDirectory(at: reportDirectory,
                                                                           includingPropertiesForKeys: Array(keys)) else { return nil }
        for report in reports where report.pathExtension == "ips" {
            guard report.lastPathComponent.hasPrefix("ClamAVDesk") || report.lastPathComponent.hasPrefix("Aura Protect"),
                  let info = try? report.resourceValues(forKeys: keys),
                  let modified = info.contentModificationDate, modified >= session.launchedAt,
                  let size = info.fileSize, size < 4_000_000,
                  let data = try? Data(contentsOf: report),
                  let separator = data.firstIndex(of: 10),
                  let header = (try? JSONSerialization.jsonObject(with: data.prefix(upTo: separator))) as? [String: Any],
                  header["bug_type"] as? String == "309",
                  let body = (try? JSONSerialization.jsonObject(with: data.suffix(from: data.index(after: separator)))) as? [String: Any],
                  body["pid"] as? Int32 == session.processID,
                  body["procName"] as? String == "ClamAVDesk" else { continue }
            let termination = body["termination"] as? [String: Any]
            let exception = body["exception"] as? [String: Any]
            var details = [termination?["namespace"] as? String, termination?["indicator"] as? String,
                           exception?["signal"] as? String, exception?["type"] as? String].compactMap { $0 }
            if let code = termination?["code"] as? NSNumber {
                details.append("code 0x" + String(code.uint64Value, radix: 16))
            }
            return details.isEmpty ? "See the matching report in macOS Console" : details.joined(separator: ", ")
        }
        return nil
    }
}
