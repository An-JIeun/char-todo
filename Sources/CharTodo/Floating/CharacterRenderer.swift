import SwiftUI

/// 캐릭터 캔버스 배치 계산 (몸통 위치와 팔다리 여유 공간)
struct CharacterLayout: Equatable {
    var bodySize: CGSize
    var canvasSize: CGSize
    var bodyOrigin: CGPoint

    init(rig: CharacterRig, aspect: Double, scale: CGFloat = 1) {
        let w = CGFloat(rig.size) * scale
        let h = w * CGFloat(aspect)
        let arms = [rig.leftArm, rig.rightArm].filter(\.enabled)
        let legs = [rig.leftLeg, rig.rightLeg].filter(\.enabled)
        let armReach = CGFloat(arms.map(\.length).max() ?? 0.1)
        let legReach = CGFloat(legs.map { $0.length + max(0, $0.anchor.y - 1) }.max() ?? 0)
        let side = w * (armReach + 0.18)
        let top = w * (max(armReach * 0.9, CGFloat(rig.jumpHeight) * 1.15) + 0.3)
        let bottom = w * (legReach + 0.16)
        bodySize = CGSize(width: w, height: h)
        canvasSize = CGSize(width: ceil(w + side * 2), height: ceil(top + h + bottom))
        bodyOrigin = CGPoint(x: side, y: top)
    }
}

/// GraphicsContext 위에 캐릭터 한 프레임을 그린다.
struct CharacterRenderer {
    var rig: CharacterRig
    var pose: CharacterPose
    var layout: CharacterLayout
    var image: Image?
    var bodyColor: Color
    var mood: CharacterMood
    var time: Double
    /// 바라보는 방향 (1 오른쪽 기본, −1 뒤집힘)
    var facing: Double = 1
    /// 파츠 분리 결과 (있으면 다듬은 조각으로 그린다)
    var puppetBody: Image? = nil
    var puppetParts: [String: Image] = [:]
    /// 이미지 얼굴의 실제 눈 영역 (몸통 단위 좌표, [왼, 오른])
    var eyeRects: [CGRect]? = nil
    /// 눈 모양대로 칠한 피부색 가림막 (눈썹은 비어 있음)
    var eyeCover: Image? = nil

    private var W: CGFloat { layout.bodySize.width }
    private var H: CGFloat { layout.bodySize.height }

    func draw(in ctx: inout GraphicsContext) {
        let limbColor = Color(hex: rig.limbColorHex) ?? .black
        let usesCutout = rig.limbMode == .cutout && image != nil
        let legDrop = usesCutout ? 0 : W * CGFloat(max(rig.leftLeg.length, rig.rightLeg.length))
        let groundY = layout.bodyOrigin.y + H + legDrop + W * 0.03

        // 바닥 그림자: 높이 뜰수록 작고 옅게
        let air = CGFloat(max(pose.airborne, -pose.offsetY / max(0.05, rig.jumpHeight)))
        let shadowW = W * (0.82 - min(0.45, air * 0.45))
        let shadowX = layout.bodyOrigin.x + W / 2 + CGFloat(pose.offsetX) * W - shadowW / 2
        ctx.fill(Path(ellipseIn: CGRect(x: shadowX, y: groundY - W * 0.035, width: shadowW, height: W * 0.07)),
                 with: .color(.black.opacity(0.16 - Double(min(0.45, air * 0.45)) * 0.2)))

        // 몸통 좌표계: (0,0) = 몸통 왼쪽 위. 발(아래 가운데)을 축으로 기울고 늘어난다.
        var body = ctx
        body.translateBy(x: layout.bodyOrigin.x + W / 2 + CGFloat(pose.offsetX) * W,
                         y: layout.bodyOrigin.y + H + CGFloat(pose.offsetY) * W)
        body.rotate(by: .degrees(pose.tilt))
        body.scaleBy(x: CGFloat(pose.scaleX * pose.turn * facing), y: CGFloat(pose.scaleY))
        body.translateBy(x: -W / 2, y: -H)

        let rect = CGRect(origin: .zero, size: layout.bodySize)
        if usesCutout, let puppetBody {
            drawPuppet(&body, bodyImage: puppetBody, rect: rect)
        } else if usesCutout, let image {
            drawCutout(&body, image: image, rect: rect)
            if rig.face.enabled { drawFace(&body) }
        } else {
            if !rig.limbsInFront { drawLimbs(&body, color: limbColor) }
            if let image { body.draw(image, in: rect) } else { drawSkin(&body, rect: rect) }
            if rig.limbsInFront { drawLimbs(&body, color: limbColor) }
            if rig.face.enabled { drawFace(&body) }
        }

        if mood == .sleepy { drawZzz(&ctx) }
        if mood == .thinking { drawThinkingDots(&ctx) }
    }

