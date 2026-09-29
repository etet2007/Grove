import AppKit
import CoreGraphics
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/MyGitIcon.png")
let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo)!
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

let background = CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                        cornerWidth: 196, cornerHeight: 196, transform: nil)
context.addPath(background)
context.clip()
let gradient = CGGradient(colorsSpace: colorSpace,
                          colors: [color(0.105, 0.18, 0.23), color(0.045, 0.085, 0.13)] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 140, y: 900),
                           end: CGPoint(x: 880, y: 100), options: [])

// A restrained highlight gives the tile some depth at Dock size.
let glow = CGGradient(colorsSpace: colorSpace,
                      colors: [color(0.23, 0.70, 0.65, 0.22), color(0.23, 0.70, 0.65, 0)] as CFArray,
                      locations: [0, 1])!
context.drawRadialGradient(glow, startCenter: CGPoint(x: 740, y: 800), startRadius: 0,
                           endCenter: CGPoint(x: 740, y: 800), endRadius: 520, options: [])

func stroke(_ path: CGPath, width: CGFloat, shade: CGColor) {
    context.addPath(path)
    context.setStrokeColor(shade)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
}

let cream = color(0.94, 0.96, 0.92)
let mint = color(0.37, 0.88, 0.74)

// The open upper-right curve and inset crossbar keep the "G" readable at 16 px.
let letter = CGMutablePath()
letter.move(to: CGPoint(x: 700, y: 690))
letter.addCurve(to: CGPoint(x: 400, y: 715), control1: CGPoint(x: 600, y: 790),
                control2: CGPoint(x: 475, y: 760))
letter.addCurve(to: CGPoint(x: 300, y: 510), control1: CGPoint(x: 325, y: 670),
                control2: CGPoint(x: 300, y: 600))
letter.addCurve(to: CGPoint(x: 395, y: 310), control1: CGPoint(x: 300, y: 415),
                control2: CGPoint(x: 320, y: 340))
letter.addCurve(to: CGPoint(x: 690, y: 330), control1: CGPoint(x: 485, y: 260),
                control2: CGPoint(x: 610, y: 275))
letter.addLine(to: CGPoint(x: 690, y: 500))
letter.addLine(to: CGPoint(x: 555, y: 500))
stroke(letter, width: 82, shade: cream)

// One small accent node hints at Git history without changing the letterform.
context.setFillColor(mint)
context.fillEllipse(in: CGRect(x: 505, y: 450, width: 100, height: 100))

let image = context.makeImage()!
let representation = NSBitmapImageRep(cgImage: image)
try representation.representation(using: .png, properties: [:])!.write(to: output)
