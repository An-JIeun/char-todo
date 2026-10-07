import Foundation

/// 캐릭터가 혼자 있을 때 하는 짧은 행동
enum CharacterAction: String, CaseIterable, Identifiable {
    case hop, doubleHop, wiggle, lookAround, wave, stretch, turnAround, waddle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hop: "깡총"
        case .doubleHop: "두 번 깡총"
        case .wiggle: "몸 흔들기"
        case .lookAround: "두리번"
        case .wave: "손 흔들기"
        case .stretch: "기지개"
        case .turnAround: "뒤돌기"
        case .waddle: "종종걸음"
        }
    }

    var duration: Double {
        switch self {
        case .hop: 0.95
        case .doubleHop: 1.6
        case .wiggle: 1.3
        case .lookAround: 2.8
        case .wave: 1.9
        case .stretch: 2.6
        case .turnAround: 0.75
        case .waddle: 1.8
        }
    }

    /// 랜덤으로 고를 때의 가중치 (종종걸음은 돌아다닐 때만)
    var weight: Double {
        switch self {
        case .hop: 3
        case .doubleHop: 1.2
        case .wiggle: 2
        case .lookAround: 2.2
        case .wave: 1.5
        case .stretch: 1
        case .turnAround: 0.8
        case .waddle: 0
        }
    }
}

struct ActionState: Equatable {
    var action: CharacterAction
    /// timeIntervalSinceReferenceDate
    var start: Double
    var duration: Double

    init(_ action: CharacterAction, start: Double, duration: Double? = nil) {
        self.action = action
        self.start = start
        self.duration = duration ?? action.duration
    }

    func progress(at t: Double) -> Double? {
        let p = (t - start) / max(0.01, duration)
        return (0...1).contains(p) ? p : nil
    }
}

enum CharacterExpression: Equatable {
    case normal, blink, happy, sleepy
}

/// 특정 시점의 포즈. 순수 함수로 계산해 테스트·미리보기에 재사용한다.
struct CharacterPose: Equatable {
    /// 몸통 너비 대비 이동 (y는 음수가 위)
    var offsetX = 0.0
    var offsetY = 0.0
    /// 발을 축으로 기울기(도)
    var tilt = 0.0
    /// 발 기준 찌그러짐/늘어남
    var scaleX = 1.0
    var scaleY = 1.0
    /// 뒤돌기 진행 (1 → −1)
    var turn = 1.0
    var leftArm: Double
    var rightArm: Double
    var leftLeg: Double
    var rightLeg: Double
    /// 발 들기 (몸통 너비 대비)
    var leftLegLift = 0.0
    var rightLegLift = 0.0
    var eyeOpen = 1.0
    var mouthOpen = 0.0
    var lookX = 0.0
    var expression: CharacterExpression = .normal
    /// 공중에 뜬 정도 0~1 (그림자 크기)
    var airborne = 0.0
    /// 머리 기울기(도)·위아래 (파츠 모드에서 머리를 따로 움직일 때)
    var headTilt = 0.0
    var headOffsetY = 0.0

    var bodyOffsetY: Double { offsetY }

    init(rig: CharacterRig) {
        leftArm = rig.leftArm.restAngle
        rightArm = rig.rightArm.restAngle
        leftLeg = rig.leftLeg.restAngle
        rightLeg = rig.rightLeg.restAngle
    }

