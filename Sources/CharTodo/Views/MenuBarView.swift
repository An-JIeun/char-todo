import SwiftUI

/// 메뉴바에서 바로 보는 오늘 할일
struct MenuBarView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    @Environment(TodoStore.self) private var store
    @Environment(ChatController.self) private var chat
    @Environment(FloatingController.self) private var floating

    var body: some View {
        let todos = store.todos(on: Date())
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("오늘 · \(DateFormatters.monthDayWeekday.string(from: Date()))").font(theme.font(14, .heavy))
                Spacer()
                Text("\(todos.filter(\.isDone).count)/\(todos.count)").font(theme.font(12, .bold)).foregroundStyle(theme.textMuted)
            }
            QuickAddBar(placeholder: "빠른 추가", defaultDate: Date(), compact: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    if todos.isEmpty { EmptyHint(text: "오늘 할일이 없어요") }
                    ForEach(todos) { t in TodoRowView(todo: t, compact: true) }
                }
            }
            .frame(maxHeight: 300)
            HStack(spacing: 6) {
                Button {
                    floating.showChat()
                    chat.briefing(.today)
                } label: { Label("브리핑", systemImage: "play.fill") }
                .buttonStyle(.retro(.primary, compact: true))
                Button {
                    AppEnvironment.shared.openWindowAction = openWindow
                    AppEnvironment.shared.openMainWindow()
                } label: { Label("메인 창", systemImage: "macwindow") }
                .buttonStyle(.retro(.secondary, compact: true))
                Button {
                    AppEnvironment.shared.career.open(.jobs)
                } label: { Image(systemName: "briefcase.fill") }
                .buttonStyle(.retro(.secondary, compact: true))
                .help("career-support 열기 (⌘⇧C)")
                Button {
                    floating.toggleCharacter()
                } label: { Image(systemName: floating.isCompanionVisible ? "eye.fill" : "eye.slash") }
                .buttonStyle(.retro(.secondary, compact: true))
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.retro(.ghost, compact: true))
                    .help("종료")
            }
        }
        .padding(12)
        .frame(width: 340)
        .background(theme.background)
    }
}
