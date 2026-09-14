import Foundation
import GRDB
import os

final class TrackLibrary: Sendable {
    static let didChange = Notification.Name("TrackLibrary.didChange")

    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func tracks() async throws -> [Track] {
        try await database.queue.read { db in
            try Track
                .filter(Track.Columns.libraryPosition != nil)
                .order(Track.Columns.libraryPosition)
                .fetchAll(db)
        }
    }

    func savedTracks() async throws -> [Track] {
        try await database.queue.read { db in
            try Track
                .filter(Track.Columns.cachedAt != nil)
                .order(Track.Columns.cachedAt.desc)
                .fetchAll(db)
        }
    }

    func listenedTracks() async throws -> [Track] {
        try await database.queue.read { db in
            try Track.fetchAll(db, sql: """
                SELECT track.* FROM track
                JOIN listenHistory ON listenHistory.trackOwnerID = track.ownerID AND listenHistory.trackID = track.id
                ORDER BY listenHistory.listenedAt DESC
                """)
        }
    }

    func replace(with tracks: [Track]) async throws {
        try await database.queue.write { db in
            try Track.updateAll(db, Track.Columns.libraryPosition.set(to: nil))
            for (position, track) in tracks.enumerated() {
                var record = try Track.fetchOne(db, key: ["ownerID": track.ownerID, "id": track.id]) ?? track
                record.artist = track.artist
                record.title = track.title
                record.duration = track.duration
                record.url = track.url
                record.accessKey = track.accessKey
                record.coverURL = track.coverURL
                record.libraryPosition = position
                try record.save(db)
            }
            try TrackLibrary.deleteOrphans(db)
        }
        Log.storage.info("library replaced with \(tracks.count, privacy: .public) tracks")
        notify()
    }

    func libraryIDs() async throws -> Set<String> {
        try await database.queue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT ownerID, id FROM track WHERE libraryPosition IS NOT NULL")
            return Set(rows.map { "\($0["ownerID"] as Int64)_\($0["id"] as Int64)" })
        }
    }

    func insertAtTop(_ track: Track) async throws {
        try await database.queue.write { db in
            try db.execute(sql: "UPDATE track SET libraryPosition = libraryPosition + 1 WHERE libraryPosition IS NOT NULL")
            var stored = try Track.fetchOne(db, key: ["ownerID": track.ownerID, "id": track.id]) ?? track
            stored.libraryPosition = 0
            try stored.save(db)
        }
        Log.storage.info("library insert at top \(track.storageID, privacy: .public)")
        notify()
    }

    func removeFromLibrary(_ track: Track) async throws {
        try await database.queue.write { db in
            guard var stored = try Track.fetchOne(db, key: ["ownerID": track.ownerID, "id": track.id]) else { return }
            stored.libraryPosition = nil
            try stored.save(db)
            try TrackLibrary.deleteOrphans(db)
        }
        Log.storage.info("library remove \(track.storageID, privacy: .public)")
        notify()
    }

    func track(storageID: String) async throws -> Track? {
        let parts = storageID.split(separator: "_")
        guard parts.count == 2, let ownerID = Int64(parts[0]), let id = Int64(parts[1]) else { return nil }
        return try await database.queue.read { db in
            try Track.fetchOne(db, key: ["ownerID": ownerID, "id": id])
        }
    }

    func cachedTrackIDs() async throws -> Set<String> {
        try await database.queue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT ownerID, id FROM track WHERE cachedAt IS NOT NULL")
            return Set(rows.map { "\($0["ownerID"] as Int64)_\($0["id"] as Int64)" })
        }
    }

    func markCached(_ track: Track, at date: Date?) async throws {
        try await database.queue.write { db in
            var stored = try Track.fetchOne(db, key: ["ownerID": track.ownerID, "id": track.id]) ?? track
            stored.cachedAt = date
            try stored.save(db)
            if date == nil {
                try TrackLibrary.deleteOrphans(db)
            }
        }
    }

    func clearCacheMarks() async throws {
        try await database.queue.write { db in
            try Track.updateAll(db, Track.Columns.cachedAt.set(to: nil))
            try TrackLibrary.deleteOrphans(db)
        }
    }

    func recordListen(_ track: Track) async throws {
        try await database.queue.write { db in
            if try Track.fetchOne(db, key: ["ownerID": track.ownerID, "id": track.id]) == nil {
                var stored = track
                stored.libraryPosition = nil
                stored.cachedAt = nil
                try stored.insert(db)
            }
            try ListenHistoryEntry(trackOwnerID: track.ownerID, trackID: track.id, listenedAt: Date()).save(db)
        }
    }

    func clear() async throws {
        let deleted = try await database.queue.write { db in
            try ListenHistoryEntry.deleteAll(db)
            return try Track.deleteAll(db)
        }
        Log.storage.info("library cleared, removed \(deleted, privacy: .public) tracks")
        notify()
    }

    private func notify() {
        Task { @MainActor in
            NotificationCenter.default.post(name: TrackLibrary.didChange, object: nil)
        }
    }

    private static func deleteOrphans(_ db: Database) throws {
        try db.execute(sql: """
            DELETE FROM track
            WHERE libraryPosition IS NULL AND cachedAt IS NULL
              AND NOT EXISTS (SELECT 1 FROM listenHistory WHERE trackOwnerID = track.ownerID AND trackID = track.id)
            """)
    }
}
