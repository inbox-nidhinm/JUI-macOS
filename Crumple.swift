import AppKit
import SceneKit

// A sticky, put away, is a sheet crumpled into a ball in the margin. Clicked,
// the ball lifts, comes to the card's place and opens out flat into it; put
// away again, the card crushes back into a ball and drops into the margin.
//
// Carried over from the iPhone port (JUI-iOS, `Crumple.swift`), which built it
// from a web prototype — its "fluid" motion at crease depth 0.8 — and every
// number here is that one's. The phone needed the ball because it has no
// margin to hold a card; the Mac took it so a sticky behaves the same in both
// places, and a page with several notes on it reads as a page rather than as a
// noticeboard.
//
// The card itself is an AppKit view and can't fold, so the fold is a stand-in:
// a sheet of a few thousand points drawn by SceneKit, textured with a picture
// of the card, bent between a crumpled ball and flat. The real card appears
// only once the sheet has landed flat in exactly its place — which is also why
// the card's flourish only starts drawing itself after the unfold — and on the
// way out the sheet takes over from the card the same way round.
//
// Everything in here is measured in the page's own points, y down, the way the
// page (a flipped view) measures them.

// MARK: - Creases

// Perlin noise, seeded as the prototype's, so the ball has the same creases.
enum Crease {
    private static let perm: [Int] = {
        var p = Array(0..<256)
        var seed = 7
        for i in stride(from: 255, to: 0, by: -1) {
            seed = (seed * 16807) % 2147483647
            p.swapAt(i, seed % (i + 1))
        }
        return p + p
    }()

    private static func fade(_ t: Float) -> Float { t * t * t * (t * (t * 6 - 15) + 10) }
    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    private static func grad(_ h: Int, _ x: Float, _ y: Float, _ z: Float) -> Float {
        let u = h < 8 ? x : y
        let v = h < 4 ? y : (h == 12 || h == 14 ? x : z)
        return ((h & 1) != 0 ? -u : u) + ((h & 2) != 0 ? -v : v)
    }

    static func noise(_ x: Float, _ y: Float, _ z: Float) -> Float {
        let X = Int(x.rounded(.down)) & 255, Y = Int(y.rounded(.down)) & 255, Z = Int(z.rounded(.down)) & 255
        let x = x - x.rounded(.down), y = y - y.rounded(.down), z = z - z.rounded(.down)
        let u = fade(x), v = fade(y), w = fade(z)
        let A = perm[X] + Y, AA = perm[A] + Z, AB = perm[A + 1] + Z
        let B = perm[X + 1] + Y, BA = perm[B] + Z, BB = perm[B + 1] + Z
        return lerp(lerp(lerp(grad(perm[AA] & 15, x, y, z), grad(perm[BA] & 15, x - 1, y, z), u),
                         lerp(grad(perm[AB] & 15, x, y - 1, z), grad(perm[BB] & 15, x - 1, y - 1, z), u), v),
                    lerp(lerp(grad(perm[AA + 1] & 15, x, y, z - 1), grad(perm[BA + 1] & 15, x - 1, y, z - 1), u),
                         lerp(grad(perm[AB + 1] & 15, x, y - 1, z - 1), grad(perm[BB + 1] & 15, x - 1, y - 1, z - 1), u), v), w)
    }

    /// Sharp lines where the noise crosses zero: fold lines.
    static func ridge(_ x: Float, _ y: Float, _ z: Float) -> Float {
        let n = 1 - abs(noise(x, y, z))
        return n * n
    }
}

// MARK: - The sheet

/// One sticky's sheet: every point of it laid flat (the card) and crumpled
/// (the ball), and when each starts to open. Points are in the card's own
/// points, centred, y up.
struct CrumpleSheet {
    /// How crinkled the ball is, 0…1 — the prototype's slider, settled at 0.8.
    static let depth: Float = 0.8
    /// The ball beside the words, across — small enough to sit in the air
    /// above the line without covering the next word.
    static let ballDiameter: Float = 14
    /// The centre of the sheet opens first and the edges last, by this much
    /// of the unfold.
    static let delaySpread: Float = 0.32

