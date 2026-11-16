import Foundation

/// One model TalkFlow can ask Codex for.
///
/// `id` is exactly what `codex exec -m` takes and is passed through as typed
/// here. The other two are for the screen, and are the CLI's own words rather
/// than ours: whether a model is the fast one or the frontier one is the
/// provider's claim to make, not TalkFlow's.
public struct AIModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// One line. The picker is scanned, not studied.
    public let summary: String
    public let reasoningEfforts: [AIReasoningEffort]

    public init(id: String, name: String, summary: String, reasoningEfforts: [AIReasoningEffort] = []) {
        self.id = id
        self.name = name
        self.summary = summary
        self.reasoningEfforts = reasoningEfforts
    }
}

public extension AIModel {
    private static let standardReasoning: [AIReasoningEffort] = [.low, .medium, .high, .xhigh, .max]
    private static let reasoningWithUltra = standardReasoning + [.ultra]

    /// Models that returned valid output using TalkFlow's reply schema.
    /// Keep saved choices outside this list visible through `named(_:)`.
    static let catalog: [AIModel] = [
        AIModel(
            id: "gpt-6-astra",
            name: "GPT-6 Astra",
            summary: "복잡한 요청을 처리하는 최상위 모델입니다.",
            reasoningEfforts: reasoningWithUltra
        ),
        AIModel(
            id: "gpt-6.1-sol",
            name: "GPT-6.1 Sol",
            summary: "복잡한 작업에서 품질과 사용량의 균형을 맞춘 모델입니다.",
            reasoningEfforts: reasoningWithUltra
        ),
        AIModel(
            id: "gpt-6.1-terra",
            name: "GPT-6.1 Terra",
            summary: "글쓰기와 이미지 이해에 적합한 빠른 모델입니다.",
            reasoningEfforts: reasoningWithUltra
        ),
        AIModel(
            id: "gpt-6-sol",
            name: "GPT-6 Sol",
            summary: "6.1 이전의 범용 Sol 모델입니다.",
            reasoningEfforts: reasoningWithUltra
        ),
        AIModel(
            id: "gpt-6-luna",
            name: "GPT-6 Luna",
            summary: "짧은 답변이나 반복 작업의 사용량을 줄이는 모델입니다.",
            reasoningEfforts: standardReasoning
        )
    ]

    /// The catalog entry for an id, or one that names itself.
    ///
    /// A stored id can outlive the list — the provider retires a name, or the
    /// user downgrades TalkFlow after picking something newer. Dropping it would
    /// change which model answers without saying so, and leaving the picker with
    /// nothing selected would have the screen show a blank where the user's own
    /// choice is. So an unrecognised id becomes an option whose name is the id,
    /// which is the one thing about it that is certainly true.
    static func named(_ id: String) -> AIModel {
        catalog.first { $0.id == id }
            ?? AIModel(
                id: id,
                name: id,
                summary: "이 버전의 TalkFlow가 아는 목록에는 없는 모델입니다."
            )
    }
}

/// Which model TalkFlow asks for, including the answer "don't ask".
///
/// `codexDefault` is the default and passes no `-m` at all, so the model is
/// whatever `~/.codex/config.toml` says — which is what every install did before
/// this setting existed. Nobody's replies change by upgrading.
///
/// The cost of that default is worth naming where the setting is: the file it
/// defers to belongs to Codex CLI and not to TalkFlow, so editing it for some
/// unrelated project quietly changes what answers in KakaoTalk.
public enum AIModelChoice: Hashable, Sendable {
    case codexDefault
    case pinned(AIModel)

    public var reasoningEfforts: [AIReasoningEffort] {
        guard case let .pinned(model) = self else { return [] }
        return model.reasoningEfforts
    }

    /// The value `-m` should be given, or nil when the flag must be left off.
    /// Also what gets stored: the choice is one nullable column, not a column
    /// plus a flag that could disagree with it.
    public var modelID: String? {
        switch self {
        case .codexDefault: nil
        case let .pinned(model): model.id
        }
    }

    /// Blank reads as unchosen, not as a model with an empty name. A column that
    /// once held `''` — an older write, a hand-edited row — would otherwise send
    /// `-m ''` and fail every call.
    public init(modelID: String?) {
        guard let modelID, !modelID.trimmingCharacters(in: .whitespaces).isEmpty else {
            self = .codexDefault
            return
        }
        self = .pinned(.named(modelID))
    }
}
