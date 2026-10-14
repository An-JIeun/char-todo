import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    // 회의록은 기존 단축키(설정 ⌘7)를 유지하려고 맨 뒤에 둔다. 사이드바에서는 업무일지 아래에 보인다.
    case today, week, month, matrix, tags, journal, settings, meetings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "오늘"
        case .week: "주간"
        case .month: "월간"
        case .matrix: "매트릭스"
        case .tags: "태그"
        case .journal: "업무일지 · TIL"
        case .settings: "설정"
        case .meetings: "회의록"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .week: "rectangle.split.3x1.fill"
        case .month: "calendar"
        case .matrix: "square.grid.2x2.fill"
        case .tags: "tag.fill"
        case .journal: "book.closed.fill"
        case .settings: "gearshape.fill"
        case .meetings: "person.3.sequence.fill"
        }
    }
}

struct MainView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    @Environment(SettingsStore.self) private var settings
    @Environment(FloatingController.self) private var floating
    @State private var section: AppSection = .today

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $section)
                .frame(width: 214)
            Rectangle().fill(theme.border).frame(width: theme.borderWidth)
            ZStack {
                PatternBackground(enabled: settings.settings.showPattern)
                content
                    .padding(.top, 14)
                if floating.isStageActive {
                    // 앱을 쓰는 동안에는 캐릭터가 창 아래쪽을 뛰어다닌다
                    InAppCompanionView()
                        .padding(.horizontal, 12)
                        .transition(.opacity)
                }
            }
        }
        .background(theme.background)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            AppEnvironment.shared.openWindowAction = openWindow
            // 창이 실제로 화면에 올라온 뒤에 상태를 읽는다 (가림·데스크톱·Dock 여부는 FloatingController가 추적)
            DispatchQueue.main.async { floating.refreshMainWindow() }
        }
        .onDisappear { floating.refreshMainWindow(closing: true) }
        .onReceive(NotificationCenter.default.publisher(for: .navigateRequest)) { note in
            if let raw = note.object as? String, let s = AppSection(rawValue: raw) { section = s }
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .today: TodayView()
        case .week: WeekView()
        case .month: MonthView()
        case .matrix: MatrixView()
        case .tags: TagsView()
        case .journal: JournalView()
        case .settings: SettingsView(embedded: true)
        case .meetings: MeetingsView()
        }
    }
}

struct SidebarView: View {
    @Environment(\.theme) private var theme
    @Environment(TodoStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatController.self) private var chat
    @Environment(FloatingController.self) private var floating
    @Binding var selection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 34) // 신호등 버튼 자리
            logo
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

            VStack(spacing: 6) {
                ForEach(AppSection.allCases.filter { $0 != .settings }) { s in
                    navButton(s)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            CareerShortcutCard()
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            assistantCard
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            navButton(.settings)
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
        }
        .background(theme.backgroundAlt)
    }

    private var logo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text("CHAR").foregroundStyle(theme.accent)
                Text("·").foregroundStyle(theme.text)
                Text("TODO").foregroundStyle(theme.accent2)
            }
            .font(theme.titleFont(24))
            .shadow(color: theme.shadow.opacity(0.9), radius: 0, x: 2, y: 2)
            Text("뉴트로 할일 다이어리 ✦ since 2026")
                .font(theme.font(9.5, .bold))
                .foregroundStyle(theme.textMuted)
        }
    }

    private func count(for s: AppSection) -> Int? {
        switch s {
        case .today:
            let n = store.todos(on: Date()).filter { !$0.isDone }.count + store.overdue().count
            return n > 0 ? n : nil
        case .week:
            let n = store.weekGoals(for: Date()).filter { !$0.isDone }.count
            return n > 0 ? n : nil
        default: return nil
        }
    }

    private func navButton(_ s: AppSection) -> some View {
        let selected = selection == s
        return Button {
            selection = s
        } label: {
            HStack(spacing: 9) {
                Image(systemName: s.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 18)
                Text(s.title).font(theme.font(13.5, .bold))
                Spacer()
                if let n = count(for: s) {
                    Text("\(n)")
                        .font(theme.font(10.5, .heavy))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(selected ? theme.highlight : theme.accent.opacity(0.2)))
                        .foregroundStyle(selected ? Color.black.opacity(0.85) : theme.text)
                }
            }
            .foregroundStyle(selected ? theme.onAccent : theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 2))
                    .fill(selected ? theme.accent : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 2))
                    .strokeBorder(selected ? theme.border : Color.clear, lineWidth: theme.borderWidth)
            )
            .background(
                RoundedRectangle(cornerRadius: max(0, theme.cornerRadius - 2))
                    .fill(selected ? theme.shadow : Color.clear)
                    .offset(x: 3, y: 3)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CharacterView(rig: settings.settings.character, image: settings.characterImage,
                              aspect: settings.characterAspect, mood: chat.isBusy ? .talking : .idle,
                              bodyColor: Color(hex: settings.settings.character.bodyColorHex ?? "") ?? theme.accent,
                              scale: 34 / max(40, settings.settings.character.size), puppet: settings.puppet,
                              eyes: settings.eyes)
                    .frame(width: 58, height: 58)
                    .clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.settings.assistantName).font(theme.font(13, .heavy))
                    Text(settings.settings.llm.provider.shortLabel)
                        .font(theme.font(10, .bold))
                        .foregroundStyle(theme.textMuted)
                }
            }
            HStack(spacing: 6) {
                Button {
                    floating.showChat()
                    chat.briefing(.today)
                } label: {
                    Label("브리핑", systemImage: "play.fill")
                }
                .buttonStyle(.retro(.primary, compact: true))
                Button {
                    floating.toggleCharacter()
                } label: {
                    Image(systemName: floating.isCompanionVisible ? "eye.fill" : "eye.slash.fill")
                }
                .buttonStyle(.retro(.secondary, compact: true))
                .help("떠 있는 캐릭터 보이기/숨기기")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroCard()
    }
}
