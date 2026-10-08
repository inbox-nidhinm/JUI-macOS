// Rasterises the sticky's delete and done marks into template PNGs.
//
// The marks are the Figma system's own vectors (node 330:433), drawn with a
// scatter brush — hundreds of <use> stamps of one small stroke — so they are
// rendered through WebKit for the same reason the flourish frames are (see
// render-frames.swift): AppKit's SVG loading is macOS 14+ and partial, and
// this app has to open on 13.
//
// Unlike the flourish, nothing is cropped. Each SVG is the system's whole
// 60 × 60 tile with its pieces placed where the frame places them, and the
// app draws the tile, so the mark lands exactly where the design puts it.
//
// Usage: render-marks.swift <svg dir> <out dir> <pixels per side>
import AppKit
import WebKit

let svgDir = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let side = Int(CommandLine.arguments[3])!

let files = (try! FileManager.default.contentsOfDirectory(atPath: svgDir))
    .filter { $0.hasSuffix(".svg") }.sorted()
guard !files.isEmpty else { fatalError("no marks in \(svgDir)") }

// One page, one cell per mark, each drawn at the full cell size.
let cell = 240.0
let pageW = cell * Double(files.count), pageH = cell

func page() -> String {
    let cells = files.map { f -> String in
        let svg = try! String(contentsOfFile: "\(svgDir)/\(f)", encoding: .utf8)
        return "<div class='c'>\(svg)</div>"
    }.joined()
    return """
    <!doctype html><html><head><style>
      html,body{margin:0;padding:0;background:transparent}
      .g{display:flex;width:\(Int(pageW))px}
      .c{width:\(Int(cell))px;height:\(Int(cell))px;overflow:hidden;flex:none}
      .c svg{width:\(Int(cell))px !important;height:\(Int(cell))px !important;display:block}
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
let w = sheet.pixelsWide
let src = sheet.bitmapData!
let bpr = sheet.bytesPerRow, spp = sheet.samplesPerPixel
let cellPx = Int(cell * px)

for (i, f) in files.enumerated() {
    // white silhouette carrying the coverage; the app supplies the colour
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cellPx, pixelsHigh: cellPx,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: cellPx * 4, bitsPerPixel: 32)!
    let out = rep.bitmapData!
    var covered = 0
    for y in 0..<cellPx {
        for x in 0..<cellPx {
            let a = src[y * bpr + (i * cellPx + x) * spp + 3]
            if a > 5 { covered += 1 }
            // premultiplied — see render-frames.swift
            let o = y * cellPx * 4 + x * 4
            out[o] = a; out[o + 1] = a; out[o + 2] = a; out[o + 3] = a
        }
    }
    guard covered > 0, covered < cellPx * cellPx / 2 else {
        fatalError("\(f): coverage looks wrong (\(covered) of \(cellPx * cellPx))")
    }
    let scaled = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled)
    NSGraphicsContext.current!.imageInterpolation = .high
    let img = NSImage(size: NSSize(width: cellPx, height: cellPx))
    img.addRepresentation(rep)
    img.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()

    let name = (f as NSString).deletingPathExtension
    let data = scaled.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("\(name): \(side)px, \(data.count / 1024) KB")
}
