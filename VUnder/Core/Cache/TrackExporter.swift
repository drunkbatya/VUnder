import Foundation
import os

final class TrackExporter: Sendable {
    static func musicDirectory() throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let music = documents.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        return music
    }

    static func fileName(for track: Track) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.controlCharacters).union(.newlines)
        var name = "\(track.artist) - \(track.title)"
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = track.storageID
        }
        if name.count > 120 {
            name = String(name.prefix(120))
        }
        return name
    }

    func renameForSharing(_ source: URL, for track: Track) throws -> URL {
        let named = source.deletingLastPathComponent().appendingPathComponent(TrackExporter.fileName(for: track) + ".mp3")
        try? FileManager.default.removeItem(at: named)
        try FileManager.default.moveItem(at: source, to: named)
        return named
    }

    func placeInMusicFolder(_ source: URL, for track: Track) throws -> URL {
        let directory = try TrackExporter.musicDirectory()
        let base = TrackExporter.fileName(for: track)
        var destination = directory.appendingPathComponent(base + ".mp3")
        var attempt = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(base) (\(attempt)).mp3")
            attempt += 1
        }
        try FileManager.default.moveItem(at: source, to: destination)
        Log.cache.info("exported \(track.storageID, privacy: .public) to \(destination.lastPathComponent, privacy: .public)")
        return destination
    }
}
