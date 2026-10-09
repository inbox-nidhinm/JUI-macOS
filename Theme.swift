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

    // Every token here is drawn by something. Three used to sit alongside them
    // and no longer do, because what they described stopped existing:
    //
    // - `divider`, a colour a step darker than the sheet, which inverted the
    //   moment the panels took their paper and became `panelDividerColor` — a
    //   *tone*, so it darkens whatever it lands on in all six themes.
    // - `rule`, for the horizontal rules that are gone from the editor. The
    //   ruled page draws itself with `Style.ruleTone`, for the same reason.
    // - `flourishHover`, from the treatment where hovering *lifted* the corner
    //   mark. It has to deepen it now, so the hover tint is panel taken a step
    //   toward the ink and is computed rather than stored.
    let sheet: NSColor          // the page
    let panel: NSColor          // popovers, palette, text selection, traffic lights
    let folderBase: NSColor     // folder card at rest
    let envelope: NSColor       // onboarding envelope
    let letterSheet: NSColor    // onboarding letter
    let ink: NSColor            // every word in the app
    let sticky: NSColor         // sticky notes, selection icon — the anchor tone
    let openDot: NSColor        // the dot marking the open note; the picker's ring
    let flourish: NSColor       // the corner flourish, and onboarding's

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
        envelope: rgb(0xEBCEA3), letterSheet: rgb(0xFFFAF3),
        ink: rgb(0x71390D), sticky: rgb(0xF7C82D), openDot: rgb(0xA88D34),
        flourish: rgb(0xF2E3C9))

    static let mint = Theme(
        id: "mint", label: "mint",
        sheet: rgb(0xDDF9EF), panel: rgb(0xC3E7DA), folderBase: rgb(0xCEEFE3),
        envelope: rgb(0xAAE4CE), letterSheet: rgb(0xF4FEFA),
        ink: rgb(0x176742), sticky: rgb(0x61E7C1), openDot: rgb(0x409C82),
        flourish: rgb(0xCDEEE2))

    static let sky = Theme(
        id: "sky", label: "sky",
        sheet: rgb(0xD9F1FD), panel: rgb(0xBEDCEC), folderBase: rgb(0xCAE5F3),
        envelope: rgb(0xA3D4EB), letterSheet: rgb(0xF3FBFF),
        ink: rgb(0x0D5A71), sticky: rgb(0x65BFFF), openDot: rgb(0x3478A8),
        flourish: rgb(0xC9E4F2))

    static let coral = Theme(
        id: "coral", label: "coral",
        sheet: rgb(0xFDE3D9), panel: rgb(0xECCBBE), folderBase: rgb(0xF3D6CA),
        envelope: rgb(0xEBB6A3), letterSheet: rgb(0xFFF6F3),
        ink: rgb(0x711F0D), sticky: rgb(0xFF985E), openDot: rgb(0xA85E34),
        flourish: rgb(0xF2D5C9))

    static let lilac = Theme(
        id: "lilac", label: "lilac",
        sheet: rgb(0xE6D9FD), panel: rgb(0xCFBEEC), folderBase: rgb(0xD9CAF3),
        envelope: rgb(0xBCA3EB), letterSheet: rgb(0xF7F3FF),
        ink: rgb(0x270D71), sticky: rgb(0xC18FFF), openDot: rgb(0x6834A8),
        flourish: rgb(0xD8C9F2))

    static let orchid = Theme(
        id: "orchid", label: "orchid",
        sheet: rgb(0xFDD9F8), panel: rgb(0xECBEE6), folderBase: rgb(0xF3CAED),
        envelope: rgb(0xEBA3E2), letterSheet: rgb(0xFFF3FE),
        ink: rgb(0x710D6E), sticky: rgb(0xFF87E5), openDot: rgb(0xA8348F),
        flourish: rgb(0xF2C9EC))

    // order is the order of the dots, in both onboarding and settings
    static let all: [Theme] = [cream, mint, sky, coral, lilac, orchid]

    static func named(_ id: String?) -> Theme {
        all.first { $0.id == id } ?? cream
    }
}

// The app's icon follows the mood, as the iPhone app's does: six icons from the
// Figma system (node 331:539), each drawn in its mood's own colours — the same
// artwork, set on the macOS icon grid by build.sh into Resources/AppIcons.
// Cream is also the bundle's AppIcon.icns, so it is what Finder shows before
// the app has ever run.
//
// This replaces two older arrangements: a fixed black icon that told this
// build apart from the shipping JUI, and before it a recolour of the original
// gold icon worked out pixel by pixel. Designed icons need neither.
enum AppIcon {
    private static var cache: [String: NSImage] = [:]

    private static func image(for theme: Theme) -> NSImage? {
        if let hit = cache[theme.id] { return hit }
        guard let url = Bundle.main.url(
                forResource: theme.id, withExtension: "png", subdirectory: "AppIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[theme.id] = image
        return image
    }

    /// The icon for `theme`, everywhere: the running app at once, and the
    /// bundle so it stays after quitting.
    static func apply(_ theme: Theme) {
        guard let image = image(for: theme) else { return }
        NSApplication.shared.applicationIconImage = image // Dock, ⌘-Tab, About
        persist(theme, image) // Finder, Launchpad
        tellDockTile(theme) // the Dock, once the app has quit
    }

    // Writes the icon onto the bundle itself — the same thing pasting into a Get
    // Info window does. applicationIconImage alone only lasts as long as the
    // process, so quitting reverted the tile to the bundle's own icon.
    //
    // The icon is drawn exactly as handed over, which is why the pictures carry
    // the macOS shape, inset and shadow (see Art/render-icons.swift).
    //
    // The cost, measured on the main branch: this writes an `Icon\r` at the
    // bundle root, after which `codesign --verify --deep --strict` fails with
    // "resource fork, Finder information, or similar detritus not allowed".
    // Plain `codesign --verify` still passes and the app still launches. It only
    // ever affects an installed copy that has been run — the build output and the
    // shipped zip are untouched, since build.sh rebuilds the bundle from scratch.
    // Cream is the bundle's own icon, so it removes the override rather than
    // writing a copy over it, which also restores the seal.
    private static func persist(_ theme: Theme, _ image: NSImage) {
        let icon: NSImage? = theme.id == Themes.cream.id ? nil : image
        NSWorkspace.shared.setIcon(icon, forFile: Bundle.main.bundlePath, options: [])
    }

    // The Dock keeps its own cache of a *pinned* tile's icon, and after the app
    // quits it shows that — the previous mood's, if the mood changed. Measured
    // on the old main branch: touching the bundle and `lsregister -f` both left
    // the stale tile; only restarting the Dock cleared it, and the app used to
    // do that on quit, which made the whole Dock vanish for a moment.
    //
    // Now the Dock tile plug-in (DockTile.swift, built into
    // Contents/PlugIns) draws the tile while the app isn't running. This tells
    // it the mood the moment it changes — and again on quit — so it never has
    // to wait on the preferences it would otherwise read.
    static let moodChanged = Notification.Name("com.nidhin.jui.moodChanged")

    static func tellDockTile(_ theme: Theme) {
        DistributedNotificationCenter.default().postNotificationName(
            moodChanged, object: nil, userInfo: ["mood": theme.id], deliverImmediately: true)
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