    static func compute(rig: CharacterRig, mood: CharacterMood, time t: Double, action: ActionState? = nil) -> CharacterPose {
        var pose = CharacterPose(rig: rig)
        let s = max(0.2, rig.speed)
        let sq = max(0, min(1, rig.squash))
        let tau = 2 * Double.pi

        // 깜빡임: 4.3초 주기, 가끔 두 번
        let bp = (t * s).truncatingRemainder(dividingBy: 4.3)
        let cycle = Int(t * s / 4.3)
        let doubleBlink = cycle % 3 == 1
        if (4.05...4.18).contains(bp) || (doubleBlink && (3.78...3.9).contains(bp)) {
            pose.eyeOpen = 0.05
            pose.expression = .blink
        }

        switch mood {
        case .idle:
            // 숨쉬기: 아주 살짝 부풀었다 가라앉기
            let breathe = sin(t * tau * 0.28 * s)
            pose.scaleY = 1 + 0.022 * breathe * (0.5 + sq)
            pose.scaleX = 1 - 0.014 * breathe * (0.5 + sq)
            pose.offsetY = -abs(sin(t * tau * 0.14 * s)) * rig.bobAmount * 0.4
            pose.tilt = sin(t * tau * 0.11 * s) * 1.8
            pose.leftArm += sin(t * tau * 0.28 * s + 0.4) * rig.leftArm.swing * 0.35
            pose.rightArm -= sin(t * tau * 0.28 * s + 1.1) * rig.rightArm.swing * 0.35
            pose.headTilt = sin(t * tau * 0.11 * s - 0.9) * 2.6
            pose.headOffsetY = -breathe * 0.006
        case .listening:
            // 고개를 끄덕이며 귀 기울이기
            let nodPhase = (t * s).truncatingRemainder(dividingBy: 1.8) / 1.8
            let nod = nodPhase < 0.25 ? sin(nodPhase / 0.25 * .pi) : 0
            pose.tilt = 4 + sin(t * tau * 0.2) * 1.5
            pose.scaleY = 1 - 0.035 * nod * (0.5 + sq)
            pose.scaleX = 1 + 0.02 * nod * (0.5 + sq)
            pose.lookX = 0.35
            pose.rightArm = rig.rightArm.restAngle + 18 + sin(t * tau * 0.5) * 4
            pose.leftArm += sin(t * tau * 0.25) * rig.leftArm.swing * 0.3
            pose.headTilt = 6 + nod * 4
            pose.headOffsetY = nod * 0.018
        case .thinking:
            // 갸웃갸웃 + 발 까딱
            pose.tilt = sin(t * tau * 0.35 * s) * 6
            pose.offsetX = sin(t * tau * 0.35 * s) * 0.012
            let tap = max(0, sin(t * tau * 1.8 * s))
            pose.rightLegLift = tap * 0.035
            pose.rightLeg = rig.rightLeg.restAngle + tap * 8
            pose.leftArm = rig.leftArm.restAngle + 30 + sin(t * tau * 0.6) * 6
            pose.lookX = sin(t * tau * 0.25) * 0.9
            pose.headTilt = sin(t * tau * 0.35 * s - 0.5) * 8
        case .talking:
            let beat = abs(sin(t * tau * 1.7 * s))
            pose.offsetY = -beat * 0.018
            pose.scaleY = 1 + 0.035 * beat * sq
            pose.scaleX = 1 - 0.022 * beat * sq
            pose.tilt = sin(t * tau * 0.45) * 3
            pose.rightArm = rig.rightArm.restAngle + 35 + sin(t * tau * 0.95 * s) * 28
            pose.leftArm = rig.leftArm.restAngle - sin(t * tau * 0.7 * s + 1) * 14
            // 불규칙한 입 모양
            pose.mouthOpen = 0.15 + 0.85 * abs(sin(t * 11.3)) * (0.65 + 0.35 * sin(t * 3.1))
            pose.headTilt = sin(t * tau * 0.45 - 0.7) * 4
            pose.headOffsetY = -beat * 0.01
        case .happy:
            let u = (t * 1.15 * s).truncatingRemainder(dividingBy: 1)
            let h = Motion.hop(u, height: rig.jumpHeight * 1.1, squash: sq)
            pose.offsetY = h.y
            pose.scaleX = h.sx
            pose.scaleY = h.sy
            pose.airborne = h.air
            let flap = sin(t * tau * 2.6) * 16
            pose.leftArm = -140 + flap
            pose.rightArm = 140 - flap
            pose.leftLeg = rig.leftLeg.restAngle - h.air * 14
            pose.rightLeg = rig.rightLeg.restAngle + h.air * 14
            pose.expression = .happy
            pose.mouthOpen = 0.75
            pose.headTilt = sin(t * tau * 2.3) * 5
            pose.headOffsetY = h.air * 0.02
        case .sleepy:
            let breathe = sin(t * tau * 0.18)
            pose.scaleY = 1 + 0.045 * breathe * (0.5 + sq)
            pose.scaleX = 1 - 0.03 * breathe * (0.5 + sq)
            pose.tilt = -6 + breathe * 2
            pose.leftArm = rig.leftArm.restAngle * 0.55
            pose.rightArm = rig.rightArm.restAngle * 0.55
            pose.expression = .sleepy
            pose.eyeOpen = 0
            pose.headTilt = -7 + breathe * 2
            pose.headOffsetY = 0.015
        }

        if let action, mood == .idle || mood == .listening, let p = action.progress(at: t) {
            apply(action.action, p, rig: rig, sq: sq, time: t, to: &pose)
        }
        return pose
    }

