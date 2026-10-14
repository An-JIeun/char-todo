import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 회의록: 파일 넣기 → AI 정리(안건·결정·할일) → 지식그래프 → 질문봇
struct MeetingsView: View {
    enum Mode: String, CaseIterable {
        case notes, graph
        var label: String { self == .notes ? "회의록" : "지식그래프" }
    }

    @Environment(\.theme) private var theme
    @Environment(MeetingStore.self) private var meetings

    @State private var selectedID: UUID?
    @State private var mode: Mode = .notes
    @State private var focusNodeID: String?
    @State private var showPaste = false
    @State private var dropTargeted = false
    @State private var importMessage: String?
    @State private var search = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 14) {
                importCard
                meetingList
            }
            .frame(width: 270)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(mode == .notes ? "회의록" : "업무 지식그래프").font(theme.titleFont(24)).foregroundStyle(theme.text)
                    Spacer()
                    RetroSegmented(options: Mode.allCases, selection: $mode) { $0.label }
                        .frame(width: 220)
                }
                switch mode {
                case .notes:
                    if let m = meetings.meeting(id: selectedID) ?? meetings.meetings.first {
                        MeetingDetailView(meetingID: m.id) { nodeID in
                            focusNodeID = nodeID
                            mode = .graph
                        }
                        .id(m.id)
                    } else {
                        emptyState
                    }
                case .graph:
                    KnowledgeGraphView(selectedNodeID: $focusNodeID) { id in
                        selectedID = id
                        mode = .notes
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .dropDestination(for: URL.self) { urls, _ in
            importFiles(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .sheet(isPresented: $showPaste) {
            PasteMeetingSheet { title, text, date in
                let id = meetings.add(text: text, title: title, date: date)
                selectedID = id
                mode = .notes
                meetings.requestAnalysis(id)
            }
        }
    }

    // MARK: 넣기

    private var importCard: some View {
        RetroWindow("회의록 넣기", symbol: "tray.and.arrow.down.fill") {
            VStack(spacing: 8) {
                VStack(spacing: 4) {
                    Image(systemName: "doc.text.fill").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(dropTargeted ? theme.accent : theme.textMuted)
                    Text("여기로 .txt · .md 파일을 끌어다 놓기").font(theme.font(11.5, .bold))
                    Text("AI가 안건 · 결정 · 할일을 정리해요").font(theme.font(10.5)).foregroundStyle(theme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 6).fill(dropTargeted ? theme.accent.opacity(0.12) : .clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(dropTargeted ? theme.accent : theme.border.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
                HStack(spacing: 6) {
                    Button { openFiles() } label: { Label("파일 열기", systemImage: "folder") }
                        .buttonStyle(.retro(.primary, compact: true))
                    Button { showPaste = true } label: { Label("붙여넣기", systemImage: "doc.on.clipboard") }
                        .buttonStyle(.retro(.secondary, compact: true))
                }
                if let importMessage {
                    Text(importMessage).font(theme.font(10.5)).foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
        }
    }

    private var meetingList: some View {
        let q = search.trimmed.lowercased()
        let list = meetings.meetings.filter { m in
            q.isEmpty || m.title.lowercased().contains(q) || m.rawText.lowercased().contains(q)
                || m.participants.contains { $0.lowercased().contains(q) }
        }
        let current = (meetings.meeting(id: selectedID) ?? meetings.meetings.first)?.id
        return RetroWindow("회의록 \(meetings.meetings.count)", symbol: "list.bullet.rectangle.portrait") {
            EmptyView()
        } content: {
            VStack(spacing: 6) {
                TextField("제목 · 내용 · 참석자 검색", text: $search).retroField()
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if list.isEmpty { EmptyHint(text: meetings.meetings.isEmpty ? "아직 회의록이 없어요" : "검색 결과가 없어요") }
                        ForEach(list) { m in
                            Button {
                                selectedID = m.id
                                mode = .notes
                            } label: {
                                row(m, selected: m.id == current && mode == .notes)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func row(_ m: MeetingNote, selected: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(spacing: 0) {
                Text(DateFormatters.monthDay.string(from: m.date)).font(theme.font(11, .heavy))
                Text(DateFormatters.weekdayShort.string(from: m.date)).font(theme.font(9, .bold)).foregroundStyle(theme.textMuted)
            }
            .frame(width: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title).font(theme.font(12, .bold)).lineLimit(1)
                statusLine(m)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 4).fill(selected ? theme.accent.opacity(0.15) : .clear))
        .contentShape(Rectangle())
    }

    @ViewBuilder private func statusLine(_ m: MeetingNote) -> some View {
        Group {
            if meetings.isAnalyzing(m.id) {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(meetings.analyzingID == m.id ? "AI 정리 중…" : "정리 대기")
                }
            } else {
                switch m.status {
                case .failed: Text("정리 실패 — 다시 시도해 주세요").foregroundStyle(.red)
                case .pending: Text("정리 전")
                case .analyzed: Text(m.countsLabel.isEmpty ? "정리 완료" : m.countsLabel)
                }
            }
        }
        .font(theme.font(10.5))
        .foregroundStyle(theme.textMuted)
        .lineLimit(1)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("이렇게 쓰면 돼요", symbol: "sparkles")
            ForEach(Array([
                ("1", "회의록 넣기", "왼쪽에 .txt · .md 파일을 끌어다 놓거나 붙여 넣어요. 여러 개도 한 번에 돼요."),
                ("2", "AI가 정리", "요약 · 안건 · 결정사항 · 할일 · 등장한 프로젝트/사람을 뽑아요. 할일은 버튼 하나로 앱 할일이 돼요."),
                ("3", "지식그래프", "같은 프로젝트·사람·시스템이 나온 회의끼리 이어져요. '지식그래프' 탭에서 볼 수 있어요."),
                ("4", "질문하기", "질문봇(⌘J)에게 \"지난달 결제 개편 회의에서 뭐 정했지?\"처럼 물으면 회의록을 근거로 답해요."),
            ].enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: 10) {
                    Text(step.0).font(theme.font(13, .heavy))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(theme.highlight))
                        .overlay(Circle().strokeBorder(theme.border, lineWidth: 1.5))
                        .foregroundStyle(Color.black.opacity(0.85))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.1).font(theme.font(13, .bold))
                        Text(step.2).font(theme.font(12)).foregroundStyle(theme.textMuted)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroCard()
    }

    // MARK: 동작

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.plainText] + ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }
        panel.message = "회의록 파일(.txt, .md)을 고르세요"
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    private func importFiles(_ urls: [URL]) {
        var added: [UUID] = [], problems: [String] = []
        for url in urls {
            guard MeetingParser.supportedExtensions.contains(url.pathExtension.lowercased()) else {
                problems.append("\(url.lastPathComponent): .txt · .md 파일만 넣을 수 있어요")
                continue
            }
            do {
                let text = try MeetingParser.readText(at: url)
                if meetings.meetings.contains(where: { $0.rawText == text }) {
                    problems.append("\(url.lastPathComponent): 이미 넣은 회의록이에요")
                    continue
                }
                let name = url.deletingPathExtension().lastPathComponent
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let date = MeetingParser.date(fromFileName: name) ?? modified ?? Date()
                added.append(meetings.add(text: text, title: name, sourceName: url.lastPathComponent, date: date))
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        for id in added { meetings.requestAnalysis(id) }
        if let first = added.first {
            selectedID = first
            mode = .notes
        }
        var lines: [String] = []
        if !added.isEmpty { lines.append("\(added.count)개 가져왔어요. AI가 차례로 정리해요 ✍️") }
        lines += problems
        importMessage = lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

// MARK: - 상세

struct MeetingDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(MeetingStore.self) private var meetings
    @Environment(TodoStore.self) private var todos
    let meetingID: UUID
    /// 개체 칩을 누르면 지식그래프에서 그 노드를 연다
    var onShowNode: (String) -> Void

    @State private var showRaw = false
    @State private var confirmDelete = false
    @State private var copied = false

    var body: some View {
        if let m = meetings.meeting(id: meetingID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(m)
                    status(m)
                    if !m.summary.trimmed.isEmpty {
                        card("요약", symbol: "text.alignleft") {
                            Text(m.summary).font(theme.font(13)).textSelection(.enabled)
                        }
                    }
                    if !m.topics.isEmpty { topics(m) }
                    if !m.decisions.isEmpty { decisions(m) }
                    if !m.actions.isEmpty { actions(m) }
                    if !m.entities.isEmpty { entities(m) }
                    raw(m)
                }
                .padding(.bottom, 20)
            }
            .confirmationDialog("이 회의록을 삭제할까요?", isPresented: $confirmDelete) {
                Button("삭제", role: .destructive) { meetings.delete(m.id) }
            } message: {
                Text("앱 할일로 등록한 항목은 그대로 남아요.")
            }
        }
    }

    private func header(_ m: MeetingNote) -> some View {
        HStack(alignment: .top, spacing: 14) {
            TearOffCalendar(date: m.date, size: 66)
            VStack(alignment: .leading, spacing: 6) {
                TextField("회의 제목", text: Binding(
                    get: { meetings.meeting(id: meetingID)?.title ?? "" },
                    set: { new in meetings.mutate(meetingID) { $0.title = new } }
                ))
                .textFieldStyle(.plain)
                .font(theme.titleFont(22))
                HStack(spacing: 8) {
                    DatePicker("", selection: Binding(
                        get: { meetings.meeting(id: meetingID)?.date ?? Date() },
                        set: { new in meetings.mutate(meetingID) { $0.date = new.startOfDay } }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .fixedSize()
                    if !m.sourceName.isEmpty { Chip(text: m.sourceName, symbol: "doc.text") }
                }
                if !m.participants.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(m.participants, id: \.self) { p in
                            Button { onShowNode(KnowledgeGraph.entityID(p)) } label: {
                                Chip(text: p, symbol: "person.fill", color: Color(hex: KGNodeKind.person.hex))
                            }
                            .buttonStyle(.plain)
                            .help("지식그래프에서 보기")
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button { AppEnvironment.shared.askAboutMeeting(m.id) } label: {
                    Label("질문봇에게 묻기", systemImage: "bubble.left.and.text.bubble.right.fill")
                }
                .buttonStyle(.retro(.accent2, compact: true))
                HStack(spacing: 6) {
                    Button { meetings.requestAnalysis(m.id) } label: {
                        Label(m.status == .analyzed ? "다시 정리" : "AI 정리", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.retro(.secondary, compact: true))
                    .disabled(meetings.isAnalyzing(m.id))
                    Button { copyMarkdown(m) } label: {
                        Label(copied ? "복사됨!" : "마크다운", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.retro(.secondary, compact: true))
                    Button { confirmDelete = true } label: { Image(systemName: "trash") }
                        .buttonStyle(.retro(.danger, compact: true))
                        .help("회의록 삭제")
                }
            }
        }
    }

    @ViewBuilder private func status(_ m: MeetingNote) -> some View {
        if meetings.isAnalyzing(m.id) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meetings.analyzingID == m.id ? "AI가 회의록을 정리하고 있어요…" : "정리 대기 중 (앞 회의록이 끝나면 시작해요)")
                        .font(theme.font(13, .bold))
                    Text("로컬 모델은 1~2분 걸릴 수 있어요. 다른 화면에 가 있어도 계속 진행돼요.")
                        .font(theme.font(11.5)).foregroundStyle(theme.textMuted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .retroCard(fill: theme.surfaceAlt)
        } else if m.status == .failed {
            VStack(alignment: .leading, spacing: 8) {
                Label("정리하지 못했어요", systemImage: "exclamationmark.triangle.fill")
                    .font(theme.font(13, .bold)).foregroundStyle(.red)
                Text(m.errorMessage ?? "").font(theme.font(11.5)).foregroundStyle(theme.textMuted).textSelection(.enabled)
                HStack(spacing: 6) {
                    Button { meetings.requestAnalysis(m.id) } label: { Label("다시 시도", systemImage: "arrow.clockwise") }
                        .buttonStyle(.retro(.primary, compact: true))
                    Button { AppEnvironment.shared.openSettings(tab: "ai") } label: { Label("AI 설정", systemImage: "gearshape") }
                        .buttonStyle(.retro(.secondary, compact: true))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .retroCard()
        } else if m.status == .pending {
            HStack(spacing: 10) {
                Text("아직 AI로 정리하지 않은 회의록이에요. 원문은 지금도 질문봇이 참고해요.")
                    .font(theme.font(12.5)).foregroundStyle(theme.textMuted)
                Spacer()
                Button { meetings.requestAnalysis(m.id) } label: { Label("AI 정리", systemImage: "wand.and.stars") }
                    .buttonStyle(.retro(.primary, compact: true))
            }
            .padding(14)
            .retroCard()
        }
    }

    private func topics(_ m: MeetingNote) -> some View {
        card("안건", symbol: "text.bubble.fill", count: m.topics.count) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(m.topics) { t in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.title).font(theme.font(13.5, .heavy))
                        ForEach(Array(t.points.enumerated()), id: \.offset) { _, p in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("–").foregroundStyle(theme.textMuted)
                                Text(p).font(theme.font(12.5))
                            }
                            .padding(.leading, 6)
                        }
                    }
                    .textSelection(.enabled)
                }
            }
        }
    }

    private func decisions(_ m: MeetingNote) -> some View {
        card("결정사항", symbol: "checkmark.seal.fill", count: m.decisions.count) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(m.decisions.enumerated()), id: \.offset) { _, d in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 11))
                            .foregroundStyle(Color(hex: KGNodeKind.decision.hex) ?? theme.accent2)
                        Text(d).font(theme.font(13))
                    }
                    .textSelection(.enabled)
                }
            }
        }
    }

    private func actions(_ m: MeetingNote) -> some View {
        let unregistered = m.actions.filter { a in a.todoID.flatMap { todos.todo(id: $0) } == nil }
        return card("할일", symbol: "checklist", count: m.actions.count) {
            Button { AppEnvironment.shared.addMeetingActions(m.id) } label: {
                Label("모두 할일로 (\(unregistered.count))", systemImage: "plus.circle")
            }
            .buttonStyle(.retro(.primary, compact: true))
            .disabled(unregistered.isEmpty)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(m.actions) { a in actionRow(m, a) }
                Text("등록하면 #회의 태그와 회의 이름이 메모로 붙어요. 기한이 없으면 오늘 할일로 들어가요.")
                    .font(theme.font(10.5)).foregroundStyle(theme.textMuted)
            }
        }
    }

    private func actionRow(_ m: MeetingNote, _ a: MeetingAction) -> some View {
        let todo = a.todoID.flatMap { todos.todo(id: $0) }
        return HStack(spacing: 8) {
            if let todo {
                RetroCheckbox(isOn: todo.isDone, size: 16) { todos.toggle(todo.id) }
            } else {
                Image(systemName: "circle.dashed").foregroundStyle(theme.textMuted).frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(a.title).font(theme.font(13, .semibold))
                    .strikethrough(todo?.isDone == true)
                    .foregroundStyle(todo?.isDone == true ? theme.textMuted : theme.text)
                if !a.owner.trimmed.isEmpty || a.due != nil {
                    HStack(spacing: 4) {
                        if !a.owner.trimmed.isEmpty {
                            Chip(text: a.owner, symbol: "person.fill", color: Color(hex: KGNodeKind.person.hex))
                        }
                        if let due = a.due {
                            Chip(text: "~ " + DateFormatters.monthDayWeekday.string(from: due), symbol: "calendar")
                        }
                    }
                }
            }
            Spacer(minLength: 6)
            if todo != nil {
                Chip(text: "할일 등록됨", symbol: "checkmark", color: theme.accent2)
            } else {
                Button { AppEnvironment.shared.addMeetingActions(m.id, actionIDs: [a.id]) } label: {
                    Label("할일로", systemImage: "plus")
                }
                .buttonStyle(.retro(.secondary, compact: true))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme.surfaceAlt.opacity(0.6)))
    }

    private func entities(_ m: MeetingNote) -> some View {
        card("등장한 개체", symbol: "point.3.connected.trianglepath.dotted", count: m.entities.count) {
            Text("눌러서 그래프로").font(theme.font(10.5)).foregroundStyle(theme.textMuted)
        } content: {
            FlowLayout(spacing: 5) {
                ForEach(m.entities, id: \.self) { e in
                    let others = (meetings.graph.node(KnowledgeGraph.entityID(e.name))?.meetingIDs.count ?? 1) - 1
                    Button { onShowNode(KnowledgeGraph.entityID(e.name)) } label: {
                        Chip(text: e.name + (others > 0 ? " · 다른 회의 \(others)" : ""), symbol: e.kind.symbol,
                             color: Color(hex: e.kind.hex))
                    }
                    .buttonStyle(.plain)
                    .help("\(e.kind.label) · 지식그래프에서 보기")
                }
            }
        }
    }

    private func raw(_ m: MeetingNote) -> some View {
        card("원문", symbol: "doc.plaintext") {
            Button(showRaw ? "접기" : "펼치기") { showRaw.toggle() }
                .buttonStyle(.retro(.ghost, compact: true))
        } content: {
            if showRaw {
                Text(m.rawText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(m.rawText.trimmed.prefix(200) + (m.rawText.count > 200 ? "…" : ""))
                    .font(theme.font(11.5)).foregroundStyle(theme.textMuted).lineLimit(3)
            }
        }
    }

    private func card<C: View>(_ title: String, symbol: String, count: Int? = nil, @ViewBuilder content: () -> C) -> some View {
        card(title, symbol: symbol, count: count) { EmptyView() } content: { content() }
    }

    private func card<A: View, C: View>(_ title: String, symbol: String, count: Int? = nil,
                                        @ViewBuilder accessory: () -> A, @ViewBuilder content: () -> C) -> some View {
        let acc = accessory()
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title, symbol: symbol, count: count) { acc }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroCard()
    }

    private func copyMarkdown(_ m: MeetingNote) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(m.markdown(), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

// MARK: - 붙여넣기

struct PasteMeetingSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    var onAdd: (_ title: String, _ text: String, _ date: Date) -> Void

    @State private var title = ""
    @State private var text = ""
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("회의록 붙여넣기").font(theme.titleFont(20))
            HStack(spacing: 10) {
                TextField("제목 (비워 두면 AI가 붙여요)", text: $title).retroField()
                DatePicker("회의 날짜", selection: $date, displayedComponents: .date).fixedSize()
            }
            RetroTextEditor(text: $text, placeholder: "회의록 내용을 붙여 넣으세요", minHeight: 320)
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .buttonStyle(.retro(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button("추가하고 정리하기") {
                    onAdd(title, text, date)
                    dismiss()
                }
                .buttonStyle(.retro(.primary))
                .disabled(text.trimmed.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
        .background(theme.background)
    }
}
