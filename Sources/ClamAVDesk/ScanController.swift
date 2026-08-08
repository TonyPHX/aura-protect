import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ScanController {
    var settings = ScanSettings.load() { didSet { settings.save() } }
    var selectedURL: URL? = FileManager.default.homeDirectoryForCurrentUser
    var state: ScanState = .idle
    var progress = 0.0
    var processedFiles = 0
    var totalFiles = 0
    var elapsed: TimeInterval = 0
    var estimatedRemaining: TimeInterval?
    var log = "Choose a file or folder to begin."
    var detections: [String] = []
    var summary = ScanSummary()
    var definitionsStatus = "Not checked"
    var isUpdating = false
    var clamVersion = "Checking…"
    var engineUpdateStatus = "Checking for engine updates…"
    var isUpdatingEngine = false
    var engineIsCurrent = false
    var definitionsAreCurrent = false
    var lastDefinitionsAttempt: Date?
    var lastDefinitionsSuccess: Date?
    var definitionDatabaseVersion = "Unknown"
    var definitionRelease = "Unknown"
    var definitionUpdateLog = "No definition update has been recorded yet."
    var signatureSnapshot: SignatureSnapshot?
    var previousSignatureSnapshot: SignatureSnapshot?
    var scanCompletedAt: Date?
    var quarantinedPaths: Set<String> = []
    var quarantineStatus: String?
    var hasFullDiskAccess = false
    var showFullDiskAccessHelp = false
    var parallelScannerAvailable = false
    var parallelScannerStatus = "Checking parallel scanner…"
    var isCheckingParallelScanner = false
    var skippedFileDetails: [String] = []
    private var skippedFileCount = 0

    private var scanProcess: Process?
    private var scanProcesses: [Process] = []
    private var daemonProcess: Process?
    private var updateProcess: Process?
    private var scanTask: Task<Void, Never>?
    private var startTime: Date?
    private var timer: Timer?
    private var outputBuffer = ""
    private var scanFileListURLs: [URL] = []
    private var parallelClientsRemaining = 0
    private var parallelExitCode: Int32 = 0
    private var parallelOutputBuffers: [ObjectIdentifier: String] = [:]
    private var daemonOutputBuffer = ""
    private var scanErrorCount = 0
    private var definitionUpdateTimer: Timer?
    private var definitionRetryTask: Task<Void, Never>?
    private var definitionRetryCount = 0
    private var activeDaemonConfig: URL?
    private var activeDaemonSettings: ScanSettings?
    private var incrementalCache: [String: FileStamp] = [:]
    private var incrementalCacheKey = ""
    private var pendingCache: [String: FileStamp] = [:]
    private var reusedFileCount = 0
    private var scanUsesIncrementalCache = false

    private struct FileStamp: Equatable, Sendable {
        let size: Int64
        let modified: TimeInterval
    }

    private struct ScanPreparation: Sendable {
        let count: Int
        let fileLists: [URL]
        let directFiles: [URL]
        let skipped: [String]
        let skippedCount: Int
        let reused: Int
    }

    private static let lastDefinitionsAttemptKey = "lastDefinitionsAttempt"
    private static let lastDefinitionsSuccessKey = "lastDefinitionsSuccess"

    init() {
        Self.migrateLegacySupportData()
        loadDefinitionUpdateState()
        loadSignatureSnapshots()
        refreshSignatureSnapshot(recordChange: false)
        checkFullDiskAccess(showHelpWhenMissing: true)
        scheduleDefinitionUpdates()
        Task {
            await loadVersion()
            checkParallelScannerAvailability()
            await checkForEngineUpdates()
            updateDefinitions(automatic: true)
        }
    }

    var scannerReady: Bool { hasFullDiskAccess && engineIsCurrent && definitionsAreCurrent }
    var dashboardReady: Bool { scannerReady && (!settings.parallelScanning || parallelScannerAvailable) }
    var canScan: Bool { selectedURL != nil && !isBusy && !isUpdatingEngine && scannerReady }
    var isBusy: Bool { [.counting, .scanning, .cancelling].contains(state) }

    private var effectiveWorkerCount: Int {
        guard settings.automaticWorkerTuning else { return settings.workerCount }
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let memoryGB = max(Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824), 1)
        return min(max(min(cores / 2, memoryGB / 2), 2), 8)
    }

    func chooseTarget() {
        let panel = NSOpenPanel()
        panel.title = "Choose a file or folder to scan"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        if panel.runModal() == .OK { selectedURL = panel.url }
    }

    func checkFullDiskAccess(showHelpWhenMissing: Bool = true) {
        hasFullDiskAccess = Self.canReadProtectedData()
        if hasFullDiskAccess {
            showFullDiskAccessHelp = false
        } else if showHelpWhenMissing {
            showFullDiskAccessHelp = true
        }
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func checkParallelScannerAvailability() {
        isCheckingParallelScanner = true
        let daemon = Self.findExecutable("clamd")
        let client = Self.findExecutable("clamdscan")
        parallelScannerAvailable = daemon != nil && client != nil
        parallelScannerStatus = parallelScannerAvailable
            ? "Parallel scanner components are installed. Their connection is verified when each scan starts."
            : "Parallel workers are unavailable. Scans will continue safely in single-process mode."
        isCheckingParallelScanner = false
    }

    func startScan() {
        guard scannerReady else {
            fail("Scanner readiness checks are incomplete. Open Status and resolve the red items before scanning.")
            return
        }
        guard let target = selectedURL, let executable = Self.findExecutable("clamscan") else {
            fail("Could not find clamscan. Install ClamAV with Homebrew, or reinstall it with: brew install clamav")
            return
        }
        guard Self.hasVirusDatabase else {
            fail("Virus definitions have not been downloaded yet. Open Definitions and choose Update Now, then start the scan again.")
            return
        }
        resetScan()
        state = .counting
        log = ""
        var tunedSettings = settings
        tunedSettings.workerCount = tunedSettings.parallelScanning ? effectiveWorkerCount : 1
        let currentSettings = tunedSettings
        let cacheKey = "\(EngineUpdater.version(from: clamVersion) ?? clamVersion)|\(definitionDatabaseVersion)"
        if incrementalCacheKey != cacheKey {
            incrementalCache.removeAll(keepingCapacity: false)
            incrementalCacheKey = cacheKey
        }
        let reusableCache = currentSettings.incrementalScanning ? incrementalCache : [:]
        scanUsesIncrementalCache = currentSettings.incrementalScanning
        scanTask = Task {
            let preparation = await Task.detached(priority: .userInitiated) {
                try? Self.prepareScanFileList(at: target, settings: currentSettings, cache: reusableCache)
            }.value
            guard !Task.isCancelled else { return }
            guard let preparation else {
                fail("Aura Protect could not prepare the file inventory.")
                return
            }
            totalFiles = preparation.count
            skippedFileDetails = preparation.skipped
            skippedFileCount = preparation.skippedCount
            reusedFileCount = preparation.reused
            pendingCache = currentSettings.incrementalScanning ? reusableCache : [:]
            if currentSettings.parallelScanning,
               (!preparation.fileLists.isEmpty || !preparation.directFiles.isEmpty),
               let daemon = Self.findExecutable("clamd"),
                let client = Self.findExecutable("clamdscan") {
                scanFileListURLs = preparation.fileLists
                launchParallelScan(daemon: daemon, client: client, fileLists: preparation.fileLists,
                                   directFiles: preparation.directFiles, fallbackScanner: executable,
                                   target: target, settings: currentSettings)
            } else {
                launchInventoryScan(executable: executable, fileLists: preparation.fileLists,
                                    directFiles: preparation.directFiles, settings: currentSettings)
            }
        }
    }

    func cancelScan() {
        guard isBusy else { return }
        state = .cancelling
        scanTask?.cancel()
        scanProcess?.interrupt()
        scanProcesses.forEach { $0.interrupt() }
        daemonProcess?.interrupt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.state == .cancelling else { return }
            if self.scanProcess?.isRunning == true { self.scanProcess?.terminate() }
            self.scanProcesses.filter(\.isRunning).forEach { $0.terminate() }
            if self.daemonProcess?.isRunning == true { self.daemonProcess?.terminate() }
            self.finishScan(exitCode: 0)
        }
    }

    func shutdown() {
        cancelScan()
        stopWarmDaemon()
    }

    func updateDefinitions(automatic: Bool = false) {
        if isUpdating {
            definitionsStatus = "A definition update is already in progress."
            return
        }
        if isUpdatingEngine {
            definitionsStatus = "Waiting for the engine update to finish…"
            if automatic { scheduleDefinitionRetry() }
            return
        }
        stopWarmDaemon()
        guard let executable = Self.findExecutable("freshclam") else {
            definitionsStatus = "Could not find freshclam"
            recordDefinitionLog("FreshClam executable was not found in the managed, bundled, or supported external engine locations.")
            return
        }
        if !automatic { definitionRetryCount = 0; definitionRetryTask?.cancel() }
        let updaterFiles: (config: URL, database: URL)
        do {
            updaterFiles = try Self.prepareUpdaterFiles()
        } catch {
            definitionsStatus = "Could not prepare the definition folder: \(error.localizedDescription)"
            recordDefinitionLog(definitionsStatus)
            return
        }
        lastDefinitionsAttempt = Date()
        UserDefaults.standard.set(lastDefinitionsAttempt, forKey: Self.lastDefinitionsAttemptKey)
        isUpdating = true
        definitionsAreCurrent = false
        definitionsStatus = "Updating definitions…"
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        Self.configureEnvironment(for: process, executable: executable)
        process.arguments = ["--stdout",
                             "--config-file=\(updaterFiles.config.path)",
                             "--datadir=\(updaterFiles.database.path)"]
        if let certificates = Self.certificatesDirectory {
            process.arguments?.append("--cvdcertsdir=\(certificates.path)")
        }
        process.standardOutput = pipe
        process.standardError = pipe
        updateProcess = process
        Task.detached { [weak self] in
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self)
                await MainActor.run {
                    self?.recordDefinitionLog(text, exitCode: process.terminationStatus)
                    self?.isUpdating = false
                    self?.definitionsAreCurrent = process.terminationStatus == 0
                    if process.terminationStatus == 0 {
                        let now = Date()
                        self?.lastDefinitionsSuccess = now
                        UserDefaults.standard.set(now, forKey: Self.lastDefinitionsSuccessKey)
                        self?.definitionsStatus = text.lowercased().contains("up-to-date")
                            ? "Definitions are already current (checked \(now.formatted(date: .abbreviated, time: .shortened)))"
                            : "Definitions updated \(now.formatted(date: .abbreviated, time: .shortened))"
                        self?.definitionRetryCount = 0
                        self?.definitionRetryTask?.cancel()
                        self?.refreshDefinitionDatabaseInfo()
                        self?.refreshSignatureSnapshot(recordChange: true)
                    } else {
                        self?.definitionsStatus = Self.friendlyUpdateError(text)
                        self?.scheduleDefinitionRetry()
                    }
                    self?.updateProcess = nil
                }
            } catch {
                await MainActor.run {
                    self?.isUpdating = false
                    self?.definitionsAreCurrent = false
                    self?.definitionsStatus = "Update failed: \(error.localizedDescription)"
                    self?.recordDefinitionLog("FreshClam could not start: \(error.localizedDescription)")
                    self?.scheduleDefinitionRetry()
                    self?.updateProcess = nil
                }
            }
        }
    }

    private func scheduleDefinitionUpdates() {
        definitionUpdateTimer?.invalidate()
        definitionUpdateTimer = .scheduledTimer(withTimeInterval: 4 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateDefinitions(automatic: true) }
        }
    }

    private func scheduleDefinitionRetry() {
        guard definitionRetryCount < 3 else { return }
        let delays: [Duration] = [.seconds(15 * 60), .seconds(60 * 60), .seconds(4 * 60 * 60)]
        let delay = delays[definitionRetryCount]
        definitionRetryCount += 1
        definitionRetryTask?.cancel()
        definitionRetryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.updateDefinitions(automatic: true)
        }
    }

    private func loadDefinitionUpdateState() {
        lastDefinitionsAttempt = UserDefaults.standard.object(forKey: Self.lastDefinitionsAttemptKey) as? Date
        lastDefinitionsSuccess = UserDefaults.standard.object(forKey: Self.lastDefinitionsSuccessKey) as? Date
        if let text = try? String(contentsOf: Self.definitionUpdateLogURL, encoding: .utf8), !text.isEmpty {
            let readable = Self.humanReadableDefinitionLog(text)
            definitionUpdateLog = String(readable.suffix(80_000))
            Self.replaceDefinitionLog(definitionUpdateLog)
        }
        refreshDefinitionDatabaseInfo()
    }

    private func refreshDefinitionDatabaseInfo() {
        guard let info = Self.dailyDefinitionInfo() else {
            definitionDatabaseVersion = "Unknown"
            definitionRelease = "Unknown"
            return
        }
        definitionDatabaseVersion = info.version
        definitionRelease = info.release
    }

    private func recordDefinitionLog(_ output: String, exitCode: Int32? = nil) {
        let cleaned = Self.humanReadableDefinitionLog(output)
        let outcome = exitCode.map { $0 == 0 ? "Update completed successfully" : "Update failed (code \($0))" }
        let entry = "[\(Date.now.formatted(date: .numeric, time: .standard))] " +
            (outcome ?? "Update event") + "\n" +
            (cleaned.isEmpty ? "No additional details were reported." : cleaned) + "\n\n"
        Self.appendDefinitionLog(entry)
        definitionUpdateLog = String((definitionUpdateLog == "No definition update has been recorded yet."
            ? entry : definitionUpdateLog + entry).suffix(80_000))
    }

    func requestEngineUpdateCheck() {
        guard !isUpdatingEngine else { return }
        Task { await checkForEngineUpdates() }
    }

    func exportReport() {
        guard state.hasResults else { return }
        let panel = NSSavePanel()
        panel.title = "Save Scan Report"
        panel.nameFieldStringValue = "Aura Protect Scan Report.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let signatures = signatureSnapshot?.total.formatted() ?? "Unknown"
        let completed = (scanCompletedAt ?? Date()).formatted(date: .complete, time: .standard)
        let throughput = summary.duration > 0
            ? "\(Int(Double(summary.scannedFiles) / summary.duration).formatted()) files/sec" : "Unknown"
        let detectionText = detections.isEmpty ? "None" : detections.map { "- \($0)" }.joined(separator: "\n")
        let concerns = log.isEmpty ? "None" : log
        let report = """
        AURA PROTECT SCAN REPORT
        =======================
        Completed: \(completed)
        Target: \(selectedURL?.path(percentEncoded: false) ?? "Unknown")
        Engine: \(clamVersion)
        Protection signatures: \(signatures)

        SUMMARY
        Files scanned: \(summary.scannedFiles.formatted())
        Concerning detections: \(summary.infectedFiles.formatted())
        Files quarantined by user: \(quarantinedPaths.count.formatted())
        Scan errors: \(summary.errors.formatted())
        Files skipped by limits or access: \(summary.skippedFiles.formatted())
        Unchanged clean files reused: \(summary.reusedFiles.formatted())
        Duration: \(String(format: "%.1f seconds", summary.duration))
        Average throughput: \(throughput)

        DETECTED FILES
        \(detectionText)

        QUARANTINE DISPOSITION
        \(quarantineStatus ?? "No quarantine action was taken.")

        CONCERNING FINDINGS AND ERRORS
        \(concerns)

        FILES NOT SCANNED (first 100)
        \(skippedFileDetails.isEmpty ? "None" : skippedFileDetails.joined(separator: "\n"))
        """
        do { try report.write(to: url, atomically: true, encoding: .utf8) }
        catch { log = "Could not save report: \(error.localizedDescription)" }
    }

    var unquarantinedDetections: [String] {
        detections.filter { !quarantinedPaths.contains($0) }
    }

    func quarantineDetectedFiles() {
        guard state.hasResults, !unquarantinedDetections.isEmpty else { return }
        let manager = FileManager.default
        let directory = Self.quarantineDirectory
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        } catch {
            quarantineStatus = "Could not create the quarantine folder: \(error.localizedDescription)"
            return
        }
        var moved = 0
        var failures: [String] = []
        for displayedPath in unquarantinedDetections {
            let source = Self.resolveDetectionPath(displayedPath)
            guard manager.fileExists(atPath: source.path) else {
                failures.append("\(displayedPath): file is no longer present")
                continue
            }
            let safeName = source.lastPathComponent.replacingOccurrences(of: "/", with: "_")
            let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(safeName).quarantine")
            let metadata = destination.appendingPathExtension("json")
            let record = QuarantineRecord(originalPath: source.path, quarantinedPath: destination.path,
                                          quarantinedAt: Date(), engineVersion: clamVersion)
            do {
                try manager.moveItem(at: source, to: destination)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                do {
                    let data = try JSONEncoder().encode(record)
                    try data.write(to: metadata, options: .atomic)
                    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadata.path)
                } catch {
                    try? manager.moveItem(at: destination, to: source)
                    throw error
                }
                quarantinedPaths.insert(displayedPath)
                moved += 1
            } catch {
                failures.append("\(displayedPath): \(error.localizedDescription)")
            }
        }
        if failures.isEmpty {
            quarantineStatus = "Quarantined \(moved) file\(moved == 1 ? "" : "s"). Recovery metadata was saved with each file."
        } else {
            quarantineStatus = "Quarantined \(moved) file\(moved == 1 ? "" : "s"); \(failures.count) could not be moved.\n" + failures.joined(separator: "\n")
        }
    }

    func revealQuarantine() {
        try? FileManager.default.createDirectory(at: Self.quarantineDirectory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Self.quarantineDirectory.path)
    }

    private func checkForEngineUpdates() async {
        stopWarmDaemon()
        guard let current = EngineUpdater.version(from: clamVersion) else {
            engineUpdateStatus = "Unable to determine the installed engine version."
            return
        }
        isUpdatingEngine = true
        engineIsCurrent = false
        engineUpdateStatus = "Checking for the latest ClamAV engine…"
        do {
            let release = try await EngineUpdater.latestRelease()
            if EngineUpdater.compare(release.version, current) == .orderedDescending {
                engineUpdateStatus = "Downloading ClamAV \(release.version)…"
                let directory = try await EngineUpdater.install(release: release) { [weak self] status in
                    Task { @MainActor in self?.engineUpdateStatus = status }
                }
                UserDefaults.standard.set(directory.path, forKey: EngineUpdater.currentEngineKey)
                engineUpdateStatus = "ClamAV \(release.version) installed and ready."
                engineIsCurrent = true
                await loadVersion()
            } else {
                engineUpdateStatus = "ClamAV \(current) is the latest available engine."
                engineIsCurrent = true
            }
        } catch {
            engineIsCurrent = false
            engineUpdateStatus = "Engine update check failed: \(error.localizedDescription)"
        }
        isUpdatingEngine = false
    }

    private func launchScan(executable: URL, target: URL, settings: ScanSettings) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        Self.configureEnvironment(for: process, executable: executable)
        process.arguments = Self.arguments(for: target, settings: settings, databaseDirectory: Self.databaseDirectory)
        process.standardOutput = pipe
        process.standardError = pipe
        scanProcess = process
        state = .scanning
        startTime = Date()
        timer = .scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshTiming() }
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.consume(text) }
        }
        do {
            try process.run()
        } catch {
            fail("Unable to start ClamAV: \(error.localizedDescription)")
            return
        }
        Task.detached { [weak self] in
            process.waitUntilExit()
            await MainActor.run { self?.finishScan(exitCode: process.terminationStatus) }
        }
    }

    private func launchInventoryScan(executable: URL, fileLists: [URL], directFiles: [URL], settings: ScanSettings) {
        guard let fileList = try? Self.consolidateScanFileLists(fileLists) else {
            fail("Aura Protect could not prepare the scanner input list.")
            return
        }
        scanFileListURLs.append(fileList)
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        Self.configureEnvironment(for: process, executable: executable)
        var arguments = Self.baseScanArguments(settings: settings, databaseDirectory: Self.databaseDirectory)
        arguments.append("--file-list=\(fileList.path)")
        if !directFiles.isEmpty {
            arguments.append("--")
            arguments.append(contentsOf: directFiles.map(\.path))
        }
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        scanProcess = process
        state = .scanning
        startTime = Date()
        timer = .scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshTiming() }
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consume(String(decoding: data, as: UTF8.self)) }
        }
        do { try process.run() }
        catch { fail("Unable to start ClamAV: \(error.localizedDescription)"); return }
        Task.detached { [weak self] in
            process.waitUntilExit()
            await MainActor.run { self?.finishScan(exitCode: process.terminationStatus) }
        }
    }

    private func launchParallelScan(daemon: URL, client: URL, fileLists: [URL], directFiles: [URL],
                                    fallbackScanner: URL, target: URL, settings: ScanSettings) {
        if daemonProcess?.isRunning == true,
           activeDaemonSettings == settings,
           let config = activeDaemonConfig {
            state = .scanning
            parallelScannerAvailable = true
            parallelScannerStatus = "Warm parallel scanner ready with up to \(settings.workerCount) workers."
            launchDaemonClients(executable: client, config: config, fileLists: fileLists, directFiles: directFiles)
            return
        }
        stopWarmDaemon()
        let daemonFiles: (config: URL, socket: URL)
        do {
            daemonFiles = try Self.prepareDaemonFiles(settings: settings)
        } catch {
            fail("Could not prepare the parallel scanner: \(error.localizedDescription)")
            return
        }

        let process = Process()
        let daemonPipe = Pipe()
        process.executableURL = daemon
        Self.configureEnvironment(for: process, executable: daemon)
        process.arguments = ["--foreground", "--config-file=\(daemonFiles.config.path)"]
        if let certificates = Self.certificatesDirectory {
            process.arguments?.append("--cvdcertsdir=\(certificates.path)")
        }
        process.standardOutput = daemonPipe
        process.standardError = daemonPipe
        daemonProcess = process
        state = .scanning
        daemonPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.consumeDaemonOutput(text) }
        }
        do {
            try process.run()
        } catch {
            fail("Unable to start ClamAV’s parallel scanner: \(error.localizedDescription)")
            return
        }

        scanTask = Task { [weak self] in
            for _ in 0..<300 {
                guard let self, !Task.isCancelled else { return }
                let ready = await Task.detached(priority: .userInitiated) {
                    Self.daemonResponds(client: client, config: daemonFiles.config)
                }.value
                if ready {
                    self.activeDaemonConfig = daemonFiles.config
                    self.activeDaemonSettings = settings
                    self.parallelScannerAvailable = true
                    self.parallelScannerStatus = "Connected and ready with up to \(settings.workerCount) parallel workers."
                    self.launchDaemonClients(executable: client, config: daemonFiles.config,
                                             fileLists: fileLists, directFiles: directFiles)
                    return
                }
                if process.isRunning == false {
                    self.fallbackToSingleScan(executable: fallbackScanner, fileLists: fileLists,
                                              directFiles: directFiles, settings: settings)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            process.terminate()
            self?.fallbackToSingleScan(executable: fallbackScanner, fileLists: fileLists,
                                       directFiles: directFiles, settings: settings)
        }
    }

    private func fallbackToSingleScan(executable: URL, fileLists: [URL], directFiles: [URL], settings: ScanSettings) {
        stopWarmDaemon()
        daemonOutputBuffer = ""
        parallelScannerAvailable = false
        parallelScannerStatus = "Parallel workers could not connect. This scan is continuing safely in single-process mode."
        launchInventoryScan(executable: executable, fileLists: fileLists, directFiles: directFiles, settings: settings)
    }

    private func launchDaemonClients(executable: URL, config: URL, fileLists: [URL], directFiles: [URL]) {
        startTime = Date()
        parallelClientsRemaining = fileLists.count + directFiles.count
        parallelExitCode = 0
        timer = .scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshTiming() }
        }
        let clients: [(fileList: URL?, directFile: URL?)] =
            fileLists.map { ($0, nil) } + directFiles.map { (nil, $0) }
        for client in clients {
            let process = Process()
            let pipe = Pipe()
            let source = ObjectIdentifier(process)
            process.executableURL = executable
            Self.configureEnvironment(for: process, executable: executable)
            if let fileList = client.fileList {
                process.arguments = ["--stdout", "--verbose", "--wait", "--ping=60:1", "--multiscan",
                                     "--config-file=\(config.path)", "--file-list=\(fileList.path)"]
            } else if let directFile = client.directFile {
                process.arguments = ["--stdout", "--verbose", "--wait", "--ping=60:1",
                                     "--config-file=\(config.path)",
                                     "--", directFile.path]
            }
            process.standardOutput = pipe
            process.standardError = pipe
            scanProcesses.append(process)
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = String(decoding: data, as: UTF8.self)
                Task { @MainActor in self?.consume(text, source: source) }
            }
            do {
                try process.run()
            } catch {
                daemonProcess?.terminate()
                scanProcesses.filter(\.isRunning).forEach { $0.terminate() }
                fail("Unable to connect to ClamAV’s parallel scanner: \(error.localizedDescription)")
                return
            }
            Task.detached { [weak self] in
                process.waitUntilExit()
                await MainActor.run {
                    self?.parallelClientFinished(exitCode: process.terminationStatus,
                                                 directFile: client.directFile)
                }
            }
        }
    }

    private func parallelClientFinished(exitCode: Int32, directFile: URL?) {
        guard parallelClientsRemaining > 0 else { return }
        if let directFile {
            processedFiles += 1
            if exitCode == 1 {
                let displayPath = directFile.path.replacingOccurrences(of: "\r", with: "\\r")
                    .replacingOccurrences(of: "\n", with: "\\n")
                if !detections.contains(displayPath) { detections.append(displayPath) }
                appendConcern("\(displayPath): Threat detected")
            }
            if exitCode > 1 { scanErrorCount += 1 }
            progress = totalFiles > 0 ? min(Double(processedFiles) / Double(totalFiles), 0.99) : 0
            refreshTiming()
        }
        parallelExitCode = max(parallelExitCode, exitCode)
        parallelClientsRemaining -= 1
        if parallelClientsRemaining == 0 { finishScan(exitCode: parallelExitCode) }
    }

    private func consume(_ text: String, source: ObjectIdentifier? = nil) {
        var buffer = source.flatMap { parallelOutputBuffers[$0] } ?? outputBuffer
        buffer += text
        let lines = buffer.components(separatedBy: .newlines)
        if let source { parallelOutputBuffers[source] = lines.last ?? "" }
        else { outputBuffer = lines.last ?? "" }
        for line in lines.dropLast() where OutputParser.isFileResult(line) {
            processedFiles += 1
            updateIncrementalCache(from: line)
            if line.contains(" ERROR") { scanErrorCount += 1 }
            if let path = OutputParser.infectionPath(line), !detections.contains(path) {
                detections.append(path)
                appendConcern(line)
            } else if OutputParser.isConcerning(line) {
                appendConcern(line)
            }
        }
        for line in lines.dropLast() where !OutputParser.isFileResult(line) && OutputParser.isConcerning(line) {
            appendConcern(line)
        }
        progress = totalFiles > 0 ? min(Double(processedFiles) / Double(totalFiles), 0.99) : 0
        refreshTiming()
    }

    private func refreshTiming() {
        guard let startTime else { return }
        elapsed = Date().timeIntervalSince(startTime)
        guard processedFiles > 0, totalFiles > processedFiles else { estimatedRemaining = nil; return }
        estimatedRemaining = elapsed / Double(processedFiles) * Double(totalFiles - processedFiles)
    }

    private func finishScan(exitCode: Int32) {
        let remainingLines = [outputBuffer] + Array(parallelOutputBuffers.values)
        for line in remainingLines where !line.isEmpty && OutputParser.isFileResult(line) {
            processedFiles += 1
            updateIncrementalCache(from: line)
            if line.contains(" ERROR") { scanErrorCount += 1 }
            if let path = OutputParser.infectionPath(line), !detections.contains(path) {
                detections.append(path)
                appendConcern(line)
            } else if OutputParser.isConcerning(line) {
                appendConcern(line)
            }
        }
        if !daemonOutputBuffer.isEmpty && OutputParser.isConcerning(daemonOutputBuffer) { appendConcern(daemonOutputBuffer) }
        daemonOutputBuffer = ""
        outputBuffer = ""
        parallelOutputBuffers = [:]
        timer?.invalidate()
        timer = nil
        refreshTiming()
        estimatedRemaining = nil
        scanProcess = nil
        scanProcesses = []
        parallelClientsRemaining = 0
        if daemonProcess?.isRunning == true {
            parallelScannerStatus = "Warm parallel scanner ready for the next scan."
        }
        scanFileListURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        scanFileListURLs = []
        if state == .cancelling {
            state = .idle
            log += "\nScan cancelled."
            return
        }
        if scanUsesIncrementalCache && exitCode <= 1 { incrementalCache = pendingCache }
        summary = .init(scannedFiles: processedFiles, infectedFiles: detections.count,
                        errors: max(scanErrorCount, exitCode > 1 ? 1 : 0),
                        skippedFiles: skippedFileCount, reusedFiles: reusedFileCount, duration: elapsed)
        scanCompletedAt = Date()
        progress = 1
        state = ScanState.completionState(exitCode: exitCode, processedFiles: processedFiles)
        if state == .finishedWithIssues {
            appendConcern("Scan completed, but ClamAV reported \(summary.errors) error\(summary.errors == 1 ? "" : "s") (exit code \(exitCode)). Review the errors above and the Files not scanned section.")
        } else if state == .failed {
            appendConcern("ClamAV could not complete the scan (exit code \(exitCode)). Review the preceding error details.")
        }
        if log.isEmpty { log = "No concerning detections or scan errors were reported." }
        if settings.bellOnDetection && !detections.isEmpty { NSSound.beep() }
    }

    private func resetScan() {
        scanTask?.cancel()
        timer?.invalidate()
        processedFiles = 0; totalFiles = 0; progress = 0; elapsed = 0
        estimatedRemaining = nil; detections = []; summary = .init()
        scanCompletedAt = nil
        quarantinedPaths = []; quarantineStatus = nil
        outputBuffer = ""
        scanFileListURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        scanFileListURLs = []
        scanProcesses = []; parallelClientsRemaining = 0; parallelExitCode = 0
        parallelOutputBuffers = [:]
        scanErrorCount = 0
        daemonOutputBuffer = ""
        skippedFileDetails = []; skippedFileCount = 0; reusedFileCount = 0
        pendingCache = [:]; scanUsesIncrementalCache = false
    }

    private func fail(_ message: String) {
        timer?.invalidate(); timer = nil
        state = .failed; log = message
    }

    private func stopWarmDaemon() {
        if daemonProcess?.isRunning == true { daemonProcess?.terminate() }
        daemonProcess = nil
        activeDaemonConfig = nil
        activeDaemonSettings = nil
    }

    private func consumeDaemonOutput(_ text: String) {
        daemonOutputBuffer += text
        let lines = daemonOutputBuffer.components(separatedBy: .newlines)
        daemonOutputBuffer = lines.last ?? ""
        for line in lines.dropLast() where OutputParser.isConcerning(line) { appendConcern(line) }
    }

    private func appendConcern(_ line: String) {
        guard !line.isEmpty else { return }
        if !log.isEmpty { log += "\n" }
        log += line
        if log.count > 100_000 { log.removeFirst(log.count - 80_000) }
    }

    private func updateIncrementalCache(from line: String) {
        guard scanUsesIncrementalCache, let path = OutputParser.resultPath(line) else { return }
        if line.hasSuffix(" FOUND") || line.contains(" ERROR") {
            pendingCache.removeValue(forKey: path)
            return
        }
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        pendingCache[path] = FileStamp(size: Int64(values.fileSize ?? 0),
                                       modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0)
    }

    private func loadSignatureSnapshots() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "currentSignatureSnapshot") {
            signatureSnapshot = try? decoder.decode(SignatureSnapshot.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: "previousSignatureSnapshot") {
            previousSignatureSnapshot = try? decoder.decode(SignatureSnapshot.self, from: data)
        }
    }

    private func refreshSignatureSnapshot(recordChange: Bool) {
        guard let fresh = Self.readSignatureSnapshot() else { return }
        if recordChange, let current = signatureSnapshot, current.categories != fresh.categories {
            previousSignatureSnapshot = current
            if let data = try? JSONEncoder().encode(current) {
                UserDefaults.standard.set(data, forKey: "previousSignatureSnapshot")
            }
        }
        signatureSnapshot = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(data, forKey: "currentSignatureSnapshot")
        }
    }

    private func loadVersion() async {
        guard let executable = Self.findExecutable("clamscan") else {
            clamVersion = "Bundled ClamAV engine is unavailable"
            return
        }
        let process = Process(); let pipe = Pipe()
        process.executableURL = executable; process.arguments = ["--version"]; process.standardOutput = pipe
        Self.configureEnvironment(for: process, executable: executable)
        do {
            try process.run(); process.waitUntilExit()
            clamVersion = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            definitionsStatus = Self.hasVirusDatabase ? "Definitions installed" : "Definitions need to be downloaded"
        } catch { clamVersion = "ClamAV unavailable" }
    }

    nonisolated static func findExecutable(_ name: String) -> URL? {
        var candidates: [String] = []
        if let managed = UserDefaults.standard.string(forKey: EngineUpdater.currentEngineKey) {
            candidates += [URL(fileURLWithPath: managed).appendingPathComponent("bin/\(name)").path,
                           URL(fileURLWithPath: managed).appendingPathComponent("sbin/\(name)").path]
        }
        if let resources = Bundle.main.resourceURL {
            candidates += [resources.appendingPathComponent("ClamAV/bin/\(name)").path,
                           resources.appendingPathComponent("ClamAV/sbin/\(name)").path]
        }
        candidates += ["/opt/homebrew/bin/\(name)", "/opt/homebrew/sbin/\(name)",
                          "/usr/local/bin/\(name)", "/usr/local/sbin/\(name)",
                          "/usr/local/clamav/bin/\(name)", "/usr/local/clamav/sbin/\(name)",
                          "/opt/homebrew/opt/clamav/bin/\(name)", "/opt/homebrew/opt/clamav/sbin/\(name)"]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    nonisolated static func configureEnvironment(for process: Process, executable: URL) {
        var environment = ProcessInfo.processInfo.environment
        if let certificates = certificatesDirectory {
            environment["CVD_CERTS_DIR"] = certificates.path
        }
        let parent = executable.deletingLastPathComponent()
        if ["bin", "sbin"].contains(parent.lastPathComponent) {
            let library = parent.deletingLastPathComponent().appendingPathComponent("lib", isDirectory: true)
            if FileManager.default.fileExists(atPath: library.path) {
                environment["DYLD_LIBRARY_PATH"] = library.path
            }
        }
        process.environment = environment
    }

    nonisolated static var certificatesDirectory: URL? {
        var candidates: [URL] = []
        if let managed = UserDefaults.standard.string(forKey: EngineUpdater.currentEngineKey) {
            candidates.append(URL(fileURLWithPath: managed).appendingPathComponent("etc/certs", isDirectory: true))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("ClamAV/etc/certs", isDirectory: true))
        }
        candidates += [URL(fileURLWithPath: "/opt/homebrew/etc/clamav/certs", isDirectory: true),
                       URL(fileURLWithPath: "/usr/local/clamav/etc/certs", isDirectory: true)]
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("clamav.crt").path)
        }
    }

    nonisolated static func arguments(for target: URL, settings: ScanSettings, databaseDirectory: URL? = nil) -> [String] {
        var result = baseScanArguments(settings: settings, databaseDirectory: databaseDirectory)
        if settings.recursive { result.append("--recursive=yes") }
        result.append("--")
        result.append(target.path)
        return result
    }

    nonisolated static func baseScanArguments(settings: ScanSettings, databaseDirectory: URL? = nil) -> [String] {
        var result = ["--stdout", "--verbose", "--archive=\(settings.scanArchives ? "yes" : "no")",
                      "--max-filesize=\(settings.maxFileSizeMB)M", "--max-scansize=\(settings.maxFileSizeMB * 4)M"]
        if let databaseDirectory { result.append("--database=\(databaseDirectory.path)") }
        if let certificates = certificatesDirectory { result.append("--cvdcertsdir=\(certificates.path)") }
        if settings.detectPUA { result.append("--detect-pua=yes") }
        let follow = settings.followSymlinks ? "1" : "0"
        result += ["--follow-dir-symlinks=\(follow)", "--follow-file-symlinks=\(follow)"]
        if !settings.scanHidden { result.append("--exclude=(^|/)\\.[^/]+") }
        return result
    }

    nonisolated static func consolidateScanFileLists(_ lists: [URL]) throws -> URL {
        if lists.count == 1 { return lists[0] }
        let destination = databaseDirectory.deletingLastPathComponent()
            .appendingPathComponent("scan-files-combined-\(UUID().uuidString).txt")
        guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        for list in lists {
            let input = try FileHandle(forReadingFrom: list)
            defer { try? input.close() }
            while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
                try output.write(contentsOf: data)
            }
        }
        return destination
    }

    nonisolated static func countFiles(at url: URL, recursive: Bool, includeHidden: Bool) -> Int {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else { return 1 }
        guard recursive else {
            return (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: includeHidden ? [] : [.skipsHiddenFiles]))?.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.count ?? 0
        }
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: options) else { return 0 }
        var count = 0
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { count += 1 }
        }
        return count
    }

    nonisolated private static func prepareScanFileList(at target: URL, settings: ScanSettings,
                                                        cache: [String: FileStamp]) throws -> ScanPreparation {
        let support = databaseDirectory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
            return ScanPreparation(count: 0, fileLists: [], directFiles: [], skipped: ["Target does not exist: \(target.path)"], skippedCount: 1, reused: 0)
        }

        let workerCount = max(settings.workerCount, 1)
        var fileLists: [URL] = []
        var handles: [FileHandle] = []
        var buffers = Array(repeating: Data(), count: workerCount)
        var groupCounts = Array(repeating: 0, count: workerCount)
        var groupBytes = Array(repeating: Int64(0), count: workerCount)
        var regularCount = 0
        var directFiles: [URL] = []
        var skipped: [String] = []
        var skippedCount = 0
        var reused = 0
        var completed = false
        do {
            for _ in 0..<workerCount {
                let url = support.appendingPathComponent("scan-files-\(UUID().uuidString).txt")
                guard FileManager.default.createFile(atPath: url.path, contents: nil,
                    attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
                fileLists.append(url)
                handles.append(try FileHandle(forWritingTo: url))
            }
        } catch {
            handles.forEach { try? $0.close() }
            fileLists.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
        defer {
            handles.forEach { try? $0.close() }
            if !completed { fileLists.forEach { try? FileManager.default.removeItem(at: $0) } }
        }

        func add(_ url: URL, size: Int64, modified: TimeInterval) throws {
            if size > Int64(settings.maxFileSizeMB) * 1_048_576 {
                skippedCount += 1
                if skipped.count < 100 { skipped.append("Over size limit: \(url.path)") }
                return
            }
            let stamp = FileStamp(size: size, modified: modified)
            if cache[url.path] == stamp {
                reused += 1
                return
            }
            if url.path.contains("\n") || url.path.contains("\r") {
                directFiles.append(url)
                return
            }
            let index = groupBytes.indices.min(by: { groupBytes[$0] < groupBytes[$1] }) ?? 0
            buffers[index].append(Data((url.path + "\n").utf8))
            groupCounts[index] += 1
            groupBytes[index] += max(size, 1)
            regularCount += 1
            if buffers[index].count >= 131_072 {
                try handles[index].write(contentsOf: buffers[index])
                buffers[index].removeAll(keepingCapacity: true)
            }
        }

        if !isDirectory.boolValue {
            let values = try target.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            try add(target, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0)
        } else if !settings.recursive {
            let options: FileManager.DirectoryEnumerationOptions = settings.scanHidden ? [] : [.skipsHiddenFiles]
            let children = try FileManager.default.contentsOfDirectory(at: target,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: options)
            for url in children {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true,
                      settings.followSymlinks || values.isSymbolicLink != true else { continue }
                guard FileManager.default.isReadableFile(atPath: url.path) else {
                    skippedCount += 1
                    if skipped.count < 100 { skipped.append("Unreadable: \(url.path)") }
                    continue
                }
                try add(url, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0)
            }
        } else {
            var options: FileManager.DirectoryEnumerationOptions = []
            if !settings.scanHidden { options.insert(.skipsHiddenFiles) }
            guard let enumerator = FileManager.default.enumerator(at: target,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
                options: options, errorHandler: { url, error in
                    skippedCount += 1
                    if skipped.count < 100 { skipped.append("Could not access \(url.path): \(error.localizedDescription)") }
                    return true
                }) else {
                return ScanPreparation(count: 0, fileLists: [], directFiles: [], skipped: ["Could not enumerate \(target.path)"], skippedCount: 1, reused: 0)
            }
            for case let url as URL in enumerator {
                if Task.isCancelled { throw CancellationError() }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true,
                      settings.followSymlinks || values.isSymbolicLink != true else { continue }
                guard FileManager.default.isReadableFile(atPath: url.path) else {
                    skippedCount += 1
                    if skipped.count < 100 { skipped.append("Unreadable: \(url.path)") }
                    continue
                }
                try add(url, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0)
            }
        }

        for index in 0..<workerCount where !buffers[index].isEmpty {
            try handles[index].write(contentsOf: buffers[index])
        }
        var usedLists: [URL] = []
        for index in 0..<workerCount {
            if groupCounts[index] > 0 { usedLists.append(fileLists[index]) }
            else { try? FileManager.default.removeItem(at: fileLists[index]) }
        }
        completed = true
        return ScanPreparation(count: regularCount + directFiles.count, fileLists: usedLists,
                               directFiles: directFiles, skipped: skipped,
                               skippedCount: skippedCount, reused: reused)
    }

    nonisolated static func lastUsefulLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).map(String.init).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    nonisolated static var databaseDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Aura Protect/Database", isDirectory: true)
    }

    nonisolated static var quarantineDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Aura Protect/Quarantine", isDirectory: true)
    }

    nonisolated static var definitionUpdateLogURL: URL {
        databaseDirectory.deletingLastPathComponent().appendingPathComponent("definition-update.log")
    }

    nonisolated static func dailyDefinitionInfo() -> (version: String, release: String)? {
        let manager = FileManager.default
        let candidates = ["daily.cvd", "daily.cld", "daily.cud"]
        guard let name = candidates.first(where: {
            manager.fileExists(atPath: databaseDirectory.appendingPathComponent($0).path)
        }), let handle = try? FileHandle(forReadingFrom: databaseDirectory.appendingPathComponent(name)) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 512) else { return nil }
        let fields = String(decoding: data, as: UTF8.self).split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count > 2 else { return nil }
        return (String(fields[2]), String(fields[1]))
    }

    nonisolated static func appendDefinitionLog(_ entry: String) {
        let manager = FileManager.default
        let url = definitionUpdateLogURL
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                     attributes: [.posixPermissions: 0o700])
        var existing = (try? Data(contentsOf: url)) ?? Data()
        if existing.count > 500_000 { existing = existing.suffix(250_000) }
        existing.append(Data(entry.utf8))
        do {
            try existing.write(to: url, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { }
    }

    nonisolated static func replaceDefinitionLog(_ text: String) {
        let url = definitionUpdateLogURL
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { }
    }

    nonisolated static func humanReadableDefinitionLog(_ output: String) -> String {
        let ansiPattern = "\\u{001B}\\[[0-9;?]*[ -/]*[@-~]"
        let withoutANSI = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "\n")
        let noisePrefixes = [
            "current working dir is ", "loaded freshclam.dat:", "version:", "uuid:",
            "querying current.cvd.clamav.net", "trying to retrieve cvd header", "check_for_new_database_version:",
            "updatedb: running ", "download_complete_callback:", "fc_context->", "* ", "time:"
        ]
        var result: [String] = []
        var seenRepeatedMessages: Set<String> = []
        for rawLine in withoutANSI.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            guard !noisePrefixes.contains(where: lower.hasPrefix),
                  !line.allSatisfy({ $0 == "=" || $0 == ">" || $0 == "-" || $0.isNumber || $0 == "." || $0 == "%" || $0 == " " }) else { continue }
            let repeatable = lower.hasPrefix("warning:") || lower.hasPrefix("error:") ||
                lower.hasPrefix("failed") || lower.contains("could not resolve")
            if repeatable && !seenRepeatedMessages.insert(line).inserted { continue }
            result.append(line)
        }
        return result.suffix(200).joined(separator: "\n")
    }

    nonisolated static func migrateLegacySupportData() {
        let manager = FileManager.default
        let library = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let legacy = library.appendingPathComponent("ClamAV Desk", isDirectory: true)
        let current = library.appendingPathComponent("Aura Protect", isDirectory: true)
        guard manager.fileExists(atPath: legacy.path) else { return }
        try? manager.createDirectory(at: current, withIntermediateDirectories: true,
                                     attributes: [.posixPermissions: 0o700])
        for name in ["Database", "Quarantine"] {
            let source = legacy.appendingPathComponent(name, isDirectory: true)
            let destination = current.appendingPathComponent(name, isDirectory: true)
            if manager.fileExists(atPath: source.path), !manager.fileExists(atPath: destination.path) {
                try? manager.copyItem(at: source, to: destination)
            }
        }
    }

    nonisolated static func resolveDetectionPath(_ displayedPath: String) -> URL {
        if FileManager.default.fileExists(atPath: displayedPath) { return URL(fileURLWithPath: displayedPath) }
        let decoded = displayedPath.replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\n", with: "\n")
        return URL(fileURLWithPath: decoded)
    }

    nonisolated static var hasVirusDatabase: Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: databaseDirectory.path)) ?? []
        return names.contains { name in
            [".cvd", ".cld", ".cud"].contains { name.lowercased().hasSuffix($0) }
        }
    }

    nonisolated static func readSignatureSnapshot() -> SignatureSnapshot? {
        let definitions: [(String, String)] = [
            ("main", "Core malware"), ("daily", "Latest threats"), ("bytecode", "Bytecode detections")
        ]
        var categories: [SignatureCategory] = []
        let contents = (try? FileManager.default.contentsOfDirectory(at: databaseDirectory,
            includingPropertiesForKeys: nil)) ?? []
        for (prefix, label) in definitions {
            guard let file = contents.first(where: {
                $0.deletingPathExtension().lastPathComponent == prefix && ["cvd", "cld", "cud"].contains($0.pathExtension.lowercased())
            }), let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 512) else { continue }
            let header = String(decoding: data, as: UTF8.self)
            let fields = header.split(separator: ":")
            guard fields.count > 3, let count = Int(fields[3]) else { continue }
            categories.append(.init(name: label, count: count))
        }
        return categories.isEmpty ? nil : .init(capturedAt: Date(), categories: categories)
    }

    nonisolated static func prepareUpdaterFiles() throws -> (config: URL, database: URL) {
        let database = databaseDirectory
        let support = database.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let config = support.appendingPathComponent("freshclam.conf")
        let contents = """
        DatabaseDirectory \(database.path)
        DatabaseMirror database.clamav.net
        DatabaseOwner \(NSUserName())
        \(certificatesDirectory.map { "CVDCertsDirectory \($0.path)" } ?? "")
        ConnectTimeout 30
        ReceiveTimeout 120
        TestDatabases yes
        """
        try contents.write(to: config, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        return (config, database)
    }

    nonisolated static func prepareDaemonFiles(settings: ScanSettings) throws -> (config: URL, socket: URL) {
        let database = databaseDirectory
        let support = database.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let socket = support.appendingPathComponent("clamd.sock")
        let config = support.appendingPathComponent("clamd.conf")
        if FileManager.default.fileExists(atPath: socket.path) {
            try FileManager.default.removeItem(at: socket)
        }
        var lines = [
            "LocalSocket \(socket.path)",
            "FixStaleSocket yes",
            "LocalSocketMode 600",
            "DatabaseDirectory \(database.path)",
            certificatesDirectory.map { "CVDCertsDirectory \($0.path)" } ?? "",
            "Foreground yes",
            "MaxThreads \(settings.workerCount)",
            "MaxQueue \(max(settings.workerCount * 20, 100))",
            "ReadTimeout 300",
            "CommandReadTimeout 30",
            "ScanArchive \(settings.scanArchives ? "yes" : "no")",
            "FollowDirectorySymlinks \(settings.followSymlinks ? "yes" : "no")",
            "FollowFileSymlinks \(settings.followSymlinks ? "yes" : "no")",
            "MaxFileSize \(settings.maxFileSizeMB)M",
            "MaxScanSize \(settings.maxFileSizeMB * 4)M"
        ]
        if settings.detectPUA { lines.append("DetectPUA yes") }
        if !settings.scanHidden { lines.append("ExcludePath (^|/)\\.[^/]+") }
        try (lines.joined(separator: "\n") + "\n").write(to: config, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        return (config, socket)
    }

    nonisolated static func daemonResponds(client: URL, config: URL) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = client
        process.arguments = ["--quiet", "--ping=1:1", "--config-file=\(config.path)"]
        process.standardOutput = output
        process.standardError = output
        configureEnvironment(for: process, executable: client)
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    nonisolated static func friendlyUpdateError(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("invalid certs directory") || lower.contains("code-signature verifier") {
            return "ClamAV could not verify the downloaded database signature. Check the update log for the certificate path."
        }
        if lower.contains("permission denied") { return "Definition folder is not writable. Check its permissions and try again." }
        if lower.contains("rate limit") || lower.contains("429") { return "The update server is rate-limiting requests. Please try again later." }
        if lower.contains("network") || lower.contains("resolve host") || lower.contains("connection") { return "Could not reach the ClamAV update server. Check your internet connection." }
        return lastUsefulLine(text) ?? "Definition update failed."
    }


    nonisolated static func canReadProtectedData() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let protectedLocations = [
            home.appendingPathComponent("Library/Mail", isDirectory: true),
            home.appendingPathComponent("Library/Messages", isDirectory: true),
            home.appendingPathComponent("Library/Safari", isDirectory: true)
        ]

        for location in protectedLocations where FileManager.default.fileExists(atPath: location.path) {
            do {
                _ = try FileManager.default.contentsOfDirectory(at: location,
                                                                 includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])
                return true
            } catch {
                continue
            }
        }
        return false
    }
}