    private static func apply(_ action: CharacterAction, _ p: Double, rig: CharacterRig, sq: Double, time t: Double,
                              to pose: inout CharacterPose) {
        let tau = 2 * Double.pi
        let ramp = Motion.ramp(p, edge: 0.15)
        switch action {
        case .hop:
            let h = Motion.hop(p, height: rig.jumpHeight, squash: sq)
            pose.offsetY = h.y
            pose.scaleX = h.sx
            pose.scaleY = h.sy
            pose.airborne = h.air
            pose.leftArm = rig.leftArm.restAngle - 45 * h.air + 12 * h.crouch
            pose.rightArm = rig.rightArm.restAngle + 45 * h.air - 12 * h.crouch
            pose.leftLeg = rig.leftLeg.restAngle - 10 * h.air
            pose.rightLeg = rig.rightLeg.restAngle + 10 * h.air
            pose.mouthOpen = 0.45 * h.air
            if h.air > 0.3 { pose.expression = .happy }
            // 머리는 한 박자 늦게: 웅크릴 때 눌리고 떠오를 때 살짝 뒤처짐
            pose.headOffsetY = 0.02 * h.crouch + 0.015 * h.air
        case .doubleHop:
            let first = p < 0.45
            let u = first ? p / 0.45 : (p - 0.45) / 0.55
            let h = Motion.hop(u, height: rig.jumpHeight * (first ? 0.6 : 0.95), squash: sq)
            pose.offsetY = h.y
            pose.scaleX = h.sx
            pose.scaleY = h.sy
            pose.airborne = h.air
            pose.leftArm = rig.leftArm.restAngle - 55 * h.air
            pose.rightArm = rig.rightArm.restAngle + 55 * h.air
            pose.mouthOpen = 0.6 * h.air
            if h.air > 0.2 { pose.expression = .happy }
        case .wiggle:
            let env = sin(Double.pi * p)
            let w = sin(p * tau * 4.5)
            pose.tilt = w * 10 * env
            pose.offsetX = w * 0.025 * env
            pose.scaleY = 1 - 0.04 * abs(w) * env * sq
            pose.scaleX = 1 + 0.03 * abs(w) * env * sq
            pose.leftArm = rig.leftArm.restAngle - 30 * env + w * 15
            pose.rightArm = rig.rightArm.restAngle + 30 * env + w * 15
            pose.leftLegLift = max(0, w) * 0.025 * env
            pose.rightLegLift = max(0, -w) * 0.025 * env
            pose.expression = env > 0.3 ? .happy : pose.expression
            pose.mouthOpen = 0.5 * env
            pose.headTilt = -sin(p * tau * 4.5 - 0.8) * 7 * env
        case .lookAround:
            let lean = Motion.keyframes(p, [(0, 0), (0.15, -1), (0.4, -1), (0.55, 1), (0.82, 1), (1, 0)])
            pose.tilt = lean * 7
            pose.offsetX = lean * 0.02
            pose.lookX = lean
            pose.headTilt = lean * 10
            pose.scaleY = 1 + 0.015 * abs(lean) * sq
            let curious = Motion.keyframes(p, [(0, 0), (0.15, 1), (0.85, 1), (1, 0)])
            pose.leftArm = rig.leftArm.restAngle + 15 * curious
            pose.rightArm = rig.rightArm.restAngle - 15 * curious
        case .wave:
            pose.rightArm = rig.rightArm.restAngle + (125 + sin(p * tau * 3.2) * 22) * ramp
            pose.tilt = -4 * ramp
            pose.headTilt = -6 * ramp + sin(p * tau * 1.6) * 2 * ramp
            pose.offsetY = -abs(sin(p * tau * 1.6)) * 0.015 * ramp
            pose.mouthOpen = 0.45 * ramp
            if ramp > 0.5 { pose.expression = .happy }
        case .stretch:
            let up = Motion.keyframes(p, [(0, 0), (0.35, 1), (0.65, 1), (0.8, 0), (1, 0)])
            let settle = p > 0.8 ? Motion.wobble((p - 0.8) / 0.2, freq: 1.5, decay: 4) : 0
            pose.scaleY = 1 + 0.12 * up * (0.4 + sq) + 0.05 * settle * sq
            pose.scaleX = 1 - 0.07 * up * (0.4 + sq) - 0.03 * settle * sq
            pose.leftArm = rig.leftArm.restAngle + (-150 - rig.leftArm.restAngle) * up
            pose.rightArm = rig.rightArm.restAngle + (150 - rig.rightArm.restAngle) * up
            pose.leftLegLift = 0
            pose.tilt = sin(p * tau) * 2
            pose.headTilt = sin(p * tau) * 6
            pose.headOffsetY = -0.02 * up
            if up > 0.4 { pose.expression = .sleepy; pose.eyeOpen = 0 }
            pose.mouthOpen = Motion.keyframes(p, [(0, 0), (0.3, 0), (0.45, 0.95), (0.62, 0.9), (0.75, 0), (1, 0)])
        case .turnAround:
            pose.turn = cos(Double.pi * p)
            let lift = sin(Double.pi * p)
            pose.offsetY = -lift * 0.07
            pose.airborne = lift * 0.3
            pose.scaleY = 1 + 0.05 * lift * sq
            pose.leftArm = rig.leftArm.restAngle - 25 * lift
            pose.rightArm = rig.rightArm.restAngle + 25 * lift
        case .waddle:
            let step = t * tau * 2.3
            let contact = 1 - abs(sin(step))
            pose.offsetY = -abs(sin(step)) * 0.04
            pose.tilt = sin(step) * 5
            pose.scaleY = 1 - 0.045 * contact * sq
            pose.scaleX = 1 + 0.03 * contact * sq
            pose.leftLegLift = max(0, sin(step)) * 0.05
            pose.rightLegLift = max(0, -sin(step)) * 0.05
            pose.leftLeg = rig.leftLeg.restAngle - sin(step) * 8
            pose.rightLeg = rig.rightLeg.restAngle - sin(step) * 8
            pose.leftArm = rig.leftArm.restAngle + sin(step) * 20
            pose.rightArm = rig.rightArm.restAngle + sin(step) * 20
            pose.airborne = abs(sin(step)) * 0.2
            pose.headTilt = -sin(step - 0.6) * 3.5
        }
    }
}

