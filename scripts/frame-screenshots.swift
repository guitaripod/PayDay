#!/usr/bin/env swift

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvasWidth: CGFloat = 1320
let canvasHeight: CGFloat = 2868
let sideMargin: CGFloat = 96
let textTop: CGFloat = 150
let titleMaxSize: CGFloat = 92
let titleMinSize: CGFloat = 64
let titleStep: CGFloat = 4
let titleMaxLines = 2
let titleKern: CGFloat = -1.5
let titleLineHeightMultiple: CGFloat = 0.98
let subtitleSize: CGFloat = 44
let subtitleGap: CGFloat = 24
let imageGap: CGFloat = 80
let imageWidth: CGFloat = 1080
let shadowBlur: CGFloat = 60
let shadowYOffset: CGFloat = 28
let shadowAlpha: CGFloat = 0.18
let titleColorHex = "#1A1712"
let subtitleColorHex = "#6B6353"
let backgroundTopHex = "#FAF7F0"
let backgroundBottomHex = "#F1EBDD"

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

struct ScriptError: Error {
    let reason: String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
    exit(1)
}

func warn(_ message: String) {
    FileHandle.standardError.write("warning: \(message)\n".data(using: .utf8)!)
}

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r, g, b, a])!
}

func hexColor(_ hex: String) -> CGColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let value = UInt32(s, radix: 16) else {
        fail("invalid hex color: \(hex)")
    }
    let r = CGFloat((value >> 16) & 0xFF) / 255
    let g = CGFloat((value >> 8) & 0xFF) / 255
    let b = CGFloat(value & 0xFF) / 255
    return rgba(r, g, b, 1)
}

struct Caption {
    let title: String
    let subtitle: String
}

struct LocaleCaptions {
    let order: [String]
    let entries: [String: Caption]
}

/// Loads `<locale>.json`, tolerating a missing/malformed entry for an individual screen (the
/// caller treats that as a skippable screen) but failing on a missing or unparseable file.
func loadCaptions(at url: URL) throws -> LocaleCaptions {
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw ScriptError(reason: "cannot read captions file: \(url.path)")
    }
    let jsonObject: Any
    do {
        jsonObject = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw ScriptError(reason: "malformed captions JSON: \(url.path)")
    }
    guard let root = jsonObject as? [String: Any] else {
        throw ScriptError(reason: "captions JSON root is not an object: \(url.path)")
    }
    guard let order = root["order"] as? [String] else {
        throw ScriptError(reason: "captions file missing \"order\" array: \(url.path)")
    }
    var entries: [String: Caption] = [:]
    for screen in order {
        guard let entry = root[screen] as? [String: Any],
              let title = entry["title"] as? String,
              let subtitle = entry["subtitle"] as? String else {
            continue
        }
        entries[screen] = Caption(title: title, subtitle: subtitle)
    }
    return LocaleCaptions(order: order, entries: entries)
}

struct TextBlock {
    let lines: [CTLine]
    let font: NSFont
    let lineHeight: CGFloat

    var blockHeight: CGFloat { lineHeight * CGFloat(lines.count) }
}

func naturalLineHeight(_ font: NSFont, multiple: CGFloat) -> CGFloat {
    (font.ascender - font.descender + font.leading) * multiple
}

/// Word-wraps `text` at `maxWidth` using CoreText's typesetter directly, so the resulting line
/// count is exact and matches what is later drawn (no separate measure/draw passes to drift).
func wrapIntoLines(_ text: String, font: NSFont, kern: CGFloat, color: CGColor, maxWidth: CGFloat) -> [CTLine] {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .kern: kern,
        .foregroundColor: color,
    ]
    let attributedString = NSAttributedString(string: text, attributes: attributes)
    let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
    let length = attributedString.length
    var lines: [CTLine] = []
    var start = 0
    while start < length {
        var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(maxWidth))
        if count <= 0 { count = 1 }
        lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
        start += count
    }
    return lines
}

/// Steps the title size down from 92pt to 64pt (in 4pt steps) until it wraps to at most two
/// lines. If even 64pt does not fit two lines, keeps 64pt and lets it wrap further — the text is
/// never truncated.
func fitTitleBlock(_ text: String, maxWidth: CGFloat, color: CGColor) -> TextBlock {
    let candidateSizes = Array(stride(from: titleMaxSize, through: titleMinSize, by: -titleStep))
    for size in candidateSizes {
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        let lines = wrapIntoLines(text, font: font, kern: titleKern, color: color, maxWidth: maxWidth)
        if lines.count <= titleMaxLines {
            return TextBlock(lines: lines, font: font, lineHeight: naturalLineHeight(font, multiple: titleLineHeightMultiple))
        }
    }
    let font = NSFont.systemFont(ofSize: titleMinSize, weight: .bold)
    let lines = wrapIntoLines(text, font: font, kern: titleKern, color: color, maxWidth: maxWidth)
    return TextBlock(lines: lines, font: font, lineHeight: naturalLineHeight(font, multiple: titleLineHeightMultiple))
}

