import Foundation

/// Works out which KakaoTalk account is actually signed in.
///
/// KakaoTalk keeps one database per account, named after `(user_id, device
/// uuid)`. Signing into a different account creates a new file and leaves the
/// old one in place, and the connector — which derives a single name from a
/// cached id — keeps reading the account that was signed out.
///
/// So the live account is identified the other way round: find the database
/// KakaoTalk is actually writing, then find which candidate id derives that
/// name. An id that derives nothing on disk is not the signed-in account, no
/// matter which cache it came from.
struct KakaoAccountResolver: Sendable {
    private let environment: KatokEnvironment

    init(environment: KatokEnvironment = KatokEnvironment()) {
        self.environment = environment
    }

    /// The database KakaoTalk has written most recently. Nothing else on disk
    /// distinguishes a live account from one that was signed out months ago.
    func liveDatabaseName() -> String? {
        let databases = environment.kakaoDatabases()
        guard let newest = databases.max(by: { $0.modifiedAt < $1.modifiedAt }),
              databases.filter({ $0.modifiedAt == newest.modifiedAt }).count == 1
        else { return nil }
        return newest.url.lastPathComponent
    }

    /// Tries every id TalkFlow knows about and returns the one that derives the
    /// live database. Deriving a name costs a PBKDF2 pass, so callers should
    /// remember the answer rather than resolving on every read.
    func resolve(candidates: [Int], liveDatabaseName: String) -> Int? {
        guard let deviceUUID = environment.deviceUUID() else { return nil }
        return candidates.first {
            KakaoKeyDerivation.databaseName(userID: $0, deviceUUID: deviceUUID) == liveDatabaseName
        }
    }
}
