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
        migrator.registerMigration("v3_messages") { db in
            try db.create(table: "profile") { table in
                table.column("id", .integer).primaryKey()
                table.column("name", .text).notNull()
                table.column("photoURL", .text)
            }
            try db.create(table: "conversation") { table in
                table.column("peerID", .integer).primaryKey()
                table.column("title", .text).notNull()
                table.column("photoURL", .text)
                table.column("unreadCount", .integer).notNull()
                table.column("inRead", .integer).notNull()
                table.column("outRead", .integer).notNull()
                table.column("canWrite", .boolean).notNull()
                table.column("lastMessage", .text)
                table.column("sortDate", .datetime).notNull()
            }
            try db.create(table: "message") { table in
                table.column("id", .integer).primaryKey()
                table.column("peerID", .integer).notNull()
                table.column("fromID", .integer).notNull()
                table.column("date", .datetime).notNull()
                table.column("text", .text).notNull()
                table.column("out", .boolean).notNull()
                table.column("attachments", .text).notNull()
                table.column("randomID", .integer).notNull()
            }
            try db.create(index: "message_peerID", on: "message", columns: ["peerID", "id"])
            try db.create(table: "outgoingMessage") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("peerID", .integer).notNull()
                table.column("text", .text).notNull()
                table.column("track", .text)
                table.column("randomID", .integer).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("failure", .text)
            }
        }
        migrator.registerMigration("v4_outgoing_attachments") { db in
            try db.drop(table: "outgoingMessage")
            try db.create(table: "outgoingMessage") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("peerID", .integer).notNull()
                table.column("text", .text).notNull()
                table.column("attachments", .text).notNull()
                table.column("randomID", .integer).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("failure", .text)
            }
        }
        return migrator
    }
}
