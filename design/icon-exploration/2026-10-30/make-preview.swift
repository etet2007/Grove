import AppKit
import Foundation

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let w = 960, h = 650
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
func fill(_ rect: NSRect, _ color: NSColor) { color.setFill(); rect.fill() }
func label(_ text: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 14, color: NSColor = .white) {
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
}
fill(NSRect(x: 0, y: 0, width: w, height: h), NSColor(white: 0.10, alpha: 1))
label("MyGit / Three icon directions", 28, 610, size: 24)
label("16 / 32 / 64 px samples · simulated macOS mask · no native Dark variant", 28, 580, size: 13, color: .lightGray)
let files = ["A-branch-rail", "B-working-layers", "C-confluence"]
let titles = ["A / Branch rail", "B / Working layers", "C / Confluence"]
for i in 0..<3 {
    let x = CGFloat(i * 320)
    let source = NSImage(contentsOf: dir.appendingPathComponent(files[i] + ".png"))!
    func icon(_ rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.height * 0.22).addClip()
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
    label(titles[i], x + 28, 539, size: 18)
    icon(NSRect(x: x + 72, y: 330, width: 176, height: 176))
    for (row, light) in [false, true].enumerated() {
        let y = CGFloat(182 - row * 142)
        fill(NSRect(x: x + 16, y: y, width: 288, height: 124), NSColor(white: light ? 0.93 : 0.19, alpha: 1))
        label(light ? "Light surrounding" : "Dark surrounding", x + 28, y + 98, size: 12, color: light ? .darkGray : .lightGray)
        for (j, s) in [16, 32, 64].enumerated() {
            let center = x + CGFloat(60 + j * 96)
            icon(NSRect(x: center - CGFloat(s)/2, y: y + 25, width: CGFloat(s), height: CGFloat(s)))
            label("\(s) px", center - 17, y + 6, size: 10, color: light ? .darkGray : .lightGray)
        }
    }
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("comparison.png"))
