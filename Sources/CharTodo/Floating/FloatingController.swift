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
    /// 바탕화면에 떠 있는 캐릭터 패널이 보이는지
    private(set) var isCharacterVisible = false
    /// 앱 안(메인 창)에서 뛰어다니는 중인지
    private(set) var isStageActive = false
    /// 어느 쪽으로든 캐릭터가 보이는지
    var isCompanionVisible: Bool { isCharacterVisible || isStageActive }

    /// 메인 창이 실제로 화면에 보이는지. 열려 있어도 다른 창에 완전히 가려졌거나, 다른 데스크톱에 있거나,
    /// Dock으로 내려가 있으면 false — 이때 앱 안으로 들어가면 캐릭터가 안 보이는 창 속으로 사라진다.
    @ObservationIgnored private(set) var mainWindowVisible = false {
        didSet { if mainWindowVisible != oldValue { applyVisibility() } }
    }
    @ObservationIgnored var appActive = true {
        didSet { if appActive != oldValue { applyVisibility() } }
    }

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
        // 모니터 연결이 바뀌면 화면 밖으로 사라진 캐릭터를 데려온다
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ensureOnScreen() }
        }
        // 메인 창이 가려지거나·닫히거나·내려가면 캐릭터를 바탕화면으로 돌려보낸다
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let w = note.object as? NSWindow, Self.isMainWindow(w) else { return }
                    self?.refreshMainWindow(closing: name == NSWindow.willCloseNotification)
                }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMainWindow() }
        }
    }

    static func isMainWindow(_ w: NSWindow) -> Bool {
        guard !(w is FloatingPanel), let id = w.identifier?.rawValue else { return false }
        return id == "main" || id.hasPrefix("main")
    }

    /// 메인 창 상태를 다시 읽는다 (창 이벤트·앱 활성화 때)
    func refreshMainWindow(closing: Bool = false) {
        guard !closing, let w = NSApp.windows.first(where: Self.isMainWindow) else {
            mainWindowVisible = false
            return
        }
        mainWindowVisible = w.isVisible && !w.isMiniaturized && w.isOnActiveSpace && w.occlusionState.contains(.visible)
    }

    /// 사용자가 지금 캐릭터를 볼 수 있는지 (보이는 메인 창 안에서 뛰어다니거나, 패널이 실제로 화면에 있음)
    var isActuallyVisible: Bool {
        if isStageActive { return true }
        guard isCharacterVisible, let p = characterPanel else { return false }
        return p.isVisible && p.occlusionState.contains(.visible)
    }

    // MARK: 캐릭터 패널

    func applyVisibility() {
        let s = env.settings.settings
        let stage = s.showFloatingCharacter && s.roamInApp && mainWindowVisible && appActive
        if isStageActive != stage {
            isStageActive = stage
            stopWalking()
        }
        if s.showFloatingCharacter && !stage { showCharacter() } else { hideCharacter() }
        positionChat()
    }

    /// 캐릭터 창이 어느 화면에도 충분히 걸쳐 있지 않으면 메인 화면 오른쪽 아래로 옮기고,
    /// 화면 가장자리에 반쯤 걸쳐 있으면 몸이 다 보이도록 안쪽으로 당긴다.
    func ensureOnScreen() {
        guard let panel = characterPanel else { return }
        var origin = panel.frame.origin
        let core = panel.frame.insetBy(dx: panel.frame.width * 0.3, dy: panel.frame.height * 0.3)
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(core) }) {
            // 패널 가운데에 그려지는 캐릭터 몸이 화면 밖으로 잘리지 않게
            let vf = screen.visibleFrame
            let charW = CharacterLayout(rig: env.settings.settings.character, aspect: env.settings.characterAspect).canvasSize.width
            let margin = max(0, (panel.frame.width - charW) / 2)
            origin.x = min(max(origin.x, vf.minX - margin), vf.maxX - panel.frame.width + margin)
        } else {
            let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            origin = NSPoint(x: vf.maxX - panel.frame.width - 24, y: vf.minY + 12)
        }
        guard origin != panel.frame.origin else { return }
        panel.setFrameOrigin(origin)
        homeX = origin.x
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: originKey)
        positionChat()
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
        ensureOnScreen()
        characterPanel?.orderFrontRegardless()
        isCharacterVisible = true
    }

    func hideCharacter() {
        characterPanel?.orderOut(nil)
        isCharacterVisible = false
    }

    /// ⌘⇧K · 👁 버튼. 켜져 있는데 어디에도 안 보이면 끄지 않고 불러온다.
    func toggleCharacter() {
        if env.settings.settings.showFloatingCharacter && !isActuallyVisible {
            summon()
        } else {
            env.settings.settings.showFloatingCharacter.toggle()
        }
    }

    /// 캐릭터를 지금 보이는 곳으로 데려온다
    func summon() {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        env.settings.settings.showFloatingCharacter = true
        refreshMainWindow()
        applyVisibility()
        env.companion.flash(.happy, duration: 1.2)
        env.companion.say(env.line(.greeting), duration: 3)
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
        } else if isStageActive, let main = DevSnapshot.mainWindow() {
            // 앱 안에서 뛰어다니는 중이면 메인 창 오른쪽 아래 안쪽에
            origin = NSPoint(x: main.frame.maxX - size.width - 24, y: main.frame.minY + 110)
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
            .environment(env.meetings)
            .environment(env.settings)
            .environment(env.chat)
            .environment(env.companion)
            .environment(env.floating)
            .environment(env.director)
            .environment(env.calendar)
            .environment(env.career)
            .preferredColorScheme(theme.colorScheme)
    }
}