    let size: CGSize
    let columns: Int
    let rows: Int
    /// The ball's radius before it is scaled down to the margin — sized to
    /// the sheet's area, so a tall sticky makes a ball as round as a square one.
    let radius: Float
    private(set) var flat: [SIMD3<Float>] = []
    private(set) var ball: [SIMD3<Float>] = []
    private(set) var delay: [Float] = []
    private(set) var wrinkle: [Float] = []

    init(size: CGSize, depth: Float = CrumpleSheet.depth) {
        self.size = size
        let w = Float(max(size.width, 1)), h = Float(max(size.height, 1))
        columns = 56
        rows = min(140, max(8, Int((56 * h / w).rounded())))
        radius = 58 * (w * h).squareRoot() / 280
        for row in 0...rows {
            for column in 0...columns {
                let x: Float = (Float(column) / Float(columns) - 0.5) * w
                let y: Float = (0.5 - Float(row) / Float(rows)) * h
                flat.append(SIMD3<Float>(x, y, 0))
                let u: Float = x / (w / 2), v: Float = y / (h / 2)
                let r: Float = min(1, (u * u + v * v).squareRoot() / Float(2).squareRoot())
                // Gathered like a handkerchief: the middle of the sheet faces
                // out, the edges are drawn round to the back, with a twist as
                // they go.
                let theta: Float = atan2(v, u) + r * 1.4
                let alpha: Float = r * .pi * 0.93
                let d = SIMD3<Float>(sin(alpha) * cos(theta), sin(alpha) * sin(theta), cos(alpha))
                let lump: Float = 1 + 0.14 * Crease.noise(d.x * 1.6 + 3.1, d.y * 1.6, d.z * 1.6)
                let coarse: Float = Crease.ridge(d.x * 2.6, d.y * 2.6, d.z * 2.6)
                let fine: Float = Crease.ridge(d.x * 5.3 + 9, d.y * 5.3, d.z * 5.3)
                let crease: Float = coarse * 0.62 + fine * 0.38 - 0.5
                let reach: Float = radius * (lump + crease * 0.42 * depth)
                ball.append(d * reach)
                delay.append(r * Self.delaySpread)
                // Creases left in the paper as it flattens, gone once it's flat.
                let broad: Float = Crease.ridge(u * 2.2 + 4, v * 2.2, 1.7)
                let small: Float = Crease.ridge(u * 4.4, v * 4.4 + 2, 5.1)
                let left: Float = (broad * 0.7 + small * 0.3 - 0.45) * 26 * depth
                wrinkle.append(left)
            }
        }
    }

    var count: Int { flat.count }

    /// Texture coordinates, the image's top left at (0, 0).
    var uvs: [CGPoint] {
        var out: [CGPoint] = []
        out.reserveCapacity(count)
        for row in 0...rows {
            for column in 0...columns {
                out.append(CGPoint(x: Double(column) / Double(columns), y: Double(row) / Double(rows)))
            }
        }
        return out
    }

    /// Two triangles a cell, wound so the card's face is the front.
    var indices: [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(columns * rows * 6)
        let stride = UInt32(columns + 1)
        for row in 0..<UInt32(rows) {
            for column in 0..<UInt32(columns) {
                let a = column + stride * row, b = column + stride * (row + 1)
                let c = column + 1 + stride * (row + 1), d = column + 1 + stride * row
                out += [a, b, d, b, c, d]
            }
        }
        return out
    }

    /// Every point, `unfold` of the way from the ball to flat (0…1).
    func positions(unfold: Float, into out: inout [SCNVector3]) {
        if out.count != count { out = Array(repeating: SCNVector3Zero, count: count) }
        let span = 1 - Self.delaySpread
        for i in 0..<count {
            let p = Ease.inOutCubic(Ease.clamp((unfold - delay[i]) / span))
            let settle = 4 * p * (1 - p) // creases linger mid-way
            let at = ball[i] + (flat[i] - ball[i]) * p
            out[i] = SCNVector3(at.x, at.y, at.z + wrinkle[i] * settle)
        }
    }
}

