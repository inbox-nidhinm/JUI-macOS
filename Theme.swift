import SwiftUI
import AppKit

// A theme is a complete recolour of the app. Every colour the app draws comes
// from the active one, so switching swaps the whole surface at once — sheet,
// panel, ink, stickies, rules, the flourish, the onboarding envelope.
//
// The five alternates were derived from the cream original in Figma: each holds
// the original's lightness and saturation exactly and rotates every hue into an
// 11° band anchored on its sticky-note colour. Only the temperature moves, so
// the value relationships the app leans on for hierarchy survive intact —
// panels still sit a shade under the sheet, hover states still resolve one step
// lighter, and ink on sheet stays past 4.5:1 in all six.
//
// Colours are held as NSColor because AppKit needs them (text storage, layout
// manager, sticky drawing) and SwiftUI can always borrow one via Color(nsColor:).
// That also means each value exists exactly once, rather than as a Color and an
// NSColor typed out separately and free to drift apart.
struct Theme: Identifiable, Equatable {
    let id: String
    let label: String

    let sheet: NSColor          // the page
    let panel: NSColor          // popovers, palette, text selection, traffic lights
    let folderBase: NSColor     // folder card at rest
    let divider: NSColor        // hairlines
    let envelope: NSColor       // onboarding envelope
    let letterSheet: NSColor    // onboarding letter
    let ink: NSColor            // every word in the app
    let sticky: NSColor         // sticky notes, selection icon — the anchor tone
    let openDot: NSColor        // the dot marking the open note; the picker's ring
    let rule: NSColor           // horizontal rules
    let flourish: NSColor       // corner flourish at rest
    let flourishHover: NSColor  // corner flourish hovered

    static func == (a: Theme, b: Theme) -> Bool { a.id == b.id }
}

private func rgb(_ hex: UInt32) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

enum Themes {
    static let cream = Theme(
        id: "cream", label: "cream",
        sheet: rgb(0xFDF0D9), panel: rgb(0xECDBBE), folderBase: rgb(0xF3E4CA),
        divider: rgb(0xE6D4B5), envelope: rgb(0xEBCEA3), letterSheet: rgb(0xFFFAF3),
        ink: rgb(0x71390D), sticky: rgb(0xF7C82D), openDot: rgb(0xA88D34),
        rule: rgb(0xAD9E84), flourish: rgb(0xF2E3C9), flourishHover: rgb(0xF2DEBA))

    static let mint = Theme(
        id: "mint", label: "mint",
        sheet: rgb(0xDDF9EF), panel: rgb(0xC3E7DA), folderBase: rgb(0xCEEFE3),
        divider: rgb(0xBAE1D3), envelope: rgb(0xAAE4CE), letterSheet: rgb(0xF4FEFA),
        ink: rgb(0x176742), sticky: rgb(0x61E7C1), openDot: rgb(0x409C82),
        rule: rgb(0x88A99D), flourish: rgb(0xCDEEE2), flourishHover: rgb(0xC0ECDD))

    static let sky = Theme(
        id: "sky", label: "sky",
        sheet: rgb(0xD9F1FD), panel: rgb(0xBEDCEC), folderBase: rgb(0xCAE5F3),
        divider: rgb(0xB5D5E6), envelope: rgb(0xA3D4EB), letterSheet: rgb(0xF3FBFF),
        ink: rgb(0x0D5A71), sticky: rgb(0x65BFFF), openDot: rgb(0x3478A8),
        rule: rgb(0x849FAD), flourish: rgb(0xC9E4F2), flourishHover: rgb(0xBADEF2))

    static let coral = Theme(
        id: "coral", label: "coral",
        sheet: rgb(0xFDE3D9), panel: rgb(0xECCBBE), folderBase: rgb(0xF3D6CA),
        divider: rgb(0xE6C3B5), envelope: rgb(0xEBB6A3), letterSheet: rgb(0xFFF6F3),
        ink: rgb(0x711F0D), sticky: rgb(0xFF985E), openDot: rgb(0xA85E34),
        rule: rgb(0xAD9084), flourish: rgb(0xF2D5C9), flourishHover: rgb(0xF2CABA))

    static let lilac = Theme(
        id: "lilac", label: "lilac",
        sheet: rgb(0xE6D9FD), panel: rgb(0xCFBEEC), folderBase: rgb(0xD9CAF3),
        divider: rgb(0xC7B5E6), envelope: rgb(0xBCA3EB), letterSheet: rgb(0xF7F3FF),
        ink: rgb(0x270D71), sticky: rgb(0xC18FFF), openDot: rgb(0x6834A8),
        rule: rgb(0x9384AD), flourish: rgb(0xD8C9F2), flourishHover: rgb(0xCFBAF2))

