import Foundation
import GRDB
import Testing
import TalkFlowDomain
@testable import TalkFlowInfrastructure

@Test
func upgradingAnExistingModelKeepsCodexDefaultsUntilAnEffortIsChosen() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "settings.sqlite")
    let old = try DatabaseQueue(path: url.path)
    try TalkFlowDatabase.migrator.migrate(old, upTo: "v31-admin-rooms")
    try await old.write { db in
        try db.execute(sql: """
            INSERT INTO app_settings (id, responses_enabled, launches_at_login, ai_model)
            VALUES (1, 0, 0, 'gpt-6-luna')
            """)
    }

    let database = try TalkFlowDatabase(fileURL: url)
    let settings = AppSettingsRepository(database: database)
    let luna = AIModelChoice.pinned(.named("gpt-6-luna"))
    #expect(try await settings.aiRequestSettings() == AIRequestSettings(model: luna))

    try await settings.setAIReasoningEffort(.high, forModelID: "gpt-6-luna")
    await #expect(throws: AppSettingsRepository.AISettingsError.self) {
        try await settings.setAIReasoningEffort(.ultra, forModelID: "gpt-6-luna")
    }
    #expect(try await settings.aiRequestSettings() == AIRequestSettings(model: luna, reasoningEffort: .high))
    try await settings.setAIModel(.codexDefault)
    #expect(try await settings.aiRequestSettings() == .codexDefault)
    try await settings.setAIModel(luna)
    #expect(try await settings.aiRequestSettings().reasoningEffort == .high)
    try await settings.setAIReasoningEffort(nil, forModelID: "gpt-6-luna")
    #expect(try await settings.aiRequestSettings() == AIRequestSettings(model: luna))
}

@Test
func theNextDraftReadsTheSavedEffortAndPassesItToTheCLI() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cli = directory.appending(path: "codex")
    try #"""
        #!/bin/sh
        [ "$1" = exec ] || exit 2
        shift
        reply="기본 설정"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --model) [ "$2" = gpt-6-luna ] || exit 3; shift ;;
            --config) [ "$2" = model_reasoning_effort=high ] || exit 4; reply="높음 설정"; shift ;;
            --output-last-message) output="$2"; shift ;;
          esac
          shift
        done
        cat >/dev/null
        printf '{"should_reply":true,"reply_mode":"spontaneous","confidence":"high","reply_text":"%s"}' "$reply" > "$output"
        """#.write(to: cli, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)

    let settings = AppSettingsRepository(database: try TalkFlowDatabase(fileURL: directory.appending(path: "settings.sqlite")))
    try await settings.setAIModel(.pinned(.named("gpt-6-luna")))
    let generator = CodexReplyGenerator(executableURL: cli) {
        (try? await settings.aiRequestSettings()) ?? .codexDefault
    }
    let request = ReplyDraftRequest(
        room: ChatRoom(id: "room-1", displayName: "산책 모임", kind: .direct),
        intent: .openConversation,
        trigger: .spontaneous,
        triggerMessageID: "synthetic-test",
        recentMessages: [],
        style: ResponseStyle(),
        answeringCondition: .empty,
        openerHint: "민준에게 산책을 제안하세요."
    )

    #expect(try await generator.generateReply(request).usableText == "기본 설정")
    try await settings.setAIReasoningEffort(.high, forModelID: "gpt-6-luna")
    #expect(try await generator.generateReply(request).usableText == "높음 설정")
}