enum Ease {
    static func clamp(_ t: Float) -> Float { min(1, max(0, t)) }
    static func outCubic(_ t: Float) -> Float { 1 - pow(1 - t, 3) }
    static func inOutCubic(_ t: Float) -> Float { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
}

// MARK: - The scene

/// The sheet, its shadow, the light and an orthographic camera measured in
/// points — rendered by the stage over the page, or offscreen for the
/// margin's ball.
final class CrumpleScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let sheetNode = SCNNode()
    private let shadowNode = SCNNode()
    private var sheet: CrumpleSheet?
    private var buffer: [SCNVector3] = []
    private var normals: SCNGeometrySource?
    private var uvs: SCNGeometrySource?
    private var element: SCNGeometryElement?
    private let front = CrumpleScene.paper(cull: .back)
    private let back = CrumpleScene.paper(cull: .front)
    private(set) var viewport = CGSize(width: 1, height: 1)

    init() {
        scene.background.contents = NSColor.clear
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.zNear = 1
        camera.zFar = 4000
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 1000)
        scene.rootNode.addChildNode(cameraNode)

        // Lit so that the sheet, lying flat, comes out the colour of the card
        // it hands over to: ambient plus the sun's share facing it is 1.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 600
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 500
        sun.position = SCNVector3(-400, 600, 1000)
        sun.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(sun)

        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.writesToDepthBuffer = false
        shadowNode.geometry = SCNPlane(width: 1, height: 1)
        shadowNode.geometry?.materials = [shadowMaterial]
        scene.rootNode.addChildNode(shadowNode)
        scene.rootNode.addChildNode(sheetNode)
        rest()
    }

    // Paper is lit as matte facets — the normals come from the facets
    // themselves, so every crease catches the light — and the stamp's
    // perforations are cut out of it.
    private static func paper(cull: SCNCullMode) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.cullMode = cull
        m.transparencyMode = .aOne
        m.diffuse.mipFilter = .linear
        m.shaderModifiers = [
            .surface: """
            #pragma body
            _surface.normal = normalize(cross(dfdy(_surface.position), dfdx(_surface.position)));
            """,
            .fragment: """
            #pragma body
            if (_output.color.a < 0.5) { discard_fragment(); }
            """,
        ]
        return m
    }

    func setViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewport = size
        cameraNode.camera?.orthographicScale = Double(size.height / 2)
    }

    /// A new sheet the size of the card, with the card's two faces.
    func load(size: CGSize, front frontImage: NSImage, back backImage: NSImage) {
        if sheet?.size != size {
            let sheet = CrumpleSheet(size: size)
            self.sheet = sheet
            normals = SCNGeometrySource(normals: Array(repeating: SCNVector3(0, 0, 1), count: sheet.count))
            uvs = SCNGeometrySource(textureCoordinates: sheet.uvs)
            element = SCNGeometryElement(indices: sheet.indices, primitiveType: .triangles)
        }
        front.diffuse.contents = frontImage
        back.diffuse.contents = backImage
        let shadow = CrumpleArt.shadow(for: size)
        shadowNode.geometry?.firstMaterial?.diffuse.contents = shadow
        (shadowNode.geometry as? SCNPlane)?.width = shadow.size.width
        (shadowNode.geometry as? SCNPlane)?.height = shadow.size.height
    }

    /// Nothing to show: the sheet put away.
    func rest() {
        sheetNode.isHidden = true
        shadowNode.isHidden = true
    }

    /// The sheet at `t` of the way from the ball at `mark` (0) to flat over
    /// `card` (1), both in the viewport's points, y down. No mark: it crumples
    /// to nothing where it is — a sticky deleted, rather than put away.
    func pose(_ t: Float, mark: CGPoint?, card: CGRect, elapsed: Float) {
        guard let sheet, let normals, let uvs, let element else { return }
        let travel = Ease.outCubic(Ease.clamp(t / 0.42))
        let unfold = Ease.clamp((t - 0.26) / 0.74)
        sheet.positions(unfold: unfold, into: &buffer)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: buffer), normals, uvs],
                                   elements: [element, element])
        geometry.materials = [front, back]
        sheetNode.geometry = geometry

        let end = scenePoint(CGPoint(x: card.midX, y: card.midY))
        let start = mark.map(scenePoint) ?? end
        let lift = sin(travel * .pi) * 46 // an arc on the way
        sheetNode.position = SCNVector3(start.x + (end.x - start.x) * travel,
                                        start.y + (end.y - start.y) * travel + lift, 0)
        let closed = mark == nil ? 0.001 : CrumpleSheet.ballDiameter / (2 * sheet.radius)
        let scale = closed + (1 - closed) * travel
        sheetNode.scale = SCNVector3(scale, scale, scale)
        let tumble = 1 - unfold
        sheetNode.eulerAngles = SCNVector3(
            tumble * 0.55 + (1 - travel) * 0.2 * sin(elapsed * 1.2),
            tumble * (0.9 + (1 - travel) * 1.6),
            tumble * -0.5)
        shadowNode.position = SCNVector3(end.x, end.y, -900)
        // Only as the sheet comes down flat, once it covers the card's
        // footprint — earlier, the clear middle showed as a pale outline.
        shadowNode.opacity = CGFloat(Ease.clamp((unfold - 0.8) / 0.2))
        sheetNode.isHidden = false
        shadowNode.isHidden = false
    }

    private func scenePoint(_ p: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(p.x - viewport.width / 2), Float(viewport.height / 2 - p.y))
    }
}

