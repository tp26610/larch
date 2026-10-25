// 產生 assets/AppIcon.icns：鼠尾草綠圓角方塊 + 三層弧線組成的落葉松。
// 用法：swift scripts/make-icon.swift
import AppKit

func draw(_ ctx: CGContext, size s: CGFloat) {
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // 圖示本體：macOS 規格 824pt 圓角方塊，留邊給陰影
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor(white: 0, alpha: 0.35).cgColor)
    ctx.setFillColor(NSColor(srgbRed: 0.41, green: 0.60, blue: 0.53, alpha: 1).cgColor)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let top = NSColor(srgbRed: 0.55, green: 0.74, blue: 0.65, alpha: 1).cgColor
    let bottom = NSColor(srgbRed: 0.29, green: 0.48, blue: 0.40, alpha: 1).cgColor
    let grad = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // 上緣高光
    let glow = CGGradient(colorsSpace: space,
                          colors: [NSColor(white: 1, alpha: 0.22).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(glow, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
    ctx.restoreGState()

    // 三層疊起來的落葉松（由下到上漸亮）+ 樹幹
    func tone(_ v: CGFloat) -> CGColor { NSColor(srgbRed: v * 0.93, green: v * 0.97, blue: v * 0.95, alpha: 1).cgColor }
    ctx.saveGState()
    ctx.setLineJoin(.round)
    ctx.setLineWidth(30)
    let trunk = CGPath(roundedRect: CGRect(x: 482, y: 270, width: 60, height: 150), cornerWidth: 14, cornerHeight: 14, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 14, color: NSColor(white: 0, alpha: 0.22).cgColor)
    ctx.setFillColor(tone(0.90)); ctx.addPath(trunk); ctx.fillPath()
    ctx.restoreGState()
    let tiers: [(apex: CGFloat, base: CGFloat, half: CGFloat, v: CGFloat)] = [
        (640, 380, 255, 0.93), (725, 505, 190, 0.97), (805, 625, 130, 1.0),
    ]
    for t in tiers {
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: 512, y: t.apex))
        tri.addLine(to: CGPoint(x: 512 + t.half, y: t.base))
        tri.addLine(to: CGPoint(x: 512 - t.half, y: t.base))
        tri.closeSubpath()
        ctx.setFillColor(tone(t.v)); ctx.setStrokeColor(tone(t.v))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 14, color: NSColor(white: 0, alpha: 0.22).cgColor)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(tri); ctx.drawPath(using: .fillStroke)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    draw(gc.cgContext, size: CGFloat(size))
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = "build/AppIcon.iconset"
try? fm.removeItem(atPath: set)
try fm.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
try png(size: 1024).write(to: URL(fileURLWithPath: "build/AppIcon-1024.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set, "-o", "assets/AppIcon.icns"]
try p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "完成：assets/AppIcon.icns" : "iconutil 失敗")
