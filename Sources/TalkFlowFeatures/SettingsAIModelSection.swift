import SwiftUI
import TalkFlowDomain

struct SettingsAIModelSection: View {
    let model: SettingsModel

    var body: some View {
        Section {
            SettingHelpRow("모델", help: .aiModel) {
                Picker("모델", selection: selection) {
                    Text(Self.defaultTitle).tag(AIModelChoice.codexDefault)
                    ForEach(model.aiModelOptions) { Text($0.name).tag(AIModelChoice.pinned($0)) }
                }
                .labelsHidden()
                .disabled(!model.hasLoaded || model.isSavingReasoningEffort)
            }

            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("추론 수준", selection: reasoningSelection) {
                Text("Codex CLI 설정 그대로").tag(nil as AIReasoningEffort?)
                ForEach(model.aiModel.reasoningEfforts, id: \.self) { effort in
                    Text(effort.title).tag(Optional(effort))
                }
            }
            .disabled(!model.hasLoaded || model.isSavingReasoningEffort || model.aiModel.reasoningEfforts.isEmpty)
            if model.aiModel.reasoningEfforts.isEmpty {
                Text(model.aiModel == .codexDefault
                     ? "모델을 직접 고르면 지원하는 추론 수준을 선택할 수 있습니다."
                     : "지원 수준을 확인할 수 없는 모델은 Codex CLI 설정을 사용합니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("답장과 채팅방 요약에 적용됩니다. 변경한 값은 다음 호출부터 사용합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            SettingHelpLabel("AI 모델", help: .aiModel)
        }
    }

    private static let defaultTitle = "선택 안 함 (Codex 설정 그대로)"

    private var selection: Binding<AIModelChoice> {
        Binding(get: { model.aiModel }, set: { model.setAIModel($0) })
    }

    private var reasoningSelection: Binding<AIReasoningEffort?> {
        Binding(get: { model.aiReasoningEffort }, set: { effort in
            Task { await model.setAIReasoningEffort(effort) }
        })
    }

    private var detail: String {
        switch model.aiModel {
        case .codexDefault:
            // Deliberately does not claim to know which model that is. TalkFlow
            // does not read that file, and a screen guessing at its contents
            // would be wrong the first time somebody edited it.
            return """
            지금은 TalkFlow가 모델을 지정하지 않고, Codex CLI가 설정된 모델을 씁니다. \
            터미널에서 다른 작업 때문에 Codex 설정을 바꾸면 답장 품질도 함께 바뀝니다.
            """
        case let .pinned(model):
            return "\(model.summary) (\(model.id))"
        }
    }
}

private extension AIReasoningEffort {
    var title: String {
        switch self {
        case .low: "낮음"
        case .medium: "보통"
        case .high: "높음"
        case .xhigh: "매우 높음"
        case .max: "최대"
        case .ultra: "울트라"
        }
    }
}