    // MARK: 컷아웃 팔다리 (원본 그림을 잘라 관절처럼 회전)

    private func angle(_ kind: LimbKind) -> Double {
        switch kind {
        case .leftArm: pose.leftArm
        case .rightArm: pose.rightArm
        case .leftLeg: pose.leftLeg
        case .rightLeg: pose.rightLeg
        }
    }

    private func lift(_ kind: LimbKind) -> CGFloat {
        switch kind {
        case .leftLeg: CGFloat(pose.leftLegLift) * W
        case .rightLeg: CGFloat(pose.rightLegLift) * W
        default: 0
        }
    }

    private func pixelRect(_ unit: CGRect) -> CGRect {
        CGRect(x: unit.minX * W, y: unit.minY * H, width: unit.width * W, height: unit.height * H)
    }

    /// 다듬은 파츠로 그리기: 다리(몸 뒤) → 몸통 → 머리(+얼굴) → 팔(몸 앞)
    private func drawPuppet(_ ctx: inout GraphicsContext, bodyImage: Image, rect: CGRect) {
        func piece(_ kind: LimbKind) {
            guard let img = puppetParts[kind.rawValue], rig.limb(kind).enabled else { return }
            let cfg = rig.limb(kind)
            let pivot = CGPoint(x: cfg.anchor.x * W, y: cfg.anchor.y * H)
            var c = ctx
            c.translateBy(x: pivot.x, y: pivot.y - lift(kind))
            c.rotate(by: .degrees(-(angle(kind) - cfg.restAngle)))
            c.translateBy(x: -pivot.x, y: -pivot.y)
            c.draw(img, in: rect)
        }
        piece(.leftLeg)
        piece(.rightLeg)
        ctx.draw(bodyImage, in: rect)

        if let head = puppetParts[PuppetPart.head.rawValue], rig.head.enabled {
            var c = ctx
            let pivot = CGPoint(x: rig.head.pivot.x * W, y: rig.head.pivot.y * H)
            c.translateBy(x: pivot.x, y: pivot.y + CGFloat(pose.headOffsetY) * W)
            c.rotate(by: .degrees(pose.headTilt))
            c.translateBy(x: -pivot.x, y: -pivot.y)
            c.draw(head, in: rect)
            if rig.face.enabled { drawFace(&c) }
        } else if rig.face.enabled {
            drawFace(&ctx)
        }

        piece(.leftArm)
        piece(.rightArm)
    }

    private func drawCutout(_ ctx: inout GraphicsContext, image: Image, rect: CGRect) {
        let limbs = LimbKind.allCases.filter { rig.limb($0).enabled && rig.limb($0).spriteRect != nil }
        // 1) 팔다리 영역을 뺀 몸통
        var bodyLayer = ctx
        var clip = Path(rect.insetBy(dx: -W, dy: -H))
        for kind in limbs { clip.addRect(pixelRect(rig.limb(kind).spriteRect!)) }
        bodyLayer.clip(to: clip, style: FillStyle(eoFill: true))
        bodyLayer.draw(image, in: rect)

        // 2) 다리 → 팔 순서로, anchor를 축으로 회전한 조각
        for kind in [LimbKind.leftLeg, .rightLeg, .leftArm, .rightArm] where limbs.contains(kind) {
            let cfg = rig.limb(kind)
            let pivot = CGPoint(x: cfg.anchor.x * W, y: cfg.anchor.y * H)
            let delta = angle(kind) - cfg.restAngle
            var piece = ctx
            piece.translateBy(x: pivot.x, y: pivot.y - lift(kind))
            piece.rotate(by: .degrees(-delta))
            piece.translateBy(x: -pivot.x, y: -pivot.y)
            piece.clip(to: Path(pixelRect(cfg.spriteRect!)))
            piece.draw(image, in: rect)
        }
    }

    // MARK: 팔다리 (고무호스 스타일)

    private func drawLimbs(_ ctx: inout GraphicsContext, color: Color) {
        // 다리 먼저, 팔은 나중 (팔이 위로 겹치게)
        for kind in [LimbKind.leftLeg, .rightLeg, .leftArm, .rightArm] {
            let cfg = rig.limb(kind)
            guard cfg.enabled else { continue }
            drawLimb(&ctx, cfg: cfg, angle: angle(kind), kind: kind, color: color)
        }
    }

