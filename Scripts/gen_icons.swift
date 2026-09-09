#!/usr/bin/env swift
// Renderuje znak Privio offscreen (bez uprawnień do nagrywania ekranu):
//  - referencyjny PNG znaku (do weryfikacji kształtu),
//  - komplet PNG-ów AppIcon (rounded‑square, niebieski gradient, biały znak).
// Geometria MUSI odpowiadać PrivioLogoGeometry.path w aplikacji.
import AppKit
import SwiftUI

// Znak pochodzi 1:1 z logo_privio.svg (projekt użytkownika); parser SVG→Path
// zdublowany z Sources/PrivioApp/UI/Components/SVGPath.swift (trzymać w zgodzie).
let SVG_VIEWBOX = CGSize(width: 312, height: 400)
let ASPECT: CGFloat = SVG_VIEWBOX.width / SVG_VIEWBOX.height

let svgSource: String = {
    for p in ["Logo/logo_privio.svg", "Sources/PrivioApp/Resources/logo_privio.svg"] {
        if let s = try? String(contentsOfFile: p, encoding: .utf8) { return s }
    }
    fatalError("Nie znaleziono logo_privio.svg")
}()
let nativeLogoPath: Path = svgCombinedPath(fromSVG: svgSource)
let SMALL_SVG_VIEWBOX = CGSize(width: 211, height: 310)
let SMALL_ASPECT: CGFloat = SMALL_SVG_VIEWBOX.width / SMALL_SVG_VIEWBOX.height
let smallSVGSource: String = {
    for p in ["Logo/logo_privio_small.svg",
              "Sources/PrivioApp/Resources/logo_privio_small.svg"] {
        if let s = try? String(contentsOfFile: p, encoding: .utf8) { return s }
    }
    fatalError("Nie znaleziono logo_privio_small.svg")
}()
let nativeSmallLogoPath: Path = svgCombinedPath(fromSVG: smallSVGSource)

func markPath(in size: CGSize, lineWidthRatio: CGFloat) -> Path {
    nativeLogoPath.applying(CGAffineTransform(scaleX: size.width / SVG_VIEWBOX.width,
                                              y: size.height / SVG_VIEWBOX.height))
}

func svgCombinedPath(fromSVG svg: String) -> Path {
    var combined = Path()
    var range = svg.startIndex..<svg.endIndex
    while let d = svg.range(of: "d=\"", range: range),
          let end = svg.range(of: "\"", range: d.upperBound..<svg.endIndex) {
        combined.addPath(svgParse(String(svg[d.upperBound..<end.lowerBound])))
        range = end.upperBound..<svg.endIndex
    }
    return combined
}

func svgNumbers(_ s: String) -> [CGFloat] {
    var out: [CGFloat] = []; var cur = ""
    func flush() { if !cur.isEmpty, let v = Double(cur) { out.append(CGFloat(v)) }; cur = "" }
    for ch in s {
        switch ch {
        case "0"..."9": cur.append(ch)
        case ".": if cur.contains(".") { flush(); cur = "." } else { cur.append(ch) }
        case "-", "+": if cur.isEmpty || cur.last == "e" || cur.last == "E" { cur.append(ch) } else { flush(); cur = String(ch) }
        case "e", "E": cur.append(ch)
        default: flush()
        }
    }
    flush(); return out
}

