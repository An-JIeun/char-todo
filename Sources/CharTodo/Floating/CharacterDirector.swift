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
    /// 앱 안 무대: 캐릭터 왼쪽 위치(pt)와 움직일 수 있는 폭
    var stageX: CGFloat = -1
    private(set) var stageWidth: CGFloat = 0
    @ObservationIgnored private var stageTimer: Timer?

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

    private var stage: Bool { env.floating.isStageActive }

    private var canAct: Bool {
        env.floating.isCompanionVisible && !env.chat.isBusy && env.companion.transientMood == nil
            && !isDragging && !isSleepy()
    }

    /// 바탕화면·앱 안 캐릭터가 함께 쓰는 현재 기분
    func mood(at now: Date) -> CharacterMood {
        if let m = env.companion.transientMood { return m }
        if env.chat.awaitingFirstToken { return .thinking }
        if env.chat.isBusy { return .talking }
        if env.floating.isChatVisible { return .listening }
        if isSleepy(at: now) { return .sleepy }
        return .idle
    }

    // MARK: 앱 안 무대

    /// 무대 폭이 정해지면(창 크기 변경 포함) 위치를 범위 안으로 맞춘다
    func setStage(width: CGFloat) {
        stageWidth = max(0, width)
        if stageX < 0 { stageX = stageWidth * 0.82 }
        stageX = min(max(0, stageX), stageWidth)
    }

    func stageDragged(to x: CGFloat) {
        isDragging = true
        stopStageWalk()
        if action?.action == .waddle { action = nil }
        stageX = min(max(0, x), stageWidth)
    }

    private func stopStageWalk() {
        stageTimer?.invalidate()
        stageTimer = nil
    }

    private func walkOnStage(by dx: CGFloat, duration: Double) {
        stopStageWalk()
        let start = stageX
        let began = Date()
        stageTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let p = min(1, Date().timeIntervalSince(began) / max(0.1, duration))
                let e = p - sin(2 * .pi * p) / (2 * .pi)
                self.stageX = min(max(0, start + dx * CGFloat(e)), self.stageWidth)
                if p >= 1 { self.stopStageWalk() }
            }
        }
    }

    private func stageWanderOffset() -> CGFloat? {
        guard stageWidth > 60 else { return nil }
        let target = CGFloat.random(in: 0...stageWidth)
        let dx = target - stageX
        return abs(dx) < 50 ? nil : dx
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
        var base = 26 - 22 * l          // 활발함 0 → 26초, 1 → 4초
        if stage { base *= 0.55 }      // 앱 안에서는 더 자주 움직인다
        nextActionAt = Date().addingTimeInterval(base * Double.random(in: 0.6...1.4))
    }

    func settingsChanged() {
        if nextActionAt == .distantFuture { scheduleNext() }
    }

    private func performRandom() {
        // 채팅 창이 열려 있으면 제자리 행동만. 앱 안에서는 뛰어다니는 비율을 높인다
        let walkChance = stage ? 0.55 : 0.28
        if (rig.wanders || stage), !env.floating.isChatVisible, Double.random(in: 0...1) < walkChance {
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
        if a.action == .waddle { env.floating.stopWalking(); stopStageWalk() }
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
            stopStageWalk()
            perform(.hop)
        }
    }

    func dragEnded() {
        isDragging = false
        touch()
        if action?.action == .waddle { action = nil }
        scheduleNext()
    }

    // MARK: 돌아다니기

    private func walk() {
        guard let dx = stage ? stageWanderOffset() : env.floating.wanderOffset() else { perform(.lookAround); return }
        let dir: Double = dx >= 0 ? 1 : -1
        if dir != facing {
            pendingWalk = dx
            perform(.turnAround)
        } else {
            startWalk(dx)
        }
    }

    private func startWalk(_ dx: CGFloat) {
        // 앱 안에서는 총총 뛰어다니듯 더 빠르게
        let speed: CGFloat = (stage ? 110 : 55) * CGFloat(max(0.4, rig.speed))   // pt/s
        let duration = Double(abs(dx) / speed)
        perform(.waddle, duration: duration)
        if stage { walkOnStage(by: dx, duration: duration) } else { env.floating.walk(by: dx, duration: duration) }
    }
}
