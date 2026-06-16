import AppKit

// Logical window size (points). Rendered @2x for retina crispness.
let W: CGFloat = 600, H: CGFloat = 400, scale: CGFloat = 2

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(W*scale), pixelsHigh: Int(H*scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
ctx.cgContext.scaleBy(x: scale, y: scale)

// Plain light fill.
NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.98, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// A single arrow from the app toward Applications, level with the icon row.
let iconY: CGFloat = 195
let arrowColor = NSColor(calibratedRed: 0.55, green: 0.60, blue: 0.70, alpha: 1)
arrowColor.setStroke()
arrowColor.setFill()
let shaft = NSBezierPath()
shaft.lineWidth = 9
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 250, y: iconY))
shaft.line(to: NSPoint(x: 340, y: iconY))
shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 366, y: iconY))
head.line(to: NSPoint(x: 338, y: iconY + 17))
head.line(to: NSPoint(x: 338, y: iconY - 17))
head.close()
head.fill()

ctx.flushGraphics()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Support/dmg-background.png"))
print("wrote dmg background")
