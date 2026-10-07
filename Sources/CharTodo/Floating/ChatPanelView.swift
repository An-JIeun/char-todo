import SwiftUI

/// ChatGPT처럼 떠 있는 브리핑/질문봇 창
struct ChatPanelView: View {
    @Environment(\.theme) private var theme
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatController.self) private var chat
    @Environment(FloatingController.self) private var floating
    @FocusState private var inputFocused: Bool

    var body: some View {
        @Bindable var chat = chat
        RetroWindow("\(settings.settings.assistantName).exe", symbol: "bubble.left.and.text.bubble.right.fill") {
            HStack(spacing: 2) {
                Button { chat.clear() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.plain).help("대화 지우기")
                Button { floating.hideChat() } label: { Image(systemName: "xmark.square.fill") }
                    .buttonStyle(.plain).help("닫기 (esc)")
            }
            .font(.system(size: 13, weight: .bold))
        } content: {
            VStack(spacing: 0) {
                providerBar
                messagesView
                quickActions
                inputBar(text: $chat.draft)
            }
            .background(theme.surfaceAlt.opacity(0.5))
        }
        .padding(6)
        .onExitCommand { floating.hideChat() }
        .onAppear { inputFocused = true }
    }

    private var providerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: settings.settings.llm.provider.symbol)
            Text(chat.providerLabel).lineLimit(1)
            Spacer()
            if chat.isBusy {
                Button("중지") { chat.stop() }
                    .buttonStyle(.retro(.danger, compact: true))
            }
        }
        .font(theme.font(10.5, .bold))
        .foregroundStyle(theme.textMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(theme.surface)
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chat.messages.isEmpty { welcome }
                    ForEach(chat.messages) { msg in
                        MessageBubble(message: msg).id(msg.id)
                    }
                    if chat.awaitingFirstToken { TypingIndicator().id("typing") }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(10)
            }
            .onChange(of: chat.messages.last?.text) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: chat.messages.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("안녕! 나는 \(settings.settings.assistantName) ✨")
                .font(theme.font(15, .heavy))
            Text("오늘 할일·캘린더 일정·업무일지를 보고 브리핑해 줄게. 아래 버튼을 누르거나 편하게 물어봐.")
                .font(theme.font(12.5))
                .foregroundStyle(theme.textMuted)
            Text("예) \"오후에 집중할 일 골라줘\", \"내일 오후 3시 팀 회의 #업무 추가해줘\" → 시간·태그까지 자동으로 등록돼요.")
                .font(theme.font(11.5))
                .foregroundStyle(theme.textMuted)
            Text("AI 없이 바로 넣기: + 팀 회의 @내일 ~15:00 #업무 !1 > 안건, 자료")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.textMuted)
        }
        .padding(12)
        .retroCard(shadow: false)
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(BriefingKind.allCases) { kind in
                    Button {
                        chat.briefing(kind)
                    } label: {
                        Label(kind.label, systemImage: kind.symbol)
                    }
                    .buttonStyle(.retro(.secondary, compact: true))
                    .disabled(chat.isBusy)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .background(theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(theme.border.opacity(0.4)).frame(height: 1) }
    }

    private func inputBar(text: Binding<String>) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("무엇이든 물어보세요…  (+ 로 시작하면 바로 추가)", text: text, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit { chat.send() }
                .retroField()
            Button {
                chat.isBusy ? chat.stop() : chat.send()
            } label: {
                Image(systemName: chat.isBusy ? "stop.fill" : "paperplane.fill")
            }
            .buttonStyle(.retro(.primary))
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(10)
        .background(theme.surface)
    }
}

