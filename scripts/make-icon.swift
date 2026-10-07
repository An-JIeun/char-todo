// 뉴트로 플로피 디스크 앱 아이콘을 코드로 그려 PNG로 저장한다.
// 사용: swift scripts/make-icon.swift <출력 폴더>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func hex(_ s: String) -> NSColor {
    let v = UInt64(s.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: (1024 - y - h) * s, width: w * s, height: h * s) }
    let ink = hex("#2B2118")

    // 배경 (둥근 사각 + 크림 + 도트)
    let bg = NSBezierPath(roundedRect: r(64, 64, 896, 896), xRadius: 190 * s, yRadius: 190 * s)
    hex("#FFF3E0").setFill(); bg.fill()
    NSGraphicsContext.current?.saveGraphicsState()
    bg.addClip()
    hex("#FFD23F").setFill()
    NSBezierPath(rect: r(64, 700, 896, 260)).fill()
    hex("#2B2118").withAlphaComponent(0.08).setFill()
    var y: CGFloat = 80
    while y < 960 { var x: CGFloat = 80; while x < 960 { NSBezierPath(ovalIn: r(x, y, 10, 10)).fill(); x += 48 }; y += 48 }
    NSGraphicsContext.current?.restoreGraphicsState()
    ink.setStroke(); bg.lineWidth = 22 * s; bg.stroke()

    // 그림자 + 플로피 몸통
    ink.setFill()
    NSBezierPath(roundedRect: r(262, 222, 520, 520), xRadius: 40 * s, yRadius: 40 * s).fill()
    let body = NSBezierPath(roundedRect: r(242, 202, 520, 520), xRadius: 40 * s, yRadius: 40 * s)
    hex("#FF5C93").setFill(); body.fill()
    ink.setStroke(); body.lineWidth = 18 * s; body.stroke()
    // 셔터
    let shutter = NSBezierPath(roundedRect: r(372, 202, 260, 190), xRadius: 12 * s, yRadius: 12 * s)
    hex("#C9CED6").setFill(); shutter.fill(); shutter.lineWidth = 14 * s; shutter.stroke()
    ink.setFill(); NSBezierPath(rect: r(530, 232, 56, 124)).fill()
    // 라벨
    let label = NSBezierPath(roundedRect: r(300, 440, 404, 250), xRadius: 18 * s, yRadius: 18 * s)
    hex("#FFFDF5").setFill(); label.fill(); label.lineWidth = 14 * s; label.stroke()
    // 얼굴
    ink.setFill()
    NSBezierPath(ovalIn: r(400, 500, 40, 52)).fill()
    NSBezierPath(ovalIn: r(564, 500, 40, 52)).fill()
    hex("#FF7FA0").withAlphaComponent(0.6).setFill()
    NSBezierPath(ovalIn: r(352, 568, 60, 26)).fill()
    NSBezierPath(ovalIn: r(592, 568, 60, 26)).fill()
    let smile = NSBezierPath()
    smile.move(to: NSPoint(x: 462 * s, y: (1024 - 590) * s))
    smile.curve(to: NSPoint(x: 542 * s, y: (1024 - 590) * s), controlPoint1: NSPoint(x: 480 * s, y: (1024 - 640) * s), controlPoint2: NSPoint(x: 524 * s, y: (1024 - 640) * s))
    smile.lineWidth = 16 * s; smile.lineCapStyle = .round; ink.setStroke(); smile.stroke()
    // 팔 (체크 표시를 든 손)
    let arm = NSBezierPath()
    arm.move(to: NSPoint(x: 762 * s, y: (1024 - 470) * s))
    arm.curve(to: NSPoint(x: 850 * s, y: (1024 - 330) * s), controlPoint1: NSPoint(x: 820 * s, y: (1024 - 470) * s), controlPoint2: NSPoint(x: 850 * s, y: (1024 - 400) * s))
    arm.lineWidth = 26 * s; arm.lineCapStyle = .round; arm.stroke()
    let hand = NSBezierPath(ovalIn: r(818, 290, 64, 64)); NSColor.white.setFill(); hand.fill(); hand.lineWidth = 12 * s; hand.stroke()
    let arm2 = NSBezierPath()
    arm2.move(to: NSPoint(x: 242 * s, y: (1024 - 480) * s))
    arm2.curve(to: NSPoint(x: 170 * s, y: (1024 - 600) * s), controlPoint1: NSPoint(x: 190 * s, y: (1024 - 490) * s), controlPoint2: NSPoint(x: 170 * s, y: (1024 - 540) * s))
    arm2.lineWidth = 26 * s; arm2.lineCapStyle = .round; arm2.stroke()
    let hand2 = NSBezierPath(ovalIn: r(138, 590, 64, 64)); hand2.fill(); hand2.lineWidth = 12 * s; hand2.stroke()
    // 다리
    for (x, dx) in [(400.0, -30.0), (604.0, 30.0)] {
        let leg = NSBezierPath()
        leg.move(to: NSPoint(x: x * s, y: (1024 - 722) * s))
        leg.line(to: NSPoint(x: (x + dx * 0.3) * s, y: (1024 - 820) * s))
        leg.lineWidth = 26 * s; leg.lineCapStyle = .round; leg.stroke()
        ink.setFill()
        NSBezierPath(roundedRect: r(x + dx * 0.3 - 50 + dx, 806, 100, 44), xRadius: 22 * s, yRadius: 22 * s).fill()
    }
    // 체크 배지
    let badge = NSBezierPath(ovalIn: r(700, 120, 190, 190))
    hex("#3CCFB4").setFill(); badge.fill(); ink.setStroke(); badge.lineWidth = 16 * s; badge.stroke()
    let check = NSBezierPath()
    check.move(to: NSPoint(x: 748 * s, y: (1024 - 214) * s))
    check.line(to: NSPoint(x: 785 * s, y: (1024 - 252) * s))
    check.line(to: NSPoint(x: 848 * s, y: (1024 - 172) * s))
    check.lineWidth = 26 * s; check.lineCapStyle = .round; check.lineJoinStyle = .round; NSColor.white.setStroke(); check.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let rep = draw(size: CGFloat(px))
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}
print("icons written to \(outDir)")
