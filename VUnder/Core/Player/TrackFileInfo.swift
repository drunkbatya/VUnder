import Foundation
import os

struct TrackFileInfo: Equatable {
    let sizeBytes: Int64
    let bitrateKbps: Int
    let isLocal: Bool
    let isHLS: Bool

    var formatted: String {
        let size = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        var parts = ["\(bitrateKbps) kbps", isHLS ? "~\(size)" : size]
        if isHLS {
            parts.append("HLS")
        }
        if isLocal {
            parts.append("saved")
        }
        return parts.joined(separator: ", ")
    }
}

final class TrackFileInfoProvider: Sendable {
    private let localFileURL: @Sendable (Track) -> URL?
    private let urlSession: URLSession
    private let hls: HLSDownloader

    init(localFileURL: @escaping @Sendable (Track) -> URL?) {
        self.localFileURL = localFileURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        urlSession = URLSession(configuration: configuration)
        hls = HLSDownloader(urlSession: urlSession, userAgent: VKClientIdentity.userAgent(.general))
    }

    func info(for track: Track) async -> TrackFileInfo? {
        guard track.duration > 0 else { return nil }
        if let local = localFileURL(track), let size = try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
            return TrackFileInfo(sizeBytes: Int64(size), bitrateKbps: TrackFileInfoProvider.bitrate(bytes: Int64(size), duration: track.duration), isLocal: true, isHLS: false)
        }
        guard let urlString = track.url, let url = URL(string: urlString) else { return nil }
        if track.isHLS {
            guard let bandwidth = try? await hls.maxBandwidth(playlistURL: url), bandwidth > 0 else { return nil }
            let estimated = Int64(bandwidth) * Int64(track.duration) / 8
            return TrackFileInfo(sizeBytes: estimated, bitrateKbps: bandwidth / 1000, isLocal: false, isHLS: true)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(VKClientIdentity.userAgent(.general), forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await urlSession.data(for: request), let http = response as? HTTPURLResponse else { return nil }
        let size = http.expectedContentLength
        guard size > 0 else {
            Log.player.notice("no content length for \(track.storageID, privacy: .public) http=\(http.statusCode, privacy: .public)")
            return nil
        }
        return TrackFileInfo(sizeBytes: size, bitrateKbps: TrackFileInfoProvider.bitrate(bytes: size, duration: track.duration), isLocal: false, isHLS: false)
    }

    private static func bitrate(bytes: Int64, duration: Int) -> Int {
        Int(bytes * 8 / Int64(duration) / 1000)
    }
}
