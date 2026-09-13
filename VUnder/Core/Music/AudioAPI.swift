import Foundation
import os

struct TrackPage {
    let tracks: [Track]
    let total: Int
}

final class AudioAPI: Sendable {
    static let libraryPageSize = 1000
    static let searchPageSize = 200

    private let api: VKAPIClient
    private let settings: AppSettings

    init(api: VKAPIClient, settings: AppSettings) {
        self.api = api
        self.settings = settings
    }

    private static let nonVersionErrorCodes: Set<Int> = [5, 6, 9, 10, 14, 17, 24, 29]

    private func audioCall(_ method: String, parameters: [(String, String)]) async throws -> JSONObject {
        guard !settings.preferHLS else {
            return try await api.call(.audio(method, version: VKAPIRequest.audioHLSVersion, parameters: parameters))
        }
        do {
            return try await api.call(.audio(method, version: VKAPIRequest.audioVersion, parameters: parameters))
        } catch VKAPIError.api(let original) where !AudioAPI.nonVersionErrorCodes.contains(original.code) {
            Log.music.error("\(method, privacy: .public) v=\(VKAPIRequest.audioVersion, privacy: .public) failed \(original.code, privacy: .public): \(original.message, privacy: .public), retrying with v=\(VKAPIRequest.audioHLSVersion, privacy: .public)")
            let json: JSONObject
            do {
                json = try await api.call(.audio(method, version: VKAPIRequest.audioHLSVersion, parameters: parameters))
            } catch {
                throw VKAPIError.api(original)
            }
            settings.preferHLS = true
            Log.music.fault("audio api v=\(VKAPIRequest.audioVersion, privacy: .public) is broken, switched to HLS version permanently")
            return json
        }
    }

    private func audioResponse(_ method: String, parameters: [(String, String)]) async throws -> JSONObject {
        let json = try await audioCall(method, parameters: parameters)
        guard let response = json.object("response") else {
            throw VKAPIError.malformedResponse(method: method)
        }
        return response
    }

    func tracksPage(ownerID: Int64, playlist: Playlist? = nil, offset: Int, count: Int = AudioAPI.libraryPageSize) async throws -> TrackPage {
        var parameters: [(String, String)] = [
            ("owner_id", String(ownerID)),
            ("offset", String(offset)),
            ("count", String(count)),
        ]
        if let playlist {
            parameters.append(("album_id", String(playlist.id)))
            if let accessKey = playlist.accessKey {
                parameters.append(("access_key", accessKey))
            }
        }
        let response = try await audioResponse("audio.get", parameters: parameters)
        return TrackPage(tracks: response.objects("items").compactMap(Track.init(json:)), total: response.int("count") ?? 0)
    }

    func allTracks(ownerID: Int64, playlist: Playlist? = nil, progress: @MainActor @Sendable (Int, Int) -> Void) async throws -> [Track] {
        var tracks: [Track] = []
        var total = 0
        repeat {
            let page = try await tracksPage(ownerID: ownerID, playlist: playlist, offset: tracks.count)
            total = page.total
            tracks += page.tracks
            Log.music.info("tracks page loaded owner=\(ownerID, privacy: .public) playlist=\(playlist?.id ?? 0, privacy: .public) offset=\(tracks.count - page.tracks.count, privacy: .public) items=\(page.tracks.count, privacy: .public) total=\(total, privacy: .public)")
            await progress(tracks.count, total)
            if page.tracks.isEmpty {
                break
            }
        } while tracks.count < total
        return tracks
    }

    func search(query: String, offset: Int, count: Int = AudioAPI.searchPageSize) async throws -> [Track] {
        let response = try await audioResponse("audio.search", parameters: [
            ("q", query),
            ("offset", String(offset)),
            ("count", String(count)),
        ])
        let tracks = response.objects("items").compactMap(Track.init(json:))
        Log.music.info("search '\(query, privacy: .public)' offset=\(offset, privacy: .public) items=\(tracks.count, privacy: .public)")
        return tracks
    }

    func freshURL(for track: Track) async throws -> String? {
        let json = try await audioCall("audio.getById", parameters: [("audios", track.fullID)])
        let items = (json.raw["response"] as? [[String: Any]])?.map(JSONObject.init) ?? []
        let url = items.first.flatMap(Track.init(json:))?.url
        Log.music.info("fresh url for \(track.fullID, privacy: .public): \(url != nil, privacy: .public)")
        return url
    }

    func playlists(ownerID: Int64) async throws -> [Playlist] {
        let response = try await audioResponse("audio.getPlaylists", parameters: [
            ("owner_id", String(ownerID)),
            ("filters", "all"),
            ("extended", "1"),
            ("count", "200"),
        ])
        let playlists = response.objects("items").compactMap(Playlist.init(json:))
        Log.music.info("playlists loaded owner=\(ownerID, privacy: .public) items=\(playlists.count, privacy: .public)")
        return playlists
    }
}