// MARK: - Pictures

enum CrumpleArt {
    /// The card's soft shadow, for while the sheet lies flat — with the card's
    /// own footprint left clear, so it never shows through a lifting corner.
    static func shadow(for size: CGSize) -> NSImage {
        let pad: CGFloat = 30
        let canvas = CGSize(width: size.width + pad * 2, height: size.height + pad * 2)
        return NSImage(size: canvas, flipped: false) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let card = CGRect(x: pad, y: pad, width: size.width, height: size.height)
            cg.setShadow(offset: .zero, blur: 20, color: NSColor.black.withAlphaComponent(0.08).cgColor)
            cg.setFillColor(NSColor.black.cgColor)
            cg.fill(card)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            cg.clear(card)
            return true
        }
    }

    /// The ball in the margin: `paper` — a blank card — crumpled, at rest.
    /// Rendered once per mood by whoever holds the paper.
    static func ball(from paper: NSImage, scale: CGFloat) -> NSImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let side = ballCanvas
        let crumple = CrumpleScene()
        crumple.setViewport(CGSize(width: side, height: side))
        crumple.load(size: paper.size, front: paper, back: paper)
        let centre = CGPoint(x: side / 2, y: side / 2)
        crumple.pose(0, mark: centre, card: CGRect(origin: centre, size: .zero).insetBy(dx: -1, dy: -1),
                     elapsed: 0)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = crumple.scene
        renderer.pointOfView = crumple.cameraNode
        let shot = renderer.snapshot(atTime: 0, with: CGSize(width: side * scale, height: side * scale),
                                     antialiasingMode: .multisampling4X)
        shot.size = CGSize(width: side, height: side)
        return shot
    }

    /// The ball's picture, across — a little more than the ball, for its
    /// creases to stand out from.
    static let ballCanvas: CGFloat = 18
}

// MARK: - Running it

/// The stage the sheet is drawn on: a SceneKit view laid over the page while
/// a sheet is moving, and hidden otherwise. It never takes a click.
final class CrumpleStageView: SCNView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Runs the fold for one page, and decides when the real card is on screen.
/// The page tells it where the ball and the card are, and is told back when
/// the card should show, and when the ball should.
final class CrumpleDirector: NSObject {
    let stage = CrumpleScene()
    let view: CrumpleStageView

    /// The sticky whose real card is showing — set once its sheet has landed
    /// flat, cleared once a sheet has taken its place on the way out.
    private(set) var cardID: UUID?
    /// The sticky whose ball has left the margin.
    private(set) var flyingID: UUID? {
        didSet { if flyingID != oldValue { onFlight?() } }
    }
    var isMoving: Bool { link != nil }

    /// The card has landed flat: show it.
    var onCardLanded: ((UUID) -> Void)?
    /// The sheet has taken over from the card: hide it.
    var onCardLeft: ((UUID) -> Void)?
    /// Which ball is in the air has changed.
    var onFlight: (() -> Void)?

    static let openSeconds: Float = 1.15
    static let closeSeconds: Float = 0.95
    // How long a hand-over keeps both the card and the sheet on screen, so
    // neither leaves before the other has drawn.
    private static let handOver: TimeInterval = 0.05

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var t: Float = 0
    private var target: Float = 0
    private var elapsed: Float = 0
    private var id: UUID?
    private var mark: CGPoint?
    private var card: CGRect = .zero