struct MessageBubble: View {
    @Environment(\.theme) private var theme
    @Environment(ChatController.self) private var chat
    @Environment(TodoStore.self) private var store
    var message: ChatMessage
    @State private var editing: TodoItem?

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                let text = message.displayText
                if !text.isEmpty || message.isStreaming {
                    Text(MarkdownLite.render(text.isEmpty ? "…" : text))
                        .font(theme.font(12.5))
                        .foregroundStyle(foreground)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if message.isError {
                    Button("AI 설정 열기") {
                        AppEnvironment.shared.openSettings(tab: SettingsTab.ai.rawValue)
                    }
                    .buttonStyle(.retro(.secondary, compact: true))
                }
                if !message.autoAddedTodoIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(message.autoAddedTodoIDs, id: \.self) { id in
                            if let todo = store.todo(id: id) { addedCard(todo) }
                        }
                    }
                }
                let suggestions = message.suggestions
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { idx, s in
                            suggestionButton(s, index: idx)
                        }
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: max(4, theme.cornerRadius)).fill(background))
            .overlay(RoundedRectangle(cornerRadius: max(4, theme.cornerRadius)).strokeBorder(theme.border, lineWidth: 1.5))
            if message.role == .assistant { Spacer(minLength: 24) }
        }
        .sheet(item: $editing) { item in TodoEditorSheet(original: item) }
    }

    private var background: Color {
        if message.isError { return Color(hex: "#FFE1E1")! }
        return message.role == .user ? theme.accent : theme.surface
    }

    private var foreground: Color {
        if message.isError { return Color(hex: "#8A1C1C")! }
        return message.role == .user ? theme.onAccent : theme.text
    }

    /// 자동 등록된 할일 카드: 요약 + 되돌리기/편집
    private func addedCard(_ todo: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent2)
                Text(todo.title).font(theme.font(12.5, .heavy)).foregroundStyle(theme.text).lineLimit(2)
                Spacer(minLength: 4)
                Button("편집") { editing = todo }
                    .buttonStyle(.retro(.ghost, compact: true))
                Button("되돌리기") { chat.undoAutoAdd(todo.id, in: message.id) }
                    .buttonStyle(.retro(.ghost, compact: true))
            }
            FlowLayout(spacing: 4) {
                Chip(text: dateLabel(todo), symbol: "calendar")
                if let start = todo.scheduledStart {
                    Chip(text: DateFormatters.time.string(from: start) + (todo.durationMinutes != 60 ? " · \(todo.durationMinutes)분" : ""),
                         symbol: "clock.fill", color: theme.accent2)
                }
                if let q = todo.quadrant { Chip(text: "\(q.shortLabel) \(q.title)", color: theme.quadrantColor(q)) }
                ForEach(todo.tags, id: \.self) { t in Chip(text: "#\(t)", color: AppEnvironment.shared.tagColor(t)) }
                if !todo.subtasks.isEmpty { Chip(text: "세부 \(todo.subtasks.count)", symbol: "list.bullet") }
                if todo.calendarEventID != nil { Chip(text: "캘린더", symbol: "calendar.badge.checkmark", color: theme.accent2) }
                if !todo.notes.trimmed.isEmpty { Chip(text: "메모", symbol: "note.text") }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: max(3, theme.cornerRadius - 6)).fill(theme.surfaceAlt))
        .overlay(RoundedRectangle(cornerRadius: max(3, theme.cornerRadius - 6)).strokeBorder(theme.accent2, lineWidth: 1.2))
    }

    private func dateLabel(_ t: TodoItem) -> String {
        switch t.scope {
        case .day: t.date.isToday ? "오늘" : DateFormatters.monthDayWeekday.string(from: t.date)
        case .week: "주간 · \(DateFormatters.monthDay.string(from: t.date))~"
        case .month: "월간 · \(DateFormatters.yearMonth.string(from: t.date))"
        }
    }

    private func suggestionButton(_ s: TodoSuggestion, index: Int) -> some View {
        let added = message.addedSuggestions[index] != nil
        return Button {
            chat.addSuggestion(at: index, in: message.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(added ? "추가됨: \(s.title)" : "할일 추가: \(s.title)", systemImage: added ? "checkmark.circle.fill" : "plus.circle.fill")
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(s.detailLabel).font(theme.font(10.5)).opacity(0.85).lineLimit(2)
            }
        }
        .buttonStyle(.retro(added ? .secondary : .accent2, compact: true))
        .disabled(added)
    }
}

struct TypingIndicator: View {
    @Environment(\.theme) private var theme
    @State private var text = AppEnvironment.shared.line(.thinking)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 7, height: 7)
                        .offset(y: -CGFloat(max(0, sin(t * 6 - Double(i) * 0.8))) * 4)
                }
                Text(text).font(theme.font(11, .bold)).foregroundStyle(theme.textMuted).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: max(4, theme.cornerRadius)).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: max(4, theme.cornerRadius)).strokeBorder(theme.border, lineWidth: 1.5))
        }
    }
}

/// 가벼운 마크다운 렌더링: 제목(#), 목록(-), 인라인(**굵게**, `코드`)
enum MarkdownLite {
    static func render(_ text: String) -> AttributedString {
        var result = AttributedString()
        let lines = text.components(separatedBy: "\n")
        for (i, raw) in lines.enumerated() {
            var line = raw
            var bold = false
            if let r = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                line.removeSubrange(r)
                bold = true
            } else if let r = line.range(of: #"^(\s*)[-*]\s+"#, options: .regularExpression) {
                let indent = line[r].prefix { $0 == " " }
                line.replaceSubrange(r, with: indent + "• ")
            }
            var attr = (try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(line)
            if bold { attr.inlinePresentationIntent = .stronglyEmphasized }
            result += attr
            if i < lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }
}
