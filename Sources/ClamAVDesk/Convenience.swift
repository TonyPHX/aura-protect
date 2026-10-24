import AppKit
import Foundation

@MainActor
final class FinderScanService: NSObject {
    weak var controller: ScanController?
    init(controller: ScanController) { self.controller = controller }
    @objc func scanWithAura(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { error.pointee = "Select a file or folder in Finder."; return }
        controller?.queueScans(urls)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

extension ScanController {
    static var historyURL: URL { databaseDirectory.deletingLastPathComponent().appendingPathComponent("scan-history.json") }

    func loadScanHistory() {
        history = (try? JSONDecoder().decode([ScanHistoryEntry].self, from: Data(contentsOf: Self.historyURL))) ?? []
    }

    func saveScanHistory() {
        history.insert(.init(id: UUID(), date: .now, target: scanHistoryTarget, scanned: summary.scannedFiles,
                             reused: summary.reusedFiles, skipped: summary.skippedFiles,
                             incomplete: summary.incompleteFiles, detections: detections,
                             duration: summary.duration, mode: scanMode, workers: scanWorkers, engine: clamVersion, detectionDetails: detectionNames), at: 0)
        history = Array(history.prefix(100))
        do {
            try JSONEncoder().encode(history).write(to: Self.historyURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.historyURL.path)
        } catch { backgroundStatus = "Scan finished; history could not be saved: \(error.localizedDescription)" }
    }

    func refreshQuarantine() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.quarantineDirectory, includingPropertiesForKeys: nil)) ?? []
        quarantineRecords = files.filter { $0.pathExtension == "json" }.compactMap {
            guard let data = try? Data(contentsOf: $0) else { return nil }
            return try? JSONDecoder().decode(QuarantineRecord.self, from: data)
        }.sorted { $0.quarantinedAt > $1.quarantinedAt }
    }

    func restoreQuarantine(_ record: QuarantineRecord) {
        let source = URL(fileURLWithPath: record.quarantinedPath).standardizedFileURL
        let original = URL(fileURLWithPath: record.originalPath).standardizedFileURL
        let manager = FileManager.default
        guard record.restoredAt == nil,
              source.deletingLastPathComponent() == Self.quarantineDirectory.standardizedFileURL,
              let stamp = CleanFileStamp.read(source),
              record.fileSHA256 == nil || record.fileSHA256 == stamp.digest else {
            recoveryStatus = "This quarantine item is missing or has changed. It was not restored."
            return
        }
        guard !manager.fileExists(atPath: original.path) else {
            recoveryStatus = "A file already exists at the original location. Nothing was overwritten."
            return
        }
        do {
            try manager.moveItem(at: source, to: original)
            if let permissions = record.originalPermissions {
                do { try manager.setAttributes([.posixPermissions: permissions & 0o777], ofItemAtPath: original.path) }
                catch {
                    try? manager.moveItem(at: original, to: source)
                    try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
                    throw error
                }
            }
            var restored = record
            restored.restoredAt = .now
            do {
                try JSONEncoder().encode(restored).write(to: source.appendingPathExtension("json"), options: .atomic)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.appendingPathExtension("json").path)
            }
            catch {
                try? manager.moveItem(at: original, to: source)
                try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
                throw error
            }
            quarantinedPaths.remove(record.originalPath)
            recoveryStatus = "Restored to \(original.path). Review this file carefully before opening it."
            refreshQuarantine()
        } catch { recoveryStatus = "Could not restore the file: \(error.localizedDescription)" }
    }

    func queueScans(_ urls: [URL]) {
        for url in urls where url.isFileURL && !pendingScanURLs.contains(url) { pendingScanURLs.append(url) }
        scanRequestID = UUID()
        runQueuedScan()
    }

    func scanPreset(_ url: URL) {
        guard !isBusy else { return }
        selectedURL = url
        scanRequestID = UUID()
        startScan()
    }

    func chooseScheduledTarget() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url { settings.scheduledTarget = url.path }
    }

    func configureBackgroundScanning(resetDownloads: Bool = false) {
        backgroundTimer?.invalidate()
        if resetDownloads {
            downloadsInitialized = false
            downloadsBaseline = [:]; downloadsPending = [:]
        }
        backgroundStatus = settings.monitorDownloads || settings.scheduledScan
            ? "Enabled while Aura is open. Scans wait for idle time and reviewed detections."
            : "Background scans are off. Finder requests still run while Aura is open."
        backgroundTimer = .scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.backgroundTick() }
        }
    }

    func backgroundTick(now: Date = .now) {
        if settings.monitorDownloads { pollDownloads() }
        if settings.scheduledScan {
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: now)
            let key = "lastScheduledScanDay"
            if calendar.component(.hour, from: now) >= settings.scheduledHour,
               (UserDefaults.standard.object(forKey: key) as? Date) != day,
               scannerReady, !isBusy, !isUpdating, !isUpdatingEngine, (unquarantinedDetections.isEmpty || resultsReviewed) {
                let target = URL(fileURLWithPath: settings.scheduledTarget)
                if FileManager.default.fileExists(atPath: target.path) {
                    queueScans([target])
                    UserDefaults.standard.set(day, forKey: key)
                } else { backgroundStatus = "Scheduled target is missing. Choose a target in Settings." }
            }
        }
        runQueuedScan()
    }

    func runQueuedScan() {
        guard !pendingScanURLs.isEmpty else { return }
        guard scannerReady, !isBusy, !isUpdating, !isUpdatingEngine, (unquarantinedDetections.isEmpty || resultsReviewed) else {
            backgroundStatus = "\(pendingScanURLs.count) scan request(s) waiting for readiness, idle time, or remediation review."
            return
        }
        let target = pendingScanURLs.removeFirst()
        selectedURL = target
        backgroundStatus = "Scanning \(target.lastPathComponent). Background scans never quarantine automatically."
        scanRequestID = UUID()
        startScan()
    }

    private func pollDownloads() {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else {
            backgroundStatus = "Downloads cannot be read. Check folder access."
            return
        }
        var current: [String: String] = [:]
        for file in files {
            guard !["download", "crdownload", "part", "partial", "tmp"].contains(file.pathExtension.lowercased()),
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let date = values.contentModificationDate else { continue }
            let stamp = "\(values.fileSize ?? 0)|\(date.timeIntervalSince1970)"
            current[file.path] = stamp
            if downloadsInitialized, downloadsBaseline[file.path] != stamp {
                if downloadsPending[file.path] == stamp, Date.now.timeIntervalSince(date) > 15 {
                    if !pendingScanURLs.contains(file) { pendingScanURLs.append(file) }
                    downloadsBaseline[file.path] = stamp
                    downloadsPending.removeValue(forKey: file.path)
                } else { downloadsPending[file.path] = stamp }
            }
        }
        if !downloadsInitialized { downloadsBaseline = current; downloadsInitialized = true }
        downloadsBaseline = downloadsBaseline.filter { current[$0.key] != nil }
        downloadsPending = downloadsPending.filter { current[$0.key] != nil }
    }
}