    static let orchid = Theme(
        id: "orchid", label: "orchid",
        sheet: rgb(0xFDD9F8), panel: rgb(0xECBEE6), folderBase: rgb(0xF3CAED),
        divider: rgb(0xE6B5DF), envelope: rgb(0xEBA3E2), letterSheet: rgb(0xFFF3FE),
        ink: rgb(0x710D6E), sticky: rgb(0xFF87E5), openDot: rgb(0xA8348F),
        rule: rgb(0xAD84A7), flourish: rgb(0xF2C9EC), flourishHover: rgb(0xF2BAEA))

    // order is the order of the dots, in both onboarding and settings
    static let all: [Theme] = [cream, mint, sky, coral, lilac, orchid]

    static func named(_ id: String?) -> Theme {
        all.first { $0.id == id } ?? cream
    }
}

// Recolours the Dock icon to match the theme.
//
// AppIcon.icns is a full-bleed gold field with a cream floral motif — exactly two
// tones, plus the anti-aliased pixels between them. So it maps cleanly: the gold
// becomes the theme's sticky, the cream becomes its sheet. Each pixel's mix is
// read off its blue channel, which is where the two source tones sit furthest
// apart (57 vs 224) and varies monotonically between them, so soft edges survive.
//
// IMPORTANT: this changes the icon of the *running* app only — Dock, ⌘-Tab, and
// the About panel. The icon Finder and Launchpad show comes from AppIcon.icns
// inside the bundle, which the code signature seals. Rewriting it would break
// that seal and the app would refuse to launch with "a sealed resource is missing
// or invalid", so there is deliberately no attempt to.
enum AppIcon {
    // On the re-JUI branch the icon is a *fixed* mark — the cream flourish on
    // black, shipped as AppIconRe.icns — so the rebuild is never mistaken for
    // the real app in the Dock, the ⌘-Tab strip or Finder, whatever mood either
    // one is set to. A dark icon also can't be produced by the recolour below,
    // which maps the artwork's two tones onto two *theme* colours and so is
    // light by construction.
    //
    // That makes the recolour, the persisted override and the Dock restart dead
    // weight, so they are switched off here at the root rather than left half
    // running. The call sites in main.swift are untouched, which keeps this a
    // one-line decision to reverse.
    static let followsTheme = false

    private static var cache: [String: NSImage] = [:]
    private static var pristine: NSImage?

    // Must run before any themed icon is applied, and exactly once.
    //
    // Clearing the override first is what keeps this correct across launches.
    // The recolour derives its two endpoint tones from the source image, so if
    // the source were a previously-persisted themed icon the remap would
    // compound — and it would do so catastrophically rather than subtly, because
    // lilac's field and motif differ by 2 in blue where the original gold and
    // cream differ by 172. Reading the pristine icon means every theme is always
    // computed from the artwork as drawn.
    static func prepare() {
        let path = Bundle.main.bundlePath
        NSWorkspace.shared.setIcon(nil, forFile: path, options: [])
        let base = NSWorkspace.shared.icon(forFile: path)
        pristine = base.size.width > 0 ? base : nil
    }

    static func apply(_ theme: Theme) {
        // Doing nothing leaves the bundle's own icon in place, which is exactly
        // what a fixed mark wants.
        guard followsTheme else { return }
        guard let image = image(for: theme) else { return }
        NSApplication.shared.applicationIconImage = image // the running app
        persist(theme, image) // Finder, Launchpad, and the Dock after quitting
    }

    // Writes the icon onto the bundle itself — the same thing pasting into a Get
    // Info window does, and the mechanism Granola settled on for this exact
    // problem. applicationIconImage alone only lasts as long as the process, so
    // quitting reverted the tile to the gold default.
    //
    // The cost, measured rather than assumed: this writes an `Icon\r` at the
    // bundle root, after which `codesign --verify --deep --strict` fails with
    // "resource fork, Finder information, or similar detritus not allowed".
    // Plain `codesign --verify` still passes and the app still launches. It only
    // ever affects an installed copy that has been run — the build output and the
    // shipped zip are untouched, since build.sh rebuilds the bundle from scratch.
    // Deleting the `Icon\r` restores the seal.
    private static func persist(_ theme: Theme, _ image: NSImage) {
        let path = Bundle.main.bundlePath
        // cream is the artwork as drawn, so drop the override rather than
        // writing a copy of the default over the top of it
        let icon: NSImage? = theme.id == Themes.cream.id ? nil : image
        NSWorkspace.shared.setIcon(icon, forFile: path, options: [])
    }

