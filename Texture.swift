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

    // How much of the photograph a surface sees.
    //
    // This, not opacity, is what decides whether paper reads as paper. A sticky
    // is about 170pt across; aspect-filling a 2048px photograph into it shrinks
    // the grain by a factor of twelve, and twelve-times-too-small grain is a
    // flat colour no matter what opacity it is drawn at. The sticky looked
    // untextured for exactly that reason, and no opacity would have fixed it.
    //
    // So the small surfaces show a *window* onto the paper at its own scale
    // rather than the whole sheet crushed into a card. Only the page, which is
    // big enough to hold a whole sheet, covers.
    enum Fit {
        /// The whole photograph across the surface. One sheet reads as one
        /// sheet, and its creases land in fixed places.
        case cover
        /// Drawn at a fixed multiple of the photograph's own size and cropped
        /// to the surface. Lower numbers mean bigger grain.
        case window(CGFloat)
    }

    var fit: Fit {
        switch self {
        // Both cover. The page is big enough to hold a whole sheet, and the
        // panels *want* the whole sheet shrunk into them: a crop carries the
        // photograph's large-scale mottling at full size, and a 260pt panel is
        // small enough that one streak crosses the whole thing. Covering
        // averages that away and leaves even tooth. Measured against the
        // system's panel, this is a grain spread of 0.086 where the crop gave
        // 0.122 — the system's own is 0.085.
        case .sheet, .ui: return .cover
        // The sticky is the exception, and the reason the mechanism exists. At
        // ~170pt across, covering shrinks the grain twelvefold into flat
        // colour; 0.5 puts one image pixel on one Retina pixel, which is both
        // the sharpest the file draws and the grain size the system shows.
        case .sticky: return .window(0.5)
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
    // Shared by both halves so an AppKit surface and a SwiftUI one can never
    // drift into showing the same stock at two different grains.
    func scale(covering surface: CGSize, image: CGSize) -> CGFloat {
        let cover = max(surface.width / image.width, surface.height / image.height)
        switch fit {
        case .cover: return cover
        // Never smaller than cover, or the crop wouldn't reach the edges — a
        // panel wider than the window still gets filled, it just isn't shrunk
        // to fit inside it.
        case .window(let k): return max(k, cover)
        }
    }

    func draw(in rect: NSRect, strength: CGFloat) {
        guard let image = image, rect.width > 0, rect.height > 0 else { return }
        let scale = scale(covering: rect.size, image: image.size)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: NSRect(x: rect.midX - size.width / 2,
                              y: rect.midY - size.height / 2,
                              width: size.width, height: size.height),
                   from: .zero, operation: .multiply, fraction: strength)
    }
}

// How hard each surface takes its paper.
//
// Strength belongs to the *surface*, not to the stock — which is not what it
// looked like at first. Every panel in the app shares one photograph, so one
// number for it seemed obvious; the system varies it by nearly ten to one. The
// folder panel and the raised buttons take their paper at almost full weight
// while the ⌘K cards take theirs at a tenth, and papering them all alike left
// the folder tiles barely separated from the panel they sit on.
//
// Every value here was recovered from a render of the node itself, by solving
//
//     result = base × (1 − a + a × stock)
//
// per channel against the token the surface is built from, and kept only where
// the three channels agreed. Reading them off an exported PNG is not equivalent
// and has been wrong twice: a 1px rule antialiases across two device pixels,
// and a blend mode does not survive an SVG export at all.
enum Surface {
    case page        // #FDF0D9 sheet
    case sticky      // #F7C82D sticky
    case folderPanel // #ECDBBE panel — the pane the tiles sit on
    case folderTile  // #F3E4CA folderBase — the tiles themselves
    case palette     // #ECDBBE panel — the ⌘K cards
    case button      // #ECDBBE panel — a raised icon button

    var paper: Paper {
        switch self {
        case .page: return .sheet
        case .sticky: return .sticky
        case .folderPanel, .folderTile, .palette, .button: return .ui
        }
    }

    var strength: CGFloat {
        switch self {
        case .page: return 0.50
        // Recovered from the system's own sticky, which exports as a flat PNG —
        // colour and paper already combined — so dividing it by the base gold
        // gives the multiply it was drawn at. Its grain spans 0.045 between the
        // 5th and 95th percentile; this stock reaches that at 46%, and matches
        // the median tone there too.
        case .sticky: return 0.46
        // #D0C1A7 against #ECDBBE — a 0.88 multiply, uniform across channels.
        case .folderPanel: return 0.93
        // #E5D6BC against #F3E4CA — 0.937. Half the panel's, and that gap is
        // the whole reason a tile reads as sitting *on* the pane: 21 levels of
        // separation in the system against the 7 that one shared value gave.
        case .folderTile: return 0.49
        // #E7D7BE against #ECDBBE — 0.987, and both ⌘K cards agree to within a
        // percent. Nearly clean paper; the card is doing the work, not the tooth.
        case .palette: return 0.10
        // #CEBFA6 — 0.873, the heaviest surface in the app.
        case .button: return 0.98
        }
    }

    func draw(in rect: NSRect) { paper.draw(in: rect, strength: strength) }
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
    func papered(_ surface: Surface) -> some View {
        overlay(PaperOverlay(surface: surface)).compositingGroup()
    }
}

private struct PaperOverlay: View {
    let surface: Surface
    private var paper: Paper { surface.paper }

    var body: some View {
        GeometryReader { geo in
            if let image = paper.image {
                let scale = paper.scale(covering: geo.size, image: image.size)
                Image(nsImage: image)
                    .resizable()
                    // sized explicitly rather than by aspectRatio(.fill), so a
                    // small card can show a crop of the paper at full size
                    // instead of the whole sheet shrunk into it
                    .frame(width: image.size.width * scale,
                           height: image.size.height * scale)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blendMode(.multiply)
                    .opacity(surface.strength)
            }
        }
        .allowsHitTesting(false)
    }
}
