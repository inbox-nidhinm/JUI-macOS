import Foundation
import CoreGraphics

// A line drawing, read from an SVG: the paper it sits on and every stroke on
// it, each flattened into points.
//
// Made for Figma's SVG export of a frame of stroked vectors: open paths, a
// stroke colour and width each, the frame's fill as a <rect> behind them.
// Anything filled rather than stroked is ignored — a fill has no line for the
// growth to travel along. Groups are read only for their transforms; the order
// strokes draw in comes from the growth, not from the layers.
public struct Artwork: Sendable {
    public struct Stroke: Sendable {
        /// The line, flattened: points about a pixel apart along it.
        public var points: [CGPoint]
        public var width: CGFloat
        public var color: CGColor
    }

    public var size: CGSize
    /// The paper: the frame's fill, if it had one.
    public var background: CGColor?
    public var strokes: [Stroke]

    public init(size: CGSize, background: CGColor?, strokes: [Stroke]) {
        self.size = size
        self.background = background
        self.strokes = strokes
    }

    public init(svgAt url: URL) throws {
        try self.init(svg: Data(contentsOf: url))
    }

    public init(svg data: Data) throws {
        let reader = SVGReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else {
            throw DrawOnError.unreadableSVG(parser.parserError?.localizedDescription ?? "unknown error")
        }
        guard !reader.strokes.isEmpty else { throw DrawOnError.noStrokes }
        self.init(size: reader.size, background: reader.background, strokes: reader.strokes)
    }
}

public enum DrawOnError: Error, CustomStringConvertible {
    case unreadableSVG(String)
    case noStrokes

    public var description: String {
        switch self {
        case .unreadableSVG(let why): return "Couldn't read the SVG: \(why)"
        case .noStrokes: return "The SVG has no stroked paths to draw."
        }
    }
}

// MARK: - Reading the SVG

private final class SVGReader: NSObject, XMLParserDelegate {
    var size = CGSize(width: 100, height: 100)
    var background: CGColor?
    var strokes: [Artwork.Stroke] = []