func svgParse(_ d: String) -> Path {
    var path = Path(); var current = CGPoint.zero; var subStart = CGPoint.zero
    var lastCtl: CGPoint?; var lastCmd: Character = " "
    let cmds = "MmLlHhVvCcSsQqTtAaZz"
    var idx = d.startIndex
    while idx < d.endIndex {
        let ch = d[idx]
        guard cmds.contains(ch) else { idx = d.index(after: idx); continue }
        let cmd = ch; idx = d.index(after: idx)
        var numStr = ""
        while idx < d.endIndex, !cmds.contains(d[idx]) { numStr.append(d[idx]); idx = d.index(after: idx) }
        let n = svgNumbers(numStr); var k = 0
        func nx() -> CGFloat { defer { k += 1 }; return k < n.count ? n[k] : 0 }
        switch cmd {
        case "M", "m":
            let rel = cmd == "m"
            var p = CGPoint(x: (rel ? current.x : 0) + nx(), y: (rel ? current.y : 0) + nx())
            path.move(to: p); current = p; subStart = p
            while k + 1 < n.count { p = CGPoint(x: (rel ? current.x : 0) + nx(), y: (rel ? current.y : 0) + nx()); path.addLine(to: p); current = p }
            lastCtl = nil
        case "L", "l":
            let rel = cmd == "l"
            while k + 1 < n.count { let p = CGPoint(x: (rel ? current.x : 0) + nx(), y: (rel ? current.y : 0) + nx()); path.addLine(to: p); current = p }
            lastCtl = nil
        case "H", "h":
            let rel = cmd == "h"
            while k < n.count { let p = CGPoint(x: (rel ? current.x : 0) + nx(), y: current.y); path.addLine(to: p); current = p }
            lastCtl = nil
        case "V", "v":
            let rel = cmd == "v"
            while k < n.count { let p = CGPoint(x: current.x, y: (rel ? current.y : 0) + nx()); path.addLine(to: p); current = p }
            lastCtl = nil
        case "C", "c":
            let rel = cmd == "c"
            while k + 5 < n.count {
                let c1 = CGPoint(x: (rel ? current.x : 0) + nx(), y: (rel ? current.y : 0) + nx())
                let c2 = CGPoint(x: (rel ? current.x : 0) + nx(), y: (rel ? current.y : 0) + nx())
                let p  = CGPoint(x: (rel ? current.x : 0) + nx(), y: (rel ? current.y : 0) + nx())
                path.addCurve(to: p, control1: c1, control2: c2); lastCtl = c2; current = p
            }
        case "S", "s":
            let rel = cmd == "s"
            while k + 3 < n.count {
                let c1: CGPoint
                if "CcSs".contains(lastCmd), let lc = lastCtl { c1 = CGPoint(x: 2*current.x - lc.x, y: 2*current.y - lc.y) } else { c1 = current }
                let c2 = CGPoint(x: (rel ? current.x : 0) + nx(), y: (rel ? current.y : 0) + nx())
                let p  = CGPoint(x: (rel ? current.x : 0) + nx(), y: (rel ? current.y : 0) + nx())
                path.addCurve(to: p, control1: c1, control2: c2); lastCtl = c2; current = p
            }
        case "Z", "z":
            path.closeSubpath(); current = subStart; lastCtl = nil
        default: break
        }
        lastCmd = cmd
    }
    return path
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF)/255, green: CGFloat((hex >> 8) & 0xFF)/255,
            blue: CGFloat(hex & 0xFF)/255, alpha: 1)
}

// Rysuje w kontekście z origin w lewym‑górnym rogu (jak SwiftUI).
func render(pixel: Int, appIcon: Bool, markColor: CGColor? = nil) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixel, pixelsHigh: pixel,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = ctx.cgContext
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let s = CGFloat(pixel)
    cg.translateBy(x: 0, y: s); cg.scaleBy(x: 1, y: -1)   // → top‑left origin

    var markRect: CGRect
    var strokeColor: CGColor
    let lineRatio: CGFloat = 12.0 / 312.0   // grubość wg projektu (SVG)

    if appIcon {
        let margin = s * 0.09
        let bg = CGRect(x: margin, y: margin, width: s - 2*margin, height: s - 2*margin)
        let radius = bg.width * 0.2255
        let rounded = CGPath(roundedRect: bg, cornerWidth: radius, cornerHeight: radius, transform: nil)
        cg.saveGState()
        cg.addPath(rounded); cg.clip()
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [color(0x3E8BFF), color(0x0E52D6)] as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(grad, start: CGPoint(x: bg.midX, y: bg.minY),
                              end: CGPoint(x: bg.midX, y: bg.maxY), options: [])
        cg.restoreGState()
        let mh = bg.height * 0.68
        let mw = mh * ASPECT
        markRect = CGRect(x: bg.midX - mw/2, y: bg.midY - mh/2, width: mw, height: mh)
        strokeColor = CGColor(gray: 1, alpha: 1)
    } else {
        let mh = s * 0.92
        let mw = mh * ASPECT
        markRect = CGRect(x: (s - mw)/2, y: (s - mh)/2, width: mw, height: mh)
        strokeColor = markColor ?? color(0x146EF5)
    }

    let p = markPath(in: markRect.size, lineWidthRatio: lineRatio)
    var t = CGAffineTransform(translationX: markRect.minX, y: markRect.minY)
    let path = p.cgPath.copy(using: &t)!
    cg.addPath(path)
    cg.setStrokeColor(strokeColor)
    cg.setLineWidth(markRect.width * lineRatio)
    cg.setLineCap(.round); cg.setLineJoin(.round)
    cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// Ikona toolbaru Chrome: uproszczony znak small v2 bez tła i mała kropka stanu.
