import Foundation
import CoreGraphics

// How a drawing grows: when every point of every stroke is reached.
//
// The picture is treated like a petri dish. A few seeds land on it at random,
// each on a stroke, and growth spreads out from them: fast along a line, slowly
// across bare paper. Where a growing tip comes near another stroke, that
// stroke is reached at the point nearest the tip and grows outward both ways
// from there — there is no "start" or "end" of a stroke, only where growth
// first got to it. Nothing is ordered by layer, size or position; the order is
// whatever the spreading produces.
//
// It is worked out once, up front, as the cheapest route from any seed to
// every point (Dijkstra over the strokes' points): a step along a line costs
// its length, a hop across paper costs its length times `paperSlowness`. The
// cost a point is reached at is then bent into seconds by `pace`. Because the
// paper is only slow, never closed, growth always finds its way across a gap
// eventually, and always prefers a line when one goes the same way.
public struct GrowthSettings: Sendable, Equatable, Codable {
    /// How many seeds land, picked at random from this range on every play.
    public var seedsMin = 3
    public var seedsMax = 4
    /// How much slower growth creeps across bare paper than along a line.
    public var paperSlowness: Double = 8
    /// How far a tip can creep across paper in one hop, in artwork points.
    /// Wider gaps are still crossed, by way of the paper, just never directly.
    public var reach: Double = 40
    /// How much each stroke's own speed wanders from the rest, 0 to 1: some
    /// lines grow eagerly, some reluctantly, so the front never moves as one.
    public var irregularity: Double = 0.3
    /// Seeds don't all wake at once: each starts up to this much later, in
    /// the same units as a line's length.
    public var seedStagger: Double = 80
    /// Seconds from the first mark to the last.
    public var duration: Double = 9
    /// Above 1 the growth starts quick and slows as it spreads; 1 is steady.
    public var pace: Double = 1.6
    /// What the clock follows, 0 to 1. At 0, distance travelled: crossing a
    /// wide stretch of bare paper takes visibly long, and a few far-off marks
    /// can hold up the ending. At 1, ink: the same order, but the drawing
    /// fills in at an even rate however far the growth had to creep.
    public var evenness: Double = 0.75
    /// How far apart the points growth travels between are, along a stroke.
    public var spacing: Double = 2

    public init() {}
}

public struct Growth: Sendable {
    /// Where growth started: one point per seed, in artwork points.
    public let seeds: [CGPoint]
    /// Each stroke resampled into the points growth travels between.
    public let points: [[CGPoint]]
    /// The second each of those points is reached, matching `points`.
    public let times: [[Double]]
    /// For each stroke, when it is first and last reached.
    public let firstTime: [Double]
    public let lastTime: [Double]
    public let duration: Double
    /// The random seed this growth came from: the same seed and settings
    /// always grow the same way.
    public let randomSeed: UInt64

    /// Measured, for the lab.
    public struct Stats: Sendable {
        public var pointCount = 0
        public var hops = 0 // paper hops considered
        public var stranded = 0 // points only reachable past `reach`
        public var milliseconds = 0.0
    }
    public let stats: Stats
}

