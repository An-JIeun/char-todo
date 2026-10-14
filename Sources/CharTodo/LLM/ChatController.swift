import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    var id = UUID()
    var role: Role
    /// 모델에 보낸/받은 원문
    var text: String
    /// 사용자 버블에 보일 짧은 라벨 (브리핑 버튼 등)
    var label: String?
    var isError = false
    var isStreaming = false
    var date = Date()
    /// 버튼으로 추가한 제안 (제안 인덱스 → 할일 id)
    var addedSuggestions: [Int: UUID] = [:]
    /// 응답과 함께 자동 등록된 할일
    var autoAddedTodoIDs: [UUID] = []

    var displayText: String {
        if role == .user { return label ?? text }
        return PromptBuilder.displayText(text)
    }

    /// 버튼으로 보여 줄 제안 (자동 등록된 것은 제외)
    var suggestions: [TodoSuggestion] {
        guard role == .assistant, !isStreaming else { return [] }
        let all = PromptBuilder.parseSuggestions(text)
        return autoAddedTodoIDs.isEmpty ? all : all.filter { $0.kind == .suggest }
    }
}

/// 플로팅 질문봇의 대화 상태와 LLM 호출을 관리한다.
@MainActor
@Observable
final class ChatController {
    private(set) var messages: [ChatMessage] = []
    private(set) var isBusy = false
    private(set) var awaitingFirstToken = false
    var draft = ""

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private unowned let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    var providerLabel: String {
        let llm = env.settings.settings.llm
        return "\(llm.provider.shortLabel) · \(llm.activeModelLabel)"
    }

    func send(_ raw: String? = nil) {
        let text = (raw ?? draft).trimmed
        guard !text.isEmpty, !isBusy else { return }
        if raw == nil { draft = "" }
        if quickAdd(text) { return }
        messages.append(ChatMessage(role: .user, text: text))
        respond()
    }

    /// `+ 할일` 또는 `/추가 할일` 은 AI 없이 빠른 입력 문법으로 바로 등록한다.
    /// 예: "+ 팀 회의 @내일 ~15:00 #업무 !1 > 안건, 자료"
    private func quickAdd(_ text: String) -> Bool {
        let prefixes = ["+", "/추가", "/add"]
        guard let prefix = prefixes.first(where: { text.hasPrefix($0) }) else { return false }
        let body = String(text.dropFirst(prefix.count)).trimmed
        messages.append(ChatMessage(role: .user, text: text))
        guard let item = QuickAddParser().makeTodo(from: body, defaultDate: Date(), defaultScope: .day) else {
            messages.append(ChatMessage(role: .assistant, text: "추가할 할일 제목을 같이 적어 줘요. 예) + 팀 회의 @내일 ~15:00 #업무", isError: true))
            return true
        }
        env.store.add(item)
        var reply = ChatMessage(role: .assistant, text: "바로 추가했어요 ✅")
        reply.autoAddedTodoIDs = [item.id]
        messages.append(reply)
        return true
    }

    /// 자동 등록된 할일 되돌리기
    func undoAutoAdd(_ todoID: UUID, in messageID: UUID) {
        env.store.delete(todoID)
        update(messageID) { $0.autoAddedTodoIDs.removeAll { $0 == todoID } }
    }

