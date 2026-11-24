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
            descriptor = open(url.path, O_WRONLY | O_NONBLOCK | O_CLOEXEC)
            if descriptor >= 0 {
                if fcntl(descriptor, F_SETNOSIGPIPE, 1) == -1 { throw POSIXError(.EIO) }
            } else {
                guard errno == ENXIO || errno == EINTR else { throw POSIXError(.EIO) }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }

    func writePaths(_ data: Data) throws {
        _ = try writeAvailable(data, shouldPause: { false })
    }

    func submitPaths(_ data: Data, shouldPause: () -> Bool) throws {
        try drainBacklog(shouldPause: shouldPause)
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

    func drainBacklog(shouldPause: () -> Bool) throws {
        guard let file = backlog else { return }
        while !shouldPause() {
            try Task.checkCancellation()
            try file.seek(toOffset: backlogReadOffset)
            guard let chunk = try file.read(upToCount: 32_768), !chunk.isEmpty else {
                backlog = nil
                backlogReadOffset = 0
                return
            }
            let written = try writeAvailable(chunk, shouldPause: shouldPause)
            backlogReadOffset += UInt64(written)
            if written < chunk.count { return }
        }
    }

    private func writeAvailable(_ data: Data, shouldPause: () -> Bool) throws -> Int {
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
