import Foundation

struct ScanWorkerActivity: Identifiable, Equatable {
    let id: Int
    var queued: Int
    var completed = 0
    var latestPath: String?
    var exitCode: Int32?
    var worstExitCode: Int32 = 0
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
    private(set) var peakRate: Double?
    var averageRate: Double? {
        guard let start = startedAt, let end = sampledAt, end > start else { return nil }
        return Double(sampledCount) / (end - start)
    }

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

    mutating func assign(files: Int, to worker: Int) {
        guard workers.indices.contains(worker) else { return }
        workers[worker].queued += files
        workers[worker].exitCode = nil
    }

    mutating func recordExit(worker: Int, code: Int32) {
        guard workers.indices.contains(worker) else { return }
        workers[worker].worstExitCode = max(workers[worker].worstExitCode, code)
    }

    mutating func finishWorker(_ worker: Int, code: Int32) {
        guard workers.indices.contains(worker) else { return }
        recordExit(worker: worker, code: code)
        workers[worker].exitCode = workers[worker].worstExitCode
        latestPathIsCurrent = false
    }

    mutating func sample(completed: Int, now: TimeInterval, force: Bool = false) {
        guard let start = startedAt, let previous = sampledAt else { return }
        let interval = now - previous
        guard interval > 0, force || interval >= 1 else { return }
        let rate = Double(max(completed - sampledCount, 0)) / interval
        peakRate = max(peakRate ?? 0, rate)
        samples.append(.init(id: nextSampleID, seconds: max(now - start, 0), filesPerSecond: rate))
        nextSampleID += 1
        samples.removeAll { $0.seconds < now - start - 60 }
        if samples.count > 61 { samples.removeFirst(samples.count - 61) }
        sampledAt = now
        sampledCount = completed
    }
}

/// The dial's numerical range is visible and shared by current/average gauges.
enum ScanSpeedScale {
    static func maximum(for peak: Double?) -> Double {
        guard let peak, peak.isFinite, peak > 10 else { return 10 }
        let power = pow(10, floor(log10(peak)))
        for step in [1.0, 2, 5, 10] where step * power >= peak { return step * power }
        return peak
    }

    static func fraction(rate: Double?, maximum: Double) -> Double {
        guard let rate, rate.isFinite, maximum.isFinite, maximum > 0 else { return 0 }
        return min(max(rate / maximum, 0), 1)
    }
}