    func briefing(_ kind: BriefingKind) {
        guard !isBusy else { return }
        messages.append(ChatMessage(role: .user, text: kind.prompt, label: "📼 \(kind.label)"))
        respond()
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func clear() {
        stop()
        messages.removeAll()
    }

    /// 제안 버튼 → 등록
    func addSuggestion(at index: Int, in messageID: UUID) {
        guard let m = messages.first(where: { $0.id == messageID }), m.suggestions.indices.contains(index) else { return }
        let id = env.addSuggestion(m.suggestions[index])
        update(messageID) { $0.addedSuggestions[index] = id }
    }

    private func respond() {
        let settings = env.settings.settings
        let client: LLMClient
        do {
            client = try LLMClientFactory.make(settings.llm)
        } catch {
            messages.append(ChatMessage(role: .assistant, text: error.localizedDescription, isError: true))
            env.companion.say("앗, 설정이 필요해요 ⚙️")
            return
        }
        let question = messages.last { $0.role == .user }?.text ?? ""
        let system = PromptBuilder.systemPrompt(name: settings.assistantName, tone: settings.assistantTone,
                                                persona: settings.persona, context: env.assistantContext(),
                                                knowledge: env.meetingKnowledge(for: question))
        let history = messages.filter { !$0.isError }.suffix(14).map {
            LLMMessage(role: $0.role == .user ? .user : .assistant, content: $0.text)
        }
        let reply = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(reply)
        let replyID = reply.id
        isBusy = true
        awaitingFirstToken = true

        task = Task { [weak self] in
            do {
                for try await chunk in client.stream(system: system, messages: Array(history)) {
                    guard let self else { return }
                    self.awaitingFirstToken = false
                    self.update(replyID) { $0.text += chunk }
                }
                self?.finish(replyID, error: nil)
            } catch {
                self?.finish(replyID, error: error)
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[i])
    }

    private func finish(_ id: UUID, error: Error?) {
        isBusy = false
        awaitingFirstToken = false
        task = nil
        update(id) { m in
            m.isStreaming = false
            if let error, !(error is CancellationError) {
                if m.text.trimmed.isEmpty {
                    m.text = error.localizedDescription
                    m.isError = true
                } else {
                    m.text += "\n\n⚠️ \(error.localizedDescription)"
                }
            } else if m.text.trimmed.isEmpty {
                m.text = "(응답이 비어 있어요)"
                m.isError = true
            }
        }
        autoAddRequested(in: id)
        if let m = messages.first(where: { $0.id == id }), !m.isError, !env.floating.isChatVisible {
            let added = m.autoAddedTodoIDs.count
            env.companion.say(added > 0 ? "할일 \(added)개 추가했어요! 📌" : "답변이 도착했어요! 눌러서 보기 💬", duration: 8)
        }
    }

    /// 응답 속 [[ADD …]] 할일을 바로 등록 (설정에서 끌 수 있음)
    private func autoAddRequested(in messageID: UUID) {
        guard env.settings.settings.chatAutoAdd,
              let m = messages.first(where: { $0.id == messageID }), m.role == .assistant, !m.isError else { return }
        let requested = PromptBuilder.parseSuggestions(m.text).filter { $0.kind == .add }
        guard !requested.isEmpty else { return }
        let ids = requested.map { env.addSuggestion($0) }
        update(messageID) { $0.autoAddedTodoIDs = ids }
    }

    /// 말투 미리보기: 실제 대화와 같은 시스템 프롬프트로 한 번 물어본다.
    func personaPreview(_ prompt: String) async throws -> String {
        let s = env.settings.settings
        let system = PromptBuilder.systemPrompt(name: s.assistantName, tone: s.assistantTone,
                                                persona: s.persona, context: env.assistantContext())
        return try await oneShot(prompt, system: system)
    }

    /// 화면 밖 단발 작업 (세부 테스크 쪼개기, 업무일지 초안, 회의록 정리 등)
    /// minTokens: 긴 출력이 필요한 작업이면 설정값보다 크게 잡는다.
    func oneShot(_ prompt: String, system: String = PromptBuilder.utilitySystem, minTokens: Int? = nil) async throws -> String {
        var config = env.settings.settings.llm
        if let minTokens { config.maxTokens = max(config.maxTokens, minTokens) }
        let client = try LLMClientFactory.make(config)
        var out = ""
        for try await chunk in client.stream(system: system, messages: [LLMMessage(role: .user, content: prompt)]) {
            out += chunk
        }
        return out.trimmed
    }
}
