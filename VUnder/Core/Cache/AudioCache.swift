import CommonCrypto
import Foundation
import os

actor AudioCache {
    static let didChange = Notification.Name("AudioCache.didChange")

    private let directory: URL
    private let library: TrackLibrary
    private let urlSession: URLSession
    private let hls: HLSDownloader
    private var cachedIDs: Set<String> = []

    init(library: TrackLibrary) throws {
        self.library = library
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = support.appendingPathComponent("AudioCache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.httpShouldSetCookies = false
        urlSession = URLSession(configuration: configuration)
        hls = HLSDownloader(urlSession: urlSession, userAgent: VKClientIdentity.userAgent(.general))
    }

    nonisolated func fileURL(for track: Track) -> URL {
        directory.appendingPathComponent("\(track.ownerID)_\(track.id).mp3")
    }

    nonisolated func localFileURL(for track: Track) -> URL? {
        let url = fileURL(for: track)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func isCached(_ track: Track) -> Bool {
        cachedIDs.contains(track.storageID)
    }

    func reconcile() async {
        do {
            let marked = try await library.cachedTrackIDs()
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for stale in files where stale.hasSuffix(".part") {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(stale))
            }
            let present = Set(files.filter { $0.hasSuffix(".mp3") }.map { String($0.dropLast(4)) })
            for id in marked.subtracting(present) {
                Log.cache.notice("file missing for \(id, privacy: .public), unmarking")
                if let track = try await library.track(storageID: id) {
                    try await library.markCached(track, at: nil)
                }
            }
            for id in present.subtracting(marked) {
                Log.cache.notice("orphan file \(id, privacy: .public), deleting")
                try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).mp3"))
            }
            cachedIDs = marked.intersection(present)
            Log.cache.info("reconciled cached=\(self.cachedIDs.count, privacy: .public)")
            notify()
        } catch {
            Log.cache.error("reconcile failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func materialize(_ track: Track, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: destination)
        if let local = localFileURL(for: track) {
            try FileManager.default.copyItem(at: local, to: destination)
            progress(1)
            return
        }
        guard let urlString = track.url, let url = URL(string: urlString) else { throw DownloadError.noURL(track.storageID) }
        if track.isHLS {
            let size = try await hls.download(playlistURL: url, to: destination, progress: progress)
            guard size > 0 else { throw HLSError.noAudioStream }
            return
        }
        var request = URLRequest(url: url)
        request.setValue(VKClientIdentity.userAgent(.general), forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await urlSession.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw DownloadError.httpStatus(track.storageID, status) }
        let expected = response.expectedContentLength
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(65_536)
        var received: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 65_536 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 {
                    progress(Double(received) / Double(expected))
                }
            }
        }
        try handle.write(contentsOf: buffer)
        received += Int64(buffer.count)
        guard received > 0, expected <= 0 || received == expected else {
            throw DownloadError.incomplete(track.storageID, Int(received), expected)
        }
        progress(1)
    }

    func install(_ track: Track, from source: URL) async throws {
        let destination = fileURL(for: track)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: source, to: destination)
        try await library.markCached(track, at: Date())
        cachedIDs.insert(track.storageID)
        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        Log.cache.info("installed \(track.storageID, privacy: .public) \(size, privacy: .public) bytes")
        notify()
    }

    func remove(_ track: Track) async {
        try? FileManager.default.removeItem(at: fileURL(for: track))
        cachedIDs.remove(track.storageID)
        do {
            try await library.markCached(track, at: nil)
        } catch {
            Log.cache.error("unmark failed for \(track.storageID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        Log.cache.info("removed \(track.storageID, privacy: .public)")
        notify()
    }

    func clear() async {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        cachedIDs = []
        do {
            try await library.clearCacheMarks()
        } catch {
            Log.cache.error("clearing cache marks failed: \(error.localizedDescription, privacy: .public)")
        }
        Log.cache.info("cleared \(files.count, privacy: .public) files")
        notify()
    }

    func totalSize() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { total, file in
            total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func notify() {
        let ids = cachedIDs
        Task { @MainActor in
            NotificationCenter.default.post(name: AudioCache.didChange, object: nil, userInfo: ["ids": ids])
        }
    }
}

enum DownloadError: Error, LocalizedError {
    case noURL(String)
    case httpStatus(String, Int)
    case incomplete(String, Int, Int64)

    var errorDescription: String? {
        switch self {
        case .noURL(let id): return "Track \(id) has no url"
        case .httpStatus(let id, let status): return "Track \(id) download http=\(status)"
        case .incomplete(let id, let size, let expected): return "Track \(id) download incomplete: \(size) of \(expected) bytes"
        }
    }
}
