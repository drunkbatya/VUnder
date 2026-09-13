import Foundation
import os

actor AudioCache {
    static let didChange = Notification.Name("AudioCache.didChange")

    private let directory: URL
    private let library: TrackLibrary
    private let urlSession: URLSession
    private let hls: HLSDownloader
    private var cachedIDs: Set<String> = []
    private var downloading: Set<String> = []
    private var pending: [Track] = []
    private var worker: Task<Void, Never>?

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

    func isDownloading(_ track: Track) -> Bool {
        downloading.contains(track.storageID) || pending.contains(where: { $0.storageID == track.storageID })
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

    func enqueue(_ track: Track) {
        guard !isCached(track), !isDownloading(track), track.url != nil else { return }
        pending.append(track)
        Log.cache.info("queued \(track.storageID, privacy: .public), pending=\(self.pending.count, privacy: .public)")
        notify()
        if worker == nil {
            worker = Task { await drain() }
        }
    }

    func remove(_ track: Track) async {
        pending.removeAll { $0.storageID == track.storageID }
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
        pending = []
        worker?.cancel()
        worker = nil
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

    private func drain() async {
        while !pending.isEmpty, !Task.isCancelled {
            let track = pending.removeFirst()
            downloading.insert(track.storageID)
            await download(track)
            downloading.remove(track.storageID)
        }
        worker = nil
    }

    private func download(_ track: Track) async {
        let temporary = directory.appendingPathComponent("\(track.storageID).part")
        let started = Date()
        do {
            let size = try await fetchAudio(track, to: temporary)
            let destination = fileURL(for: track)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            try await library.markCached(track, at: Date())
            cachedIDs.insert(track.storageID)
            Log.cache.info("downloaded \(track.isHLS ? "hls " : "", privacy: .public)\(track.storageID, privacy: .public) \(size, privacy: .public) bytes in \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public)ms")
            notify()
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            Log.cache.error("download \(track.storageID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func exportFile(for track: Track) async throws -> URL {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(track.storageID)-\(UUID().uuidString).mp3")
        if let local = localFileURL(for: track) {
            try FileManager.default.copyItem(at: local, to: temporary)
            return temporary
        }
        _ = try await fetchAudio(track, to: temporary)
        return temporary
    }

    private func fetchAudio(_ track: Track, to destination: URL) async throws -> Int {
        guard let urlString = track.url, let url = URL(string: urlString) else { throw DownloadError.noURL(track.storageID) }
        try? FileManager.default.removeItem(at: destination)
        if track.isHLS {
            let size = try await hls.download(playlistURL: url, to: destination)
            guard size > 0 else { throw HLSError.noAudioStream }
            return size
        }
        var request = URLRequest(url: url)
        request.setValue(VKClientIdentity.userAgent(.general), forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await urlSession.download(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            throw DownloadError.httpStatus(track.storageID, status)
        }
        let size = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let expected = response.expectedContentLength
        guard size > 0, expected <= 0 || Int64(size) == expected else {
            try? FileManager.default.removeItem(at: temporary)
            throw DownloadError.incomplete(track.storageID, size, expected)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return size
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
