import Foundation
import GRDB
import os

final class AppDatabase: Sendable {
    let queue: DatabaseQueue

    init(path: String) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        queue = try DatabaseQueue(path: path, configuration: configuration)
        try AppDatabase.migrator.migrate(queue)
        Log.storage.info("database opened at \(path, privacy: .public)")
    }

    static func defaultPath() throws -> String {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return directory.appendingPathComponent("VUnder.sqlite").path
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_tracks") { db in
            try db.create(table: "track") { table in
                table.column("ownerID", .integer).notNull()
                table.column("id", .integer).notNull()
                table.column("artist", .text).notNull()
                table.column("title", .text).notNull()
                table.column("duration", .integer).notNull()
                table.column("url", .text)
                table.column("accessKey", .text)
                table.column("coverURL", .text)
                table.column("libraryPosition", .integer)
                table.primaryKey(["ownerID", "id"])
            }
            try db.create(index: "track_libraryPosition", on: "track", columns: ["libraryPosition"])
        }
        migrator.registerMigration("v2_cache_and_history") { db in
            try db.alter(table: "track") { table in
                table.add(column: "cachedAt", .datetime)
            }
            try db.create(table: "listenHistory") { table in
                table.column("trackOwnerID", .integer).notNull()
                table.column("trackID", .integer).notNull()
                table.column("listenedAt", .datetime).notNull()
                table.primaryKey(["trackOwnerID", "trackID"])
            }
            try db.create(index: "listenHistory_listenedAt", on: "listenHistory", columns: ["listenedAt"])
        }
        return migrator
    }
}