    /// What a group hands down to what is inside it.
    private struct Context {
        var transform = CGAffineTransform.identity
        var stroke: String?
        var strokeWidth: CGFloat?
    }
    private var stack = [Context()]
    private var depth = 0 // inside <defs> / <clipPath> / <mask>: not drawn
    private var skipDepth: Int?

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String] = [:]) {
        depth += 1
        if skipDepth != nil { return }
        if ["defs", "clipPath", "mask", "symbol", "pattern", "linearGradient", "radialGradient"].contains(name) {
            skipDepth = depth
            return
        }

        var ctx = stack.last!
        if let t = a["transform"] { ctx.transform = SVGReader.transform(t).concatenating(ctx.transform) }
        if let s = a["stroke"] { ctx.stroke = s }
        if let w = a["stroke-width"].flatMap(Double.init) { ctx.strokeWidth = CGFloat(w) }
        stack.append(ctx)

        switch name {
        case "svg":
            if let vb = a["viewBox"] {
                let n = SVGReader.numbers(vb)
                if n.count == 4 { size = CGSize(width: n[2], height: n[3]) }
            } else if let w = a["width"].flatMap(Double.init), let h = a["height"].flatMap(Double.init) {
                size = CGSize(width: w, height: h)
            }
        case "rect":
            // The first full-size filled rect is the frame's own fill: the paper.
            if background == nil, let fill = a["fill"], let colour = SVGReader.color(fill),
               let w = a["width"].flatMap(Double.init), let h = a["height"].flatMap(Double.init),
               w >= size.width * 0.99, h >= size.height * 0.99 {
                background = colour
            }
        case "path":
            if let d = a["d"] { add(PathFlattener.flatten(d), ctx) }
        case "line":
            let p = ["x1", "y1", "x2", "y2"].map { CGFloat(Double(a[$0] ?? "0") ?? 0) }
            add([[CGPoint(x: p[0], y: p[1]), CGPoint(x: p[2], y: p[3])]], ctx)
        case "polyline":
            let n = SVGReader.numbers(a["points"] ?? "")
            let pts = stride(from: 0, to: n.count - 1, by: 2).map { CGPoint(x: n[$0], y: n[$0 + 1]) }
            add([pts], ctx)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { depth -= 1 }
        if let skip = skipDepth {
            if depth == skip { skipDepth = nil }
            return
        }
        stack.removeLast()
    }

    private func add(_ subpaths: [[CGPoint]], _ ctx: Context) {
        guard let s = ctx.stroke, s != "none", let colour = SVGReader.color(s) else { return }
        let width = ctx.strokeWidth ?? 1
        for sub in subpaths where sub.count > 1 {
            strokes.append(.init(points: sub.map { $0.applying(ctx.transform) },
                                 width: width, color: colour))
        }
    }

    // MARK: Attribute values

    static func numbers(_ s: String) -> [CGFloat] {
        var out: [CGFloat] = []
        var scanner = NumberScanner(s)
        while let n = scanner.next() { out.append(n) }
        return out
    }

    static func color(_ s: String) -> CGColor? {
        var hex = s.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#") else {
            return hex == "black" ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
                : hex == "white" ? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) : nil
        }
        hex.removeFirst()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func transform(_ s: String) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        let pattern = try! Regex<(Substring, Substring, Substring)>(#"(matrix|translate|scale|rotate)\s*\(([^)]*)\)"#)
        for m in s.matches(of: pattern) {
            let n = numbers(String(m.output.2))
            var t = CGAffineTransform.identity
            switch m.output.1 {
            case "matrix" where n.count == 6:
                t = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
            case "translate":
                t = CGAffineTransform(translationX: n.first ?? 0, y: n.count > 1 ? n[1] : 0)
            case "scale":
                t = CGAffineTransform(scaleX: n.first ?? 1, y: n.count > 1 ? n[1] : (n.first ?? 1))
            case "rotate":
                let angle = (n.first ?? 0) * .pi / 180
                if n.count == 3 {
                    t = CGAffineTransform(translationX: n[1], y: n[2]).rotated(by: angle)
                        .translatedBy(x: -n[1], y: -n[2])
                } else {
                    t = CGAffineTransform(rotationAngle: angle)
                }
            default: break
            }
            // Listed left to right, applied right to left.
            result = t.concatenating(result)
        }
        return result
    }
}

// MARK: - Path data

/// Reads numbers out of SVG attribute text, which runs them together freely:
/// "1.5-2", ".5.5" and "1e-3" are all legal.
struct NumberScanner {
    private let chars: [Character]
    private var i = 0

    init(_ s: String) { chars = Array(s) }

    var position: Int { i }

    var atEnd: Bool {
        var j = i
        while j < chars.count, chars[j] == " " || chars[j] == "," || chars[j].isNewline || chars[j] == "\t" { j += 1 }
        return j >= chars.count
    }

    /// The next character that isn't a separator, without consuming it.
    mutating func peekCommand() -> Character? {
        skipSeparators()
        guard i < chars.count, chars[i].isLetter, chars[i] != "e", chars[i] != "E" else { return nil }
        return chars[i]
    }

    mutating func takeCommand() -> Character? {
        guard let c = peekCommand() else { return nil }
        i += 1
        return c
    }

    private mutating func skipSeparators() {
        while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i].isNewline || chars[i] == "\t" { i += 1 }
    }

    mutating func next() -> CGFloat? {
        skipSeparators()
        let start = i
        if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
        var seenDot = false, seenDigit = false
        while i < chars.count {
            let c = chars[i]
            if c.isNumber { seenDigit = true; i += 1 }
            else if c == ".", !seenDot { seenDot = true; i += 1 }
            else { break }
        }
        if seenDigit, i < chars.count, chars[i] == "e" || chars[i] == "E" {
            var j = i + 1
            if j < chars.count, chars[j] == "-" || chars[j] == "+" { j += 1 }
            if j < chars.count, chars[j].isNumber {
                i = j
                while i < chars.count, chars[i].isNumber { i += 1 }
            }
        }
        guard seenDigit, let v = Double(String(chars[start..<i])) else {
            i = start
            return nil
        }
        return CGFloat(v)
    }

    /// An arc's flags may be written with no separator: "a1 1 0 011 1".
    mutating func flag() -> CGFloat? {
        skipSeparators()
        guard i < chars.count, chars[i] == "0" || chars[i] == "1" else { return next() }
        let v: CGFloat = chars[i] == "1" ? 1 : 0
        i += 1
        return v
    }
}

