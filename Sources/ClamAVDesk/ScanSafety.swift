import CryptoKit
import Foundation

/// A cache hit requires both identical content and stable file identity/metadata.
struct CleanFileStamp: Equatable, Sendable {
    let digest: String
    let size: UInt64
    let modified: Date
    let created: Date
    let inode: UInt64

    static func read(_ url: URL) -> CleanFileStamp? {
        let manager = FileManager.default
        guard let before = try? manager.attributesOfItem(atPath: url.path),
              before[.type] as? FileAttributeType == .typeRegular,
              let size = before[.size] as? UInt64,
              let modified = before[.modificationDate] as? Date,
              let created = before[.creationDate] as? Date,
              let inode = before[.systemFileNumber] as? UInt64,
              let digest = try? fileSHA256(url),
              let after = try? manager.attributesOfItem(atPath: url.path),
              NSDictionary(dictionary: before).isEqual(to: after) else { return nil }
        return .init(digest: digest, size: size, modified: modified, created: created, inode: inode)
    }
}

func fileSHA256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        if Task.isCancelled { throw CancellationError() }
        hash.update(data: data)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

struct ScanCacheContext {
    static func key(engine: URL, version: String, database: URL, settings: ScanSettings) throws -> String {
        let entries = try FileManager.default.contentsOfDirectory(at: database, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        // Include all database files, not only daily.cvd, and all scan-affecting settings.
        var key = engine.resolvingSymlinksInPath().path + "|" + version + "|" + (try fileSHA256(engine))
        for file in entries { key += "|\(file.lastPathComponent):\(try fileSHA256(file))" }
        key += "|\(settings.recursive)|\(settings.scanArchives)|\(settings.scanHidden)|\(settings.detectPUA)|\(settings.followSymlinks)|\(settings.maxFileSizeMB)"
        return key
    }
}
