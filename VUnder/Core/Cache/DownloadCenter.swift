import Foundation
import os

@MainActor
final class DownloadCenter {
    static let didChange = Notification.Name("DownloadCenter.didChange")
    static let jobDidFinish = Notification.Name("DownloadCenter.jobDidFinish")

    enum Kind: Equatable {
        case cache
        case musicFolder
        case saveTo

        var title: String {
            switch self {
            case .cache: return "Save offline"
            case .musicFolder: return "Download to Music folder"
            case .saveTo: return "Save to..."
            }
        }
    }

    enum State: Equatable {
        case queued
        case running(Double?)
        case done(URL?)
        case failed(String)
        case cancelled

        var isFinished: Bool {
            switch self {
            case .queued, .running: return false
            case .done, .failed, .cancelled: return true
            }
        }
    }

    final class Job: Identifiable {
        let id = UUID()
        let track: Track
        let kind: Kind
        fileprivate(set) var state: State = .queued
        fileprivate var task: Task<Void, Never>?

        init(track: Track, kind: Kind) {
            self.track = track
            self.kind = kind
        }
    }

    private(set) var jobs: [Job] = []
    private let cache: AudioCache
    private let exporter: TrackExporter
    private var running = false

    init(cache: AudioCache, exporter: TrackExporter) {
        self.cache = cache
        self.exporter = exporter
    }

    var activeCount: Int {
        jobs.filter { !$0.state.isFinished }.count
    }

    @discardableResult
    func enqueue(_ track: Track, kind: Kind) -> Job {
        if let existing = jobs.first(where: { $0.track.isSame(as: track) && $0.kind == kind && !$0.state.isFinished }) {
            return existing
        }
        let job = Job(track: track, kind: kind)
        jobs.append(job)
        Log.cache.info("queued \(kind.title, privacy: .public) \(track.storageID, privacy: .public), active=\(self.activeCount, privacy: .public)")
        changed()
        runNext()
        return job
    }

    func cancel(_ job: Job) {
        guard !job.state.isFinished else { return }
        job.task?.cancel()
        job.state = .cancelled
        Log.cache.info("cancelled \(job.kind.title, privacy: .public) \(job.track.storageID, privacy: .public)")
        changed()
        runNext()
    }

    func cancelCacheJobs(for track: Track) {
        for job in jobs where job.kind == .cache && job.track.isSame(as: track) && !job.state.isFinished {
            cancel(job)
        }
    }

    func isCaching(_ track: Track) -> Bool {
        jobs.contains { $0.kind == .cache && $0.track.isSame(as: track) && !$0.state.isFinished }
    }

    func cancelAll() {
        for job in jobs where !job.state.isFinished {
            cancel(job)
        }
    }

    func clearFinished() {
        jobs.removeAll { $0.state.isFinished }
        changed()
    }

    private func runNext() {
        guard !running, let job = jobs.first(where: { $0.state == .queued }) else { return }
        running = true
        job.state = .running(nil)
        changed()
        job.task = Task { [weak self] in
            await self?.run(job)
            self?.running = false
            self?.runNext()
        }
    }

    private func run(_ job: Job) async {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(job.id.uuidString).part")
        do {
            if job.kind == .cache, await cache.isCached(job.track) {
                job.state = .done(nil)
                changed()
                return
            }
            try await cache.materialize(job.track, to: temporary) { [weak self, weak job] fraction in
                Task { @MainActor in
                    guard let self, let job, case .running = job.state else { return }
                    job.state = .running(fraction)
                    self.changed()
                }
            }
            try Task.checkCancellation()
            switch job.kind {
            case .cache:
                try await cache.install(job.track, from: temporary)
                job.state = .done(nil)
            case .musicFolder:
                job.state = .done(try exporter.placeInMusicFolder(temporary, for: job.track))
            case .saveTo:
                job.state = .done(try exporter.renameForSharing(temporary, for: job.track))
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                job.state = .cancelled
            } else {
                Log.cache.error("\(job.kind.title, privacy: .public) \(job.track.storageID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                job.state = .failed(error.localizedDescription)
            }
        }
        changed()
        NotificationCenter.default.post(name: DownloadCenter.jobDidFinish, object: self, userInfo: ["job": job])
    }

    private func changed() {
        NotificationCenter.default.post(name: DownloadCenter.didChange, object: self)
    }
}
