import Foundation

struct ScanWorkerActivity: Identifiable, Equatable {
    let id: Int
    let queued: Int
    var completed = 0
    var latestPath: String?
    var exitCode: Int32?
    var fraction: Double { queued > 0 ? min(Double(completed) / Double(queued), 1) : 0 }
}

struct ScanRateSample: Identifiable, Equatable {
    let id: Int
    let seconds: TimeInterval
    let filesPerSecond: Double
}

/// Observed completions, not synthetic activity. At most one sample per second
/// is retained for the last minute, with an optional final partial interval.
struct ScanTelemetry: Equatable {
    var workers: [ScanWorkerActivity] = []
    var samples: [ScanRateSample] = []
    var latestPath: String?
    var latestPathIsCurrent = false
    private var startedAt: TimeInterval?
    private var sampledAt: TimeInterval?
    private var sampledCount = 0
    private var nextSampleID = 0
    var currentRate: Double? { samples.last?.filesPerSecond }

    mutating func start(queues: [Int], now: TimeInterval) {
        self = .init()
        workers = queues.enumerated().map { .init(id: $0.offset, queued: $0.element) }
        startedAt = now
        sampledAt = now
    }

    mutating func report(path: String, worker: Int, completed: Bool) {
        latestPath = path
        latestPathIsCurrent = !completed
        guard workers.indices.contains(worker) else { return }
        workers[worker].latestPath = path
        if completed { workers[worker].completed += 1 }
    }

    mutating func finishWorker(_ worker: Int, code: Int32) {
        guard workers.indices.contains(worker) else { return }
        workers[worker].exitCode = code
        latestPathIsCurrent = false
    }

    mutating func sample(completed: Int, now: TimeInterval, force: Bool = false) {
        guard let start = startedAt, let previous = sampledAt else { return }
        let interval = now - previous
        guard interval > 0, force || interval >= 1 else { return }
        let rate = Double(max(completed - sampledCount, 0)) / interval
        samples.append(.init(id: nextSampleID, seconds: max(now - start, 0), filesPerSecond: rate))
        nextSampleID += 1
        samples.removeAll { $0.seconds < now - start - 60 }
        if samples.count > 61 { samples.removeFirst(samples.count - 61) }
        sampledAt = now
        sampledCount = completed
    }
}