extension ScanController {
    var rollbackAvailable: Bool { UserDefaults.standard.string(forKey: EngineUpdater.previousEngineKey) != nil }

    func rollbackEngine() {
        guard !isBusy, !isUpdating, !isUpdatingEngine,
              let previous = UserDefaults.standard.string(forKey: EngineUpdater.previousEngineKey) else { return }
        let root = previous == "bundled" ? Bundle.main.resourceURL?.appendingPathComponent("ClamAV") : URL(fileURLWithPath: previous)
        guard let root else { return }
        isUpdatingEngine = true
        Task {
            let usable = await Task.detached { EngineUpdater.validateRuntime(root) }.value
            if usable {
                if previous == "bundled" { UserDefaults.standard.removeObject(forKey: EngineUpdater.currentEngineKey) }
                else { UserDefaults.standard.set(previous, forKey: EngineUpdater.currentEngineKey) }
                UserDefaults.standard.removeObject(forKey: EngineUpdater.previousEngineKey)
                engineUpdateStatus = "Previous engine restored. Check for security updates when ready."
                // Reload engine availability via the same verification used on launch.
                reloadInstalledEngine()
            } else { engineUpdateStatus = "Previous engine failed validation. Current engine was kept." }
            isUpdatingEngine = false
        }
    }
}
