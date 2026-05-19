import AppKit
import Foundation

struct IconSlot {
    let idiom: String
    let size: String
    let scale: String
    let filename: String

    var pixels: Int {
        let base = Double(size.split(separator: "x").first ?? "0") ?? 0
        let multiplier = Double(scale.replacingOccurrences(of: "x", with: "")) ?? 1
        return Int((base * multiplier).rounded())
    }
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])

let slots: [IconSlot] = [
    .init(idiom: "iphone", size: "20x20", scale: "2x", filename: "Icon-20@2x.png"),
    .init(idiom: "iphone", size: "20x20", scale: "3x", filename: "Icon-20@3x.png"),
    .init(idiom: "iphone", size: "29x29", scale: "2x", filename: "Icon-29@2x.png"),
    .init(idiom: "iphone", size: "29x29", scale: "3x", filename: "Icon-29@3x.png"),
    .init(idiom: "iphone", size: "40x40", scale: "2x", filename: "Icon-40@2x.png"),
    .init(idiom: "iphone", size: "40x40", scale: "3x", filename: "Icon-40@3x.png"),
    .init(idiom: "iphone", size: "60x60", scale: "2x", filename: "Icon-60@2x.png"),
    .init(idiom: "iphone", size: "60x60", scale: "3x", filename: "Icon-60@3x.png"),
    .init(idiom: "ipad", size: "20x20", scale: "1x", filename: "Icon-20.png"),
    .init(idiom: "ipad", size: "20x20", scale: "2x", filename: "Icon-20-ipad@2x.png"),
    .init(idiom: "ipad", size: "29x29", scale: "1x", filename: "Icon-29.png"),
    .init(idiom: "ipad", size: "29x29", scale: "2x", filename: "Icon-29-ipad@2x.png"),
    .init(idiom: "ipad", size: "40x40", scale: "1x", filename: "Icon-40.png"),
    .init(idiom: "ipad", size: "40x40", scale: "2x", filename: "Icon-40-ipad@2x.png"),
    .init(idiom: "ipad", size: "76x76", scale: "1x", filename: "Icon-76.png"),
    .init(idiom: "ipad", size: "76x76", scale: "2x", filename: "Icon-76@2x.png"),
    .init(idiom: "ipad", size: "83.5x83.5", scale: "2x", filename: "Icon-83.5@2x.png"),
    .init(idiom: "ios-marketing", size: "1024x1024", scale: "1x", filename: "Icon-1024.png")
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawShadowedStroke(_ path: NSBezierPath, color: NSColor, width: CGFloat, shadowOffset: CGSize = .zero) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = width * 0.18
    shadow.shadowOffset = shadowOffset
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    shadow.set()
    color.setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func drawSegment(from start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: start)
    path.curve(to: end, controlPoint1: control1, controlPoint2: control2)
    drawShadowedStroke(path, color: color, width: width, shadowOffset: CGSize(width: 0, height: -8))
}

