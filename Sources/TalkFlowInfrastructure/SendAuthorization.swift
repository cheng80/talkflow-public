import TalkFlowDomain

/// Rechecks permission at each delivery attempt, including katok retries.
public struct SendAuthorization: Sendable {
    private let usePolicyAccepted: @Sendable () async -> Bool
    private let automaticResponsesEnabled: @Sendable () async -> Bool

    public init(
        usePolicyAccepted: @escaping @Sendable () async -> Bool,
        automaticResponsesEnabled: @escaping @Sendable () async -> Bool
    ) {
        self.usePolicyAccepted = usePolicyAccepted
        self.automaticResponsesEnabled = automaticResponsesEnabled
    }

    func check(_ origin: SendOrigin) async throws {
        guard await usePolicyAccepted() else {
            throw MessageSendFailure(message: "전송 이용 정책에 동의해야 전송할 수 있습니다.", isRetryable: false)
        }
        if origin == .automatic, !(await automaticResponsesEnabled()) {
            throw MessageSendFailure(message: "자동 응답이 일시 중지되어 있습니다.", isRetryable: false)
        }
    }
}