extension Growth {
    public static func grow(_ art: Artwork, settings s: GrowthSettings = .init(),
                            randomSeed: UInt64 = .random(in: 0...UInt64.max)) -> Growth {
        let clock = Date()
        var rng = SplitMix64(seed: randomSeed)
        var stats = Stats()

        // MARK: Points

        // Every stroke resampled evenly, ends kept, so a step along a line is
        // always about `spacing` and a short dash still has both its ends.
        let points = art.strokes.map { resample($0.points, every: CGFloat(s.spacing)) }
        var offset = [Int](repeating: 0, count: points.count + 1)
        for (i, p) in points.enumerated() { offset[i + 1] = offset[i] + p.count }
        let n = offset.last!
        stats.pointCount = n
        var xs = [Double](repeating: 0, count: n), ys = xs
        var strokeOf = [Int32](repeating: 0, count: n)
        for (si, pts) in points.enumerated() {
            for (k, p) in pts.enumerated() {
                xs[offset[si] + k] = Double(p.x)
                ys[offset[si] + k] = Double(p.y)
                strokeOf[offset[si] + k] = Int32(si)
            }
        }

        // Each stroke's own appetite: a multiplier on what growing along it
        // costs, so neighbouring lines don't fill in lockstep.
        let appetite = points.indices.map { _ in
            1 + s.irregularity * (rng.nextDouble() * 2 - 1)
        }

        // MARK: Neighbourhoods

        let grid = Grid(xs: xs, ys: ys, cell: max(s.reach, 4), size: art.size)

        // MARK: Seeds

        // Spread out rather than clumped: each new seed is the best of a
        // handful of random candidates, the one furthest from the seeds already
        // down. Still random every time, just never two in one corner.
        let lo = max(1, min(s.seedsMin, s.seedsMax)), hi = max(lo, s.seedsMax)
        let seedCount = lo + Int(rng.next() % UInt64(hi - lo + 1))
        var seedNodes: [Int] = []
        if n > 0 {
            for _ in 0..<min(seedCount, n) {
                var best = Int(rng.next() % UInt64(n)), bestScore = -1.0
                for _ in 0..<12 {
                    let c = Int(rng.next() % UInt64(n))
                    let score = seedNodes.map { hypot(xs[$0] - xs[c], ys[$0] - ys[c]) }.min() ?? 0
                    if score > bestScore { best = c; bestScore = score }
                }
                seedNodes.append(best)
            }
        }

        // MARK: Spreading

        var cost = [Double](repeating: .infinity, count: n)
        var done = [Bool](repeating: false, count: n)
        var heap = MinHeap()
        for (i, node) in seedNodes.enumerated() {
            let wake = i == 0 ? 0 : rng.nextDouble() * s.seedStagger
            if wake < cost[node] {
                cost[node] = wake
                heap.push(wake, node)
            }
        }

        let reach2 = s.reach * s.reach
        func spread() {
            while let (c, u) = heap.pop() {
                if done[u] || c > cost[u] { continue }
                done[u] = true
                let su = Int(strokeOf[u])

                // Along its own line, both ways.
                let along = s.spacing * appetite[su]
                for v in [u - 1, u + 1] where v >= offset[su] && v < offset[su + 1] {
                    let step = hypot(xs[u] - xs[v], ys[u] - ys[v]) * appetite[su]
                    let nc = c + (step.isFinite ? step : along)
                    if nc < cost[v] { cost[v] = nc; heap.push(nc, v) }
                }

                // Across the paper, to any other stroke within reach.
                grid.forEachNear(xs[u], ys[u]) { v in
                    guard strokeOf[v] != strokeOf[u], !done[v] else { return }
                    let dx = xs[u] - xs[v], dy = ys[u] - ys[v]
                    let d2 = dx * dx + dy * dy
                    guard d2 <= reach2 else { return }
                    stats.hops += 1
                    let nc = c + d2.squareRoot() * s.paperSlowness
                    if nc < cost[v] { cost[v] = nc; heap.push(nc, v) }
                }
            }
        }
        spread()

        // Whatever is further than `reach` from everything grown is still
        // reached, the long way across the paper, from the nearest point that
        // was. Then it grows on from there as normal.
        while true {
            let stranded = (0..<n).filter { !done[$0] }
            if stranded.isEmpty { break }
            stats.stranded += stranded.count
            for v in stranded {
                if let (u, d) = grid.nearest(to: v, where: { done[$0] }) {
                    let nc = cost[u] + d * s.paperSlowness
                    if nc < cost[v] { cost[v] = nc; heap.push(nc, v) }
                }
            }
            if heap.isEmpty { break } // nothing grown at all: no seeds
            spread()
        }

        // MARK: Seconds

        // Cost is distance travelled. Blended with the share of the ink
        // reached by then (`evenness`), so the order is the growth's either
        // way, then bent by `pace`: above 1 covers the first stretch quickly
        // and slows after.
        let finite = cost.filter(\.isFinite)
        let maxCost = max(finite.max() ?? 1, 1e-9)
        var share = [Double](repeating: 1, count: n)
        let byCost = (0..<n).sorted { cost[$0] < cost[$1] }
        for (rank, i) in byCost.enumerated() { share[i] = n > 1 ? Double(rank) / Double(n - 1) : 1 }
        var times: [[Double]] = []
        var first: [Double] = [], last: [Double] = []
        times.reserveCapacity(points.count)
        for si in points.indices {
            let t = (offset[si]..<offset[si + 1]).map { i -> Double in
                let distance = cost[i].isFinite ? min(cost[i] / maxCost, 1) : 1
                let x = distance * (1 - s.evenness) + share[i] * s.evenness
                return s.duration * pow(x, s.pace)
            }
            times.append(t)
            first.append(t.min() ?? 0)
            last.append(t.max() ?? 0)
        }

        stats.milliseconds = Date().timeIntervalSince(clock) * 1000
        return Growth(seeds: seedNodes.map { CGPoint(x: xs[$0], y: ys[$0]) },
                      points: points, times: times, firstTime: first, lastTime: last,
                      duration: s.duration, randomSeed: randomSeed, stats: stats)
    }