/// 애니메이션 곡선
enum Motion {
    static func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

    static func easeInOut(_ x: Double) -> Double {
        let x = clamp01(x)
        return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }

    /// 시작·끝을 부드럽게 0→1→0
    static func ramp(_ p: Double, edge: Double) -> Double {
        min(easeInOut(p / edge), easeInOut((1 - p) / edge))
    }

    /// 감쇠 진동 (착지 후 출렁임)
    static func wobble(_ x: Double, freq: Double, decay: Double) -> Double {
        exp(-decay * x) * sin(2 * .pi * freq * x)
    }

    /// (진행도, 값) 키프레임 사이를 부드럽게 보간
    static func keyframes(_ p: Double, _ frames: [(Double, Double)]) -> Double {
        guard let first = frames.first else { return 0 }
        if p <= first.0 { return first.1 }
        for i in 1..<frames.count {
            let (p0, v0) = frames[i - 1], (p1, v1) = frames[i]
            if p <= p1 {
                let u = p1 > p0 ? (p - p0) / (p1 - p0) : 1
                return v0 + (v1 - v0) * easeInOut(u)
            }
        }
        return frames.last!.1
    }

    struct Hop { var y: Double; var sx: Double; var sy: Double; var air: Double; var crouch: Double }

    /// 깡총 한 번: 웅크림 → 늘어나며 도약 → 찌그러지며 착지 → 출렁
    static func hop(_ u: Double, height: Double, squash sq: Double) -> Hop {
        let u = clamp01(u)
        switch u {
        case ..<0.2:
            let a = easeInOut(u / 0.2)
            return Hop(y: 0, sx: 1 + 0.12 * sq * a, sy: 1 - 0.17 * sq * a, air: 0, crouch: a)
        case ..<0.7:
            let a = (u - 0.2) / 0.5
            let arc = 4 * a * (1 - a)
            let s = abs(1 - 2 * a)
            return Hop(y: -height * arc, sx: 1 - 0.09 * sq * s, sy: 1 + 0.14 * sq * s, air: arc, crouch: 0)
        case ..<0.84:
            let b = (u - 0.7) / 0.14
            let k = sin(.pi * b)
            return Hop(y: 0, sx: 1 - 0.09 * sq * (1 - b) + 0.17 * sq * k, sy: 1 + 0.14 * sq * (1 - b) - 0.24 * sq * k,
                       air: 0, crouch: k)
        default:
            let c = (u - 0.84) / 0.16
            let w = wobble(c, freq: 1.2, decay: 3.5)
            return Hop(y: 0, sx: 1 - 0.04 * sq * w, sy: 1 + 0.06 * sq * w, air: 0, crouch: 0)
        }
    }
}
