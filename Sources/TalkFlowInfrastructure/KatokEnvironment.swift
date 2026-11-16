import CryptoKit
import Foundation
import TalkFlowDomain

/// Locates katok's on-disk state and derives TalkFlow's account identity from it.
///
/// katok owns its directory. TalkFlow stores the verified account in its own
/// local cache and exposes a hashed fingerprint to the application.
struct KatokEnvironment: Sendable {
    struct AccountIdentity: Sendable {
        /// The sender id KakaoTalk stamps on messages this account sent.
        let senderID: String
        let archiveHash: String
        var fingerprint: String { "katok-\(archiveHash)" }
    }

    let dataDirectoryURL: URL
    private let containerURL: URL
    private let accountStore: KakaoAccountStore

    init(
        dataDirectoryURL: URL = KatokEnvironment.defaultDataDirectoryURL(),
        containerURL: URL = KatokEnvironment.kakaoContainerURL(),
        accountStore: KakaoAccountStore = KakaoAccountStore()
    ) {
        self.dataDirectoryURL = dataDirectoryURL
        self.containerURL = containerURL
        self.accountStore = accountStore
    }

    var archiveURL: URL {
        dataDirectoryURL.appending(path: "archive.sqlite3")
    }

    var authCacheURL: URL {
        dataDirectoryURL.appending(path: "kakao/auth.json")
    }

    func accountIdentity() -> AccountIdentity? {
        let resolver = KakaoAccountResolver(environment: self)
        guard let live = resolver.liveDatabaseName() else { return nil }
        let storeRecord = accountStore.stored()
        let userID: Int
        if let storeRecord, storeRecord.databaseName == live {
            userID = storeRecord.userID
        } else {
            let cache = (try? Data(contentsOf: authCacheURL))
                .flatMap { try? JSONDecoder().decode(AuthCache.self, from: $0) }
            let candidates = [storeRecord?.userID ?? accountStore.storedUserID(), cache?.userID]
                .compactMap { $0 }
            guard let verified = resolver.resolve(candidates: candidates, liveDatabaseName: live) else { return nil }
            userID = verified
            try? accountStore.save(userID: userID, databaseName: live)
        }
        let senderID = String(userID)
        // katok uses SHA-256 of the decimal account ID as its archive key.
        let hash = SHA256.hash(data: Data(senderID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return AccountIdentity(senderID: senderID, archiveHash: hash)
    }

    func accountProfile() -> AccountProfile? {
        guard let identity = accountIdentity() else { return nil }
        return AccountProfile(label: "카카오톡", fingerprint: identity.fingerprint)
    }

    /// KakaoTalk names each signed-in account's database after that account, so
    /// more than one file means more than one account has been used on this Mac.
    /// The connector derives a single name and cannot be told which to read, so
    /// this is how TalkFlow notices it may be reading the wrong one.
    func kakaoDatabases(
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> [(url: URL, modifiedAt: Date)] {
        let container = containerURL ?? self.containerURL
        let urls = (try? fileManager.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            let name = url.lastPathComponent
            guard name.count == 78, name.allSatisfy(\.isHexDigit) else { return nil }
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            else {
                return nil
            }
            return (url, modified)
        }
    }

    func katokProcessEnvironment() -> [String: String] {
        guard let identity = accountIdentity() else { return [:] }
        return ["KATOK_KAKAO_USER_ID": identity.senderID]
    }

    /// The device uuid the database name is derived from. Cached by the
    /// connector alongside the account id; unlike the account id it does not
    /// change when someone signs into a different account.
    func deviceUUID() -> String? {
        guard let data = try? Data(contentsOf: authCacheURL),
              let cache = try? JSONDecoder().decode(DeviceCache.self, from: data)
        else {
            return nil
        }
        return cache.uuid
    }

    static func kakaoContainerURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.kakao.KakaoTalkMac/Data/Library/Application Support/com.kakao.KakaoTalkMac")
    }

    static func defaultDataDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/katok")
    }
}

/// katok writes the account identifier it recovered from KakaoTalk here so that
/// later runs do not have to redo the recovery.
private struct DeviceCache: Decodable {
    let uuid: String
}

private struct AuthCache: Decodable {
    let userID: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}
