#!/usr/bin/env swift
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders a credit-pack icon: the Pay Day gold coin with the credit count
// engraved on it, on the same dark graphite gradient, with a scatter of coins
// that grows with the tier. Matches scripts/render-icon.swift. 1024×1024, opaque.
//   usage: render-pack-icons.swift <credits> <scatterCount> <out.png>

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

let args = CommandLine.arguments
let credits = args.count > 1 ? args[1] : "30"
let scatter = args.count > 2 ? Int(args[2]) ?? 3 : 3
let out = args.count > 3 ? args[3] : FileManager.default.currentDirectoryPath + "/pack.png"

guard let ctx = CGContext(
    data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("context") }

let bg = CGGradient(colorsSpace: cs, colors: [
    rgb(0.122, 0.129, 0.165), rgb(0.043, 0.047, 0.063)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

let center = CGPoint(x: S / 2, y: S / 2)

// Scatter grows with the tier — a deterministic spread so the visual reads as
// "more credits" without randomness (Date/random are unavailable in scripts).
let spots: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (770, 790, 46, 0.22), (250, 250, 34, 0.16), (815, 300, 24, 0.13),
    (210, 760, 40, 0.18), (840, 560, 28, 0.14), (180, 500, 22, 0.12),
    (560, 850, 30, 0.15), (470, 165, 26, 0.13), (880, 800, 20, 0.11),
    (150, 360, 18, 0.10),
]
for s in spots.prefix(max(3, scatter)) {
    ctx.addEllipse(in: CGRect(x: s.0 - s.2, y: s.1 - s.2, width: s.2 * 2, height: s.2 * 2))
    ctx.setFillColor(rgb(0.914, 0.698, 0.227, s.3))
    ctx.fillPath()
}

let coinR: CGFloat = 332
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - coinR, y: center.y - coinR, width: coinR * 2, height: coinR * 2))
ctx.clip()
let gold = CGGradient(colorsSpace: cs, colors: [
    rgb(1.0, 0.925, 0.690), rgb(0.945, 0.741, 0.275), rgb(0.706, 0.490, 0.082)] as CFArray,
    locations: [0, 0.55, 1])!
ctx.drawRadialGradient(gold, startCenter: CGPoint(x: center.x - 90, y: center.y + 120), startRadius: 10,
    endCenter: center, endRadius: coinR * 1.05, options: [.drawsAfterEndLocation])
ctx.restoreGState()

ctx.addEllipse(in: CGRect(x: center.x - (coinR - 26), y: center.y - (coinR - 26),
                          width: (coinR - 26) * 2, height: (coinR - 26) * 2))
ctx.setStrokeColor(rgb(0.478, 0.329, 0.063, 0.55))
ctx.setLineWidth(14)
ctx.strokePath()

// Engrave the credit number (sized to fit the coin) + a small "CREDITS" label.
func stamp(_ text: String, size: CGFloat, dy: CGFloat, color: CGColor, tracking: CGFloat = 0) {
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    let chars = Array(text.utf16)
    var glyphs = [CGGlyph](repeating: 0, count: chars.count)
    CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
    var adv = [CGSize](repeating: .zero, count: chars.count)
    CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &adv, chars.count)
    let path = CGMutablePath()
    var x: CGFloat = 0
    for i in 0..<glyphs.count {
        if let gp = CTFontCreatePathForGlyph(font, glyphs[i], nil) {
            path.addPath(gp, transform: CGAffineTransform(translationX: x, y: 0))
        }
        x += adv[i].width + tracking
    }
    let b = path.boundingBox
    ctx.saveGState()
    ctx.translateBy(x: center.x - b.midX, y: center.y - b.midY + dy)
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
}

let numSize: CGFloat = credits.count >= 3 ? 300 : 380
stamp(credits, size: numSize, dy: 40, color: rgb(1.0, 0.965, 0.86, 0.30)) // highlight
ctx.saveGState(); ctx.translateBy(x: 0, y: -6)
stamp(credits, size: numSize, dy: 40, color: rgb(0.231, 0.149, 0.024, 1))  // engraved number
ctx.restoreGState()
stamp("CREDITS", size: 86, dy: -150, color: rgb(0.231, 0.149, 0.024, 0.92), tracking: 8)

guard let image = ctx.makeImage() else { fatalError("image") }
guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
    UTType.png.identifier as CFString, 1, nil) else { fatalError("dest") }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