    // The Dock keeps its own cache of a *pinned* tile's icon and only re-reads it
    // when it restarts. Measured: touching the bundle and re-registering it with
    // LaunchServices (`lsregister -f`) both leave the stale tile in place;
    // relaunching the Dock is the only thing that clears it. launchd brings it
    // straight back, so this costs a brief flash and nothing else.
    //
    // Called on quit rather than on the theme change, and only when the theme
    // actually changed during the session. While the app is running the tile
    // draws applicationIconImage and is already correct — the stale cache is only
    // visible once the app is gone — so this way the flash never interrupts
    // anyone mid-use, and quitting without changing mood leaves the Dock alone.
    static func refreshDockTile() {
        // The tile never changes here, so restarting the Dock on quit would be
        // a visible flash bought for nothing.
        guard followsTheme else { return }
        for dock in NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock") {
            dock.terminate()
        }
    }

    private static func image(for theme: Theme) -> NSImage? {
        if let hit = cache[theme.id] { return hit }
        guard let base = pristine else { return nil }
        // cream is what the artwork was drawn in; leave it untouched
        let result = theme.id == Themes.cream.id
            ? base
            : (recoloured(base, field: theme.sticky, motif: theme.sheet) ?? base)
        cache[theme.id] = result
        return result
    }

    // Recolours the bundle's icon *as macOS composes it*, not the raw AppIcon.icns.
    //
    // That distinction is the whole fix. The raw asset is a full-bleed opaque
    // square; macOS insets it to the 824-in-1024 icon grid and masks it to the
    // system squircle before Finder ever shows it. But applicationIconImage is
    // drawn exactly as handed over, with no inset and no mask — so recolouring the
    // raw file produced a Dock tile that was both hard-cornered and visibly larger
    // than its neighbours. Starting from the composed icon inherits the correct
    // geometry for whatever macOS is running, with no shape maths here to go stale.
    private static func recoloured(_ base: NSImage, field: NSColor, motif: NSColor) -> NSImage? {
        let side = 512 // ample for the Dock, which tops out around 256pt @2x
        guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        base.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData,
              let f = field.usingColorSpace(.sRGB),
              let m = motif.usingColorSpace(.sRGB) else { return nil }
        let from = (f.redComponent * 255, f.greenComponent * 255, f.blueComponent * 255)
        let to = (m.redComponent * 255, m.greenComponent * 255, m.blueComponent * 255)

        // Calibrate the two endpoints from the pixels actually in this bitmap
        // rather than from constants. The .icns is colour-converted on its way in
        // here, so the tones measured in the file are not the ones that arrive —
        // the gold reads #F7C82D, not the #F9D039 the file contains. Reading the
        // range off the opaque interior is immune to that, and to the artwork
        // being redrawn later.
        var lo = 255.0, hi = 0.0
        for i in stride(from: 0, to: side * side * 4, by: 4) where data[i + 3] > 250 {
            let blue = Double(data[i + 2])
            lo = min(lo, blue)
            hi = max(hi, blue)
        }
        // A narrow spread means blue isn't separating this artwork's two tones, so
        // the remap would amplify noise instead of mapping cleanly. Fail back to
        // the untinted icon rather than producing something wrong.
        guard hi - lo > 30 else { return nil }
        let span = hi - lo
        func byte(_ value: Double) -> UInt8 { UInt8(min(max(value, 0), 255)) }

        for i in stride(from: 0, to: side * side * 4, by: 4) {
            let a = Double(data[i + 3])
            guard a > 0 else { continue } // outside the squircle; leave it clear
            // CoreGraphics hands back premultiplied RGB, so undo that before
            // reading the tone and redo it after — otherwise the soft squircle
            // edge reads as near-gold and picks up a bright fringe.
            let t = min(max((Double(data[i + 2]) * (255 / a) - lo) / span, 0), 1)
            let unmul = a / 255
            data[i] = byte((from.0 + (to.0 - from.0) * t) * unmul)
            data[i + 1] = byte((from.1 + (to.1 - from.1) * t) * unmul)
            data[i + 2] = byte((from.2 + (to.2 - from.2) * t) * unmul)
        }
        let out = NSImage(size: NSSize(width: side, height: side))
        out.addRepresentation(rep)
        return out
    }
}

// The row of mood dots. Each dot is its theme's sticky colour; the active one
// carries a ring in that theme's open-note dot, a shade darker than the fill.
// Tapping applies the theme immediately — there is no confirm step.
struct ThemePicker: View {
    @ObservedObject var store: NotesStore
    var diameter: CGFloat = 24
    var spacing: CGFloat = 18

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Themes.all) { theme in
                Button {
                    store.setTheme(theme)
                } label: {
                    Circle()
                        .fill(Color(nsColor: theme.sticky))
                        .frame(width: diameter, height: diameter)
                        .overlay(
                            Circle()
                                .strokeBorder(Color(nsColor: theme.openDot),
                                              lineWidth: max(2, diameter * 0.09))
                                .opacity(store.themeID == theme.id ? 1 : 0)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(theme.label)
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.themeID)
        .arrowCursorZone()
    }
}
