import AppKit
import SwiftUI

// Paper.
//
// Three photographed stocks — the page, the sticky notes, the panels — applied
// as *blend layers over themed colour*, never as pictures in their own right.
//
// They are measurably neutral: R = G = B on every sample, mean colour cast 0.00.
// That is the whole trick. The colour comes from the theme underneath and only
// the tone comes from the paper, so one file serves all six palettes instead of
// needing six. Tinting one on the way in would break that, and would break it
// invisibly — correct in cream, subtly muddy in the other five, with no single
// pixel you could point at.
//
// The same reasoning says a texture must never be drawn opaque. It is always a
// multiply at a fraction, so what you see is the theme's own colour with the
// paper's tone pressed into it.
enum Paper: String {
    case sheet  // the page itself
    case sticky // sticky notes
    case ui     // panels, the ⌘K palette, folder cards

    // Recovered from the Figma frames rather than guessed, by solving
    //
    //     result = base × (1 − a + a × texture)
    //
    // for `a` on each colour channel separately against the known theme colour,
    // and keeping the answer only where the three channels agreed. The sheet
    // solved cleanly at three-channel agreement; the panels sit far lighter.
    //
    // These are the numbers most likely to need taste applied to them, which is
    // why they are one table rather than sprinkled through the views.
    var opacity: CGFloat {
        switch self {
        case .sheet: return 0.50
        case .sticky: return 0.35
        case .ui: return 0.25
        }
    }

    // Bundled as greyscale JPEG, built from the full-resolution sources in
    // Art/Textures by build.sh. JPEG rather than PNG because the error it adds
    // is far below the error the downsample already costs — measured at 0.88
    // levels against 0.81 for lossless at the same size — while the file is a
    // fifth of the size. Photographic grain is the case PNG is worst at.
    var image: NSImage? {
        if let hit = Paper.cache[rawValue] { return hit }
        guard let url = Bundle.main.resourceURL?
                .appendingPathComponent("Textures/\(rawValue).jpg"),
              let image = NSImage(contentsOf: url) else { return nil }
        Paper.cache[rawValue] = image
        return image
    }

    private static var cache: [String: NSImage] = [:]

    // Aspect-fill, for the views AppKit draws by hand. Filling rather than
    // stretching keeps the grain proportional when a surface is a different
    // shape from the photograph, which every one of them is.
    func draw(in rect: NSRect) {
        guard let image = image, rect.width > 0, rect.height > 0 else { return }
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: NSRect(x: rect.midX - size.width / 2,
                              y: rect.midY - size.height / 2,
                              width: size.width, height: size.height),
                   from: .zero, operation: .multiply, fraction: opacity)
    }
}

// The SwiftUI half. `.papered(.ui)` presses paper into whatever it is applied
// to, so a call site reads as one surface rather than as a colour and a picture
// that have to be kept in agreement.
//
// `compositingGroup` is load-bearing: without it the multiply blends against
// everything already drawn behind the view — the page, other panels — instead
// of against the colour it is supposed to be texturing, and a panel picks up a
// darkened copy of whatever it happens to be sitting on.
extension View {
    func papered(_ paper: Paper) -> some View {
        overlay(PaperOverlay(paper: paper)).compositingGroup()
    }
}

private struct PaperOverlay: View {
    let paper: Paper

    var body: some View {
        GeometryReader { geo in
            if let image = paper.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blendMode(.multiply)
                    .opacity(paper.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}
