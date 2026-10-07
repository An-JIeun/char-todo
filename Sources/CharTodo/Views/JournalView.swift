import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 업무일지 + TIL
struct JournalView: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store

    @State private var day = Date().startOfDay
    @State private var calendarMonth = Date().startOfMonth

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 14) {
                miniCalendar
                recentList
            }
            .frame(width: 250)

            JournalEditor(day: day)
                .id(day)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }

    private var miniCalendar: some View {
        RetroWindow(DateFormatters.yearMonth.string(from: calendarMonth), symbol: "calendar") {
            HStack(spacing: 0) {
                Button { calendarMonth = calendarMonth.adding(months: -1) } label: { Image(systemName: "chevron.left") }
                Button { calendarMonth = calendarMonth.adding(months: 1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .bold))
        } content: {
            let days = calendarMonth.monthGridDays
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    ForEach(days.prefix(7), id: \.self) { d in
                        Text(DateFormatters.weekdayShort.string(from: d))
                            .font(theme.font(9.5, .bold)).foregroundStyle(theme.textMuted).frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            let d = days[row * 7 + col]
                            let isSel = d.isSameDay(as: day)
                            Button {
                                day = d.startOfDay
                            } label: {
                                VStack(spacing: 1) {
                                    Text("\(d.dayNumber)")
                                        .font(theme.font(11, isSel ? .heavy : .medium))
                                        .foregroundStyle(isSel ? theme.onAccent : theme.text)
                                    Circle()
                                        .fill(store.hasJournal(on: d) ? (isSel ? Color.white : theme.accent2) : Color.clear)
                                        .frame(width: 4, height: 4)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 4).fill(isSel ? theme.accent : (d.isToday ? theme.highlight.opacity(0.4) : .clear)))
                                .opacity(d.isSameMonth(as: calendarMonth) ? 1 : 0.35)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var recentList: some View {
        let entries = store.journals.filter { !$0.isEmpty }.prefix(30)
        return RetroWindow("최근 일지", symbol: "clock.arrow.circlepath") {
            EmptyView()
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if entries.isEmpty { EmptyHint(text: "아직 일지가 없어요") }
                    ForEach(Array(entries)) { e in
                        Button {
                            day = e.date
                            calendarMonth = e.date.startOfMonth
                        } label: {
                            HStack(spacing: 6) {
                                Text(e.mood.flatMap { m in JournalEntry.moods.first { $0.0 == m }?.1 } ?? "📄")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(DateFormatters.monthDayWeekday.string(from: e.date)).font(theme.font(11.5, .bold))
                                    Text(e.work.trimmed.split(separator: "\n").first.map(String.init) ?? "")
                                        .font(theme.font(10.5)).foregroundStyle(theme.textMuted).lineLimit(1)
                                }
                                Spacer()
                                if !e.tils.isEmpty { Chip(text: "TIL \(e.tils.count)", color: theme.accent2) }
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 4).fill(e.date.isSameDay(as: day) ? theme.accent.opacity(0.15) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
        }
    }
}

struct JournalEditor: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store
    let day: Date

    @State private var entry: JournalEntry
    @State private var drafting = false
    @State private var aiError: String?
    @State private var copied = false

    init(day: Date) {
        self.day = day
        _entry = State(initialValue: AppEnvironment.shared.store.journal(for: day))
    }

    var body: some View {
        let completed = store.completed(on: day)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                section("오늘 한 일", symbol: "hammer.fill") {
                    HStack(spacing: 6) {
                        Button {
                            importCompleted(completed)
                        } label: { Label("완료한 할일 가져오기 (\(completed.count))", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.retro(.secondary, compact: true))
                        .disabled(completed.isEmpty)
                        Button {
                            draftWithAI(completed)
                        } label: {
                            if drafting { ProgressView().controlSize(.small) } else { Label("AI 초안", systemImage: "wand.and.stars") }
                        }
                        .buttonStyle(.retro(.accent2, compact: true))
                        .disabled(drafting)
                    }
                } content: {
                    RetroTextEditor(text: $entry.work, placeholder: "- 오늘 진행한 업무를 적어 보세요", minHeight: 130)
                    if let aiError { Text(aiError).font(theme.font(11)).foregroundStyle(.red) }
                }

                section("이슈 · 회고", symbol: "exclamationmark.bubble.fill") {
                    EmptyView()
                } content: {
                    RetroTextEditor(text: $entry.issues, placeholder: "막혔던 점, 개선할 점, 메모…", minHeight: 80)
                }

                section("내일 할 일", symbol: "arrow.forward.circle.fill") {
                    Button {
                        addPlanAsTodos()
                    } label: { Label("내일 할일로 등록", systemImage: "plus.circle") }
                    .buttonStyle(.retro(.secondary, compact: true))
                    .disabled(entry.plan.trimmed.isEmpty)
                    .help("한 줄에 하나씩 적으면 다음 날 할일로 추가돼요")
                } content: {
                    RetroTextEditor(text: $entry.plan, placeholder: "- 한 줄에 하나씩", minHeight: 70)
                }

                tilSection
            }
            .padding(.bottom, 20)
        }
        .onChange(of: entry) { _, new in store.saveJournal(new) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            TearOffCalendar(date: day, size: 70)
            VStack(alignment: .leading, spacing: 6) {
                Text("업무일지").font(theme.titleFont(26)).foregroundStyle(theme.text)
                Text(DateFormatters.fullDate.string(from: day)).font(theme.font(13, .bold)).foregroundStyle(theme.textMuted)
                HStack(spacing: 4) {
                    Text("컨디션").font(theme.font(11, .bold)).foregroundStyle(theme.textMuted)
                    ForEach(JournalEntry.moods, id: \.0) { m in
                        Button {
                            entry.mood = entry.mood == m.0 ? nil : m.0
                        } label: {
                            Text(m.1).font(.system(size: 18))
                                .padding(3)
                                .background(RoundedRectangle(cornerRadius: 6).fill(entry.mood == m.0 ? theme.highlight : .clear))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(entry.mood == m.0 ? theme.border : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .help(m.2)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    let md = entry.markdown(completedTodos: store.completed(on: day))
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(md, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: { Label(copied ? "복사됨!" : "마크다운 복사", systemImage: copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(.retro(.secondary, compact: true))
                Button { exportMarkdown() } label: { Label("파일로 내보내기", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.retro(.secondary, compact: true))
            }
        }
    }

    private func section<A: View, C: View>(_ title: String, symbol: String,
                                           @ViewBuilder accessory: () -> A,
                                           @ViewBuilder content: () -> C) -> some View {
        let acc = accessory()
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title, symbol: symbol) { acc }
            content()
        }
        .padding(14)
        .retroCard()
    }

    private var tilSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("TIL · Today I Learned", symbol: "lightbulb.fill", count: entry.tils.isEmpty ? nil : entry.tils.count) {
                Button {
                    entry.tils.append(TILNote())
                } label: { Label("TIL 추가", systemImage: "plus") }
                .buttonStyle(.retro(.primary, compact: true))
            }
            if entry.tils.isEmpty {
                EmptyHint(text: "오늘 새로 배운 것을 기록해 보세요", symbol: "lightbulb")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                ForEach($entry.tils) { $note in
                    TILCard(note: $note) { entry.tils.removeAll { $0.id == note.id } }
                }
            }
        }
        .padding(14)
        .retroCard(fill: theme.surfaceAlt)
    }

    // MARK: 동작

    private func importCompleted(_ completed: [TodoItem]) {
        let lines = completed.map { t -> String in
            var l = "- \(t.title)"
            let subs = t.subtasks.filter(\.isDone).map(\.title)
            if !subs.isEmpty { l += " (" + subs.joined(separator: ", ") + ")" }
            return l
        }.filter { !entry.work.contains($0) }
        guard !lines.isEmpty else { return }
        entry.work = (entry.work.trimmed.isEmpty ? "" : entry.work.trimmed + "\n") + lines.joined(separator: "\n")
    }

    private func draftWithAI(_ completed: [TodoItem]) {
        drafting = true
        aiError = nil
        let remaining = store.todos(on: day).filter { !$0.isDone }
        let prompt = PromptBuilder.journalPrompt(entry: entry, completed: completed, remaining: remaining)
        Task {
            defer { drafting = false }
            do {
                let text = try await AppEnvironment.shared.chat.oneShot(prompt)
                entry.work = entry.work.trimmed.isEmpty ? text : entry.work.trimmed + "\n\n" + text
            } catch {
                aiError = error.localizedDescription
            }
        }
    }

    private func addPlanAsTodos() {
        let tomorrow = day.adding(days: 1)
        let existing = Set(store.todos(on: tomorrow).map(\.title))
        var lines = PromptBuilder.parseList(entry.plan)
        if lines.isEmpty {
            lines = entry.plan.split(whereSeparator: \.isNewline).map { String($0).trimmed }.filter { !$0.isEmpty }
        }
        var added = 0
        for line in lines where !existing.contains(line) {
            if let item = QuickAddParser().makeTodo(from: line, defaultDate: tomorrow, defaultScope: .day) {
                store.add(item)
                added += 1
            }
        }
        AppEnvironment.shared.companion.say(added > 0 ? "내일 할일 \(added)개 등록! 📌" : "이미 모두 등록돼 있어요", duration: 3)
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "업무일지-\(day.dayKey).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = entry.markdown(completedTodos: store.completed(on: day))
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct TILCard: View {
    @Environment(\.theme) private var theme
    @Binding var note: TILNote
    var onDelete: () -> Void
    @State private var tagText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.max.fill").foregroundStyle(theme.highlight)
                    .shadow(color: theme.border, radius: 0, x: 1, y: 1)
                TextField("배운 것 한 줄 제목", text: $note.title)
                    .textFieldStyle(.plain)
                    .font(theme.font(14, .heavy))
                IconButton(symbol: "trash", help: "삭제", size: 10, action: onDelete)
            }
            RetroTextEditor(text: $note.body, placeholder: "내용, 코드, 링크…", minHeight: 80)
            HStack(spacing: 4) {
                ForEach(note.tags, id: \.self) { tag in
                    Button {
                        note.tags.removeAll { $0 == tag }
                    } label: { Chip(text: "#\(tag)", color: theme.accent2) }
                    .buttonStyle(.plain)
                    .help("클릭해서 삭제")
                }
                TextField("#태그", text: $tagText)
                    .textFieldStyle(.plain)
                    .font(theme.font(11))
                    .frame(width: 90)
                    .onSubmit {
                        let t = tagText.trimmed.replacingOccurrences(of: "#", with: "")
                        if !t.isEmpty && !note.tags.contains(t) { note.tags.append(t) }
                        tagText = ""
                    }
            }
        }
        .padding(12)
        .retroCard()
    }
}