func renderChromeToolbar(pixel: Int, active: Bool) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixel, pixelsHigh: pixel,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = ctx.cgContext
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let s = CGFloat(pixel)
    cg.translateBy(x: 0, y: s)
    cg.scaleBy(x: 1, y: -1)

    // SVG zawiera celowe marginesy w viewBox. Dla ikony 16 px skalujemy
    // rzeczywiste granice ścieżki, dzięki czemu znak wykorzystuje cały dostępny
    // obszar zamiast wyglądać jak miniatura.
    let bounds = nativeSmallLogoPath.boundingRect
    let availableWidth = s * 0.82
    let availableHeight = s
    let pathScale = min(availableWidth / bounds.width, availableHeight / bounds.height)
    let renderedHeight = bounds.height * pathScale
    let transform = CGAffineTransform(
        a: pathScale, b: 0, c: 0, d: pathScale,
        tx: -bounds.minX * pathScale,
        ty: (s - renderedHeight) / 2 - bounds.minY * pathScale
    )
    let fitted = nativeSmallLogoPath.applying(transform)
    cg.addPath(fitted.cgPath)
    cg.setStrokeColor(CGColor(gray: 1, alpha: 1))
    cg.setLineWidth(12.0 * pathScale)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.strokePath()

    let diameter = pixel <= 16 ? s * 0.19 : s * 0.17
    let inset = s * 0.03
    let dot = CGRect(x: s - diameter - inset, y: s - diameter - inset,
                     width: diameter, height: diameter)
    cg.setFillColor(active ? color(0x34C759) : color(0xFF3B30))
    cg.fillEllipse(in: dot)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// Zwykłe ikony rozszerzenia korzystają również z geometrii small v2, ale
/// zachowują czytelne niebieskie tło w popupie i na stronie rozszerzeń.
func renderChromeIcon(pixel: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixel, pixelsHigh: pixel,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = ctx.cgContext
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let s = CGFloat(pixel)
    cg.translateBy(x: 0, y: s)
    cg.scaleBy(x: 1, y: -1)

    let margin = s * 0.07
    let bg = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let rounded = CGPath(roundedRect: bg, cornerWidth: bg.width * 0.2255,
                         cornerHeight: bg.width * 0.2255, transform: nil)
    cg.saveGState()
    cg.addPath(rounded)
    cg.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [color(0x3E8BFF), color(0x0E52D6)] as CFArray,
                              locations: [0, 1])!
    cg.drawLinearGradient(gradient, start: CGPoint(x: bg.midX, y: bg.minY),
                          end: CGPoint(x: bg.midX, y: bg.maxY), options: [])
    cg.restoreGState()

    let markHeight = bg.height * 0.76
    let markWidth = markHeight * SMALL_ASPECT
    let scale = CGAffineTransform(scaleX: markWidth / SMALL_SVG_VIEWBOX.width,
                                  y: markHeight / SMALL_SVG_VIEWBOX.height)
    let scaled = nativeSmallLogoPath.applying(scale)
    var translation = CGAffineTransform(translationX: bg.midX - markWidth / 2,
                                        y: bg.midY - markHeight / 2)
    cg.addPath(scaled.cgPath.copy(using: &translation)!)
    cg.setStrokeColor(CGColor(gray: 1, alpha: 1))
    cg.setLineWidth(markWidth * (12.0 / SMALL_SVG_VIEWBOX.width))
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let assets = "Sources/PrivioApp/Resources/Assets.xcassets/AppIcon.appiconset"
let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in iconSizes {
    try! render(pixel: px, appIcon: true).write(to: URL(fileURLWithPath: "\(assets)/\(name)"))
}
// Referencyjne PNG-i do wizualnej weryfikacji kształtu.
let scratch = ProcessInfo.processInfo.environment["SCRATCH"] ?? "/tmp"
try! render(pixel: 400, appIcon: false).write(to: URL(fileURLWithPath: "\(scratch)/logo_mark.png"))
try! render(pixel: 400, appIcon: true).write(to: URL(fileURLWithPath: "\(scratch)/logo_icon.png"))

// Logo do instalatora .pkg - SAM znak na przezroczystym tle (nie ikona/kwadrat):
// wariant kolorowy dla jasnego instalatora, biały dla ciemnego.
try! render(pixel: 160, appIcon: false)
    .write(to: URL(fileURLWithPath: "Installer/logo-light.png"))
try! render(pixel: 160, appIcon: false, markColor: CGColor(gray: 1, alpha: 1))
    .write(to: URL(fileURLWithPath: "Installer/logo-dark.png"))

let chromeIcons = "ChromeExtension/icons"
for size in [16, 32, 48, 128] {
    try! renderChromeIcon(pixel: size)
        .write(to: URL(fileURLWithPath: "\(chromeIcons)/icon\(size).png"))
}
for size in [16, 32] {
    try! renderChromeToolbar(pixel: size, active: true)
        .write(to: URL(fileURLWithPath: "\(chromeIcons)/icon\(size)-active.png"))
    try! renderChromeToolbar(pixel: size, active: false)
        .write(to: URL(fileURLWithPath: "\(chromeIcons)/icon\(size)-inactive.png"))
}

// UWAGA: logo_privio.svg jest źródłem znaku (edytowane przez użytkownika) -
// generator go NIE nadpisuje. Wynikiem są wyłącznie PNG-i ikon.
print("Wygenerowano \(iconSizes.count) ikon aplikacji + logo instalatora + ikony Chrome")
