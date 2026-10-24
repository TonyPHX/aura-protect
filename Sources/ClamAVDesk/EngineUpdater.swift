import CryptoKit
import Foundation

enum EngineUpdater {
    static let previousEngineKey = "previousManagedClamAVEnginePath"
    static let currentEngineKey = "managedClamAVEnginePath"

    struct Release: Sendable {
        let version: String
        let packageURL: URL
        let digest: String
        let assetName: String
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let digest: String?
    }

    enum UpdateError: LocalizedError {
        case releaseLookup, noMacPackage, download, digestMismatch, extraction, incompleteRuntime, signing, publisher

        var errorDescription: String? {
            switch self {
            case .releaseLookup: "Could not retrieve official ClamAV release information."
            case .noMacPackage: "The latest release does not include a universal macOS package."
            case .download: "The official ClamAV engine package could not be downloaded."
            case .digestMismatch: "The engine package failed its published SHA-256 integrity check."
            case .extraction: "The official ClamAV engine package could not be unpacked."
            case .incompleteRuntime: "The downloaded package did not contain the required ClamAV components."
            case .publisher: "The package publisher could not be verified as Cisco. The installed engine was kept."
            case .signing: "macOS could not prepare the downloaded engine for private app use."
            }
        }
    }

    static func version(from versionOutput: String) -> String? {
        let firstLine = versionOutput.split(whereSeparator: \.isNewline).first.map(String.init) ?? versionOutput
        guard let range = firstLine.range(of: #"\d+\.\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        return String(firstLine[range])
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    static func latestRelease() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/Cisco-Talos/clamav/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("ClamAV-Desk", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.releaseLookup }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".macos.universal.pkg") }),
              let digest = asset.digest?.replacingOccurrences(of: "sha256:", with: "") else {
            throw UpdateError.noMacPackage
        }
        return Release(version: release.tag_name.replacingOccurrences(of: "clamav-", with: ""),
                       packageURL: asset.browser_download_url, digest: digest.lowercased(), assetName: asset.name)
    }

    static func install(release: Release, status: @escaping @Sendable (String) -> Void, supportRoot: URL? = nil) async throws -> URL {
        let manager = FileManager.default
        let support = supportRoot ?? manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Aura Protect/Engine", isDirectory: true)
        let destination = support.appendingPathComponent("Versions/\(release.version)", isDirectory: true)
        if manager.fileExists(atPath: destination.path) {
            guard validateRuntime(destination, expectedVersion: release.version) else { throw UpdateError.incompleteRuntime }
            return destination
        }
        let staging = support.appendingPathComponent("Staging-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: staging) }

        status("Downloading official ClamAV \(release.version) engine…")
        var request = URLRequest(url: release.packageURL)
        request.setValue("ClamAV-Desk", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download }
        let package = staging.appendingPathComponent(release.assetName)
        try manager.moveItem(at: temporary, to: package)

        status("Verifying the engine package…")
        guard try sha256(of: package) == release.digest else { throw UpdateError.digestMismatch }

        let signature = output("/usr/sbin/pkgutil", ["--check-signature", package.path])
        guard signature.success, signature.text.contains("Developer ID Installer: Cisco (DE8Y96K9QP)") else {
            throw UpdateError.publisher
        }
        status("Preparing the new engine…")
        let expanded = staging.appendingPathComponent("Expanded", isDirectory: true)
        guard run("/usr/sbin/pkgutil", ["--expand-full", package.path, expanded.path]) else {
            throw UpdateError.extraction
        }
        let contents = try manager.contentsOfDirectory(at: expanded, includingPropertiesForKeys: [.isDirectoryKey])
        guard let programs = contents.first(where: { $0.lastPathComponent.hasSuffix("-programs.pkg") }),
              let libraries = contents.first(where: { $0.lastPathComponent.hasSuffix("-libraries.pkg") }) else {
            throw UpdateError.incompleteRuntime
        }
        let programRoot = programs.appendingPathComponent("Payload/usr/local/clamav", isDirectory: true)
        let libraryRoot = libraries.appendingPathComponent("Payload/usr/local/clamav/lib", isDirectory: true)
        let prepared = staging.appendingPathComponent("Prepared", isDirectory: true)
        for folder in ["bin", "sbin", "lib", "etc/certs", "licenses"] {
            try manager.createDirectory(at: prepared.appendingPathComponent(folder, isDirectory: true),
                                        withIntermediateDirectories: true)
        }
        for name in ["clamscan", "clamdscan", "freshclam"] {
            try manager.copyItem(at: programRoot.appendingPathComponent("bin/\(name)"),
                                 to: prepared.appendingPathComponent("bin/\(name)"))
        }
        try manager.copyItem(at: programRoot.appendingPathComponent("sbin/clamd"),
                             to: prepared.appendingPathComponent("sbin/clamd"))
        try manager.copyItem(at: programRoot.appendingPathComponent("etc/certs/clamav.crt"),
                             to: prepared.appendingPathComponent("etc/certs/clamav.crt"))
        for item in try manager.contentsOfDirectory(at: libraryRoot, includingPropertiesForKeys: nil)
            where item.lastPathComponent.hasSuffix(".dylib") {
            try manager.copyItem(at: item, to: prepared.appendingPathComponent("lib/\(item.lastPathComponent)"))
        }
        let license = expanded.appendingPathComponent("Resources/License.txt")
        if manager.fileExists(atPath: license.path) {
            try manager.copyItem(at: license, to: prepared.appendingPathComponent("licenses/ClamAV-License.txt"))
        }
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", prepared.path])
        for relative in ["bin/clamscan", "bin/clamdscan", "bin/freshclam", "sbin/clamd"] {
            guard run("/usr/bin/codesign", ["--force", "--sign", "-", prepared.appendingPathComponent(relative).path]) else {
                throw UpdateError.signing
            }
        }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !manager.fileExists(atPath: destination.path) else { throw UpdateError.incompleteRuntime }
        try manager.moveItem(at: prepared, to: destination)
        guard validateRuntime(destination, expectedVersion: release.version) else {
            try? manager.removeItem(at: destination)
            throw UpdateError.incompleteRuntime
        }
        return destination
    }

    static func validateRuntime(_ root: URL, expectedVersion: String? = nil) -> Bool {
        for relative in ["bin/clamscan", "bin/clamdscan", "bin/freshclam", "sbin/clamd"] {
            let result = output(root.appendingPathComponent(relative).path, ["--help"], library: root.appendingPathComponent("lib").path)
            guard result.success, !result.text.isEmpty else { return false }
        }
        let scanner = output(root.appendingPathComponent("bin/clamscan").path, ["--version"], library: root.appendingPathComponent("lib").path)
        guard scanner.success, let found = version(from: scanner.text), expectedVersion == nil || found == expectedVersion else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("etc/certs/clamav.crt").path)
    }

    private static func output(_ executable: String, _ arguments: [String], library: String? = nil) -> (success: Bool, text: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        if let library { environment["DYLD_LIBRARY_PATH"] = library }
        process.environment = environment
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
        } catch { return (false, error.localizedDescription) }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func run(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { return false }
    }
}
