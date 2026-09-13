import Foundation
import GRDB
import os

final class TrackLibrary: Sendable {
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
    }

    private static func deleteOrphans(_ db: Database) throws {
        try db.execute(sql: """
            DELETE FROM track
            WHERE libraryPosition IS NULL AND cachedAt IS NULL
              AND NOT EXISTS (SELECT 1 FROM listenHistory WHERE trackOwnerID = track.ownerID AND trackID = track.id)
            """)
    }
}
