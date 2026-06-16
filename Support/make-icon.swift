import AppKit

func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx

    // Rounded-rect (squircle-ish) blue tile with a little canvas margin, like
    // a native macOS app icon.
    let margin = size * 0.085
    let rect = NSRect(x: margin, y: margin, width: size - 2*margin, height: size - 2*margin)
    let radius = rect.width * 0.2237
    let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let grad = NSGradient(
        starting: NSColor(calibratedRed: 0.27, green: 0.56, blue: 1.0, alpha: 1),
        ending: NSColor(calibratedRed: 0.00, green: 0.38, blue: 0.93, alpha: 1)
    )!
    grad.draw(in: tile, angle: -90)

    // Hand-wave emoji, centered.
    let emoji = "👋"
    let fontSize = size * 0.52
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize),
        .paragraphStyle: style,
    ]
    let str = NSAttributedString(string: emoji, attributes: attrs)
    let textSize = str.size()
    str.draw(at: NSPoint(x: (size - textSize.width)/2, y: (size - textSize.height)/2))

    ctx.flushGraphics()
    return rep
}

let sizes = CommandLine.arguments.dropFirst().compactMap { Int($0) }
for px in sizes {
    let rep = renderIcon(size: CGFloat(px))
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "/tmp/icon_\(px).png"))
    print("wrote /tmp/icon_\(px).png")
}
