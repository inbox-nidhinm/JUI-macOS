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
    func draw(in rect: NSRect, fit: Fit, strength: CGFloat) {
        guard let image = image, rect.width > 0, rect.height > 0 else { return }
        let scale = fit.scale(covering: rect.size, image: image.size)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: NSRect(x: rect.midX - size.width / 2,
                              y: rect.midY - size.height / 2,
                              width: size.width, height: size.height),
                   from: .zero, operation: .multiply, fraction: strength)
    }
}

extension Paper.Fit {
    // Shared by both halves so an AppKit surface and a SwiftUI one can never
    // drift into showing the same stock at two different grains.
    func scale(covering surface: CGSize, image: CGSize) -> CGFloat {
        let cover = max(surface.width / image.width, surface.height / image.height)
        switch self {
        case .cover: return cover
        // Never smaller than cover, or the crop wouldn't reach the edges — a
        // panel wider than the window still gets filled, it just isn't shrunk
        // to fit inside it.
        case .window(let k): return max(k, cover)
        }
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
    case palette     // sheet — the ⌘K cards and the notes tray: the page's own paper
    case button      // #ECDBBE panel — a raised icon button
    case envelope    // #EBCEA3 envelope — onboarding
    case letter      // #FFFAF3 letterSheet — onboarding

    var paper: Paper {
        switch self {
        case .page, .palette: return .sheet
        case .sticky: return .sticky
        case .folderPanel, .folderTile, .button,
             .envelope, .letter: return .ui
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
        // As the page. The ⌘K cards — and the notes tray, which is made the same
        // way — are the page's own paper a shade deeper, not a panel stock: the
        // reader asked for "the same background texture as the notes with a
        // very slight darker shade" on the phone, and this is that, brought
        // back. The shade is the panel colour multiplied in at 70%
        // (`deepPaper`), so the grain darkens with the paper rather than being
        // washed out by a layer of colour over it. (It was the UI stock at 0.30
        // on a panel base, read off the system's card.)
        case .palette: return 0.50
        // The system draws this at 0.873 — 98%, the heaviest surface in it.
        // Deliberately lighter here: at full weight the raised button read as a
        // dark slug in the corner of the page, and it is the one surface that
        // appears over bare sheet rather than over another panel, so it carries
        // the contrast on its own.
        case .button: return 0.75
        // The envelope carries the strongest paper in the onboarding — it is
        // the largest flat area on screen and the one thing meant to read as
        // board rather than as page.
        case .envelope: return 0.85
        // The letter is white with the stock at 40% in the system, and stays
        // light: it is what the title is read off.
        case .letter: return 0.40
        }
    }

    // Fit belongs to the surface for the same reason strength does, and the two
    // together decide what the paper looks like: strength sets the *tone* and
    // fit sets the *grain size*. Matching one says nothing about the other, and
    // getting that wrong has produced both a panel too blotchy and a card too
    // flat, from the same file at sensible-looking numbers.
    var fit: Paper.Fit {
        switch self {
        // Big enough to hold a whole sheet, and wanting it: a crop carries the
        // photograph's large-scale mottling at full size, which in a 260pt
        // panel puts one streak across the whole thing. Covering averages that
        // away and leaves even tooth — a grain spread of 0.086 against the
        // system's 0.085, where the crop gave 0.122.
        case .page, .folderPanel, .folderTile, .button,
             .envelope, .letter: return .cover
        // Covering shrinks the grain twelvefold on a ~170pt stamp and the paper
        // reads as flat colour. 0.5 puts one image pixel on one Retina pixel.
        case .sticky: return .window(0.5)
        // The page's paper at the page's own grain: the scale the photograph
        // is drawn at to cover the window, held for a card a fraction of its
        // size — covering just the card would blow the grain up, and the card
        // would read as a different stock from the page around it.
        case .palette:
            guard let image = Paper.sheet.image else { return .cover }
            let window = NSApp.keyWindow?.contentView?.bounds.size
                ?? NSApp.windows.first?.contentView?.bounds.size
                ?? NSScreen.main?.frame.size ?? CGSize(width: 1200, height: 800)
            return .window(Paper.Fit.cover.scale(covering: window, image: image.size))
        }
    }

    func draw(in rect: NSRect) { paper.draw(in: rect, fit: fit, strength: strength) }
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
                let scale = surface.fit.scale(covering: geo.size, image: image.size)
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
