import Darwin
import Foundation

/// A bounded file list that ClamAV can read while discovery is still in progress.
final class ScanInputPipe {
    private var descriptor: Int32 = -1
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

    func openWriter() throws {
        while descriptor < 0 {
            try Task.checkCancellation()
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
        try data.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                let written = Darwin.write(descriptor, address.advanced(by: offset), bytes.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0 && (errno == EAGAIN || errno == EINTR) {
                    Thread.sleep(forTimeInterval: 0.002)
                } else {
                    throw POSIXError(.EIO)
                }
            }
        }
    }
}
