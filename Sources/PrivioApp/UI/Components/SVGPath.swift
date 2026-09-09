import SwiftUI
import CoreGraphics

/// Minimalny parser ścieżek SVG (`d="…"`) → SwiftUI `Path`.
///
/// Obsługuje komendy obecne w znaku Privio: M/m, L/l, H/h, V/v, C/c, S/s, Z/z
/// (bezwzględne i względne), z „upakowanymi" liczbami w stylu Illustratora
/// (np. `48.55.71`, `5.01-13.76`). Dzięki temu rysujemy dokładnie ścieżkę z
/// `logo_privio.svg`, zachowując pełną recolorowalność (stroke wg naszego koloru).
enum SVGPath {
    /// Wyciąga wszystkie atrybuty `d="…"` z treści SVG i łączy w jedną ścieżkę.
    static func combinedPath(fromSVG svg: String) -> Path {
        var combined = Path()
        var searchRange = svg.startIndex..<svg.endIndex
        while let dRange = svg.range(of: "d=\"", range: searchRange),
              let end = svg.range(of: "\"", range: dRange.upperBound..<svg.endIndex) {
            let d = String(svg[dRange.upperBound..<end.lowerBound])
            combined.addPath(parse(d))
            searchRange = end.upperBound..<svg.endIndex
        }
        return combined
    }

    static func parse(_ d: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastCommand: Character = " "

        let commands = "MmLlHhVvCcSsQqTtAaZz"
        var idx = d.startIndex
        while idx < d.endIndex {
            let ch = d[idx]
            guard commands.contains(ch) else { idx = d.index(after: idx); continue }
            let cmd = ch
            idx = d.index(after: idx)
            var numStr = ""
            while idx < d.endIndex, !commands.contains(d[idx]) {
                numStr.append(d[idx]); idx = d.index(after: idx)
            }
            let n = numbers(numStr)
            var k = 0
            func next() -> CGFloat { defer { k += 1 }; return k < n.count ? n[k] : 0 }

            switch cmd {
            case "M", "m":
                let rel = (cmd == "m")
                var p = CGPoint(x: (rel ? current.x : 0) + next(), y: (rel ? current.y : 0) + next())
                path.move(to: p); current = p; subpathStart = p
                // Kolejne pary po M są traktowane jak L.
                while k + 1 < n.count {
                    p = CGPoint(x: (rel ? current.x : 0) + next(), y: (rel ? current.y : 0) + next())
                    path.addLine(to: p); current = p
                }
                lastCubicControl = nil
            case "L", "l":
                let rel = (cmd == "l")
                while k + 1 < n.count {
                    let p = CGPoint(x: (rel ? current.x : 0) + next(), y: (rel ? current.y : 0) + next())
                    path.addLine(to: p); current = p
                }
                lastCubicControl = nil
            case "H", "h":
                let rel = (cmd == "h")
                while k < n.count {
                    let p = CGPoint(x: (rel ? current.x : 0) + next(), y: current.y)
                    path.addLine(to: p); current = p
                }
                lastCubicControl = nil
            case "V", "v":
                let rel = (cmd == "v")
                while k < n.count {
                    let p = CGPoint(x: current.x, y: (rel ? current.y : 0) + next())
                    path.addLine(to: p); current = p
                }
                lastCubicControl = nil
            case "C", "c":
                let rel = (cmd == "c")
                while k + 5 < n.count {
                    let c1 = CGPoint(x: (rel ? current.x : 0) + next(), y: (rel ? current.y : 0) + next())
                    let c2 = CGPoint(x: (rel ? current.x : 0) + next(), y: (rel ? current.y : 0) + next())
                    let p  = CGPoint(x: (rel ? current.x : 0) + next(), y: (rel ? current.y : 0) + next())
                    path.addCurve(to: p, control1: c1, control2: c2)
                    lastCubicControl = c2; current = p
                }
            case "S", "s":
                let rel = (cmd == "s")
                while k + 3 < n.count {
                    let c1: CGPoint
                    if lastCommand == "C" || lastCommand == "c" || lastCommand == "S" || lastCommand == "s",
                       let lc = lastCubicControl {
                        c1 = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y) // odbicie
                    } else {
                        c1 = current
                    }
                    let c2 = CGPoint(x: (rel ? current.x : 0) + next(), y: (rel ? current.y : 0) + next())
                    let p  = CGPoint(x: (rel ? current.x : 0) + next(), y: (rel ? current.y : 0) + next())
                    path.addCurve(to: p, control1: c1, control2: c2)
                    lastCubicControl = c2; current = p
                }
            case "Z", "z":
                path.closeSubpath(); current = subpathStart; lastCubicControl = nil
            default:
                break   // Q/T/A nieużywane w znaku
            }
            lastCommand = cmd
        }
        return path
    }

    /// Tokenizer liczb SVG: obsługuje znaki, przecinki/spacje, „upakowane"
    /// liczby (drugi „.” lub „-” rozpoczyna nową liczbę) oraz wykładniki.
    private static func numbers(_ s: String) -> [CGFloat] {
        var out: [CGFloat] = []
        var cur = ""
        func flush() { if !cur.isEmpty, let v = Double(cur) { out.append(CGFloat(v)) }; cur = "" }
        for ch in s {
            switch ch {
            case "0"..."9":
                cur.append(ch)
            case ".":
                if cur.contains(".") { flush(); cur = "." } else { cur.append(ch) }
            case "-", "+":
                if cur.isEmpty || cur.last == "e" || cur.last == "E" { cur.append(ch) }
                else { flush(); cur = String(ch) }
            case "e", "E":
                cur.append(ch)
            default:            // spacja, przecinek, nowa linia itp.
                flush()
            }
        }
        flush()
        return out
    }
}
