// Renders the six mood icons (Figma, node 331:539 — the same artwork the iPhone
// app uses) as macOS icons: the design's rounded tile set on the macOS icon
// grid — 824 of 1024, centred — with the soft shadow macOS icons carry, on a
// transparent canvas.
//
// The iPhone flattens these onto a full square because iOS rounds icons
// itself. macOS draws an icon exactly as it is handed over, so the shape, the
// inset and the shadow have to be in the picture.
//
// Rendered through WebKit for the reasons render-frames.swift gives (AppKit's
// SVG support is partial and drops masks). Each SVG goes in as its own <img>,
// a document of its own, because the six share element ids (`clip0_0_4`) that
// would collide inline on one page.
//
// Usage: render-icons.swift <svg dir> <out dir>   — writes <mood>.png at 1024px
import AppKit
import WebKit

let svgDir = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let side = 1024
let moods = ["cream", "mint", "sky", "coral", "lilac", "orchid"]

let cell = 1024.0, tile = 824.0
let pageW = cell * Double(moods.count), pageH = cell

func page() -> String {
    let cells = moods.map { mood -> String in
        let svg = try! Data(contentsOf: URL(fileURLWithPath: "\(svgDir)/\(mood).svg"))
        return "<div class='c'><img src='data:image/svg+xml;base64,\(svg.base64EncodedString())'></div>"
    }.joined()
    return """
    <!doctype html><html><head><style>
      html,body{margin:0;padding:0;background:transparent}
      .g{display:flex;width:\(Int(pageW))px}
      .c{width:\(Int(cell))px;height:\(Int(cell))px;flex:none;display:flex;
         align-items:center;justify-content:center}
      /* a soft shadow below the tile, as macOS icons have */
      .c img{width:\(Int(tile))px;height:\(Int(tile))px;display:block;
             filter:drop-shadow(0 10px 14px rgba(0,0,0,.24))}
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
                if let img, let tiff = img.tiffRepresentation { self.image = NSBitmapImageRep(data: tiff) }
                self.done = true
            }
        }
    }
}

let web = WKWebView(frame: NSRect(x: 0, y: 0, width: pageW, height: pageH),
                    configuration: WKWebViewConfiguration())
// Load-bearing, as in render-frames.swift: without it there is no alpha.
web.setValue(false, forKey: "drawsBackground")
let shot = Shot()
web.navigationDelegate = shot
web.loadHTMLString(page(), baseURL: nil)
let deadline = Date().addingTimeInterval(120)
while !shot.done, Date() < deadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
}
guard let sheet = shot.image else { fatalError("snapshot failed") }
guard sheet.samplesPerPixel > 3 else { fatalError("snapshot has no alpha channel") }
let px = Double(sheet.pixelsWide) / pageW
let cellPx = Int(cell * px)

for (i, mood) in moods.enumerated() {
    // Cut this mood's cell out of the sheet, then draw it at 1024.
    guard let cropped = sheet.cgImage?.cropping(to: CGRect(x: i * cellPx, y: 0, width: cellPx, height: cellPx))
    else { fatalError("\(mood): crop failed") }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    NSGraphicsContext.current!.cgContext.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    // The corners must be clear, or macOS shows a square — check the very corner.
    let corner = rep.colorAt(x: 4, y: 4)?.alphaComponent ?? 1
    let middle = rep.colorAt(x: side / 2, y: side / 2)?.alphaComponent ?? 0
    guard corner < 0.05, middle > 0.95 else {
        fatalError("\(mood): corner alpha \(corner), centre alpha \(middle) — not an icon shape")
    }
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(mood).png"))
    print("\(mood): \(side)px, \(data.count / 1024) KB")
}
