import CommonCrypto
import Foundation
import os

final class HLSDownloader: Sendable {
    private let urlSession: URLSession
    private let userAgent: String

    init(urlSession: URLSession, userAgent: String) {
        self.urlSession = urlSession
        self.userAgent = userAgent
    }

    func download(playlistURL: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Int {
        let segments = try await mediaSegments(playlistURL: playlistURL)
        Log.cache.info("hls \(playlistURL.lastPathComponent, privacy: .public): \(segments.count, privacy: .public) segments")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var demuxer = MPEGTSDemuxer()
        var keys: [URL: Data] = [:]
        var written = 0
        for (index, segment) in segments.enumerated() {
            try Task.checkCancellation()
            var data = try await fetchWithRetry(segment.url)
            if let keyURL = segment.key.url {
                if keys[keyURL] == nil {
                    let key = try await fetchWithRetry(keyURL)
                    guard key.count == kCCKeySizeAES128 else { throw HLSError.keyLength(keyURL, key.count) }
                    keys[keyURL] = key
                }
                let iv = segment.key.iv ?? Data(count: kCCBlockSizeAES128)
                data = try AESCBCDecryptor.decrypt(data, key: keys[keyURL]!, iv: iv)
            }
            let audio = try demuxer.demux(data)
            if index == 0, demuxer.audioStreamType == nil {
                throw HLSError.noAudioStream
            }
            try handle.write(contentsOf: audio)
            written += audio.count
            progress(Double(index + 1) / Double(segments.count))
        }
        Log.cache.info("hls \(playlistURL.lastPathComponent, privacy: .public): stream type \(demuxer.audioStreamType.map { String(format: "0x%02x", $0) } ?? "?", privacy: .public), \(written, privacy: .public) bytes")
        return written
    }

    func maxBandwidth(playlistURL: URL) async throws -> Int? {
        let playlist = try await fetchPlaylist(playlistURL)
        if case .master(let variants) = playlist {
            return variants.map(\.bandwidth).max()
        }
        return nil
    }

    private func mediaSegments(playlistURL: URL) async throws -> [HLSSegment] {
        switch try await fetchPlaylist(playlistURL) {
        case .media(let segments):
            return segments
        case .master(let variants):
            guard let best = variants.max(by: { $0.bandwidth < $1.bandwidth }) else { throw HLSError.emptyPlaylist(playlistURL) }
            guard case .media(let segments) = try await fetchPlaylist(best.url) else { throw HLSError.emptyPlaylist(best.url) }
            return segments
        }
    }

    private func fetchPlaylist(_ url: URL) async throws -> HLSPlaylist {
        let data = try await fetchWithRetry(url)
        guard let text = String(data: data, encoding: .utf8) else { throw HLSError.emptyPlaylist(url) }
        return try HLSPlaylist(text: text, baseURL: url)
    }

    private func fetchWithRetry(_ url: URL, attempts: Int = 3) async throws -> Data {
        var lastError: Error = HLSError.badResponse(url, 0)
        for attempt in 1...attempts {
            do {
                return try await fetch(url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                Log.cache.notice("hls fetch attempt \(attempt, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        throw lastError
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw HLSError.badResponse(url, status) }
        return data
    }
}