func makeSubtitleBlock(_ text: String, maxWidth: CGFloat, color: CGColor) -> TextBlock {
    let font = NSFont.systemFont(ofSize: subtitleSize, weight: .medium)
    let lines = wrapIntoLines(text, font: font, kern: 0, color: color, maxWidth: maxWidth)
    return TextBlock(lines: lines, font: font, lineHeight: naturalLineHeight(font, multiple: 1.0))
}

func drawTextBlock(_ block: TextBlock, in context: CGContext, left: CGFloat, topFromTop: CGFloat) {
    context.saveGState()
    context.textMatrix = .identity
    context.setTextDrawingMode(.fill)
    for (index, line) in block.lines.enumerated() {
        let baselineFromBlockTop = block.lineHeight * CGFloat(index) + block.font.ascender
        let y = canvasHeight - topFromTop - baselineFromBlockTop
        context.textPosition = CGPoint(x: left, y: y)
        CTLineDraw(line, context)
    }
    context.restoreGState()
}

func drawBackground(in context: CGContext) {
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [hexColor(backgroundTopHex), hexColor(backgroundBottomHex)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: canvasHeight),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
}

/// The raw capture inside its device's real bezel, drawn by the `frames` CLI from Apple's bezel art and trimmed to
/// the device itself, so a panel never fakes a device with a rounded rectangle.
func bezeledDevice(rawURL: URL) throws -> CGImage {
    let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("payday-frames-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDir) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["frames", "--json", "-o", workDir.path, rawURL.path]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let path = result["output"] as? String,
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let framed = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ScriptError(reason: "frames failed for \(rawURL.path)")
    }
    return try trimmedToOpaque(framed)
}

/// The image cropped to the bounding box of its non-transparent pixels.
func trimmedToOpaque(_ image: CGImage) throws -> CGImage {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw ScriptError(reason: "cannot read the framed device's pixels")
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY,
          let cropped = image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else {
        throw ScriptError(reason: "the framed device is empty")
    }
    return cropped
}

/// Draws the framed device scaled to `imageWidth` across, with a soft drop shadow under it.
func drawFramedScreenshot(_ device: CGImage, in context: CGContext, topFromTop: CGFloat) {
    let scale = imageWidth / CGFloat(device.width)
    let height = CGFloat(device.height) * scale
    let x = (canvasWidth - imageWidth) / 2
    let yTop = canvasHeight - topFromTop
    let rect = CGRect(x: x, y: yTop - height, width: imageWidth, height: height)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -shadowYOffset), blur: shadowBlur, color: rgba(0, 0, 0, shadowAlpha))
    context.interpolationQuality = .high
    context.draw(device, in: rect)
    context.restoreGState()
}

/// Lays the frame out top to bottom: title, subtitle 24px below it, then the screenshot 80px
/// below the subtitle's last line — so a shorter title/subtitle leaves more of the tall capture
/// visible before the canvas clips its bottom edge.
func composite(device: CGImage, title: String, subtitle: String, in context: CGContext) {
    drawBackground(in: context)

    let contentWidth = canvasWidth - sideMargin * 2
    let titleColor = hexColor(titleColorHex)
    let subtitleColor = hexColor(subtitleColorHex)

    let titleBlock = fitTitleBlock(title, maxWidth: contentWidth, color: titleColor)
    drawTextBlock(titleBlock, in: context, left: sideMargin, topFromTop: textTop)

    let subtitleTop = textTop + titleBlock.blockHeight + subtitleGap
    let subtitleBlock = makeSubtitleBlock(subtitle, maxWidth: contentWidth, color: subtitleColor)
    drawTextBlock(subtitleBlock, in: context, left: sideMargin, topFromTop: subtitleTop)

    let imageTop = subtitleTop + subtitleBlock.blockHeight + imageGap
    drawFramedScreenshot(device, in: context, topFromTop: imageTop)
}

