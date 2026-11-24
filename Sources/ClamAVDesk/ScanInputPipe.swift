import Darwin
import Foundation

/// A bounded file list that ClamAV can read while discovery is still in progress.
final class ScanInputPipe {
    private var descriptor: Int32 = -1
    private var backlog: FileHandle?
    private var backlogReadOffset: UInt64 = 0
    var isOpen: Bool { descriptor >= 0 }
    var hasBacklog: Bool { backlog != nil }
    let url: URL

    init(url: URL) {
        self.url = url
    }

    deinit { closeWriter() }

    func closeWriter() {
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
    }

    func openWriter(shouldPause: () -> Bool = { false }) throws {
        while descriptor < 0 {
            try Task.checkCancellation()
            if shouldPause() { return }
            if try !tryOpenWriter() { Thread.sleep(forTimeInterval: 0.01) }
        }
    }

    private func tryOpenWriter() throws -> Bool {
        if isOpen { return true }
        descriptor = open(url.path, O_WRONLY | O_NONBLOCK | O_CLOEXEC)
        if descriptor >= 0 {
            guard fcntl(descriptor, F_SETNOSIGPIPE, 1) != -1 else { throw POSIXError(.EIO) }
            return true
        }
        guard errno == ENXIO || errno == EINTR else { throw POSIXError(.EIO) }
        return false
    }

    func writePaths(_ data: Data) throws {
        _ = try writeAvailable(data, shouldPause: { false })
    }

    func submitPaths(_ data: Data, shouldPause: () -> Bool) throws {
        let written = hasBacklog ? 0 : try writeAvailable(data, shouldPause: shouldPause)
        guard written < data.count else { return }
        let file: FileHandle
        if let backlog {
            file = backlog
        } else {
            // Unlink the private spool immediately so a crash cannot leave scan paths behind.
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".scan-backlog-\(UUID().uuidString)")
            let fd = open(temporary.path, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try FileManager.default.removeItem(at: temporary)
            backlog = file
        }
        _ = try file.seekToEnd()
        try file.write(contentsOf: data.dropFirst(written))
    }

    /// Give each worker one nonblocking turn before feeding any worker again.
    /// A full FIFO must not delay delivery to other workers.
    static func drainBacklogs(_ pipes: [ScanInputPipe], shouldPause: () -> Bool) throws {
        while pipes.contains(where: { !$0.isOpen || $0.hasBacklog }) {
            try Task.checkCancellation()
            var madeProgress = false
            for pipe in pipes {
                if shouldPause() { return }
                if try pipe.tryOpenWriter(), try pipe.drainChunk(shouldPause: shouldPause) {
                    madeProgress = true
                }
            }
            if !madeProgress { Thread.sleep(forTimeInterval: 0.002) }
        }
    }

    private func drainChunk(shouldPause: () -> Bool) throws -> Bool {
        guard let file = backlog else { return false }
        try file.seek(toOffset: backlogReadOffset)
        guard let chunk = try file.read(upToCount: 32_768), !chunk.isEmpty else {
            backlog = nil
            backlogReadOffset = 0
            return true
        }
        let written = try writeAvailable(chunk, waitForSpace: false, shouldPause: shouldPause)
        backlogReadOffset += UInt64(written)
        return written > 0
    }

    private func writeAvailable(_ data: Data, waitForSpace: Bool = true,
                                shouldPause: () -> Bool) throws -> Int {
        try data.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return 0 }
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                if shouldPause() { break }
                let written = Darwin.write(descriptor, address.advanced(by: offset), bytes.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0 && (errno == EAGAIN || errno == EINTR) {
                    if !waitForSpace { break }
                    Thread.sleep(forTimeInterval: 0.002)
                } else {
                    throw POSIXError(.EIO)
                }
            }
            return offset
        }
    }
}

/// Delivers the selected inputs once startup chooses parallel workers or single-process fallback.
final class ScanInputReadiness: @unchecked Sendable {
    private let condition = NSCondition()
    private var inputs: [URL]?
    private var paused = false

    var isPaused: Bool {
        condition.lock()
        defer { condition.unlock() }
        return paused
    }

    func setPaused(_ paused: Bool) {
        condition.lock()
        self.paused = paused
        condition.broadcast()
        condition.unlock()
    }

    func waitUntilResumed() throws {
        condition.lock()
        defer { condition.unlock() }
        while paused {
            try Task.checkCancellation()
            _ = condition.wait(until: Date(timeIntervalSinceNow: 0.05))
        }
        try Task.checkCancellation()
    }

    func publish(_ inputs: [URL]) {
        condition.lock()
        self.inputs = inputs
        condition.broadcast()
        condition.unlock()
    }

    var isReady: Bool {
        condition.lock()
        defer { condition.unlock() }
        return inputs != nil
    }

    func waitForInputs() throws -> [URL] {
        condition.lock()
        defer { condition.unlock() }
        while inputs == nil {
            try Task.checkCancellation()
            _ = condition.wait(until: Date(timeIntervalSinceNow: 0.05))
        }
        try Task.checkCancellation()
        return inputs ?? []
    }
}
