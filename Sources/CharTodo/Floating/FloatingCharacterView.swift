import SwiftUI

/// 화면 위에 떠 있는 캐릭터 + 말풍선
struct FloatingCharacterView: View {
    @Environment(\.theme) private var theme
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatController.self) private var chat
    @Environment(CompanionState.self) private var companion
    @Environment(FloatingController.self) private var floating
    @Environment(TodoStore.self) private var store
    @Environment(CharacterDirector.self) private var director

    @State private var now = Date()
    private let sleepTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var mood: CharacterMood { director.mood(at: now) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Color.clear
                if let text = companion.bubble {
                    SpeechBubble(text: text)
                        .onTapGesture {
                            touch()
                            floating.showChat()
                        }
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
            }
            .frame(height: FloatingController.bubbleHeight)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: companion.bubble)

            CharacterView(rig: settings.settings.character, image: settings.characterImage,
                          aspect: settings.characterAspect, mood: mood,
                          bodyColor: bodyColor, action: director.action, facing: director.facing,
                          puppet: settings.puppet, eyes: settings.eyes)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { _ in floating.dragChanged() }
                        .onEnded { _ in floating.dragEnded(); touch() }
                )
                .onTapGesture(count: 2) {
                    touch()
                    AppEnvironment.shared.openMainWindow()
                }
                .onTapGesture {
                    director.clicked()
                    touch()
                    floating.toggleChat()
                }
                .onHover { inside in if inside { director.hovered() } }
                .contextMenu { menu }
                .help("클릭: 질문봇 열기 · 더블클릭: 메인 창 · 드래그: 이동")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onReceive(sleepTimer) { now = $0 }
        .onChange(of: chat.isBusy) { touch() }
    }

    private var bodyColor: Color {
        if let hex = settings.settings.character.bodyColorHex, let c = Color(hex: hex) { return c }
        return theme.accent
    }

    private func touch() {
        director.touch()
        now = Date()
    }

    @ViewBuilder private var menu: some View {
        Button("📼 오늘 브리핑 받기") {
            floating.showChat()
            chat.briefing(.today)
        }
        Button("💬 질문봇 열기") { floating.showChat() }
        Button("🗂 메인 창 열기") { AppEnvironment.shared.openMainWindow() }
        Menu("💼 career-support") { CareerMenuItems() }
        Divider()
        let open = store.todos(on: Date()).filter { !$0.isDone }.count
        Text("오늘 남은 할일 \(open)개")
        Divider()
        Button("캐릭터 숨기기") { floating.toggleCharacter() }
    }
}

struct SpeechBubble: View {
    @Environment(\.theme) private var theme
    var text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(theme.font(12.5, .bold))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border, lineWidth: 2))
            Triangle()
                .fill(theme.surface)
                .overlay(Triangle().stroke(theme.border, lineWidth: 2).mask(Rectangle().padding(.top, 2)))
                .frame(width: 14, height: 9)
                .offset(y: -2)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
        .shadow(color: .black.opacity(0.15), radius: 0, x: 3, y: 3)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}
