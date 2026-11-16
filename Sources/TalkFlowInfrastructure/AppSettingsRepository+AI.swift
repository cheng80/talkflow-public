import Foundation
import GRDB
import TalkFlowDomain

extension AppSettingsRepository {
    enum AISettingsError: LocalizedError {
        case unsupportedReasoningEffort

        var errorDescription: String? {
            "선택한 모델이 지원하지 않는 추론 수준입니다."
        }
    }

    public func aiRequestSettings() async throws -> AIRequestSettings {
        try await database.queue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT ai_model, effort
                FROM app_settings
                LEFT JOIN ai_reasoning_efforts ON model_id = ai_model
                WHERE id = 1
                """) else { return .codexDefault }
            return AIRequestSettings(
                model: AIModelChoice(modelID: row["ai_model"]),
                reasoningEffort: (row["effort"] as String?).flatMap(AIReasoningEffort.init(rawValue:))
            )
        }
    }

    public func aiReasoningEfforts() async throws -> [String: AIReasoningEffort] {
        try await database.queue.read { db in
            var choices: [String: AIReasoningEffort] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT model_id, effort FROM ai_reasoning_efforts") {
                let id: String = row["model_id"]
                choices[id] = AIReasoningEffort(rawValue: row["effort"])
            }
            return choices
        }
    }

    public func setAIReasoningEffort(_ effort: AIReasoningEffort?, forModelID modelID: String) async throws {
        if let effort, !AIModel.named(modelID).reasoningEfforts.contains(effort) {
            throw AISettingsError.unsupportedReasoningEffort
        }
        try await database.queue.write { db in
            if let effort {
                try db.execute(
                    sql: """
                    INSERT INTO ai_reasoning_efforts (model_id, effort) VALUES (?, ?)
                    ON CONFLICT (model_id) DO UPDATE SET effort = excluded.effort
                    """,
                    arguments: [modelID, effort.rawValue]
                )
            } else {
                try db.execute(sql: "DELETE FROM ai_reasoning_efforts WHERE model_id = ?", arguments: [modelID])
            }
        }
    }
}
