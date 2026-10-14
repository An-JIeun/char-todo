import Foundation
import Observation

private struct MeetingFile: Codable {
    var version = 1
    var meetings: [MeetingNote]
}

/// 회의록 + 회의록으로 만든 지식그래프
@MainActor
@Observable
final class MeetingStore {
    /// 최신 회의가 앞
    private(set) var meetings: [MeetingNote] = []
    private(set) var graph = KnowledgeGraph()
    /// 분석 대기열 (로컬 모델이 버거워하지 않게 한 번에 하나씩)
    private(set) var queue: [UUID] = []
    private(set) var analyzingID: UUID?

    /// 프롬프트 → AI 응답. AppEnvironment가 설정 화면의 AI 공급자로 연결한다.
    @ObservationIgnored var analyzer: (@MainActor (String) async throws -> String)?
    @ObservationIgnored var onAnalyzed: ((MeetingNote) -> Void)?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private let saver = Debouncer(delay: 0.4)
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let fileName = "meetings.json"

    init(persists: Bool = true) {
        self.persists = persists
        if persists, let file = Persistence.load(MeetingFile.self, from: fileName) {
            meetings = file.meetings
            changed(save: false)
        }
    }

    func meeting(id: UUID?) -> MeetingNote? {
        guard let id else { return nil }
        return meetings.first { $0.id == id }
    }

    func isAnalyzing(_ id: UUID) -> Bool { analyzingID == id || queue.contains(id) }

    // MARK: 변경

    @discardableResult
    func add(text: String, title: String, sourceName: String = "", date: Date) -> UUID {
        let note = MeetingNote(title: title.trimmed.isEmpty ? "회의록" : title.trimmed, date: date,
                               sourceName: sourceName, rawText: text)
        meetings.append(note)
        changed()
        return note.id
    }

    func update(_ note: MeetingNote) {
        guard let i = meetings.firstIndex(where: { $0.id == note.id }), meetings[i] != note else { return }
        meetings[i] = note
        changed()
    }

    func mutate(_ id: UUID, _ change: (inout MeetingNote) -> Void) {
        guard var note = meeting(id: id) else { return }
        change(&note)
        update(note)
    }

    func delete(_ id: UUID) {
        queue.removeAll { $0 == id }
        meetings.removeAll { $0.id == id }
        changed()
    }

    func setTodoID(_ todoID: UUID?, meeting: UUID, action: UUID) {
        mutate(meeting) { m in
            guard let i = m.actions.firstIndex(where: { $0.id == action }) else { return }
            m.actions[i].todoID = todoID
        }
    }

    private func changed(save: Bool = true) {
        meetings.sort { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }
        graph = KnowledgeGraph.build(from: meetings)
        if save { persist() }
    }

    // MARK: AI 정리

    func requestAnalysis(_ id: UUID) {
        guard meeting(id: id) != nil, !isAnalyzing(id) else { return }
        mutate(id) { $0.status = .pending; $0.errorMessage = nil }
        queue.append(id)
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, !self.queue.isEmpty {
                let next = self.queue.removeFirst()
                self.analyzingID = next
                await self.analyze(next)
                self.analyzingID = nil
            }
            self?.worker = nil
        }
    }

    func analyze(_ id: UUID) async {
        guard let note = meeting(id: id), let analyzer else { return }
        let prompt = PromptBuilder.meetingPrompt(text: note.rawText, baseDate: note.date)
        do {
            let response = try await analyzer(prompt)
            guard let obj = MeetingParser.jsonObject(from: response) else { throw MeetingImportError.badResponse(response) }
            mutate(id) { m in
                MeetingParser.apply(obj, to: &m)
                m.status = .analyzed
                m.errorMessage = nil
                m.analyzedAt = Date()
            }
            if let done = meeting(id: id) { onAnalyzed?(done) }
        } catch is CancellationError {
            mutate(id) { $0.status = .pending }
        } catch {
            mutate(id) { m in
                m.status = .failed
                m.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: 질문봇용

    func knowledgeContext(for question: String, todoStatus: (UUID) -> Bool?) -> String? {
        MeetingContextBuilder.build(question: question, meetings: meetings, graph: graph, todoStatus: todoStatus)
    }

    // MARK: 저장

    private func persist() {
        guard persists else { return }
        saver.schedule { [weak self] in self?.writeNow() }
    }

    func writeNow() {
        guard persists else { return }
        Persistence.save(MeetingFile(meetings: meetings), to: fileName)
    }
}
