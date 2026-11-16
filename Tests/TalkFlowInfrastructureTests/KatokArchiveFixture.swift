import CryptoKit
import Foundation
import GRDB
@testable import TalkFlowInfrastructure

/// Builds a throwaway katok data directory that mirrors the real archive schema.
///
/// Tests never touch the user's own archive: it holds real conversations, and a
/// fixture is the only way to assert on specific rows.
struct KatokArchiveFixture {
    static let ownID = "1000000000000000001"
    static let otherID = "1000000000000000002"
    private static let deviceUUID = "00000000-0000-4000-8000-000000000001"

    /// One archived row. A struct rather than the tuple this used to be: at
    /// eight fields the type stopped fitting in the signature that took it.
    struct ArchivedMessage {
        let id: String
        let chatID: String
        let senderID: String
        let nickname: String
        let text: String
        let timestamp: String
        let type: String
        /// The message this row answers, as KakaoTalk records a 답장. Null on
        /// almost every row in the real archive.
        let replyTo: String?
    }

    let directoryURL: URL
    let containerURL: URL
    let databaseURL: URL

    var environment: KatokEnvironment {
        KatokEnvironment(
            dataDirectoryURL: directoryURL,
            containerURL: containerURL,
            accountStore: KakaoAccountStore(fileURL: directoryURL.appending(path: "resolved-account.json"))
        )
    }

    init() throws {
        directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "talkflow-fixture-\(UUID().uuidString)")
        containerURL = directoryURL.appending(path: "container")
        databaseURL = containerURL.appending(
            path: KakaoKeyDerivation.databaseName(userID: 1_000_000_000_000_000_001, deviceUUID: Self.deviceUUID)
        )
        try FileManager.default.createDirectory(
            at: directoryURL.appending(path: "kakao"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        try Data().write(to: databaseURL)
        let authCache = ["user_id": 1_000_000_000_000_000_001, "uuid": Self.deviceUUID] as [String: Any]
        try JSONSerialization
            .data(withJSONObject: authCache)
            .write(to: directoryURL.appending(path: "kakao/auth.json"))
    }

    func destroy() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func createArchive(
        chats: [(id: String, name: String, type: String)],
        messages: [ArchivedMessage],
        otherAccountMessages: [ArchivedMessage] = []
    ) throws {
        let database = try DatabaseQueue(path: environment.archiveURL.path)
        try database.write { db in
            try db.execute(sql: """
            CREATE TABLE chats (
                chat_id TEXT PRIMARY KEY,
                chat_name TEXT NOT NULL,
                chat_type TEXT NOT NULL
            )
            """)
            try db.execute(sql: """
            CREATE TABLE messages (
                account_hash TEXT NOT NULL,
                chat_id TEXT NOT NULL,
                chat_name TEXT NOT NULL,
                chat_type TEXT NOT NULL,
                message_id TEXT NOT NULL,
                sender_id TEXT NOT NULL,
                sender_nickname TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                text TEXT NOT NULL,
                message_type TEXT NOT NULL,
                reply_to_message_id TEXT,
                PRIMARY KEY(account_hash, chat_id, message_id)
            )
            """)

            for chat in chats {
                try db.execute(
                    sql: "INSERT INTO chats VALUES (?, ?, ?)",
                    arguments: [chat.id, chat.name, chat.type]
                )
            }
            let rows = [(Self.ownID, messages), (Self.otherID, otherAccountMessages)]
            for (accountID, messages) in rows {
                let accountHash = SHA256.hash(data: Data(accountID.utf8))
                    .map { String(format: "%02x", $0) }.joined()
                for message in messages {
                    // `chats` has no account column, so the reader uses these rows.
                    let chatType = chats.first { $0.id == message.chatID }?.type ?? "direct"
                    try db.execute(
                        sql: "INSERT INTO messages VALUES (?, ?, 'room', ?, ?, ?, ?, ?, ?, ?, ?)",
                        arguments: [
                            accountHash,
                            message.chatID,
                            chatType,
                            message.id,
                            message.senderID,
                            message.nickname,
                            message.timestamp,
                            message.text,
                            message.type,
                            message.replyTo
                        ]
                    )
                }
            }
        }
    }
}
