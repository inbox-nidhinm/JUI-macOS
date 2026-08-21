// Rasterises the split animation frames into template PNGs the app can play.
//
// Rendered through WebKit, not AppKit. AppKit will load an SVG, but it drops
// <mask> entirely — and the later frames of this animation are drawn by masking
// a full-bleed rect, so the mask *is* the shape. Rendered with AppKit, every
// masked element vanishes and the flourish comes out as a sparse sprig with its
// blooms missing. Nothing errors; the content is simply not there, which is why
// it read as "the animation ends early" rather than as a broken renderer.
//
// The snapshot carries real alpha, including antialiased edges, provided the
// web view is told not to draw its own background. Without that one line it
// comes back fully opaque and every frame reads as a solid block.
//
// All thirty frames go on a single page, so this is one render rather than
// thirty.
import AppKit
import WebKit

let svgDir = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let targetHeight = Double(CommandLine.arguments[3])!
// Optional flip-and-rotate, so the same source serves the upright corner mark
// and the rotated ones on folder tiles and stickies. Applied in CSS and left to
// WebKit, which also means the crop below measures the *transformed* ink and
// needs no separate maths. `rotate(θ) scaleY(-1)` is flip-then-rotate in CSS's
// right-to-left order — the same composition the static assets were baked with.
let degrees = CommandLine.arguments.count > 4 ? Double(CommandLine.arguments[4])! : 0
// Zero means *no transform at all*, not "rotate by nothing": the flip has to go
// with the rotation or not happen. Applying `scaleY(-1)` unconditionally turned
// the upright corner mark upside down while leaving the rotated sets correct,
// which is a hard thing to spot in a contact sheet of a symmetrical-looking
// sprig and an easy one to spot in the corner of the page.
let transform = degrees == 0 ? "none" : "rotate(\(degrees)deg) scaleY(-1)"

let files = (try! FileManager.default.contentsOfDirectory(atPath: svgDir))
    .filter { $0.hasSuffix(".svg") }.sorted()
guard !files.isEmpty else { fatalError("no frames in \(svgDir)") }

let cell = 540.0, columns = 6
let rows = Int((Double(files.count) / Double(columns)).rounded(.up))
let pageW = cell * Double(columns), pageH = cell * Double(rows)

func page() -> String {
    let cells = files.map { f -> String in
        let svg = try! String(contentsOfFile: "\(svgDir)/\(f)", encoding: .utf8)
        return "<div class='c'>\(svg)</div>"
    }.joined()
    return """
    <!doctype html><html><head><style>
      html,body{margin:0;padding:0;background:transparent}
      .g{display:grid;grid-template-columns:repeat(\(columns),\(Int(cell))px);width:\(Int(pageW))px}
      .c{width:\(Int(cell))px;height:\(Int(cell))px;overflow:hidden;
         display:flex;align-items:center;justify-content:center}
      /* drawn smaller than the cell so a rotation cannot clip at the corners:
         a 380 square has a 537 diagonal, inside the 540 cell */
      .c svg{width:380px !important;height:380px !important;display:block;
             transform:\(transform);transform-origin:center}
    </style></head><body><div class='g'>\(cells)</div></body></html>
    """
}

_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.accessory)

final class Shot: NSObject, WKNavigationDelegate {
    var image: NSBitmapImageRep?
    var done = false
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let cfg = WKSnapshotConfiguration()
            cfg.rect = CGRect(origin: .zero, size: w.bounds.size)
            w.takeSnapshot(with: cfg) { img, _ in
                if let img = img, let tiff = img.tiffRepresentation {
                    self.image = NSBitmapImageRep(data: tiff)
                }
                self.done = true
            }
        }
    }
}

func render() -> NSBitmapImageRep {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: pageW, height: pageH),
                        configuration: WKWebViewConfiguration())
    // Load-bearing: without it the snapshot is opaque and there is no coverage
    // to read, so every frame comes out a solid rectangle.
    web.setValue(false, forKey: "drawsBackground")
    let shot = Shot()
    web.navigationDelegate = shot
    web.loadHTMLString(page(), baseURL: nil)
    let deadline = Date().addingTimeInterval(120)
    while !shot.done, Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    guard let image = shot.image else { fatalError("snapshot failed") }
    return image
}

