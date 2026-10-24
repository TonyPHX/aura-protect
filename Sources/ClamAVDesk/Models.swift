import Foundation

enum ScanState: Equatable {
    case idle, counting, scanning, cancelling, finished, finishedWithIssues, failed

    var label: String {
        switch self {
        case .idle: "Ready"
        case .counting: "Preparing scan…"
        case .scanning: "Scanning…"
        case .cancelling: "Cancelling…"
        case .finished: "Scan complete"
        case .finishedWithIssues: "Scan complete with issues"
        case .failed: "Scan failed"
        }
    }

    var hasResults: Bool {
        self == .finished || self == .finishedWithIssues || self == .failed
    }

    static func completionState(exitCode: Int32, processedFiles: Int) -> ScanState {
        if exitCode <= 1 { return .finished }
        return processedFiles > 0 ? .finishedWithIssues : .failed
    }
}

enum ScanMode: String, Codable, CaseIterable, Identifiable {
    case quiet = "Quiet", balanced = "Balanced", fast = "Fast"
    var id: String { rawValue }
    func workers(cores: Int, memoryGB: Int) -> Int {
        switch self {
        case .quiet: return 1
        case .balanced: return min(max(min(cores / 2, memoryGB / 2), 1), 4)
        case .fast: return min(max(min(cores - 1, memoryGB / 2), 1), 8)
        }
    }
}

struct ScanSettings: Codable, Equatable, Sendable {
    var scanMode: ScanMode = .balanced
    var monitorDownloads = false
    var scheduledScan = false
    var scheduledHour = 12
    var scheduledTarget = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
    var parallelScanning = true
    var automaticWorkerTuning = true
    var incrementalScanning = false
    var workerCount = min(max(ProcessInfo.processInfo.activeProcessorCount / 2, 2), 8)
    var recursive = true
    var scanArchives = true
    var scanHidden = true
    var detectPUA = false
    var followSymlinks = false
    var bellOnDetection = false
    var maxFileSizeMB = 100

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        scanMode = try values.decodeIfPresent(ScanMode.self, forKey: .scanMode) ?? .balanced
        monitorDownloads = try values.decodeIfPresent(Bool.self, forKey: .monitorDownloads) ?? false
        scheduledScan = try values.decodeIfPresent(Bool.self, forKey: .scheduledScan) ?? false
        scheduledHour = min(max(try values.decodeIfPresent(Int.self, forKey: .scheduledHour) ?? 12, 0), 23)
        scheduledTarget = try values.decodeIfPresent(String.self, forKey: .scheduledTarget) ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
        parallelScanning = try values.decodeIfPresent(Bool.self, forKey: .parallelScanning) ?? true
        automaticWorkerTuning = try values.decodeIfPresent(Bool.self, forKey: .automaticWorkerTuning) ?? true
        incrementalScanning = try values.decodeIfPresent(Bool.self, forKey: .incrementalScanning) ?? false
        workerCount = try values.decodeIfPresent(Int.self, forKey: .workerCount) ?? min(max(ProcessInfo.processInfo.activeProcessorCount / 2, 2), 8)
        recursive = try values.decodeIfPresent(Bool.self, forKey: .recursive) ?? true
        scanArchives = try values.decodeIfPresent(Bool.self, forKey: .scanArchives) ?? true
        scanHidden = try values.decodeIfPresent(Bool.self, forKey: .scanHidden) ?? true
        detectPUA = try values.decodeIfPresent(Bool.self, forKey: .detectPUA) ?? false
        followSymlinks = try values.decodeIfPresent(Bool.self, forKey: .followSymlinks) ?? false
        bellOnDetection = try values.decodeIfPresent(Bool.self, forKey: .bellOnDetection) ?? false
        maxFileSizeMB = try values.decodeIfPresent(Int.self, forKey: .maxFileSizeMB) ?? 100
    }

    static let defaultsKey = "scanSettings"

    static func load() -> ScanSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

struct ScanSummary: Equatable {
    var scannedFiles = 0
    var infectedFiles = 0
    var errors = 0
    var skippedFiles = 0
    var incompleteFiles = 0
    var reusedFiles = 0
    var duration: TimeInterval = 0
}

struct SignatureCategory: Codable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let count: Int
}

struct SignatureSnapshot: Codable, Equatable {
    let capturedAt: Date
    let categories: [SignatureCategory]
    var total: Int { categories.reduce(0) { $0 + $1.count } }
}

struct ScanChartItem: Identifiable {
    let name: String
    let count: Int
    let colorName: String
    var id: String { name }
}

struct QuarantineRecord: Codable {
    let originalPath: String
    let quarantinedPath: String
    let quarantinedAt: Date
    let engineVersion: String
    var detectionName: String? = nil
    var fileSHA256: String? = nil
    var restoredAt: Date? = nil
    var originalPermissions: Int? = nil
}

struct ScanHistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let target: String
    let scanned: Int
    let reused: Int
    let skipped: Int
    let incomplete: Int
    let detections: [String]
    let duration: TimeInterval
    let mode: ScanMode
    let workers: Int
    let engine: String
    var detectionDetails: [String: String]? = nil
}

enum OutputParser {
    static func resultPath(_ line: String) -> String? {
        guard isFileResult(line), let separator = line.range(of: ": ", options: .backwards)?.lowerBound else { return nil }
        return String(line[..<separator])
    }

    static func isFileResult(_ line: String) -> Bool {
        guard !line.hasPrefix("-----------"),
              !line.hasPrefix("Known viruses:"),
              !line.hasPrefix("Engine version:"),
              !line.hasPrefix("Scanned directories:"),
              !line.hasPrefix("Scanned files:"),
              !line.hasPrefix("Infected files:"),
              !line.hasPrefix("Data scanned:"),
              !line.hasPrefix("Data read:"),
              !line.hasPrefix("Time:") else { return false }
        return line.contains(": ") && (line.hasSuffix(" OK") || line.hasSuffix(" FOUND") || line.contains(" ERROR"))
    }

    static func isIncomplete(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("heuristics.limits.exceeded") || lower.contains("heuristics.encrypted") ||
            lower.contains("size limit exceeded") || lower.contains("scan time limit")
    }

    static func infectionPath(_ line: String) -> String? {
        guard line.hasSuffix(" FOUND"),
              let separator = line.range(of: ": ", options: .backwards)?.lowerBound else { return nil }
        return String(line[..<separator])
    }

    static func isGenuineError(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty,
              !lower.hasSuffix(" ok"),
              !lower.hasSuffix(" found"),
              !lower.hasPrefix("infected files:"),
              !lower.hasPrefix("total errors:"),
              !isFileAccessFailure(lower) else { return false }
        return lower.contains(" error") || lower.hasPrefix("error") ||
               lower.contains("fatal") || lower.contains("failed")
    }

    private static func isFileAccessFailure(_ lower: String) -> Bool {
        ["permission denied", "access denied", "operation not permitted",
         "can't open", "cannot open", "could not open",
         "can't access", "cannot access", "could not access",
         "no such file", "file not found"].contains { lower.contains($0) }
    }
}
