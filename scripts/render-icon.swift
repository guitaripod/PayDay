#!/usr/bin/env swift
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the Pay Day app icon: a minted gold € coin on a premium dark
// gradient, with a faint scatter of coins (the move scatters coins). Opaque,
// no alpha, 1024×1024 — the single size the asset catalog needs.

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

guard let ctx = CGContext(
    data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("context")
}

// Background: deep graphite vertical gradient (premium, distinct from the
// sea of blue/white invoice apps).
let bg = CGGradient(colorsSpace: cs, colors: [
    rgb(0.122, 0.129, 0.165), rgb(0.043, 0.047, 0.063)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

let center = CGPoint(x: S / 2, y: S / 2)

// Faint scattered coins behind the hero coin.
func scatterCoin(_ p: CGPoint, _ r: CGFloat, _ alpha: CGFloat) {
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    ctx.setFillColor(rgb(0.914, 0.698, 0.227, alpha))
    ctx.fillPath()
    ctx.restoreGState()
}
scatterCoin(CGPoint(x: 770, y: 790), 46, 0.22)
scatterCoin(CGPoint(x: 250, y: 250), 34, 0.16)
scatterCoin(CGPoint(x: 815, y: 300), 24, 0.13)

// Hero coin with a radial gold gradient (highlight offset for a minted feel).
let coinR: CGFloat = 332
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - coinR, y: center.y - coinR, width: coinR * 2, height: coinR * 2))
ctx.clip()
let gold = CGGradient(colorsSpace: cs, colors: [
    rgb(1.0, 0.925, 0.690), rgb(0.945, 0.741, 0.275), rgb(0.706, 0.490, 0.082)] as CFArray,
    locations: [0, 0.55, 1])!
ctx.drawRadialGradient(
    gold, startCenter: CGPoint(x: center.x - 90, y: center.y + 120), startRadius: 10,
    endCenter: center, endRadius: coinR * 1.05, options: [.drawsAfterEndLocation])
ctx.restoreGState()

// Minted rim.
ctx.addEllipse(in: CGRect(x: center.x - (coinR - 26), y: center.y - (coinR - 26),
                          width: (coinR - 26) * 2, height: (coinR - 26) * 2))
ctx.setStrokeColor(rgb(0.478, 0.329, 0.063, 0.55))
ctx.setLineWidth(14)
ctx.strokePath()

// Centered € as a filled glyph path — drawing the path gives exact control of
// fill colour and position (CTLineDraw's colour attribute is unreliable here).
let euroFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 560, nil)
var euroGlyph = CGGlyph(0)
var euroChar = UniChar(0x20AC)
CTFontGetGlyphsForCharacters(euroFont, &euroChar, &euroGlyph, 1)
if let euroPath = CTFontCreatePathForGlyph(euroFont, euroGlyph, nil) {
    let b = euroPath.boundingBox
    func stampEuro(dx: CGFloat, dy: CGFloat, color: CGColor) {
        ctx.saveGState()
        ctx.translateBy(x: center.x - b.midX + dx, y: center.y - b.midY + dy)
        ctx.addPath(euroPath)
        ctx.setFillColor(color)
        ctx.fillPath()
        ctx.restoreGState()
    }
    stampEuro(dx: 0, dy: -7, color: rgb(1.0, 0.965, 0.86, 0.35)) // struck-edge highlight
    stampEuro(dx: 0, dy: 0, color: rgb(0.231, 0.149, 0.024, 1))  // engraved €
}

guard let image = ctx.makeImage() else { fatalError("image") }
let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/icon-1024.png"
let url = URL(fileURLWithPath: out)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("dest")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