func drawCapsule(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: NSColor) {
    let rect = NSRect(x: x, y: y, width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 12
    shadow.shadowOffset = CGSize(width: 0, height: -5)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.set()
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func drawCircle(center: CGPoint, radius: CGFloat, color: NSColor) {
    let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 10
    shadow.shadowOffset = CGSize(width: 0, height: -5)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
    shadow.set()
    color.setFill()
    NSBezierPath(ovalIn: rect).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon(size: Int) -> NSImage {
    let canvas = CGFloat(size)
    let s = canvas / 1024
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()

    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()

    let tile = NSRect(x: 102 * s, y: 102 * s, width: 820 * s, height: 820 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 32 * s
    shadow.shadowOffset = CGSize(width: 0, height: -12 * s)
    shadow.shadowColor = color(112, 89, 255, 0.18)
    shadow.set()
    color(251, 249, 255).setFill()
    NSBezierPath(roundedRect: tile, xRadius: 96 * s, yRadius: 96 * s).fill()
    NSGraphicsContext.restoreGraphicsState()

    color(230, 223, 255, 0.7).setStroke()
    let tileBorder = NSBezierPath(roundedRect: tile.insetBy(dx: 3 * s, dy: 3 * s), xRadius: 94 * s, yRadius: 94 * s)
    tileBorder.lineWidth = 2 * s
    tileBorder.stroke()

    let questionWidth = 66 * s
    drawSegment(
        from: CGPoint(x: 205 * s, y: 600 * s),
        control1: CGPoint(x: 166 * s, y: 690 * s),
        control2: CGPoint(x: 250 * s, y: 754 * s),
        end: CGPoint(x: 350 * s, y: 726 * s),
        color: color(255, 73, 75),
        width: questionWidth
    )
    drawSegment(
        from: CGPoint(x: 325 * s, y: 726 * s),
        control1: CGPoint(x: 368 * s, y: 780 * s),
        control2: CGPoint(x: 448 * s, y: 760 * s),
        end: CGPoint(x: 486 * s, y: 696 * s),
        color: color(255, 214, 43),
        width: questionWidth * 0.92
    )
    drawSegment(
        from: CGPoint(x: 430 * s, y: 706 * s),
        control1: CGPoint(x: 502 * s, y: 690 * s),
        control2: CGPoint(x: 530 * s, y: 615 * s),
        end: CGPoint(x: 486 * s, y: 552 * s),
        color: color(136, 64, 238),
        width: questionWidth
    )
    drawSegment(
        from: CGPoint(x: 486 * s, y: 560 * s),
        control1: CGPoint(x: 468 * s, y: 505 * s),
        control2: CGPoint(x: 405 * s, y: 492 * s),
        end: CGPoint(x: 385 * s, y: 430 * s),
        color: color(36, 141, 246),
        width: questionWidth * 0.98
    )
    drawSegment(
        from: CGPoint(x: 385 * s, y: 432 * s),
        control1: CGPoint(x: 360 * s, y: 372 * s),
        control2: CGPoint(x: 392 * s, y: 326 * s),
        end: CGPoint(x: 424 * s, y: 286 * s),
        color: color(47, 197, 80),
        width: questionWidth * 1.02
    )

    drawSegment(
        from: CGPoint(x: 223 * s, y: 548 * s),
        control1: CGPoint(x: 286 * s, y: 580 * s),
        control2: CGPoint(x: 352 * s, y: 552 * s),
        end: CGPoint(x: 413 * s, y: 512 * s),
        color: color(137, 63, 237),
        width: questionWidth * 0.68
    )
    drawSegment(
        from: CGPoint(x: 474 * s, y: 650 * s),
        control1: CGPoint(x: 520 * s, y: 618 * s),
        control2: CGPoint(x: 520 * s, y: 562 * s),
        end: CGPoint(x: 486 * s, y: 518 * s),
        color: color(48, 199, 82),
        width: questionWidth * 0.72
    )

    drawCircle(center: CGPoint(x: 376 * s, y: 218 * s), radius: 45 * s, color: color(138, 62, 237))
    drawSegment(
        from: CGPoint(x: 344 * s, y: 250 * s),
        control1: CGPoint(x: 370 * s, y: 278 * s),
        control2: CGPoint(x: 410 * s, y: 268 * s),
        end: CGPoint(x: 419 * s, y: 231 * s),
        color: color(255, 214, 43),
        width: 32 * s
    )
    drawSegment(
        from: CGPoint(x: 341 * s, y: 203 * s),
        control1: CGPoint(x: 361 * s, y: 178 * s),
        control2: CGPoint(x: 407 * s, y: 175 * s),
        end: CGPoint(x: 421 * s, y: 207 * s),
        color: color(42, 143, 247),
        width: 31 * s
    )
    drawSegment(
        from: CGPoint(x: 381 * s, y: 183 * s),
        control1: CGPoint(x: 402 * s, y: 184 * s),
        control2: CGPoint(x: 417 * s, y: 196 * s),
        end: CGPoint(x: 425 * s, y: 216 * s),
        color: color(255, 72, 75),
        width: 28 * s
    )

    drawCapsule(x: 559 * s, y: 178 * s, width: 26 * s, height: 664 * s, color: color(97, 61, 235))

    let bulletX = 662 * s
    let lineX = 725 * s
    let rowY: [CGFloat] = [725, 610, 495, 380, 265]
    let colors = [
        color(255, 70, 75),
        color(255, 204, 37),
        color(48, 199, 79),
        color(20, 126, 245),
        color(132, 54, 233)
    ]
    for (index, y) in rowY.enumerated() {
        drawCircle(center: CGPoint(x: bulletX, y: y * s), radius: 24 * s, color: colors[index])
        drawCapsule(x: lineX, y: (y - 14) * s, width: 176 * s, height: 28 * s, color: colors[index])
    }

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL, pixels: Int) throws {
    guard
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
        let representation = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "AppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try representation.write(to: url)
    print("Wrote \(url.lastPathComponent) (\(pixels)x\(pixels))")
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let existingFiles = try FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil)
for file in existingFiles where file.pathExtension.lowercased() == "png" {
    try FileManager.default.removeItem(at: file)
}

for slot in slots {
    let icon = drawIcon(size: slot.pixels)
    try writePNG(icon, to: outputDirectory.appendingPathComponent(slot.filename), pixels: slot.pixels)
}

let imageJSON = slots.map { slot -> [String: String] in
    [
        "filename": slot.filename,
        "idiom": slot.idiom,
        "scale": slot.scale,
        "size": slot.size
    ]
}
let contents: [String: Any] = [
    "images": imageJSON,
    "info": [
        "author": "xcode",
        "version": 1
    ]
]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: outputDirectory.appendingPathComponent("Contents.json"))