func composeScreenshot(rawURL: URL, title: String, subtitle: String, outURL: URL) throws {
    let device = try bezeledDevice(rawURL: rawURL)

    guard let context = CGContext(
        data: nil,
        width: Int(canvasWidth),
        height: Int(canvasHeight),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw ScriptError(reason: "cannot create bitmap context for \(outURL.path)")
    }

    composite(device: device, title: title, subtitle: subtitle, in: context)

    guard let image = context.makeImage() else {
        throw ScriptError(reason: "cannot finalize rendered image for \(outURL.path)")
    }
    guard image.width == Int(canvasWidth), image.height == Int(canvasHeight) else {
        throw ScriptError(reason: "rendered image is \(image.width)x\(image.height), expected \(Int(canvasWidth))x\(Int(canvasHeight))")
    }

    let outDir = outURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    guard let destination = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ScriptError(reason: "cannot create PNG destination: \(outURL.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ScriptError(reason: "failed to write PNG: \(outURL.path)")
    }
    print("wrote \(outURL.path)")
}

struct Options {
    var rawDir: String?
    var captionsDir: String?
    var outDir: String?
    var locale: String?
    var only: String?
}

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--raw": options.rawDir = iterator.next()
        case "--captions": options.captionsDir = iterator.next()
        case "--out": options.outDir = iterator.next()
        case "--locale": options.locale = iterator.next()
        case "--only": options.only = iterator.next()
        default: fail("unknown argument: \(argument)")
        }
    }
    return options
}

func directoryExists(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
}

func discoverLocales(rawDir: URL) throws -> [String] {
    let entries = try FileManager.default.contentsOfDirectory(
        at: rawDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    return entries
        .filter { directoryExists($0) }
        .map { $0.lastPathComponent }
        .sorted()
}

func run() throws {
    let options = parseOptions(Array(CommandLine.arguments.dropFirst()))
    guard let rawDirPath = options.rawDir, let captionsDirPath = options.captionsDir, let outDirPath = options.outDir else {
        fail("usage: swift frame-screenshots.swift --raw <dir> --captions <dir> --out <dir> [--locale <code>] [--only <screen>]")
    }

    let rawDir = URL(fileURLWithPath: rawDirPath)
    let captionsDir = URL(fileURLWithPath: captionsDirPath)
    let outDir = URL(fileURLWithPath: outDirPath)

    guard directoryExists(rawDir) else {
        throw ScriptError(reason: "raw directory not found: \(rawDir.path)")
    }
    guard directoryExists(captionsDir) else {
        throw ScriptError(reason: "captions directory not found: \(captionsDir.path)")
    }

    let locales: [String]
    if let onlyLocale = options.locale {
        guard directoryExists(rawDir.appendingPathComponent(onlyLocale)) else {
            throw ScriptError(reason: "locale not found under raw dir: \(onlyLocale)")
        }
        locales = [onlyLocale]
    } else {
        locales = try discoverLocales(rawDir: rawDir)
    }

    var writtenCount = 0
    for locale in locales {
        let captionsFile = captionsDir.appendingPathComponent("\(locale).json")
        guard FileManager.default.fileExists(atPath: captionsFile.path) else {
            if options.locale != nil {
                throw ScriptError(reason: "captions file not found: \(captionsFile.path)")
            }
            warn("no captions file for locale \(locale), skipping")
            continue
        }

        let localeCaptions = try loadCaptions(at: captionsFile)
        let screensToProcess = options.only.map { [$0] } ?? localeCaptions.order

        for (index, screen) in localeCaptions.order.enumerated() where screensToProcess.contains(screen) {
            let rawFile = rawDir.appendingPathComponent(locale).appendingPathComponent("\(screen).png")
            guard FileManager.default.fileExists(atPath: rawFile.path) else {
                warn("[\(locale)] missing raw capture for \(screen), skipping")
                continue
            }
            guard let caption = localeCaptions.entries[screen] else {
                warn("[\(locale)] missing caption for \(screen), skipping")
                continue
            }
            let position = String(format: "%02d", index + 1)
            let outFile = outDir.appendingPathComponent(locale).appendingPathComponent("\(position)-\(screen).png")
            try composeScreenshot(rawURL: rawFile, title: caption.title, subtitle: caption.subtitle, outURL: outFile)
            writtenCount += 1
        }
    }

    guard writtenCount > 0 else {
        throw ScriptError(reason: "no screenshots were composed (check --raw/--captions/--locale/--only)")
    }
}

do {
    try run()
} catch let error as ScriptError {
    fail(error.reason)
} catch {
    fail("\(error)")
}