let sheet = render()
// the snapshot comes back at the display's scale, not the view's point size
let px = Double(sheet.pixelsWide) / pageW
print(String(format: "rendered %dx%d at %.0fx", sheet.pixelsWide, sheet.pixelsHigh, px))
guard sheet.samplesPerPixel > 3 else { fatalError("snapshot has no alpha channel") }

let w = sheet.pixelsWide, h = sheet.pixelsHigh
let src = sheet.bitmapData!
let bpr = sheet.bytesPerRow, spp = sheet.samplesPerPixel

var alpha = [Double](repeating: 0, count: w * h)
for i in 0..<(w * h) {
    alpha[i] = Double(src[(i / w) * bpr + (i % w) * spp + 3]) / 255
}
let covered = alpha.reduce(0) { $0 + ($1 > 0.02 ? 1 : 0) }
guard covered > 0, covered < alpha.count * 9 / 10 else {
    fatalError("coverage looks wrong (\(covered) of \(alpha.count)) — is drawsBackground still off?")
}

func cellRect(_ index: Int) -> (x: Int, y: Int, w: Int, h: Int) {
    let col = index % columns, row = index / columns
    return (Int(Double(col) * cell * px), Int(Double(row) * cell * px),
            Int(cell * px), Int(cell * px))
}

// bounds of the LAST frame, shared by all of them: cropping each to its own
// would re-centre the drawing on every tick and the flourish would swim about
// while drawing itself
let lastCell = cellRect(files.count - 1)
var minX = lastCell.w, maxX = -1, minY = lastCell.h, maxY = -1
for y in 0..<lastCell.h {
    for x in 0..<lastCell.w where alpha[(lastCell.y + y) * w + lastCell.x + x] > 0.08 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX >= minX else { fatalError("the last frame rendered empty") }
let pad = Int(6 * px)
let box = (x: max(0, minX - pad), y: max(0, minY - pad),
           w: min(lastCell.w, maxX + pad) - max(0, minX - pad),
           h: min(lastCell.h, maxY + pad) - max(0, minY - pad))
let scale = targetHeight / Double(box.h)
let outW = Int((Double(box.w) * scale).rounded()), outH = Int(targetHeight)
print("crop \(box.w)x\(box.h) -> \(outW)x\(outH) px")

var total = 0
for (i, _) in files.enumerated() {
    let c = cellRect(i)
    // white silhouette carrying the solved coverage; the app supplies the colour
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: box.w, pixelsHigh: box.h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: box.w * 4, bitsPerPixel: 32)!
    let out = rep.bitmapData!
    for y in 0..<box.h {
        for x in 0..<box.w {
            let a = alpha[(c.y + box.y + y) * w + c.x + box.x + x]
            let o = y * box.w * 4 + x * 4
            // Premultiplied, which is what NSBitmapImageRep stores by default.
            // Writing 255 with a partial alpha is not valid premultiplied data
            // and reads back as fully opaque — every frame came out a solid
            // block until this matched.
            let v = UInt8((a * 255).rounded())
            out[o] = v; out[o + 1] = v; out[o + 2] = v
            out[o + 3] = v
        }
    }
    // scale to the target height
    let scaled = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: outW, pixelsHigh: outH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: outW * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled)
    NSGraphicsContext.current!.imageInterpolation = .high
    let img = NSImage(size: NSSize(width: box.w, height: box.h))
    img.addRepresentation(rep)
    img.draw(in: NSRect(x: 0, y: 0, width: outW, height: outH))
    NSGraphicsContext.restoreGraphicsState()

    let data = scaled.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: String(format: "%@/frame-%02d.png", outDir, i + 1)))
    total += data.count
}
print("wrote \(files.count) frames, \(total / 1024) KB total")
