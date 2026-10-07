import Foundation
import Observation
import AppKit

/// 떠 있는 캐릭터의 "연출": 언제 어떤 행동을 할지, 어느 쪽을 볼지, 걸어 다닐지를 정한다.
@MainActor
@Observable
final class CharacterDirector {
    private(set) var action: ActionState?
    private(set) var facing: Double = 1
    private(set) var lastInteraction = Date()

    @ObservationIgnored private unowned let env: AppEnvironment
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var nextActionAt = Date().addingTimeInterval(6)
    @ObservationIgnored private var lastHoverReaction = Date.distantPast
    @ObservationIgnored private var pendingWalk: CGFloat?
    @ObservationIgnored var isDragging = false

    init(env: AppEnvironment) {
        self.env = env
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private var rig: CharacterRig { env.settings.settings.character }

    /// 10분 동안 아무 반응이 없으면 졸기 시작
    func isSleepy(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastInteraction) > 600
    }

    func touch() {
        lastInteraction = Date()
    }

    private var canAct: Bool {
        env.floating.isCharacterVisible && !env.chat.isBusy && env.companion.transientMood == nil
            && !isDragging && !isSleepy()
    }

    private func tick() {
        let now = Date()
        let t = now.timeIntervalSinceReferenceDate
        if let a = action, t >= a.start + a.duration { finish(a) }
        guard action == nil else { return }
        if let dx = pendingWalk, canAct {
            pendingWalk = nil
            startWalk(dx)
            return
        }
        guard canAct, now >= nextActionAt else { return }
        performRandom()
        scheduleNext()
    }

    private func scheduleNext() {
        let l = max(0, min(1, rig.liveliness))
        guard l > 0.02 else { nextActionAt = .distantFuture; return }
        let base = 26 - 22 * l          // 활발함 0 → 26초, 1 → 4초
        nextActionAt = Date().addingTimeInterval(base * Double.random(in: 0.6...1.4))
    }

    func settingsChanged() {
        if nextActionAt == .distantFuture { scheduleNext() }
    }

    private func performRandom() {
        // 채팅 창이 열려 있으면 제자리 행동만
        if rig.wanders, !env.floating.isChatVisible, Double.random(in: 0...1) < 0.28 {
            walk()
            return
        }
        let pool = CharacterAction.allCases.filter { $0.weight > 0 }
        let total = pool.reduce(0) { $0 + $1.weight }
        var r = Double.random(in: 0..<total)
        for a in pool {
            r -= a.weight
            if r < 0 { perform(a); return }
        }
    }

    func perform(_ a: CharacterAction, duration: Double? = nil) {
        action = ActionState(a, start: Date().timeIntervalSinceReferenceDate, duration: duration)
    }

    private func finish(_ a: ActionState) {
        if a.action == .turnAround { facing *= -1 }
        if a.action == .waddle { env.floating.stopWalking() }
        action = nil
    }

    // MARK: 반응

    func hovered() {
        guard canAct, action == nil, Date().timeIntervalSince(lastHoverReaction) > 8 else { return }
        lastHoverReaction = Date()
        perform(Bool.random() ? .wave : .hop)
    }

    func clicked() {
        touch()
        if action == nil || action?.action == .waddle {
            env.floating.stopWalking()
            perform(.hop)
        }
    }

    func dragEnded() {
        touch()
        if action?.action == .waddle { action = nil }
        scheduleNext()
    }

    // MARK: 돌아다니기

    private func walk() {
        guard let dx = env.floating.wanderOffset() else { perform(.lookAround); return }
        let dir: Double = dx >= 0 ? 1 : -1
        if dir != facing {
            pendingWalk = dx
            perform(.turnAround)
        } else {
            startWalk(dx)
        }
    }

    private func startWalk(_ dx: CGFloat) {
        let speed: CGFloat = 55 * CGFloat(max(0.4, rig.speed))   // pt/s
        let duration = Double(abs(dx) / speed)
        perform(.waddle, duration: duration)
        env.floating.walk(by: dx, duration: duration)
    }
}
