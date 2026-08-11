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
