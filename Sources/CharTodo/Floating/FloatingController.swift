import AppKit
import SwiftUI
import Observation

/// 항상 위에 떠 있는 테두리 없는 패널
final class FloatingPanel: NSPanel {
    var allowsKey = false

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// 비활성 창에서도 첫 클릭을 바로 받는 호스팅 뷰
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
@Observable
final class FloatingController {
    private(set) var isChatVisible = false
    private(set) var isCharacterVisible = false

    static let bubbleHeight: CGFloat = 76
    static let minPanelWidth: CGFloat = 230
    static let chatSize = NSSize(width: 390, height: 540)

    @ObservationIgnored private unowned let env: AppEnvironment
    @ObservationIgnored private var characterPanel: FloatingPanel?
    @ObservationIgnored private var chatPanel: FloatingPanel?
    @ObservationIgnored private var dragStartMouse: NSPoint?
    @ObservationIgnored private var dragStartOrigin: NSPoint?
    @ObservationIgnored private let originKey = "floating.characterOrigin"
    @ObservationIgnored private var walkTimer: Timer?
    /// 사용자가 놓아 둔 자리 (돌아다녀도 이 근처에 머문다)
    @ObservationIgnored private var homeX: CGFloat?

    init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: 캐릭터 패널

    func applyVisibility() {
        if env.settings.settings.showFloatingCharacter { showCharacter() } else { hideCharacter() }
    }

    var panelSize: NSSize {
        let layout = CharacterLayout(rig: env.settings.settings.character, aspect: env.settings.characterAspect)
        return NSSize(width: max(Self.minPanelWidth, layout.canvasSize.width),
                      height: layout.canvasSize.height + Self.bubbleHeight)
    }

    func showCharacter() {
        if characterPanel == nil {
            let panel = FloatingPanel(size: panelSize)
            let root = EnvRoot(env: env) { FloatingCharacterView() }
            panel.contentView = ClickThroughHostingView(rootView: root)
            characterPanel = panel
            panel.setFrameOrigin(savedOrigin(for: panel.frame.size))
            homeX = panel.frame.origin.x
        }
        layoutForRig()
        characterPanel?.orderFrontRegardless()
        isCharacterVisible = true
    }

    func hideCharacter() {
        characterPanel?.orderOut(nil)
        isCharacterVisible = false
    }

    func toggleCharacter() {
        env.settings.settings.showFloatingCharacter.toggle()
    }

    /// 리그(크기·팔다리)가 바뀌면 발 위치를 고정한 채 패널 크기를 맞춘다.
    func layoutForRig() {
        guard let panel = characterPanel else { return }
        let size = panelSize
        let old = panel.frame
        guard old.size != size else { return }
        let origin = NSPoint(x: old.midX - size.width / 2, y: old.minY)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        positionChat()
    }

    private func savedOrigin(for size: NSSize) -> NSPoint {
        if let s = UserDefaults.standard.string(forKey: originKey) {
            let p = NSPointFromString(s)
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -40, dy: -40).contains(NSPoint(x: p.x + size.width / 2, y: p.y + 20)) }) {
                return p
            }
        }
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: vf.maxX - size.width - 24, y: vf.minY + 12)
    }

    // MARK: 드래그 이동

    func dragChanged() {
        guard let panel = characterPanel else { return }
        stopWalking()
        env.director.isDragging = true
        let mouse = NSEvent.mouseLocation
        if dragStartMouse == nil {
            dragStartMouse = mouse
            dragStartOrigin = panel.frame.origin
        }
        guard let sm = dragStartMouse, let so = dragStartOrigin else { return }
        panel.setFrameOrigin(NSPoint(x: so.x + mouse.x - sm.x, y: so.y + mouse.y - sm.y))
        positionChat()
    }

    func dragEnded() {
        dragStartMouse = nil
        dragStartOrigin = nil
        env.director.isDragging = false
        env.director.dragEnded()
        if let panel = characterPanel {
            homeX = panel.frame.origin.x
            UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: originKey)
        }
    }

    // MARK: 걸어 다니기

    /// 원래 자리 ±130pt 안에서 갈 곳을 고른다. 너무 가까우면 nil.
    func wanderOffset() -> CGFloat? {
        guard let panel = characterPanel, isCharacterVisible else { return nil }
        let home = homeX ?? panel.frame.origin.x
        let vf = (NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var target = home + CGFloat.random(in: -130...130)
        target = min(max(target, vf.minX), vf.maxX - panel.frame.width)
        let dx = target - panel.frame.origin.x
        return abs(dx) < 35 ? nil : dx
    }

    func walk(by dx: CGFloat, duration: Double) {
        stopWalking()
        guard let panel = characterPanel else { return }
        let startX = panel.frame.origin.x
        let start = Date()
        walkTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.characterPanel else { return }
                let p = min(1, Date().timeIntervalSince(start) / max(0.1, duration))
                // 출발·도착만 부드럽게, 중간은 일정한 걸음
                let e = p - sin(2 * .pi * p) / (2 * .pi)
                panel.setFrameOrigin(NSPoint(x: startX + dx * CGFloat(e), y: panel.frame.origin.y))
                self.positionChat()
                if p >= 1 { self.stopWalking() }
            }
        }
    }

    func stopWalking() {
        walkTimer?.invalidate()
        walkTimer = nil
    }

    // MARK: 채팅 패널

    func toggleChat() {
        isChatVisible ? hideChat() : showChat()
    }

    func showChat() {
        if chatPanel == nil {
            let panel = FloatingPanel(size: Self.chatSize)
            panel.allowsKey = true
            panel.hasShadow = true
            let root = EnvRoot(env: env) { ChatPanelView() }
            panel.contentView = ClickThroughHostingView(rootView: root)
            chatPanel = panel
        }
        env.companion.dismissBubble()
        isChatVisible = true
        positionChat()
        chatPanel?.orderFrontRegardless()
        chatPanel?.makeKey()
    }

    func hideChat() {
        chatPanel?.orderOut(nil)
        isChatVisible = false
    }

    private func positionChat() {
        guard isChatVisible, let chat = chatPanel else { return }
        let size = Self.chatSize
        let screen = characterPanel.flatMap { p in NSScreen.screens.first { $0.frame.intersects(p.frame) } } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin: NSPoint
        if let cp = characterPanel, isCharacterVisible {
            let f = cp.frame
            let placeLeft = f.midX > vf.midX
            let x = placeLeft ? f.midX - size.width - 40 : f.midX + 40
            origin = NSPoint(x: x, y: f.minY + 20)
        } else {
            origin = NSPoint(x: vf.maxX - size.width - 24, y: vf.minY + 24)
        }
        origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        chat.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// 모든 창(메인·설정·플로팅·메뉴바) 공통 루트: 환경 객체 + 테마 주입
struct EnvRoot<Content: View>: View {
    let env: AppEnvironment
    @ViewBuilder var content: () -> Content

    var body: some View {
        let theme = env.settings.theme
        content()
            .environment(\.theme, theme)
            .environment(env.store)
            .environment(env.settings)
            .environment(env.chat)
            .environment(env.companion)
            .environment(env.floating)
            .environment(env.director)
            .environment(env.calendar)
            .preferredColorScheme(theme.colorScheme)
    }
}