    private func drawLimb(_ ctx: inout GraphicsContext, cfg: LimbConfig, angle: Double, kind: LimbKind, color: Color) {
        let a = CGPoint(x: cfg.anchor.x * W, y: cfg.anchor.y * H - lift(kind))
        let len = CGFloat(cfg.length) * W
        let th = max(2, CGFloat(cfg.thickness) * W)
        let rad = angle * .pi / 180
        let end = CGPoint(x: a.x + CGFloat(sin(rad)) * len, y: a.y + CGFloat(cos(rad)) * len)
        let mid = CGPoint(x: (a.x + end.x) / 2, y: (a.y + end.y) / 2)
        let bend: CGFloat = (kind.isLeft ? 1 : -1) * len * 0.14
        let ctrl = CGPoint(x: mid.x + CGFloat(cos(rad)) * bend, y: mid.y - CGFloat(sin(rad)) * bend)

        var path = Path()
        path.move(to: a)
        path.addQuadCurve(to: end, control: ctrl)

        let fill = rig.limbFillHex.flatMap { Color(hex: $0) }
        let outline = max(1.2, th * 0.2)
        if let fill {
            // 손그림 스타일: 외곽선 + 채움
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: th, lineCap: .round))
            ctx.stroke(path, with: .color(fill), style: StrokeStyle(lineWidth: max(1, th - outline * 2), lineCap: .round))
        } else {
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: th, lineCap: .round))
        }

        if kind.isArm {
            switch rig.handStyle {
            case .glove:
                let r = th * 1.05
                let hand = Path(ellipseIn: CGRect(x: end.x - r, y: end.y - r, width: r * 2, height: r * 2))
                ctx.fill(hand, with: .color(.white))
                ctx.stroke(hand, with: .color(color), lineWidth: max(1.2, th * 0.38))
            case .round:
                let r = th * 0.8
                let hand = Path(ellipseIn: CGRect(x: end.x - r, y: end.y - r, width: r * 2, height: r * 2))
                ctx.fill(hand, with: .color(fill ?? color))
                if fill != nil { ctx.stroke(hand, with: .color(color), lineWidth: outline) }
            case .none:
                break
            }
        } else {
            let dir: CGFloat = kind.isLeft ? -1 : 1
            switch rig.footStyle {
            case .shoe:
                let sw = th * 2.6, sh = th * 1.5
                let shoe = Path(roundedRect: CGRect(x: end.x - sw / 2 + dir * sw * 0.22, y: end.y - sh * 0.45, width: sw, height: sh),
                                cornerRadius: sh / 2)
                ctx.fill(shoe, with: .color(color))
                let shine = Path(ellipseIn: CGRect(x: end.x + dir * sw * 0.2 - sh * 0.18, y: end.y - sh * 0.25, width: sh * 0.36, height: sh * 0.22))
                ctx.fill(shine, with: .color(.white.opacity(0.55)))
            case .round:
                let fw = th * 1.7, fh = th * 1.15
                let foot = Path(ellipseIn: CGRect(x: end.x - fw / 2 + dir * fw * 0.15, y: end.y - fh / 2, width: fw, height: fh))
                ctx.fill(foot, with: .color(fill ?? color))
                if fill != nil { ctx.stroke(foot, with: .color(color), lineWidth: outline) }
            case .none:
                break
            }
        }
    }

    // MARK: 기본 스킨

    private func drawSkin(_ ctx: inout GraphicsContext, rect: CGRect) {
        let outline = Color(hex: "#1E1E1E")!
        let lw = max(1.5, W * 0.03)
        switch rig.skin {
        case .floppy:
            let body = Path(roundedRect: rect, cornerRadius: W * 0.07)
            ctx.fill(body, with: .color(bodyColor))
            ctx.stroke(body, with: .color(outline), lineWidth: lw)
            // 셔터
            let shutter = Path(roundedRect: CGRect(x: W * 0.24, y: 0, width: W * 0.52, height: H * 0.36), cornerRadius: W * 0.02)
            ctx.fill(shutter, with: .color(Color(hex: "#C9CED6")!))
            ctx.stroke(shutter, with: .color(outline), lineWidth: lw * 0.8)
            ctx.fill(Path(CGRect(x: W * 0.54, y: H * 0.06, width: W * 0.11, height: H * 0.23)), with: .color(outline.opacity(0.85)))
            // 라벨
            let label = Path(roundedRect: CGRect(x: W * 0.11, y: H * 0.46, width: W * 0.78, height: H * 0.5), cornerRadius: W * 0.03)
            ctx.fill(label, with: .color(Color(hex: "#FFFDF5")!))
            ctx.stroke(label, with: .color(outline), lineWidth: lw * 0.8)
            ctx.fill(Path(CGRect(x: W * 0.11, y: H * 0.46, width: W * 0.78, height: H * 0.06)), with: .color(bodyColor.opacity(0.6)))
            // 쓰기방지 구멍
            ctx.fill(Path(CGRect(x: W * 0.05, y: H * 0.86, width: W * 0.04, height: W * 0.04)), with: .color(outline.opacity(0.7)))
        case .cassette:
            let body = Path(roundedRect: rect, cornerRadius: W * 0.06)
            ctx.fill(body, with: .color(bodyColor))
            ctx.stroke(body, with: .color(outline), lineWidth: lw)
            let label = Path(roundedRect: CGRect(x: W * 0.07, y: H * 0.08, width: W * 0.86, height: H * 0.6), cornerRadius: W * 0.03)
            ctx.fill(label, with: .color(Color(hex: "#FFF6E0")!))
            ctx.stroke(label, with: .color(outline), lineWidth: lw * 0.7)
            // 색 띠
            ctx.fill(Path(CGRect(x: W * 0.07, y: H * 0.58, width: W * 0.86, height: H * 0.04)), with: .color(Color(hex: "#FF8A3D")!))
            ctx.fill(Path(CGRect(x: W * 0.07, y: H * 0.62, width: W * 0.86, height: H * 0.04)), with: .color(Color(hex: "#FFD23F")!))
            // 릴 창
            let window = Path(roundedRect: CGRect(x: W * 0.22, y: H * 0.70, width: W * 0.56, height: H * 0.17), cornerRadius: H * 0.08)
            ctx.fill(window, with: .color(outline.opacity(0.85)))
            let spin = time * 3
            for cx in [W * 0.34, W * 0.66] {
                let r = H * 0.065
                let reel = Path(ellipseIn: CGRect(x: cx - r, y: H * 0.785 - r, width: r * 2, height: r * 2))
                ctx.fill(reel, with: .color(.white))
                for k in 0..<3 {
                    let ang = spin + Double(k) * 2 * .pi / 3
                    var tooth = Path()
                    tooth.move(to: CGPoint(x: cx, y: H * 0.785))
                    tooth.addLine(to: CGPoint(x: cx + CGFloat(cos(ang)) * r * 0.8, y: H * 0.785 + CGFloat(sin(ang)) * r * 0.8))
                    ctx.stroke(tooth, with: .color(outline), lineWidth: max(1, r * 0.25))
                }
            }
            // 아래 사다리꼴
            var trap = Path()
            trap.move(to: CGPoint(x: W * 0.18, y: H))
            trap.addLine(to: CGPoint(x: W * 0.26, y: H * 0.9))
            trap.addLine(to: CGPoint(x: W * 0.74, y: H * 0.9))
            trap.addLine(to: CGPoint(x: W * 0.82, y: H))
            ctx.stroke(trap, with: .color(outline), lineWidth: lw * 0.7)
        case .tv:
            // 안테나
            for (dx, tip) in [(-1.0, CGPoint(x: W * 0.22, y: -H * 0.32)), (1.0, CGPoint(x: W * 0.74, y: -H * 0.36))] {
                var ant = Path()
                ant.move(to: CGPoint(x: W * 0.48 + CGFloat(dx) * W * 0.02, y: 0))
                ant.addLine(to: tip)
                ctx.stroke(ant, with: .color(outline), lineWidth: lw * 0.8)
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x - lw * 1.4, y: tip.y - lw * 1.4, width: lw * 2.8, height: lw * 2.8)), with: .color(outline))
            }
            let body = Path(roundedRect: rect, cornerRadius: W * 0.08)
            ctx.fill(body, with: .color(bodyColor))
            ctx.stroke(body, with: .color(outline), lineWidth: lw)
            let screenRect = CGRect(x: W * 0.07, y: H * 0.1, width: W * 0.7, height: H * 0.8)
            let screen = Path(roundedRect: screenRect, cornerRadius: W * 0.09)
            ctx.fill(screen, with: .color(Color(hex: "#16281C")!))
            ctx.stroke(screen, with: .color(outline), lineWidth: lw * 0.8)
            // 주사선
            var y = screenRect.minY + 2
            while y < screenRect.maxY - 2 {
                ctx.fill(Path(CGRect(x: screenRect.minX + 3, y: y, width: screenRect.width - 6, height: 0.8)), with: .color(.white.opacity(0.06)))
                y += 3
            }
            ctx.fill(Path(ellipseIn: CGRect(x: screenRect.minX + 4, y: screenRect.minY + 4, width: screenRect.width * 0.35, height: screenRect.height * 0.2)),
                     with: .color(.white.opacity(0.08)))
            // 다이얼
            for (i, cy) in [H * 0.3, H * 0.55].enumerated() {
                let r = W * 0.055
                let knob = Path(ellipseIn: CGRect(x: W * 0.885 - r, y: cy - r, width: r * 2, height: r * 2))
                ctx.fill(knob, with: .color(Color(hex: "#E8D9B8")!))
                ctx.stroke(knob, with: .color(outline), lineWidth: lw * 0.6)
                var tick = Path()
                let ang = Double(i) * 1.3 + 0.4
                tick.move(to: CGPoint(x: W * 0.885, y: cy))
                tick.addLine(to: CGPoint(x: W * 0.885 + CGFloat(cos(ang)) * r * 0.8, y: cy + CGFloat(sin(ang)) * r * 0.8))
                ctx.stroke(tick, with: .color(outline), lineWidth: lw * 0.5)
            }
            for k in 0..<3 {
                ctx.fill(Path(CGRect(x: W * 0.84, y: H * 0.72 + CGFloat(k) * H * 0.05, width: W * 0.09, height: H * 0.02)), with: .color(outline.opacity(0.6)))
            }
        }
    }

    // MARK: 얼굴

    private var faceColor: Color {
        if image == nil && rig.skin == .tv && rig.face.colorHex.uppercased() == "#1E1E1E" { return Color(hex: "#9CFFB5")! }
        return Color(hex: rig.face.colorHex) ?? .black
    }

    private var expression: CharacterExpression {
        if mood == .sleepy { return .sleepy }
        if mood == .happy { return .happy }
        return pose.expression
    }

    private struct FaceGeometry {
        var center: CGPoint
        var spacing: CGFloat
        var eye: CGFloat
        var mouthY: CGFloat
        var mouthW: CGFloat
        var line: CGFloat
    }

    private var geometry: FaceGeometry {
        let f = rig.face
        let es = CGFloat(f.eyeSize) * W
        return FaceGeometry(center: CGPoint(x: f.center.x * W, y: f.center.y * H),
                            spacing: CGFloat(f.eyeSpacing) * W, eye: es,
                            mouthY: f.center.y * H + CGFloat(f.mouthOffset) * W,
                            mouthW: CGFloat(f.mouthWidth) * W, line: max(1.4, es * 0.24))
    }

    private func drawFace(_ ctx: inout GraphicsContext) {
        let g = geometry
        let f = rig.face
        let ink = faceColor
        let overlay = f.style == .overlay

        // 눈
        let found = overlay ? eyeRects.map { $0.map(pixelRect) } : nil
        let closedNow = expression != .normal
        if closedNow, let found, found.count == 2, let eyeCover {
            // 눈 모양 가림막 한 장으로 두 눈만 지운다 (눈썹은 가림막에 없어서 그대로 보인다)
            ctx.draw(eyeCover, in: CGRect(origin: .zero, size: layout.bodySize))
        }
        for (idx, side) in [-1.0, 1.0].enumerated() {
            if let found, found.count == 2 {
                let r = found[idx]
                if closedNow {
                    if eyeCover == nil { coverEye(&ctx, rect: r) }
                    closedEye(&ctx, in: r, ink: ink, line: g.line, smiling: expression == .happy)
                }
                continue
            }
            let ex = g.center.x + CGFloat(side) * g.spacing / 2
            let ey = g.center.y
            switch expression {
            case .blink, .sleepy:
                if overlay { coverEye(&ctx, ex, ey, g) }
                closedEye(&ctx, ex, ey, g, ink: ink, smiling: false)
            case .happy:
                if overlay { coverEye(&ctx, ex, ey, g) }
                closedEye(&ctx, ex, ey, g, ink: ink, smiling: true)
            case .normal:
                if !overlay { openEye(&ctx, ex + CGFloat(pose.lookX) * g.eye * 0.35, ey, g, ink: ink) }
            }
        }

        // 볼터치 (빗금 포함)
        if f.blush {
            for side in [-1.0, 1.0] {
                let bx = g.center.x + CGFloat(side) * (g.spacing / 2 + g.eye * 0.75)
                let by = g.center.y + g.eye * 1.15
                let r = CGRect(x: bx - g.eye * 0.75, y: by - g.eye * 0.33, width: g.eye * 1.5, height: g.eye * 0.66)
                ctx.fill(Path(ellipseIn: r), with: .color(Color(hex: "#FF8FA8")!.opacity(0.5)))
                for k in 0..<3 {
                    var hatch = Path()
                    let hx = r.minX + r.width * (0.3 + CGFloat(k) * 0.2)
                    hatch.move(to: CGPoint(x: hx + g.eye * 0.08, y: r.minY + r.height * 0.25))
                    hatch.addLine(to: CGPoint(x: hx - g.eye * 0.08, y: r.maxY - r.height * 0.25))
                    ctx.stroke(hatch, with: .color(Color(hex: "#E0607E")!.opacity(0.7)), lineWidth: max(0.8, g.line * 0.45))
                }
            }
        }

        // 입
        let open = CGFloat(pose.mouthOpen)
        if f.mouthStyle == .cat {
            if !overlay { catMouthLine(&ctx, g, ink: ink) }
            if open > 0.05 { catMouthOpen(&ctx, g, ink: ink, open: open) }
        } else if open > 0.05 {
            if overlay {
                ctx.fill(Path(ellipseIn: CGRect(x: g.center.x - g.mouthW * 0.75, y: g.mouthY - g.mouthW * 0.45,
                                                width: g.mouthW * 1.5, height: g.mouthW * 0.9)),
                         with: .color(Color(hex: f.skinHex) ?? .white))
            }
            roundMouthOpen(&ctx, g, ink: ink, open: open)
        } else if !overlay {
            var smile = Path()
            smile.move(to: CGPoint(x: g.center.x - g.mouthW / 2, y: g.mouthY - g.mouthW * 0.05))
            let depth: CGFloat = mood == .sleepy ? 0.05 : 0.38
            smile.addQuadCurve(to: CGPoint(x: g.center.x + g.mouthW / 2, y: g.mouthY - g.mouthW * 0.05),
                               control: CGPoint(x: g.center.x, y: g.mouthY + g.mouthW * depth))
            ctx.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: g.line, lineCap: .round))
        }
    }

    /// 찾은 눈 영역만 피부색으로 가린다 (가장자리 1~2px 여유)
    private func coverEye(_ ctx: inout GraphicsContext, rect r: CGRect) {
        let skin = Color(hex: rig.face.skinHex) ?? .white
        let pad = max(1, r.width * 0.12)
        ctx.fill(Path(ellipseIn: r.insetBy(dx: -pad, dy: -pad * 0.8)), with: .color(skin))
    }

    /// 찾은 눈 영역 안에 감은 눈 (깜빡임 ◡ / 웃음 ^)
    private func closedEye(_ ctx: inout GraphicsContext, in r: CGRect, ink: Color, line: CGFloat, smiling: Bool) {
        var p = Path()
        let half = r.width * 0.5
        let y = r.midY + r.height * (smiling ? 0.15 : 0.05)
        p.move(to: CGPoint(x: r.midX - half, y: y))
        p.addQuadCurve(to: CGPoint(x: r.midX + half, y: y),
                       control: CGPoint(x: r.midX, y: smiling ? r.midY - r.height * 0.45 : r.midY + r.height * 0.45))
        ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: max(line, r.width * 0.16), lineCap: .round))
    }

    /// 이미지의 원래 눈을 피부색으로 가린다
    private func coverEye(_ ctx: inout GraphicsContext, _ ex: CGFloat, _ ey: CGFloat, _ g: FaceGeometry) {
        let skin = Color(hex: rig.face.skinHex) ?? .white
        ctx.fill(Path(ellipseIn: CGRect(x: ex - g.eye * 0.82, y: ey - g.eye * 0.85, width: g.eye * 1.64, height: g.eye * 1.9)),
                 with: .color(skin))
    }

    /// 감은 눈: 깜빡임·졸림은 ◡, 웃음은 ^
    private func closedEye(_ ctx: inout GraphicsContext, _ ex: CGFloat, _ ey: CGFloat, _ g: FaceGeometry, ink: Color, smiling: Bool) {
        var p = Path()
        let w = g.eye * 0.62
        if smiling {
            p.move(to: CGPoint(x: ex - w, y: ey + g.eye * 0.28))
            p.addQuadCurve(to: CGPoint(x: ex + w, y: ey + g.eye * 0.28), control: CGPoint(x: ex, y: ey - g.eye * 0.62))
        } else {
            p.move(to: CGPoint(x: ex - w, y: ey + g.eye * 0.05))
            p.addQuadCurve(to: CGPoint(x: ex + w, y: ey + g.eye * 0.05), control: CGPoint(x: ex, y: ey + g.eye * 0.55))
        }
        ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: g.line * 1.05, lineCap: .round))
    }

    /// 직접 그리는 뜬 눈 (하이라이트 두 개)
    private func openEye(_ ctx: inout GraphicsContext, _ ex: CGFloat, _ ey: CGFloat, _ g: FaceGeometry, ink: Color) {
        let es = g.eye
        let open = CGFloat(max(0.15, min(1, pose.eyeOpen)))
        switch rig.face.eyeStyle {
        case .dot, .happy:
            let h = es * 1.3 * open
            ctx.fill(Path(ellipseIn: CGRect(x: ex - es / 2, y: ey - h / 2, width: es, height: h)), with: .color(ink))
            ctx.fill(Path(ellipseIn: CGRect(x: ex - es * 0.22, y: ey - h * 0.36, width: es * 0.32, height: es * 0.32 * open)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: ex + es * 0.06, y: ey + h * 0.1, width: es * 0.16, height: es * 0.16 * open)), with: .color(.white.opacity(0.9)))
        case .oval:
            let ow = es * 1.5, oh = es * 1.9 * open
            let white = Path(ellipseIn: CGRect(x: ex - ow / 2, y: ey - oh / 2, width: ow, height: oh))
            ctx.fill(white, with: .color(.white))
            ctx.stroke(white, with: .color(ink), lineWidth: max(1, es * 0.16))
            let ph = es * 0.95 * open
            ctx.fill(Path(ellipseIn: CGRect(x: ex - es * 0.4, y: ey - ph / 2 + es * 0.1, width: es * 0.8, height: ph)), with: .color(ink))
        case .pixel:
            let h = es * 1.2 * open
            ctx.fill(Path(CGRect(x: ex - es / 2, y: ey - h / 2, width: es, height: h)), with: .color(ink))
            ctx.fill(Path(CGRect(x: ex - es / 2 + es * 0.15, y: ey - h / 2 + es * 0.12, width: es * 0.3, height: es * 0.3 * open)), with: .color(.white.opacity(0.9)))
        }
    }

    /// 고양이 입 ω (닫힌 입)
    private func catMouthLine(_ ctx: inout GraphicsContext, _ g: FaceGeometry, ink: Color) {
        let w = g.mouthW * 0.5, cx = g.center.x, y = g.mouthY
        var p = Path()
        p.move(to: CGPoint(x: cx - w, y: y - w * 0.25))
        p.addQuadCurve(to: CGPoint(x: cx, y: y - w * 0.15), control: CGPoint(x: cx - w * 0.5, y: y + w * 0.55))
        p.addQuadCurve(to: CGPoint(x: cx + w, y: y - w * 0.25), control: CGPoint(x: cx + w * 0.5, y: y + w * 0.55))
        ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: g.line, lineCap: .round, lineJoin: .round))
    }

    /// ω 아래로 벌어지는 분홍 입 + 혀 + 송곳니
    private func catMouthOpen(_ ctx: inout GraphicsContext, _ g: FaceGeometry, ink: Color, open: CGFloat) {
        let cx = g.center.x
        let top = g.mouthY + g.mouthW * 0.1
        let w = g.mouthW * (0.36 + 0.14 * open)
        let h = g.mouthW * (0.25 + 0.55 * open)
        var mouth = Path()
        mouth.move(to: CGPoint(x: cx - w / 2, y: top))
        mouth.addLine(to: CGPoint(x: cx + w / 2, y: top))
        mouth.addCurve(to: CGPoint(x: cx, y: top + h), control1: CGPoint(x: cx + w * 0.55, y: top + h * 0.55),
                       control2: CGPoint(x: cx + w * 0.3, y: top + h))
        mouth.addCurve(to: CGPoint(x: cx - w / 2, y: top), control1: CGPoint(x: cx - w * 0.3, y: top + h),
                       control2: CGPoint(x: cx - w * 0.55, y: top + h * 0.55))
        mouth.closeSubpath()
        ctx.fill(mouth, with: .color(Color(hex: "#9A3B3F")!))
        var tongueCtx = ctx
        tongueCtx.clip(to: mouth)
        tongueCtx.fill(Path(ellipseIn: CGRect(x: cx - w * 0.38, y: top + h * 0.5, width: w * 0.76, height: h * 0.7)),
                       with: .color(Color(hex: "#F49AA6")!))
        if rig.face.fangs {
            for side in [-1.0, 1.0] {
                let fx = cx + CGFloat(side) * w * 0.3
                var fang = Path()
                fang.move(to: CGPoint(x: fx - w * 0.09, y: top))
                fang.addLine(to: CGPoint(x: fx + w * 0.09, y: top))
                fang.addLine(to: CGPoint(x: fx, y: top + max(2, h * 0.3)))
                fang.closeSubpath()
                tongueCtx.fill(fang, with: .color(.white))
            }
        }
        ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: g.line * 0.85, lineJoin: .round))
        catMouthLine(&ctx, g, ink: ink)
    }

    private func roundMouthOpen(_ ctx: inout GraphicsContext, _ g: FaceGeometry, ink: Color, open: CGFloat) {
        let cx = g.center.x, my = g.mouthY, mw = g.mouthW
        let mh = mw * 0.75 * open
        var mouth = Path()
        mouth.move(to: CGPoint(x: cx - mw / 2, y: my - mh * 0.2))
        mouth.addQuadCurve(to: CGPoint(x: cx + mw / 2, y: my - mh * 0.2), control: CGPoint(x: cx, y: my - mh * 0.45))
        mouth.addQuadCurve(to: CGPoint(x: cx - mw / 2, y: my - mh * 0.2), control: CGPoint(x: cx, y: my + mh * 1.25))
        mouth.closeSubpath()
        ctx.fill(mouth, with: .color(Color(hex: "#7A1F2B")!))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - mw * 0.2, y: my + mh * 0.25, width: mw * 0.4, height: mh * 0.35)),
                 with: .color(Color(hex: "#FF7F8F")!))
        ctx.stroke(mouth, with: .color(ink), lineWidth: max(1.2, g.line * 0.75))
    }

    private func drawZzz(_ ctx: inout GraphicsContext) {
        for i in 0..<3 {
            let phase = (time * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let x = layout.bodyOrigin.x + W * (0.85 + CGFloat(phase) * 0.3)
            let y = layout.bodyOrigin.y - W * CGFloat(phase) * 0.35
            ctx.opacity = 1 - phase
            ctx.draw(Text("z").font(.system(size: W * (0.12 + CGFloat(phase) * 0.1), weight: .black, design: .rounded))
                .foregroundColor(.gray), at: CGPoint(x: x, y: y))
        }
        ctx.opacity = 1
    }

    private func drawThinkingDots(_ ctx: inout GraphicsContext) {
        for i in 0..<3 {
            let bounce = sin(time * 6 - Double(i) * 0.7)
            let r = W * 0.035
            let x = layout.bodyOrigin.x + W * 0.35 + CGFloat(i) * W * 0.15
            let y = layout.bodyOrigin.y - W * 0.2 - CGFloat(max(0, bounce)) * W * 0.06
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.gray.opacity(0.85)))
        }
    }
}