    /// Evenly spaced points along a polyline, its two ends always included.
    static func resample(_ line: [CGPoint], every step: CGFloat) -> [CGPoint] {
        guard line.count > 1 else { return line + line }
        var total: CGFloat = 0
        for i in 1..<line.count { total += dist(line[i - 1], line[i]) }
        let count = max(1, Int((total / step).rounded()))
        let spacing = total / CGFloat(count)
        var out = [line[0]]
        var i = 1, segStart: CGFloat = 0
        for k in 1..<count {
            let target = spacing * CGFloat(k)
            while i < line.count {
                let seg = dist(line[i - 1], line[i])
                if segStart + seg >= target {
                    let f = seg > 0 ? (target - segStart) / seg : 0
                    out.append(CGPoint(x: line[i - 1].x + (line[i].x - line[i - 1].x) * f,
                                       y: line[i - 1].y + (line[i].y - line[i - 1].y) * f))
                    break
                }
                segStart += seg
                i += 1
            }
        }
        out.append(line[line.count - 1])
        return out
    }
}

// MARK: - Pieces

/// Points bucketed into square cells, for finding what is near a point
/// without looking at everything.
private struct Grid {
    let cell: Double
    let cols: Int, rows: Int
    var buckets: [[Int]]
    let xs: [Double], ys: [Double]

    init(xs: [Double], ys: [Double], cell: Double, size: CGSize) {
        self.cell = cell
        self.xs = xs; self.ys = ys
        let maxX = max(Double(size.width), xs.max() ?? 0), maxY = max(Double(size.height), ys.max() ?? 0)
        cols = max(1, Int(maxX / cell) + 1)
        rows = max(1, Int(maxY / cell) + 1)
        buckets = Array(repeating: [], count: cols * rows)
        for i in xs.indices { buckets[index(xs[i], ys[i])].append(i) }
    }

    func index(_ x: Double, _ y: Double) -> Int {
        let c = min(max(Int(x / cell), 0), cols - 1), r = min(max(Int(y / cell), 0), rows - 1)
        return r * cols + c
    }

    /// Everything in this cell and the eight around it — within one cell
    /// width of the point, and some further.
    func forEachNear(_ x: Double, _ y: Double, _ body: (Int) -> Void) {
        let c = min(max(Int(x / cell), 0), cols - 1), r = min(max(Int(y / cell), 0), rows - 1)
        for rr in max(r - 1, 0)...min(r + 1, rows - 1) {
            for cc in max(c - 1, 0)...min(c + 1, cols - 1) {
                for i in buckets[rr * cols + cc] { body(i) }
            }
        }
    }

    /// The nearest point passing `test`, searching outward ring by ring.
    func nearest(to v: Int, where test: (Int) -> Bool) -> (Int, Double)? {
        let c = min(max(Int(xs[v] / cell), 0), cols - 1), r = min(max(Int(ys[v] / cell), 0), rows - 1)
        var best: (Int, Double)?
        for ring in 0...max(cols, rows) {
            // Anything in a further ring is at least (ring - 1) cells away.
            if let b = best, b.1 < Double(ring - 1) * cell { break }
            for rr in (r - ring)...(r + ring) where rr >= 0 && rr < rows {
                for cc in (c - ring)...(c + ring) where cc >= 0 && cc < cols {
                    guard abs(rr - r) == ring || abs(cc - c) == ring else { continue }
                    for i in buckets[rr * cols + cc] where test(i) {
                        let d = hypot(xs[i] - xs[v], ys[i] - ys[v])
                        if best == nil || d < best!.1 { best = (i, d) }
                    }
                }
            }
        }
        return best
    }
}

private struct MinHeap {
    private var items: [(Double, Int)] = []
    var isEmpty: Bool { items.isEmpty }

    mutating func push(_ key: Double, _ value: Int) {
        items.append((key, value))
        var i = items.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            if items[p].0 <= items[i].0 { break }
            items.swapAt(p, i); i = p
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count, items[l].0 < items[m].0 { m = l }
                if r < items.count, items[r].0 < items[m].0 { m = r }
                if m == i { break }
                items.swapAt(m, i); i = m
            }
        }
        return top
    }
}

/// A small seeded random generator, so a growth can be replayed exactly.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextDouble() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
