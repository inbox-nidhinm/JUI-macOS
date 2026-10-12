import SwiftUI
import CoreGraphics

// Painting a growth at one moment.
//
// Each stroke draws whatever of it growth has reached by `time`. A segment
// between two points is drawn whole once both are reached, and part-way
// while growth is between them, from the end reached first — so a stroke
// reached in its middle visibly spreads both ways from there.
//
// The work is in Core Graphics, so the view, the lab's still frames and any
// app taking this in all draw through the one function.
public enum GrowthPainter {
    public enum Mode: String, CaseIterable, Sendable {
        /// The drawing as it grows.
        case growing
        /// Every stroke whole, coloured by when it is reached: early warm,
        /// late cool. For seeing the shape of the spread at a glance.
        case timing
    }

    /// Draws into `cg`, whose coordinates are the artwork's own scaled to fit
    /// `rect` (y down, as in SwiftUI).
    public static func draw(_ art: Artwork, _ growth: Growth, at time: Double, in rect: CGRect,
                            context cg: CGContext, mode: Mode = .growing,
                            paper: Bool = true, showSeeds: Bool = false,
                            ink: CGColor? = nil, minimumLineWidth: CGFloat = 0) {
        let scale = min(rect.width / art.size.width, rect.height / art.size.height)
        let origin = CGPoint(x: rect.midX - art.size.width * scale / 2,
                             y: rect.midY - art.size.height * scale / 2)
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.translateBy(x: origin.x, y: origin.y)
        cg.scaleBy(x: scale, y: scale)

        if paper, let bg = art.background {
            cg.setFillColor(bg)
            cg.fill(CGRect(origin: .zero, size: art.size))
        }
        cg.setLineCap(.round)
        cg.setLineJoin(.round)

        switch mode {
        case .growing:
            // `ink` redraws every stroke in one colour, for an app that has
            // its own (JUI's moods). `minimumLineWidth` is in the points being
            // drawn into, not the artwork's: a drawing made large and shown
            // small would otherwise thin to a hairline.
            drawGrowing(art, growth, time, cg, ink: ink, minimumWidth: minimumLineWidth / scale)
        case .timing: drawTiming(art, growth, cg)
        }

        if showSeeds {
            for (i, s) in growth.seeds.enumerated() {
                let r: CGFloat = 9 / scale
                cg.setFillColor(CGColor(srgbRed: 0.85, green: 0.25, blue: 0.2, alpha: 0.85))
                cg.fillEllipse(in: CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2))
                _ = i
            }
        }
    }

    private static func drawGrowing(_ art: Artwork, _ growth: Growth, _ time: Double, _ cg: CGContext,
                                    ink: CGColor?, minimumWidth: CGFloat) {
        // Strokes sharing a colour and width go into one path, so a mostly
        // single-ink drawing is a single stroke call.
        var paths: [Style: CGMutablePath] = [:]
        for si in strokes(art, growth) where growth.firstTime[si] <= time {
            let style = Style(art.strokes[si])
            let path = paths[style] ?? CGMutablePath()
            paths[style] = path
            let pts = growth.points[si], ts = growth.times[si]
            if growth.lastTime[si] <= time {
                path.addLines(between: pts)
                continue
            }
            var penAt = -1 // the point the current subpath ends on
            for i in 0..<(pts.count - 1) {
                let ta = ts[i], tb = ts[i + 1]
                if max(ta, tb) <= time {
                    if penAt != i { path.move(to: pts[i]) }
                    path.addLine(to: pts[i + 1])
                    penAt = i + 1
                } else if min(ta, tb) < time {
                    // Part-way: from the end reached first, as far as growth
                    // has got between the two.
                    let (from, to, t0, t1) = ta <= tb ? (i, i + 1, ta, tb) : (i + 1, i, tb, ta)
                    let f = CGFloat((time - t0) / max(t1 - t0, 1e-9))
                    let a = pts[from], b = pts[to]
                    let tip = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                    if penAt != from { path.move(to: a) }
                    path.addLine(to: tip)
                    penAt = -1
                }
            }
        }
        for (style, path) in paths {
            cg.addPath(path)
            cg.setStrokeColor(ink ?? style.color)
            cg.setLineWidth(max(style.width, minimumWidth))
            cg.strokePath()
        }
    }

    private static func drawTiming(_ art: Artwork, _ growth: Growth, _ cg: CGContext) {
        let d = max(growth.duration, 1e-9)
        for si in strokes(art, growth) {
            let x = (growth.firstTime[si] + growth.lastTime[si]) / 2 / d
            // warm to cool: early growth red-orange, late growth blue
            let colour = CGColor(srgbRed: 0.9 - 0.7 * x, green: 0.35 + 0.2 * x, blue: 0.15 + 0.75 * x, alpha: 1)
            cg.addLines(between: growth.points[si])
            cg.setStrokeColor(colour)
            cg.setLineWidth(art.strokes[si].width)
            cg.strokePath()
        }
    }

    /// The strokes a growth covers. A growth belongs to the artwork it was
    /// worked out for; handed another, draw what both have rather than
    /// running off the end of the shorter.
    private static func strokes(_ art: Artwork, _ growth: Growth) -> Range<Int> {
        0..<min(art.strokes.count, growth.points.count)
    }

    private struct Style: Hashable {
        let color: CGColor
        let width: CGFloat
        init(_ s: Artwork.Stroke) { color = s.color; width = s.width }
        static func == (a: Style, b: Style) -> Bool { a.width == b.width && a.color == b.color }
        func hash(into h: inout Hasher) {
            h.combine(width)
            for c in color.components ?? [] { h.combine(c) }
        }
    }

    /// A still frame, for checking a growth without watching it.
    public static func image(_ art: Artwork, _ growth: Growth, at time: Double, width: Int,
                             mode: Mode = .growing, showSeeds: Bool = false) -> CGImage? {
        let height = Int((CGFloat(width) * art.size.height / art.size.width).rounded())
        guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                 bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // y down, like the view
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: 1, y: -1)
        draw(art, growth, at: time, in: CGRect(x: 0, y: 0, width: width, height: height),
             context: cg, mode: mode, showSeeds: showSeeds)
        return cg.makeImage()
    }
}

/// The drawing growing in, for SwiftUI: give it the moment to show.
public struct GrowthView: View {
    let art: Artwork
    let growth: Growth
    let time: Double
    var mode: GrowthPainter.Mode = .growing
    var showSeeds = false
    var paper = true
    var ink: CGColor?
    var minimumLineWidth: CGFloat = 0

    public init(art: Artwork, growth: Growth, time: Double,
                mode: GrowthPainter.Mode = .growing, showSeeds: Bool = false,
                paper: Bool = true, ink: CGColor? = nil, minimumLineWidth: CGFloat = 0) {
        self.paper = paper
        self.ink = ink
        self.minimumLineWidth = minimumLineWidth
        self.art = art
        self.growth = growth
        self.time = time
        self.mode = mode
        self.showSeeds = showSeeds
    }

    public var body: some View {
        Canvas { ctx, size in
            ctx.withCGContext { cg in
                GrowthPainter.draw(art, growth, at: time, in: CGRect(origin: .zero, size: size),
                                   context: cg, mode: mode, paper: paper, showSeeds: showSeeds,
                                   ink: ink, minimumLineWidth: minimumLineWidth)
            }
        }
    }
}