/// 애니메이션되는 캐릭터 뷰
struct CharacterView: View {
    var rig: CharacterRig
    var image: NSImage?
    var aspect: Double
    var mood: CharacterMood
    var bodyColor: Color
    var scale: CGFloat = 1
    var animated = true
    var action: ActionState? = nil
    var facing: Double = 1
    var puppet: PuppetImages? = nil
    var eyes: FaceAnalyzer.Eyes? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 40, paused: !animated)) { tl in
            CharacterFrame(rig: rig, image: image, aspect: aspect, mood: mood, bodyColor: bodyColor, scale: scale,
                           time: animated ? tl.date.timeIntervalSinceReferenceDate : 0, action: action, facing: facing,
                           puppet: puppet, eyes: eyes)
        }
    }
}

/// 특정 시각의 한 프레임 (미리보기·스냅샷용으로도 사용)
struct CharacterFrame: View {
    var rig: CharacterRig
    var image: NSImage?
    var aspect: Double
    var mood: CharacterMood
    var bodyColor: Color
    var scale: CGFloat = 1
    var time: Double
    var action: ActionState? = nil
    var facing: Double = 1
    var puppet: PuppetImages? = nil
    var eyes: FaceAnalyzer.Eyes? = nil

    var body: some View {
        let layout = CharacterLayout(rig: rig, aspect: aspect, scale: scale)
        let swiftImage = image.map { Image(nsImage: $0) }
        let pose = CharacterPose.compute(rig: rig, mood: mood, time: time, action: action)
        let usable = puppet?.key == rig.puppetKey ? puppet : nil
        let puppetBody = usable.map { Image(nsImage: $0.body) }
        let puppetParts = usable?.parts.mapValues { Image(nsImage: $0) } ?? [:]
        Canvas { ctx, _ in
            let renderer = CharacterRenderer(rig: rig, pose: pose, layout: layout, image: swiftImage,
                                             bodyColor: bodyColor, mood: mood, time: time, facing: facing,
                                             puppetBody: puppetBody, puppetParts: puppetParts,
                                             eyeRects: eyes?.rects, eyeCover: eyes.map { Image(nsImage: $0.cover) })
            renderer.draw(in: &ctx)
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
    }
}