/// Turns SVG path data into polylines, one per subpath, with curves flattened
/// to points about `tolerance` apart.
enum PathFlattener {
    static func flatten(_ d: String, spacing: CGFloat = 1) -> [[CGPoint]] {
        var s = NumberScanner(d)
        var paths: [[CGPoint]] = []
        var current: [CGPoint] = []
        var p = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint? // for S and T
        var command: Character = "M"

        func finish() {
            if current.count > 1 { paths.append(current) }
            current = []
        }
        func lineTo(_ q: CGPoint) {
            if current.isEmpty { current = [p] }
            current.append(q)
            p = q
        }
        func cubic(_ c1: CGPoint, _ c2: CGPoint, _ e: CGPoint) {
            if current.isEmpty { current = [p] }
            let length = dist(p, c1) + dist(c1, c2) + dist(c2, e)
            let n = max(2, Int((length / spacing).rounded(.up)))
            let p0 = p
            for k in 1...n {
                let t = CGFloat(k) / CGFloat(n), u = 1 - t
                let x = u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*e.x
                let y = u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*e.y
                current.append(CGPoint(x: x, y: y))
            }
            p = e
        }
        func quad(_ c: CGPoint, _ e: CGPoint) {
            cubic(CGPoint(x: p.x + 2/3 * (c.x - p.x), y: p.y + 2/3 * (c.y - p.y)),
                  CGPoint(x: e.x + 2/3 * (c.x - e.x), y: e.y + 2/3 * (c.y - e.y)), e)
        }

        while !s.atEnd {
            let before = s.position
            defer { if s.position == before { s = NumberScanner("") } } // stuck: stop
            if let c = s.takeCommand() { command = c }
            let rel = command.isLowercase
            let o = rel ? p : .zero
            func pt() -> CGPoint? {
                guard let x = s.next(), let y = s.next() else { return nil }
                return CGPoint(x: o.x + x, y: o.y + y)
            }
            var control: CGPoint?
            switch command.uppercased() {
            case "M":
                guard let q = pt() else { return paths + [current].filter { $0.count > 1 } }
                finish()
                p = q; start = q
                // Further pairs after a moveto are linetos.
                command = rel ? "l" : "L"
            case "L":
                guard let q = pt() else { break }
                lineTo(q)
            case "H":
                guard let x = s.next() else { break }
                lineTo(CGPoint(x: (rel ? p.x : 0) + x, y: p.y))
            case "V":
                guard let y = s.next() else { break }
                lineTo(CGPoint(x: p.x, y: (rel ? p.y : 0) + y))
            case "C":
                guard let c1 = pt(), let c2 = pt(), let e = pt() else { break }
                cubic(c1, c2, e); control = c2
            case "S":
                guard let c2 = pt(), let e = pt() else { break }
                let c1 = lastControl.map { CGPoint(x: 2*p.x - $0.x, y: 2*p.y - $0.y) } ?? p
                cubic(c1, c2, e); control = c2
            case "Q":
                guard let c = pt(), let e = pt() else { break }
                quad(c, e); control = c
            case "T":
                guard let e = pt() else { break }
                let c = lastControl.map { CGPoint(x: 2*p.x - $0.x, y: 2*p.y - $0.y) } ?? p
                quad(c, e); control = c
            case "A":
                // Arcs are drawn as straight lines to their end: the growth
                // needs the route, and Figma doesn't write arcs for strokes.
                _ = s.next(); _ = s.next(); _ = s.next(); _ = s.flag(); _ = s.flag()
                guard let e = pt() else { break }
                lineTo(e)
            case "Z":
                lineTo(start)
                finish()
            default:
                _ = s.next() // unknown: step past it rather than loop
            }
            lastControl = control
            if command.uppercased() == "Z" { command = "M" }
        }
        finish()
        return paths
    }
}

@inline(__always) func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}
