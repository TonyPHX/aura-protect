import Foundation
import Testing
@testable import ClamAVDesk

struct ScanPerformanceTests {
    private func fixture() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp/aura-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func batchesAreAssignedExactlyOnceAndBounded() {
        let batches = (0..<40).map { URL(fileURLWithPath: "/batch-\($0)") }
        var queue = ScanBatchQueue()
        queue.reset(batches)
        var seen: [URL] = []
        for worker in 0..<4 { seen.append(queue.take(for: worker)!) }
        #expect(queue.take(for: 0) == nil)
        while queue.pendingCount > 0 {
            // A faster worker takes more work while the others remain occupied.
            queue.complete(worker: 0)
            seen.append(queue.take(for: 0)!)
            #expect(queue.active.count == 4)
        }
        #expect(Set(seen) == Set(batches))
        #expect(seen.count == batches.count)
        #expect(!queue.isFinished)
        for worker in 0..<4 { queue.complete(worker: worker) }
        #expect(queue.isFinished)
        queue.reset(batches)
        _ = queue.take(for: 0)
        queue.reset()
        #expect(queue.isFinished)
        #expect(queue.take(for: 0) == nil)
    }

    @Test func workerTotalsAndErrorsSurviveBatchChanges() {
        var telemetry = ScanTelemetry()
        telemetry.start(queues: [0, 0], now: 0)
        telemetry.assign(files: 2, to: 0)
        telemetry.report(path: "/one", worker: 0, completed: true)
        telemetry.recordExit(worker: 0, code: 2)
        telemetry.assign(files: 3, to: 0)
        telemetry.finishWorker(0, code: 0)
        #expect(telemetry.workers[0].queued == 5)
        #expect(telemetry.workers[0].completed == 1)
        #expect(telemetry.workers[0].exitCode == 2)
    }

    @Test func inventoryCoverageAndLimits() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("corpus")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for index in 0..<1000 { try Data([65]).write(to: target.appendingPathComponent("file-\(index)")) }
        try Data([65]).write(to: target.appendingPathComponent("line\nbreak"))
        try Data([65]).write(to: target.appendingPathComponent(".hidden"))
        try FileManager.default.createSymbolicLink(at: target.appendingPathComponent("link"), withDestinationURL: target.appendingPathComponent("file-0"))
        var settings = ScanSettings()
        settings.workerCount = 2
        let result = try ScanController.prepareScanFileList(at: target, settings: settings, cache: [:], inventoryDirectory: root)
        let listed = try result.fileLists.flatMap { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n").map(String.init) }
        #expect(result.count == 1001)
        #expect(result.skippedCount == 1)
        #expect(listed.count == Set(listed).count)
        #expect(listed.count == result.count)
        #expect(result.fileLists.count > settings.workerCount)
        #expect(result.fileLists.count <= settings.workerCount * 8)
        #expect(result.queueCounts.values.reduce(0, +) == result.count)
        #expect(listed.contains(target.appendingPathComponent(".hidden").path))
        #expect(!listed.contains(target.appendingPathComponent("link").path))
        for list in result.fileLists {
            let mode = try FileManager.default.attributesOfItem(atPath: list.path)[.posixPermissions] as? Int
            #expect(mode == 0o600)
        }
    }

    @Test func smallScansAvoidExtraClientsAndSerialStaysSerial() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("corpus")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for index in 0..<20 { try Data([65]).write(to: target.appendingPathComponent("file-\(index)")) }
        var settings = ScanSettings()
        settings.workerCount = 4
        let small = try ScanController.prepareScanFileList(at: target, settings: settings, cache: [:], inventoryDirectory: root)
        #expect(small.fileLists.count == 4)
        settings.parallelScanning = false
        let serial = try ScanController.prepareScanFileList(at: target, settings: settings, cache: [:], inventoryDirectory: root)
        #expect(serial.fileLists.count == 1)
        #expect(serial.count == small.count)
    }

    @Test func hiddenRecursionAndSizeFilters() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("corpus")
        try FileManager.default.createDirectory(at: target.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try Data([65]).write(to: target.appendingPathComponent(".hidden"))
        try Data([65]).write(to: target.appendingPathComponent("nested/file"))
        try Data(repeating: 65, count: 1_048_577).write(to: target.appendingPathComponent("large"))
        var settings = ScanSettings()
        settings.recursive = false
        settings.scanHidden = false
        settings.maxFileSizeMB = 1
        let result = try ScanController.prepareScanFileList(at: target, settings: settings, cache: [:], inventoryDirectory: root)
        #expect(result.count == 0)
        #expect(result.skippedCount == 1)
        #expect(result.fileLists.isEmpty)
    }

    @Test func cancelledInventoryDoesNotLeaveLists() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ScanController.prepareScanFileList(at: root, settings: ScanSettings(), cache: [:], inventoryDirectory: root)
        }
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError { }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func contentCacheRefusesSameSizeReplacement() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        try Data("before".utf8).write(to: file)
        let original = try #require(CleanFileStamp.read(file))
        try Data("after!".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: original.modified], ofItemAtPath: file.path)
        let replaced = try #require(CleanFileStamp.read(file))
        #expect(original.size == replaced.size)
        #expect(original != replaced)
    }

    @Test func oldHistoryDecodesWithoutPhaseTimings() throws {
        let entry = ScanHistoryEntry(id: UUID(), date: .now, target: "/fixture", scanned: 1, reused: 0,
                                     skipped: 0, incomplete: 0, detections: [], duration: 2, mode: .balanced,
                                     workers: 1, engine: "ClamAV 1.5.4")
        let decoded = try JSONDecoder().decode(ScanHistoryEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded.preparationDuration == nil)
        #expect(decoded.duration == 2)
    }
}
