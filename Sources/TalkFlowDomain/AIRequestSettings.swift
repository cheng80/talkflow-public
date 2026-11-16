public enum AIReasoningEffort: String, Sendable {
    case low, medium, high, xhigh, max, ultra
}

/// Only an explicit choice supported by the pinned model overrides Codex.
public struct AIRequestSettings: Equatable, Sendable {
    public let model: AIModelChoice
    public let reasoningEffort: AIReasoningEffort?

    public init(model: AIModelChoice, reasoningEffort: AIReasoningEffort? = nil) {
        self.model = model
        self.reasoningEffort = reasoningEffort.flatMap { model.reasoningEfforts.contains($0) ? $0 : nil }
    }

    public static let codexDefault = Self(model: .codexDefault)
}
