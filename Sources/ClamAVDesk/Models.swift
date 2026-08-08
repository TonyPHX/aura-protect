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

struct ScanSettings: Codable, Equatable, Sendable {
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

    static func infectionPath(_ line: String) -> String? {
        guard line.hasSuffix(" FOUND"),
              let separator = line.range(of: ": ", options: .backwards)?.lowerBound else { return nil }
        return String(line[..<separator])
    }

    static func isConcerning(_ line: String) -> Bool {
        if line.hasSuffix(" FOUND") || line.contains(" ERROR") { return true }
        let lower = line.lowercased()
        guard !lower.contains("infected files: 0"),
              !lower.contains("total errors: 0") else { return false }
        return lower.contains("error:") || lower.contains("warning:") ||
               lower.contains("permission denied") || lower.contains("access denied") ||
               lower.contains("failed") || lower.contains("can't open") || lower.contains("cannot open")
    }
}
