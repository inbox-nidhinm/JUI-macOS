// Rasterises the split animation frames into template PNGs the app can play.
//
// Raster rather than vector, for once. The artwork is a single tone, so a
// template image tinted at draw time still follows the theme — the property
// that made vectors worth the trouble elsewhere. What vectors would cost here
// is reimplementing SVG mask semantics: the later frames are drawn by masking
// a full-bleed rect, so the *mask* carries the shape, and getting that subtly
// wrong is easy. Letting the renderer resolve it is exact.
//
// Every frame is cropped to the LAST frame's bounds. Cropping each to its own
// would re-centre the drawing on every tick and the flourish would swim about
// while it drew itself.
import AppKit

let svgDir = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let targetHeight = Double(CommandLine.arguments[3])!

let frames = (try! FileManager.default.contentsOfDirectory(atPath: svgDir))
    .filter { $0.hasSuffix(".svg") }.sorted()
guard let last = frames.last else { fatalError("no frames in \(svgDir)") }

func draw(_ path: String, into size: NSSize, from box: NSRect?) -> NSBitmapImageRep {
    let img = NSImage(contentsOfFile: path)!
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: Int(size.width) * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if let box = box {
        // scale the source box up to fill the output
        let sx = size.width / box.width, sy = size.height / box.height
        img.draw(in: NSRect(x: -box.minX * sx, y: -box.minY * sy,
                            width: img.size.width * sx, height: img.size.height * sy))
    } else {
        img.draw(in: NSRect(origin: .zero, size: size))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// the final frame's ink bounds. Measured on a probe render and then converted
// into the SVG's own coordinate space — measuring in one space and cropping in
// another is a quiet way to crop the wrong region entirely.
let probeSide = 540.0
let documentSide = NSImage(contentsOfFile: "\(svgDir)/\(last)")!.size.width
let probe = draw("\(svgDir)/\(last)", into: NSSize(width: probeSide, height: probeSide), from: nil)
var minX = probeSide, maxX = 0.0, minY = probeSide, maxY = 0.0
let d = probe.bitmapData!
for y in 0..<Int(probeSide) {
    for x in 0..<Int(probeSide) where d[(y * Int(probeSide) + x) * 4 + 3] > 30 {
        minX = min(minX, Double(x)); maxX = max(maxX, Double(x))
        minY = min(minY, Double(y)); maxY = max(maxY, Double(y))
    }
}
// probe is drawn unflipped, so y is measured from the bottom already
let pad = 6.0
let probed = NSRect(x: max(0, minX - pad), y: max(0, minY - pad),
                    width: min(probeSide, maxX + pad) - max(0, minX - pad),
                    height: min(probeSide, maxY + pad) - max(0, minY - pad))
// into document units, which is what `draw(in:)` works in
let k = documentSide / probeSide
let box = NSRect(x: probed.minX * k, y: probed.minY * k,
                 width: probed.width * k, height: probed.height * k)
let scale = targetHeight / box.height
let out = NSSize(width: (box.width * scale).rounded(), height: targetHeight)
print(String(format: "crop %.0fx%.0f of %.0f document units -> %.0fx%.0f px",
             box.width, box.height, documentSide, out.width, out.height))

var total = 0
for (i, f) in frames.enumerated() {
    let rep = draw("\(svgDir)/\(f)", into: out, from: box)
    // Flattened to a white silhouette on transparency: the app tints it, so the
    // exported colour is noise. Alpha is the whole payload.
    let px = rep.bitmapData!
    for p in 0..<(Int(out.width) * Int(out.height)) {
        px[p * 4] = 255; px[p * 4 + 1] = 255; px[p * 4 + 2] = 255
    }
    let url = URL(fileURLWithPath: String(format: "%@/frame-%02d.png", outDir, i + 1))
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
    total += data.count
}
print("wrote \(frames.count) frames, \(total / 1024) KB total")
