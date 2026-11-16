import Foundation
import GRDB
import TalkFlowDomain

/// Read-only access to the archive katok maintains.
///
/// katok is the only writer. Opening read-only makes that guarantee explicit and
/// keeps a TalkFlow bug from corrupting an archive that took a full sync to build.
/// The schema coupling stops with this reader and the row mapping beside it;
/// callers see domain models.
struct KatokArchiveReader: Sendable {
    enum ReadError: LocalizedError, Equatable {
        case archiveMissing
        case accountUnverified

        var errorDescription: String? {
            switch self {
            case .archiveMissing: "카카오톡 대화 아카이브가 아직 없습니다. 동기화를 먼저 실행하세요."
            case .accountUnverified: "현재 카카오톡 계정을 확인할 수 없어 대화를 읽지 않았습니다."
            }
        }
    }

    private let database: DatabaseQueue
    private let accountSenderID: String
    /// katok stores every account it has ever synced in one archive, so reads
    /// have to be scoped. Without this a room list mixes accounts, and a reply
    /// could be drafted from a conversation the signed-in account never had.
    private let accountHash: String

    init(environment: KatokEnvironment = KatokEnvironment()) throws {
        let url = environment.archiveURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReadError.archiveMissing
        }
        guard let identity = environment.accountIdentity() else {
            throw ReadError.accountUnverified
        }

        var configuration = Configuration()
        configuration.readonly = true
        database = try DatabaseQueue(path: url.path, configuration: configuration)
        accountSenderID = identity.senderID
        accountHash = identity.archiveHash
    }

    /// The name KakaoTalk shows for this account: the nickname stamped on the
    /// messages it sent. Nothing else in the archive names the account.
    ///
    /// The newest one wins, because renaming yourself leaves every older message
    /// under the old name. Nil is a real answer — an account that has never
    /// written has no name on record — and borrowing somebody else's would have
    /// the app answer to a stranger.
    func accountNickname() -> String? {
        newestNickname(inChat: nil)
    }

    /// The name this account goes by in one room.
    ///
    /// The nickname is stamped on each message rather than held once per account,
    /// and KakaoTalk lets the same account carry a different name in each chat —
    /// open chats are where people do it on purpose. Read across all rooms, a
    /// room where the user renamed themselves never hears its own name called.
    ///
    /// Falling back to the all-rooms answer covers the room this account has not
    /// written in yet: there is no name to read there, and the name it uses
    /// everywhere else is the one that room would know it by.
    func accountNickname(chatRoomID: String) -> String? {
        newestNickname(inChat: chatRoomID) ?? accountNickname()
    }

    /// The newest name this account wrote under, in one room or in any of them.
    ///
    /// A blank nickname is no nickname: katok writes one for some rows, and an
    /// empty name would match every message ever sent.
    private func newestNickname(inChat chatRoomID: String?) -> String? {
        let accountHash = accountHash

        let stored = try? database.read { db -> String? in
            guard let chatRoomID else {
                return try String.fetchOne(
                    db,
                    sql: """
                    SELECT sender_nickname
                    FROM messages
                    WHERE account_hash = ? AND sender_id = ?
                    ORDER BY timestamp DESC
                    LIMIT 1
                    """,
                    arguments: [accountHash, accountSenderID]
                )
            }
            // Scoping to a room stays an indexed read: (chat_id, timestamp,
            // message_id) covers the filter and the ordering both, so the room's
            // newest row is found without walking its history.
            return try String.fetchOne(
                db,
                sql: """
                SELECT sender_nickname
                FROM messages
                WHERE account_hash = ? AND sender_id = ? AND chat_id = ?
                ORDER BY timestamp DESC
                LIMIT 1
                """,
                arguments: [accountHash, accountSenderID, chatRoomID]
            )
        }

        return stored
            .flatMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    func chatRooms() throws -> [ChatRoom] {
        // Only `messages` scopes rooms to an account. A renamed room can still
        // have older messages under its previous name.
        let accountHash = accountHash
        return try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT current.chat_id, current.chat_name, current.chat_type
                FROM (SELECT DISTINCT chat_id FROM messages WHERE account_hash = ?) AS room
                JOIN messages AS current ON current.rowid = (
                    SELECT rowid
                    FROM messages
                    WHERE account_hash = ? AND chat_id = room.chat_id
                    ORDER BY timestamp DESC, message_id DESC
                    LIMIT 1
                )
                """,
                arguments: [accountHash, accountHash]
            )
            .compactMap(ChatRoom.init(archiveRow:))
        }
    }

    func recentMessages(chatRoomID: String, limit: Int) throws -> [ChatMessage] {
        let senderID = accountSenderID
        let accountHash = accountHash
        return try database.read { db in
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime]

            // The (chat_id, timestamp, message_id) index covers this ordering, so
            // the newest slice is read without scanning the chat's full history.
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT message_id, chat_id, sender_id, sender_nickname, text, timestamp,
                       message_type, reply_to_message_id
                FROM messages
                WHERE chat_id = ? AND account_hash = ?
                ORDER BY timestamp DESC, message_id DESC
                LIMIT ?
                """,
                arguments: [chatRoomID, accountHash, limit]
            )

            return rows
                .compactMap { ChatMessage(archiveRow: $0, accountSenderID: senderID, parser: parser) }
                .reversed()
        }
    }

    /// Message and chat totals for the connection status screen.
    func archiveSummary() throws -> (messages: Int, chatRooms: Int) {
        try database.read { db in
            let messages = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM messages WHERE account_hash = ?", arguments: [accountHash]
            ) ?? 0
            let chatRooms = try Int.fetchOne(
                db, sql: "SELECT COUNT(DISTINCT chat_id) FROM messages WHERE account_hash = ?", arguments: [accountHash]
            ) ?? 0
            return (messages, chatRooms)
        }
    }
}
