import CryptoKit
import Darwin
import Foundation
import Testing
@testable import ClamAVDesk

@Suite(.serialized)
struct EngineIntegrationTests {
    private var runtime: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Vendor/ClamAV")
    }

    @Test func scannerReportsFirstFileBeforeInputCloses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let list = root.appendingPathComponent("scan-input")
        try #require(mkfifo(list.path, 0o600) == 0)
        let database = root.appendingPathComponent("fixture.ndb")
        try Data("Aura.Stream.Test:0:*:415552412d53545245414d2d54455354\n".utf8).write(to: database)
        let first = root.appendingPathComponent("first.txt")
        let second = root.appendingPathComponent("second.txt")
        for file in [first, second] { try Data("Clean document.\n".utf8).write(to: file) }

        let log = root.appendingPathComponent("scanner.log")
        try Data().write(to: log)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = runtime.appendingPathComponent("bin/clamscan")
        process.arguments = ["--verbose", "--stdout", "--database=\(database.path)", "--file-list=\(list.path)"]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["CVD_CERTS_DIR": runtime.appendingPathComponent("etc/certs").path]) { _, new in new }
        process.standardOutput = output
        process.standardError = output
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let pipe = ScanInputPipe(url: list)
                try pipe.openWriter()
                try pipe.writePaths(Data("\(first.path)\n".utf8))
                for _ in 0..<150 {
                    try Task.checkCancellation()
                    if try String(contentsOf: log, encoding: .utf8).contains("first.txt: OK") {
                        try pipe.writePaths(Data("\(second.path)\n".utf8))
                        return
                    }
                    try await Task.sleep(for: .milliseconds(20))
                }
                throw POSIXError(.ETIMEDOUT)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw POSIXError(.ETIMEDOUT)
            }
            defer { group.cancelAll() }
            try await group.next()
        }
        for _ in 0..<150 where process.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        try #require(!process.isRunning)
        #expect(process.terminationStatus == 0)
        #expect(try String(contentsOf: log, encoding: .utf8).contains("second.txt: OK"))
    }

    @Test func candidateEngineChecksCleanAndDetectedFilesWithLocalDatabase() throws {
        let database = FileManager.default.temporaryDirectory.appendingPathComponent("AuraEngineDatabase-\(UUID())")
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: database) }
        let local = database.appendingPathComponent("local.ndb")

        try EngineUpdater.smokeTest(runtime, database: nil)
        try "Aura.Local.Test:0:*:41415552412d4c4f43414c2d4441544142415345\n"
            .write(to: local, atomically: true, encoding: .utf8)
        try EngineUpdater.smokeTest(runtime, database: database)

        try "invalid signature\n".write(to: local, atomically: true, encoding: .utf8)
        #expect(throws: EngineUpdater.UpdateError.self) {
            try EngineUpdater.smokeTest(runtime, database: database)
        }
    }

    @Test @MainActor func realEngineDrainsEveryBatchAndPreservesDetection() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/aura-engine-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("db")
        let corpus = root.appendingPathComponent("corpus")
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: corpus, withIntermediateDirectories: true)
        let marker = Data("Aura Protect harmless integration fixture; this is not malware.\n".utf8)
        let digest = Insecure.MD5.hash(data: marker).map { String(format: "%02x", $0) }.joined()
        try "\(digest):\(marker.count):Aura.Regression.Test\n".write(to: database.appendingPathComponent("fixture.hdb"), atomically: true, encoding: .utf8)
        for index in 0..<1000 {
            try Data("Clean document \(index) for local validation.\n".utf8).write(to: corpus.appendingPathComponent("file-\(index)"))
        }
        let detected = corpus.appendingPathComponent("test: 🐱")
        try marker.write(to: detected)
        let config = root.appendingPathComponent("clamd.conf")
        let socket = root.appendingPathComponent("d.sock")
        try "LocalSocket \(socket.path)\nForeground yes\nLocalSocketMode 600\nDatabaseDirectory \(database.path)\nMaxThreads 3\nMaxQueue 100\n".write(to: config, atomically: true, encoding: .utf8)
        let daemon = Process()
        daemon.executableURL = runtime.appendingPathComponent("sbin/clamd")
        daemon.arguments = ["--config-file=\(config.path)"]
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_LIBRARY_PATH"] = runtime.appendingPathComponent("lib").path
        environment["CVD_CERTS_DIR"] = runtime.appendingPathComponent("etc/certs").path
        daemon.environment = environment
        daemon.standardOutput = FileHandle.nullDevice
        daemon.standardError = FileHandle.nullDevice
        try daemon.run()
        defer { if daemon.isRunning { daemon.terminate(); daemon.waitUntilExit() } }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: socket.path) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(daemon.isRunning && FileManager.default.fileExists(atPath: socket.path))
        var settings = ScanSettings()
        settings.workerCount = 2
        let inventory = try ScanController.prepareScanFileList(at: corpus, settings: settings, cache: [:], inventoryDirectory: root)
        #expect(inventory.fileLists.count > 2)
        let controller = ScanController(startServices: false, recordsHistory: false)
        controller.state = .scanning
        controller.totalFiles = inventory.count
        controller.scanWorkers = 2
        controller.launchDaemonClients(executable: runtime.appendingPathComponent("bin/clamdscan"), config: config,
                                      fileLists: inventory.fileLists, directFiles: [], queueCounts: inventory.queueCounts)
        defer { controller.shutdown() }
        for _ in 0..<500 {
            if !controller.isBusy { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.state == .finished)
        #expect(controller.processedFiles == inventory.count)
        #expect(controller.detections == [detected.path])
        #expect(controller.summary.errors == 0)
        #expect(controller.scanTelemetry.workers.count == 2)
        #expect(controller.scanTelemetry.workers.reduce(0) { $0 + $1.completed } == inventory.count)
        #expect(controller.scanTelemetry.workers.allSatisfy { $0.exitCode != nil && $0.queued == $0.completed })
        #expect(controller.history.isEmpty)
    }
    @Test @MainActor func missingBatchResultsCannotBeReportedAsClean() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/aura-missing-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = root.appendingPathComponent("empty-client")
        try "#!/bin/sh\nexit 0\n".write(to: client, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: client.path)
        let batches = (0..<5).map { root.appendingPathComponent("batch-\($0)") }
        let controller = ScanController(startServices: false, recordsHistory: false)
        controller.state = .scanning
        controller.scanWorkers = 2
        controller.totalFiles = 10
        controller.launchDaemonClients(executable: client, config: root.appendingPathComponent("unused"),
                                      fileLists: batches, directFiles: [],
                                      queueCounts: Dictionary(uniqueKeysWithValues: batches.map { ($0, 2) }))
        defer { controller.shutdown() }
        for _ in 0..<200 {
            if !controller.isBusy { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.state == .failed)
        #expect(controller.summary.errors == 5)
        #expect(controller.log.contains("Coverage could not be confirmed"))
        #expect(controller.scanTelemetry.workers.allSatisfy { $0.exitCode == 2 })
    }

    @Test @MainActor func cancellingDoesNotLaunchPendingBatches() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/aura-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = root.appendingPathComponent("slow-client")
        let launches = root.appendingPathComponent("launches")
        try "#!/bin/sh\necho started >> '\(launches.path)'\nexec /bin/sleep 10\n".write(to: client, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: client.path)
        let batches = (0..<20).map { root.appendingPathComponent("batch-\($0)") }
        let controller = ScanController(startServices: false, recordsHistory: false)
        controller.state = .scanning
        controller.scanWorkers = 2
        controller.totalFiles = 20
        controller.launchDaemonClients(executable: client, config: root.appendingPathComponent("unused"),
                                      fileLists: batches, directFiles: [],
                                      queueCounts: Dictionary(uniqueKeysWithValues: batches.map { ($0, 1) }))
        defer { controller.shutdown() }
        try await Task.sleep(for: .milliseconds(100))
        controller.cancelScan()
        for _ in 0..<200 {
            if !controller.isBusy { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.state == .idle)
        #expect(controller.scanWasCancelled)
        let started = (try? String(contentsOf: launches, encoding: .utf8))?.split(separator: "\n").count ?? 0
        #expect(started <= 2)
        #expect(controller.history.isEmpty)
    }

}
