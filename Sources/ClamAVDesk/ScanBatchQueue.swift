import Foundation

/// Bounded work assignment: workers pull another batch only after their prior one exits.
struct ScanBatchQueue {
    private var batches: [URL] = []
    private var nextIndex = 0
    private(set) var active: [Int: URL] = [:]
    var pendingCount: Int { batches.count - nextIndex }
    var isFinished: Bool { pendingCount == 0 && active.isEmpty }

    mutating func reset(_ batches: [URL] = []) {
        self.batches = batches
        nextIndex = 0
        active = [:]
    }

    mutating func take(for worker: Int) -> URL? {
        guard active[worker] == nil, nextIndex < batches.count else { return nil }
        let batch = batches[nextIndex]
        nextIndex += 1
        active[worker] = batch
        return batch
    }

    mutating func complete(worker: Int) {
        active.removeValue(forKey: worker)
    }
}
