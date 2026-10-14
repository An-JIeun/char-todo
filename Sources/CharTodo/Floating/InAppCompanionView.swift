import SwiftUI

/// 앱을 쓰는 동안 메인 창 아래쪽을 뛰어다니는 캐릭터
struct InAppCompanionView: View {
    @Environment(\.theme) private var theme
    @Environment(SettingsStore.self) private var settings
    @Environment(CharacterDirector.self) private var director
    @Environment(CompanionState.self) private var companion
    @Environment(FloatingController.self) private var floating
    @Environment(ChatController.self) private var chat
    @Environment(TodoStore.self) private var store

    @State private var now = Date()
    @State private var dragStartX: CGFloat?
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// 앱 안에서는 화면을 덜 가리도록 몸통 너비 76pt 정도로
    private var scale: CGFloat {
        min(1, 76 / max(40, CGFloat(settings.settings.character.size)))
    }

    var body: some View {
        GeometryReader { geo in
            let rig = settings.settings.character
            let layout = CharacterLayout(rig: rig, aspect: settings.characterAspect, scale: scale)
            let charW = layout.canvasSize.width
            let charH = layout.canvasSize.height
            let x = max(0, director.stageX)

            ZStack(alignment: .bottomLeading) {
                Color.clear.allowsHitTesting(false)
                if let text = companion.bubble {
                    SpeechBubble(text: text)
                        .frame(maxWidth: 240)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(x: min(max(0, x + charW / 2 - 120), geo.size.width - 240), y: -charH + 6)
                        .onTapGesture { floating.showChat() }
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
                CharacterView(rig: rig, image: settings.characterImage, aspect: settings.characterAspect,
                              mood: director.mood(at: now), bodyColor: bodyColor, scale: scale,
                              action: director.action, facing: director.facing,
                              puppet: settings.puppet, eyes: settings.eyes)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 3, coordinateSpace: .named("stage"))
                            .onChanged { v in
                                if dragStartX == nil { dragStartX = director.stageX }
                                director.stageDragged(to: (dragStartX ?? 0) + v.translation.width)
                            }
                            .onEnded { _ in
                                dragStartX = nil
                                director.dragEnded()
                            }
                    )
                    .onTapGesture(count: 2) { director.perform(.doubleHop); director.touch() }
                    .onTapGesture {
                        director.clicked()
                        floating.toggleChat()
                    }
                    .onHover { inside in if inside { director.hovered() } }
                    .contextMenu {
                        Button("📼 오늘 브리핑 받기") {
                            floating.showChat()
                            chat.briefing(.today)
                        }
                        Button("💬 질문봇 열기") { floating.showChat() }
                        Menu("💼 career-support") { CareerMenuItems() }
                        Divider()
                        Text("오늘 남은 할일 \(store.todos(on: Date()).filter { !$0.isDone }.count)개")
                        Divider()
                        Button("앱 안에서 뛰어다니기 끄기") { settings.settings.roamInApp = false }
                        Button("캐릭터 숨기기") { floating.toggleCharacter() }
                    }
                    .help("클릭: 질문봇 · 더블클릭: 깡총 · 드래그: 옮기기")
                    .offset(x: x, y: 4)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            .coordinateSpace(name: "stage")
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: companion.bubble)
            .onAppear { director.setStage(width: geo.size.width - charW) }
            .onChange(of: geo.size.width) { _, w in director.setStage(width: w - charW) }
            .onChange(of: charW) { _, w in director.setStage(width: geo.size.width - w) }
        }
        .onReceive(clock) { now = $0 }
        .onChange(of: chat.isBusy) { director.touch(); now = Date() }
    }

    private var bodyColor: Color {
        if let hex = settings.settings.character.bodyColorHex, let c = Color(hex: hex) { return c }
        return theme.accent
    }
}