    override init() {
        view = CrumpleStageView(frame: .zero, options: nil)
        super.init()
        view.scene = stage.scene
        view.pointOfView = stage.cameraNode
        view.backgroundColor = .clear
        // see-through, so only the sheet and its shadow cover the page
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = false
        view.isHidden = true
    }

    /// Compiles the paper's shaders now rather than on the first click.
    func prepare(paper: NSImage) {
        stage.load(size: paper.size, front: paper, back: paper)
        stage.setViewport(CGSize(width: 400, height: 400))
        stage.pose(1, mark: nil, card: CGRect(x: -100, y: -100, width: 40, height: 40), elapsed: 0)
        view.prepare([stage.scene]) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.isMoving else { return }
                self.stage.rest()
            }
        }
    }

    /// Where the stage sits on the page while a sheet moves. The page sets it
    /// before each run, wide enough for the ball, the card and the arc between.
    private var stageFrame: CGRect = .zero

    private func local(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - stageFrame.minX, y: p.y - stageFrame.minY)
    }

    /// Takes `id` out of its ball at `mark` and opens it flat into `frame`,
    /// all in page points. `face` is the card as it will look, `back` its
    /// blank reverse.
    func open(_ id: UUID, face: NSImage, back: NSImage, frame: CGRect, mark: CGPoint?, stage stageFrame: CGRect) {
        if self.id == id, link != nil { // put away and taken out again mid-way
            target = 1
            return
        }
        stop()
        cardID = nil
        self.id = id
        self.stageFrame = stageFrame
        card = frame.offsetBy(dx: -stageFrame.minX, dy: -stageFrame.minY)
        self.mark = mark.map(local)
        stage.load(size: frame.size, front: face, back: back)
        t = 0
        target = 1
        run()
        // The ball in the scene is drawing now; the one in the margin can go.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handOver) { [weak self] in
            if self?.id == id { self?.flyingID = id }
        }
    }

    /// Puts `id`'s card at `frame` away into its ball at `mark` — or, with no
    /// mark, crumples it to nothing where it is (deleted, or never written).
    func close(_ id: UUID, face: NSImage, back: NSImage, frame: CGRect, mark: CGPoint?, stage stageFrame: CGRect) {
        if self.id == id, link != nil, target == 1 { // still opening: turn back
            target = 0
            if mark == nil { self.mark = nil }
            return
        }
        stop()
        self.id = id
        self.stageFrame = stageFrame
        card = frame.offsetBy(dx: -stageFrame.minX, dy: -stageFrame.minY)
        self.mark = mark.map(local)
        stage.load(size: frame.size, front: face, back: back)
        t = 1
        target = 0
        flyingID = id
        run()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handOver) { [weak self] in
            guard let self, self.cardID == id else { return }
            self.cardID = nil
            self.onCardLeft?(id)
        }
    }

    /// Everything back where it rests, at once — a note switched, or another
    /// sticky taken out while this one was moving.
    func reset() {
        stop()
        cardID = nil
        flyingID = nil
        id = nil
        stage.rest()
        view.isHidden = true
        view.rendersContinuously = false
    }

    private func run() {
        view.frame = stageFrame
        stage.setViewport(stageFrame.size)
        view.isHidden = false
        elapsed = 0
        last = CACurrentMediaTime()
        stage.pose(t, mark: mark, card: card, elapsed: elapsed)
        view.rendersContinuously = true
        let link = view.displayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stop() {
        link?.invalidate()
        link = nil
        if let shown = cardID, shown != id {
            cardID = nil
            onCardLeft?(shown)
        }
        flyingID = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = min(0.05, Float(now - last))
        last = now
        elapsed += dt
        if t != target {
            let step = dt / (target > t ? Self.openSeconds : Self.closeSeconds)
            t = target > t ? min(target, t + step) : max(target, t - step)
        }
        stage.pose(t, mark: mark, card: card, elapsed: elapsed)
        if t == target { landed() }
    }

    private func landed() {
        link?.invalidate()
        link = nil
        guard let id = self.id else { return }
        if target == 1 {
            cardID = id // the real card, flat where the sheet is; its flourish starts now
            onCardLanded?(id)
        } else {
            flyingID = nil // the ball is back in the margin
            self.id = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handOver) { [weak self] in
            guard let self, self.link == nil else { return }
            self.stage.rest()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self.link == nil else { return }
                self.view.rendersContinuously = false
                self.view.isHidden = true
            }
        }
    }
}
