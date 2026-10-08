import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Every colour token reads through the active theme (Theme.swift), so changing
// theme repaints the whole app without a single call site knowing about it.
var sheetColor: Color { Color(nsColor: Style.theme.sheet) }
var panelColor: Color { Color(nsColor: Style.theme.panel) }
var openDotColor: Color { Color(nsColor: Style.theme.openDot) }
var flourishColor: Color { Color(nsColor: Style.theme.flourish) }

// The corner flourish's two states.
//
// `flourishHover` was drawn for the old treatment, where the mark was painted
// on and hovering lifted it a shade. Multiplied into the page it does nothing
// visible: against panel's 0.925/0.859/0.745 it is 0.949/0.871/0.729 — the same
// darkness, a different hue. Hovering has to *deepen* the mark now, so the
// hover tint is panel taken a step toward the ink.
var flourishRest: Color { panelColor }
var flourishHovered: Color {
    Color(nsColor: Style.theme.panel.blended(withFraction: 0.22, of: Style.theme.ink)
        ?? Style.theme.panel)
}
var brownInk: Color { Color(nsColor: Style.theme.ink) }

// The ink ladder — four steps, and only these four. Everything written in the
// app is brownInk at one of them. Reaching for a fresh opacity adds a colour
// nobody chose; pick the step that matches the role instead.
var inkStrong: Color { brownInk.opacity(0.85) } // panel rows, settings values, folder names
var inkMuted: Color { brownInk.opacity(0.55) } // labels, snippets, secondary rows
var inkFaint: Color { brownInk.opacity(0.4) } // placeholders, empty states, icons, disabled

// Type, handled the way colour is: one function every call site reads through,
// so the family chosen in settings reaches the chrome and not only the page.
//
// This was `.font(.custom("Courier", size:))` written out at every call site,
// which meant the picker restyled the note and left every panel row, search
// result, folder name and onboarding title in Courier. Worst inside the ⌘K
// field, where the typed text went through `HouseField` and followed the
// choice while the placeholder drawn behind it stayed Courier — two families
// on one line. The scale is unchanged: 10 / 11 / 12 / 13 / 14 / 16.
func houseFont(_ size: CGFloat) -> Font { Font(Style.font(size) as CTFont) }

// The hairline *inside* a papered surface, as a tone rather than a colour —
// the same reasoning as `Style.ruleTone`.
//
// It replaced a `divider` *colour* chosen to sit a step darker than the sheet,
// which stopped working the moment the panels took their paper: at 93% the
// folder pane goes to #D0C1A7, which is darker than the #E6D4B5 hairline, so
// the divider inverted and read as a pale scratch across the card. Nothing
// draws a fixed divider colour any more, so the token is gone from `Theme`.
//
// Black at 12% over a base is arithmetically a multiply by 0.88 — no blend mode
// needed, since a black source at alpha `a` composites to exactly `base × (1−a)`.
// So this is always a darkening, on any surface, in any of the six themes, and
// it cannot invert the way a fixed colour can.
var panelDividerColor: Color { Color.black.opacity(0.12) }

// A flourish that draws itself on, from the stop-motion frames.
//
// Three sets ship: the same drawing at the three angles the static artwork used
// — upright for the page corner, rotated for folder tiles and for stickies — so
// animating a mark changes nothing about how it looks once it settles. The last
// frame *is* the finished flourish; nothing swaps in at the end.
//
// Frames are white silhouettes tinted at draw time, so one set serves all six
// themes.
enum FlourishSet: String {
    case corner, folder, sticky
}

struct AnimatedFlourish: View {
    // When a flourish draws itself is the caller's decision, not the view's.
    // The same mark is a permanent fixture in one place, a replayable flourish
    // in another, and a small celebration for something just made in a third.
    enum Play {
        /// Already there. Show the finished drawing and never animate.
        case never
        /// Draws itself the first time this key appears, then holds.
        case onceInSession(key: String)
        /// Draws itself every time it appears.
        case always
    }

    let set: FlourishSet
    let tint: Color
    let play: Play
    @State private var index: Int

    init(set: FlourishSet = .corner, tint: Color, play: Play) {
        self.set = set
        self.tint = tint
        self.play = play
        _index = State(initialValue: Self.startIndex(set: set, play: play))
    }

    private static func startIndex(set: FlourishSet, play: Play) -> Int {
        let last = max(0, frames(set).count - 1)
        switch play {
        case .never: return last
        case .always: return 0
        case .onceInSession(let key): return played.contains(key) ? last : 0
        }
    }

    private static var cache: [String: [NSImage]] = [:]
    private static var played: Set<String> = []

    static func frames(_ set: FlourishSet) -> [NSImage] {
        if let hit = cache[set.rawValue] { return hit }
        // Counted off what actually shipped rather than written down here. The
        // aspect, the sequence's duration and the onboarding beat that waits
        // for it are all derived from this array, and a hardcoded range made
        // that derivation a fiction: a re-export of a different length would
        // have been rasterised and shipped in full, then played thirty frames
        // of and stopped. Sorted by the number in the name, not the string, so
        // a hundred-frame export doesn't order 100 before 11.
        let urls = Bundle.main.urls(
            forResourcesWithExtension: "png",
            subdirectory: "FlourishFrames/" + set.rawValue) ?? []
        let loaded = urls
            .map { ($0, Int($0.deletingPathExtension().lastPathComponent
                .drop { !$0.isNumber }) ?? 0) }
            .sorted { $0.1 < $1.1 }
            .compactMap { NSImage(contentsOf: $0.0) }
        cache[set.rawValue] = loaded
        return loaded
    }

    /// Taken from the artwork rather than written down, so a re-export at a
    /// different crop cannot leave a frame stretching it.
    static func aspect(_ set: FlourishSet) -> CGFloat {
        guard let first = frames(set).first, first.size.height > 0 else { return 1 }
        return first.size.width / first.size.height
    }

    // 30 frames over 2.5s in the source, which is 12fps.
    static let frameDuration = 1.0 / 12.0

    /// How long the sequence takes, for callers that need to wait it out.
    /// Derived from the frames actually shipped, so a re-export of a different
    /// length keeps whatever is sequenced behind it in step.
    static var duration: TimeInterval { Double(frames(.corner).count) * frameDuration }

    var body: some View {
        let all = Self.frames(set)
        return Group {
            if all.indices.contains(index) {
                Image(nsImage: all[index]).resizable().renderingMode(.template)
            } else {
                Color.clear // no frames shipped: draw nothing rather than a box
            }
        }
        .foregroundStyle(tint)
        .onAppear(perform: start)
    }

    private func start() {
        let all = Self.frames(set)
        guard all.count > 1 else { return }
        switch play {
        case .never: return
        case .onceInSession(let key):
            guard !Self.played.contains(key) else { return }
            Self.played.insert(key)
        case .always: break
        }
        index = 0
        // Stepped by a repeating timer rather than animated: stop-motion is
        // discrete by definition, and interpolating between frames would take
        // the character out of it.
        let timer = Timer.scheduledTimer(withTimeInterval: Self.frameDuration, repeats: true) { t in
            if index < all.count - 1 { index += 1 } else { t.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common) // keeps drawing while scrolling
    }
}

var folderBaseColor: Color { Color(nsColor: Style.theme.folderBase) }

// The air a folder tile keeps above its name.
//
// It used to be occupied: a small botanical sprig sat there in the flow, as a
// PNG. In the system the mark is a watermark behind the whole tile instead, so
// it moved to the background and these hold the space it left — which is why
// the numbers are the sprig's and not something rounder. The tile's height is
// computed from them, so they set the grid the folder grid is laid out on.
let folderMarkHeight: CGFloat = 32
let folderMarkWidth: CGFloat = 32 * (181.0 / 271.0)
let folderMarkGap: CGFloat = 14 // breathing room between the mark and the name
let folderTitleHeight: CGFloat = 16
let folderCellPadding: CGFloat = 9
let folderCellHeight: CGFloat =
    folderMarkHeight + folderMarkGap + folderTitleHeight + folderCellPadding * 2

enum Style {
    // The one piece of mutable global state the colours hang off. Set on launch
    // from UserDefaults and by NotesStore.setTheme thereafter; everything else
    // in this file reads through it.
    static var theme: Theme = Themes.named(UserDefaults.standard.string(forKey: "themeID"))

    static var ink: NSColor { theme.ink }
    static var selection: NSColor { theme.panel }
    static var sheet: NSColor { theme.sheet }
    static let sideMargin: CGFloat = 200
    // user-selectable via the flourish settings page
    static var fontFamily: String = UserDefaults.standard.string(forKey: "fontFamily") ?? "Courier"

    // The body size, and the top of the type scale — see `houseFont`.
    static let baseSize: CGFloat = 16

    static var baseFont: NSFont { font(baseSize) }

    /// The chosen family at a given size, with the same fallback chain
    /// everywhere. Resolved through `NSFontManager` because `fontFamily` is a
    /// *family* name and `NSFont(name:)` wants a font's own name — they happen
    /// to coincide for Courier and don't for most of what the picker offers.
    static func font(_ size: CGFloat) -> NSFont {
        NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: 5, size: size)
            ?? NSFont(name: fontFamily, size: size)
            ?? NSFont(name: "Courier", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // force every font run to the chosen family/size, keeping italic/bold traits
    //
    // Collected first and applied after, rather than written from inside the
    // walk. Adding an attribute can merge a run with its neighbour, which
    // reshapes the very ranges being enumerated — the same reason
    // `normalizeFonts` builds a list of fixes instead of editing in place.
    static func applyFont(to text: NSMutableAttributedString) {
        let manager = NSFontManager.shared
        let full = NSRange(location: 0, length: text.length)
        var fixes: [(NSFont, NSRange)] = []
        text.enumerateAttribute(.font, in: full) { value, range, _ in
            let font = value as? NSFont ?? baseFont
            guard font.familyName != fontFamily || font.pointSize != baseSize else { return }
            var fixed = manager.convert(font, toFamily: fontFamily)
            fixed = manager.convert(fixed, toSize: baseSize)
            fixes.append((fixed, range))
        }
        guard !fixes.isEmpty else { return }
        text.beginEditing()
        for (font, range) in fixes { text.addAttribute(.font, value: font, range: range) }
        text.endEditing()
    }
    // MARK: Ruled paper

    // The one number that sets how open the page feels. Everything else on the
    // ruled grid is derived from it: the pitch is this plus the font's own line
    // height, a paragraph break is two pitches, and a bullet or a line break is
    // one — which is the relationship measured off the Figma frames, where the
    // pitch is 33pt and a paragraph break comes in at 1.96 times it.
    // Three times the type size — the rule the Figma system is built on. There
    // the type is 22 on a 66pt line with the ruling drawn at exactly 66; the
    // app's type is 16, and 16 × 3 = 48. (The whole system scales by 16/22:
    // its 279 margins come out at 203, which is the 200 this app already had.)
    //
    // Held as the *pitch* rather than as a leading, and the leading derived
    // from it, so the grid survives the font picker in settings. A family with
    // a different natural line height gets different leading and still lands on
    // the same rules; the other way round, every family would rule its own page.
    static let linePitch: CGFloat = 48

    static var lineSpacing: CGFloat {
        max(0, linePitch - NSLayoutManager().defaultLineHeight(for: baseFont))
    }

    // The ruling runs wider than the text on both sides — 36 units in the
    // system, which is 26 here. The text column sits inside its ruling rather
    // than being bounded by it, which is what stops the rules reading as a
    // table.
    static let ruleOverhang: CGFloat = 26

    // The type's own height, without the leading that follows it.
    static var lineHeight: CGFloat { NSLayoutManager().defaultLineHeight(for: baseFont) }

    // MARK: The ink box
    //
    // Where the glyphs actually sit inside a line fragment, and how tall they
    // are. AppKit puts the baseline `defaultBaselineOffset` down from the
    // fragment's top; the ink runs from there up by the ascender and down by
    // the descender, and everything else in the fragment is leading.
    //
    // Anything that marks the *words* rather than the line — the selection, the
    // caret — has to measure from here. It cannot measure from the rect AppKit
    // hands it, because that rect's height is not one thing: for the same 16pt
    // type it arrives 19pt tall on the last line of the document, 48 on a line
    // with another line under it (the line plus `lineSpacing`), and 96 on a
    // line that ends a paragraph (plus `paragraphSpacing`). Only its *origin*
    // is dependable — it is the fragment's top in all three cases.
    static var inkOffset: CGFloat {
        NSLayoutManager().defaultBaselineOffset(for: baseFont) - baseFont.ascender
    }
    static var inkHeight: CGFloat { baseFont.ascender - baseFont.descender }

    /// Where a rule actually lands, given the y it would ideally sit at.
    ///
    /// `drawRuling` snaps to the pixel so a hairline doesn't smear across two,
    /// and that snap moves the rule — by up to a point, in whichever direction
    /// the fraction falls. Anything positioning itself *against* the ruling has
    /// to snap the same way, or it will be measuring to where the rule was
    /// computed rather than to where it was drawn.
    static func ruleY(_ y: CGFloat) -> CGFloat { y.rounded() + 0.5 }

    /// The midpoint between the two rules bracketing a line, as drawn.
    static func ruledCentre(forLineTop top: CGFloat) -> CGFloat {
        let above = ruleY(top - lineSpacing / 2)
        return (above + ruleY(top - lineSpacing / 2 + linePitch)) / 2
    }

    // How far a selection reaches past the ink it covers, top and bottom.
    //
    // The selection marks the words; this is the air around them. Taken from
    // the original app, where the highlight was simply the whole line fragment
    // and the fragment was barely taller than the type — which worked out to
    // about 4.5pt of air on a 16pt ink box. At 8 the band read as a slab laid
    // over the line rather than as words being marked, which is not what a
    // wider line should buy: the ruling opens the page up, and the highlight
    // should stay the size of the writing.
    static let selectionPadding: CGFloat = 5

    // The selection in the note editor is a *tone*, not a colour — the same
    // reasoning as `ruleTone` and the panel divider.
    //
    // It used to be `panel`, painted opaque, which covered the paper wherever
    // it fell: a flat swatch on a textured page, and the one place the illusion
    // broke. Black at 13% composites to `base × 0.87`, so the grain and the
    // ruling both come through it, darkened in proportion rather than hidden.
    // No blend mode is needed for that — a black source at alpha `a` *is* a
    // multiply by (1 − a) — and it works here where it would not in a SwiftUI
    // overlay, because the page is painted into this same context by
    // `drawBackground` a moment earlier.
    static let selectionTone = NSColor(white: 0, alpha: 0.13)

    // How far the caret reaches past the type, top and bottom.
    static let caretOvershoot: CGFloat = 2

    // Black at 10%, which is what the system specifies — and black at 10% over
    // a colour is the same arithmetic as multiplying it by 0.9, so it is drawn
    // as a multiply. That keeps it a *tone* rather than a colour: one value
    // that is right in all six themes, and that stays right over the paper's
    // creases, where a flat colour would go lighter than the paper it sits on
    // and read as a highlight instead of a rule.
    //
    // Measured off the exported frames this looked like 4.7%, which is what it
    // was set to before. That was the export halving it — a 1px line at 2x is
    // antialiased across two device pixels — not the value the design asks for.
    static let ruleTone = NSColor(white: 0.9, alpha: 1)

    static var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        // A whole pitch, so a paragraph break is exactly one blank rule and the
        // grid survives it. This was 24 against a pitch of ~21 — close enough
        // to look deliberate, far enough that type walked off the ruling a
        // little further with every paragraph.
        p.paragraphSpacing = linePitch
        p.alignment = .justified // flush both margins, last line falls left
        return p
    }
    static var base: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: ink, .paragraphStyle: paragraph]
    }

    // A horizontal rule is stored as a lone no-break space on its own
    // paragraph; the text view draws a full-width line over it.
    // Horizontal rules are gone from the editing experience — the ruled page
    // does that job now, and one more line cannot mean "a break" on a page made
    // of lines. The marker survives only so notes that already contain one open
    // as a blank line rather than as a stray box-drawing run.
    static let hrMarker = "\u{00A0}"
    static let bulletPrefix = "• "
    static var bulletIndent: CGFloat {
        (bulletPrefix as NSString).size(withAttributes: [.font: baseFont]).width
    }
    // hanging indent so wrapped lines align after the bullet; tighter spacing
    // between list items than between prose paragraphs
    static var bulletParagraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        // Zero rather than the old 8, for the same reason paragraphs take a
        // whole pitch: any gap that isn't a multiple of the ruling walks the
        // list off the grid. Zero also keeps list items tighter than prose,
        // which is what the 8 was there for.
        p.paragraphSpacing = 0
        p.headIndent = bulletIndent
        return p
    }
}

struct NoteMeta: Identifiable, Equatable {
    let id: String
    var title: String
    var modified: Date
    var folder: String? // nil = unfiled (vault root)
}

struct SearchHit: Identifiable {
    let id: String
    let title: String
    let snippet: String
    let folder: String?
}

// A margin annotation anchored to a character range of the note, not pixels.
//
// `pinX`/`pinY`/`rotation` are from when a sticky could be dragged out onto
// the page and left there. That went with the crumpled ball — a sticky lives in
// its margin now, on the Mac as on the phone — but the fields stay, unread, so
// a file written by an older build still decodes and keeps them when rewritten.
struct Sticky: Identifiable, Codable, Equatable {
    let id: UUID
    var start: Int
    var length: Int
    var text: String
    var pinX: Double?
    var pinY: Double?
    var rotation: Double?
    var left: Bool? // which margin it lives in; nil/false = right
}

final class NotesStore: ObservableObject {
    @Published var notes: [NoteMeta] = []
    @Published var currentID: String = UUID().uuidString
    // Bumped only when a different document is loaded into the editor,
    // never on typing — the text view watches this to know when to reset.
    @Published private(set) var docVersion = 0

    private(set) var attr = NSAttributedString()
    private var saveWork: DispatchWorkItem?
    @Published private(set) var dir: URL
    @Published private(set) var fontFamily: String = Style.fontFamily

    // MARK: Folders (real subdirectories of the vault, one level deep)

    @Published private(set) var folders: [String] = []
    private(set) var currentFolder: String?
    // .some(x) = the panel is open at location x (nil = root);
    // nil = panel closed, new notes follow the open note's folder
    var panelContext: String?? = nil

    func baseDir(_ folder: String?) -> URL {
        guard let folder, !folder.isEmpty else { return dir }
        return dir.appendingPathComponent(folder, isDirectory: true)
    }

    func folderOf(_ id: String) -> String? {
        if id == currentID { return currentFolder }
        return notes.first(where: { $0.id == id })?.folder
    }

    var vaultDisplay: String {
        dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: First run & display name

    // The vault is named after the app rather than after the string "JUI", so a
    // build carrying a different CFBundleName — the re-JUI look rebuild — keeps
    // its own notes instead of writing into the shipping app's. For the real
    // app this resolves to exactly what it always did.
    static var appFolderName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "JUI"
    }

    static var defaultVaultDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(appFolderName)/Notes", isDirectory: true)
    }

    // The single source of truth for the name: onboarding writes it, the
    // settings card edits it, and the hidden page reads it.
    @Published var displayName: String =
        UserDefaults.standard.string(forKey: "displayName") ?? ""
    @Published var onboardingShown: Bool =
        !UserDefaults.standard.bool(forKey: "onboardingCompleted")

    // typing is suspended while a full-window overlay is up
    var editorBlocked: Bool { hiddenShown || onboardingShown }

    func setDisplayName(_ raw: String) {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean != displayName else { return }
        displayName = clean
        UserDefaults.standard.set(clean, forKey: "displayName")
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        onboardingShown = false
    }

    // Replays the first-run flow on demand — the hidden "onboard again" row in
    // ⌘K. Deliberately does not clear onboardingCompleted: the only way out of
    // onboarding is to finish it (Escape is dead by design), so if someone quits
    // half-way the next launch should still open straight into the editor.
    func replayOnboarding() {
        searchShown = false
        hiddenShown = false
        saveNow() // the editor is about to freeze behind a full-window overlay
        onboardingShown = true
    }

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let defaultDir = base.appendingPathComponent(
            "\(Self.appFolderName)/Notes", isDirectory: true)
        // migrate notes saved under the app's old name
        let oldDir = base.appendingPathComponent("PlainEditor/Notes", isDirectory: true)
        if !fm.fileExists(atPath: defaultDir.path), fm.fileExists(atPath: oldDir.path) {
            try? fm.createDirectory(
                at: defaultDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: oldDir, to: defaultDir)
        }
        // a user-chosen vault overrides the default location
        if let saved = UserDefaults.standard.string(forKey: "vaultPath"),
           fm.fileExists(atPath: saved) {
            dir = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            dir = defaultDir
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        refreshList()
        if let latest = notes.first { open(latest.id) }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.saveNow()
            // Only if the mood actually changed: a pinned Dock tile keeps showing
            // the old icon until the Dock restarts, and there's no reason to
            // disturb it on an ordinary quit.
            if self?.themeChangedThisSession == true { AppIcon.refreshDockTile() }
        }
    }

    @Published private(set) var wordCount = 0

    private func updateWordCount() {
        // The bullet is furniture, not a word. Runs of "─" were filtered here
        // too, back when a horizontal rule was stored as one; nothing writes one
        // any more, and the marker that replaced it is a no-break space, which
        // `isWhitespace` already splits on.
        let tokens = attr.string.split { $0.isWhitespace || $0.isNewline }
        wordCount = tokens.filter { $0 != "•" }.count
    }

    func textChanged(_ new: NSAttributedString) {
        attr = NSAttributedString(attributedString: new)
        updateWordCount()
        scheduleSave()
    }

    // The hidden page is a read-only overlay toggled by the corner flourish;
    // while it's up, the editor underneath is frozen.
    @Published var hiddenShown = false

    // MARK: Sticky annotations

    @Published var stickies: [Sticky] = []

    private func stickiesURL(_ id: String, in folder: String?) -> URL {
        baseDir(folder).appendingPathComponent("\(id).stickies.json")
    }

    private func loadStickies(_ id: String, in folder: String?) -> [Sticky] {
        guard let data = try? Data(contentsOf: stickiesURL(id, in: folder)) else { return [] }
        return (try? JSONDecoder().decode([Sticky].self, from: data)) ?? []
    }

    // Made during this session, so their flourish can draw itself on once while
    // everything already on the page keeps still. Never cleared: the set of
    // things you have made since launch is small, and the alternative — a flag
    // wiped on a timer — races the view that is meant to read it. (A sticky
    // needs no such set: its flourish draws itself on every time it is opened.)
    @Published private(set) var freshFolders: Set<String> = []

    func addSticky(range: NSRange, left: Bool) -> UUID {
        var sticky = Sticky(id: UUID(), start: range.location, length: range.length, text: "")
        sticky.left = left
        stickies.append(sticky)
        scheduleSave()
        return sticky.id
    }

    func updateStickyText(_ id: UUID, _ text: String) {
        guard let i = stickies.firstIndex(where: { $0.id == id }), stickies[i].text != text else { return }
        stickies[i].text = text
        scheduleSave()
    }

    func removeSticky(_ id: UUID) {
        stickies.removeAll { $0.id == id }
        scheduleSave()
    }

    // Shift anchors through a text edit so they keep tracking their text.
    // Anchors inside a deleted range collapse to the edit point but survive.
    func remapStickies(edit: NSRange, replacementLength: Int) {
        guard !stickies.isEmpty else { return }
        let delta = replacementLength - edit.length
        let editEnd = edit.location + edit.length
        var changed = false
        func map(_ position: Int) -> Int {
            if position <= edit.location { return position }
            if position >= editEnd { return position + delta }
            return edit.location
        }
        for i in stickies.indices {
            let start = stickies[i].start
            let end = start + stickies[i].length
            let newStart = map(start)
            let newEnd = max(map(end), newStart)
            if newStart != start || newEnd - newStart != stickies[i].length {
                stickies[i].start = newStart
                stickies[i].length = newEnd - newStart
                changed = true
            }
        }
        if changed { scheduleSave() }
    }

    // MARK: Search (⌘K)

    @Published var searchShown = false {
        didSet {
            guard !searchShown, oldValue else { return }
            // The cache is every note's text held in memory. Dropped a beat
            // after the palette closes rather than with it: the rows are still
            // being laid out while it fades out over 0.6s, and clearing on the
            // instant took the snippets out of them on the way past.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, !self.searchShown else { return }
                self.searchCache.removeAll()
            }
        }
    }
    var pendingReveal: NSRange? // consumed by the text view after a reveal()
    private var searchCache: [String: String] = [:]

    func openSearch() {
        hiddenShown = false
        searchCache = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, plainTextForNote($0.id)) })
        searchShown = true
    }

    // MARK: Folder management

    @discardableResult
    func createFolder(_ name: String) -> String? {
        let clean = sanitizeFolderName(name)
        guard !clean.isEmpty else { return nil }
        let fm = FileManager.default
        var candidate = clean
        var counter = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            candidate = "\(clean) \(counter)"
            counter += 1
        }
        try? fm.createDirectory(
            at: dir.appendingPathComponent(candidate, isDirectory: true),
            withIntermediateDirectories: true)
        freshFolders.insert(candidate)
        refreshList()
        return candidate
    }

    @discardableResult
    func renameFolder(_ name: String, to newName: String) -> String? {
        let clean = sanitizeFolderName(newName)
        guard !clean.isEmpty, clean != name else { return name }
        let fm = FileManager.default
        // Skip the uniquing loop when the only thing changing is case.
        //
        // The vault sits on a case-insensitive filesystem, so `fileExists` for
        // "Notes" is true while the folder is still called "notes" — the folder
        // being renamed answers for the name it is being renamed *to*. The loop
        // read that as a collision and settled on "Notes 2", so fixing a
        // folder's capitalisation was the one rename that could not be done.
        // A same-name-different-case move is exactly what the filesystem
        // handles for us.
        var candidate = clean
        if clean.lowercased() != name.lowercased() {
            var counter = 2
            while fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
                candidate = "\(clean) \(counter)"
                counter += 1
            }
        }
        do {
            try fm.moveItem(
                at: dir.appendingPathComponent(name),
                to: dir.appendingPathComponent(candidate))
        } catch { return nil }
        if currentFolder == name { currentFolder = candidate }
        refreshList()
        return candidate
    }

    // Deleting a folder deletes what is in it. There is no trash and no undo,
    // which is the same deal `delete(_:)` offers for a single note.
    //
    // The whole directory goes, not a filtered sweep of it: a leftover file of
    // some other kind would have made `removeItem` fail and left a ghost folder
    // in the panel that nothing could get rid of.
    func deleteFolder(_ name: String) {
        let fm = FileManager.default
        let folderURL = dir.appendingPathComponent(name, isDirectory: true)
        // The open note may be one of the ones about to go. Cancel its pending
        // save first, or the debounce fires afterwards and writes the file
        // straight back — into a directory that no longer exists, so the note
        // is lost and the folder half-returns.
        let losingCurrent = folderOf(currentID) == name
        if losingCurrent { saveWork?.cancel() }
        try? fm.removeItem(at: folderURL)
        if currentFolder == name { currentFolder = nil }
        refreshList()
        if losingCurrent { openMostRecentOrBlank() }
    }

    func moveNote(_ id: String, to folder: String?) {
        let from = folderOf(id)
        guard from != folder else { return }
        if id == currentID { saveNow() } // files must exist at the old location
        let fm = FileManager.default
        try? fm.createDirectory(at: baseDir(folder), withIntermediateDirectories: true)
        for ext in ["rtf", "txt"] {
            let src = baseDir(from).appendingPathComponent(id).appendingPathExtension(ext)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.moveItem(
                at: src, to: baseDir(folder).appendingPathComponent(id).appendingPathExtension(ext))
        }
        let stickySrc = baseDir(from).appendingPathComponent("\(id).stickies.json")
        if fm.fileExists(atPath: stickySrc.path) {
            try? fm.moveItem(
                at: stickySrc, to: baseDir(folder).appendingPathComponent("\(id).stickies.json"))
        }
        if id == currentID { currentFolder = folder }
        refreshList()
    }

    private func sanitizeFolderName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    // MARK: Settings

    func changeVault(to newDir: URL) {
        guard newDir != dir else { return }
        saveNow()
        let fm = FileManager.default
        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        // bring notes and folders along; never overwrite what's already there
        if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for item in items {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir, !item.lastPathComponent.hasPrefix(".") {
                    let dest = newDir.appendingPathComponent(item.lastPathComponent, isDirectory: true)
                    if !fm.fileExists(atPath: dest.path) {
                        try? fm.moveItem(at: item, to: dest)
                    } else if let inner = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                        for file in inner where ["rtf", "txt", "json"].contains(file.pathExtension) {
                            let fileDest = dest.appendingPathComponent(file.lastPathComponent)
                            if !fm.fileExists(atPath: fileDest.path) {
                                try? fm.moveItem(at: file, to: fileDest)
                            }
                        }
                    }
                } else if ["rtf", "txt", "json"].contains(item.pathExtension) {
                    let dest = newDir.appendingPathComponent(item.lastPathComponent)
                    if !fm.fileExists(atPath: dest.path) {
                        try? fm.moveItem(at: item, to: dest)
                    }
                }
            }
        }
        dir = newDir
        UserDefaults.standard.set(newDir.path, forKey: "vaultPath")
        refreshList()
    }

    func setFont(_ family: String) {
        guard family != fontFamily else { return }
        fontFamily = family
        Style.fontFamily = family
        UserDefaults.standard.set(family, forKey: "fontFamily")
        let restyled = NSMutableAttributedString(attributedString: attr)
        Style.applyFont(to: restyled)
        attr = restyled
        docVersion += 1
        scheduleSave()
    }

    @Published private(set) var themeID: String = Style.theme.id
    private var themeChangedThisSession = false

    // Deliberately does NOT bump docVersion the way setFont does. A font change
    // reflows the document and can afford a reload; a theme change happens
    // mid-sentence from the settings page, so the text view recolours its
    // storage in place instead (PlainTextView.applyTheme) — no reload, no lost
    // undo, no caret jump to the end of the note.
    func setTheme(_ theme: Theme) {
        guard theme.id != themeID else { return }
        Style.theme = theme
        themeID = theme.id
        UserDefaults.standard.set(theme.id, forKey: "themeID")
        AppIcon.apply(theme) // the Dock icon follows too
        themeChangedThisSession = true
    }

    func search(_ query: String) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var hits: [SearchHit] = []
        for meta in notes {
            let text = meta.id == currentID ? attr.string : (searchCache[meta.id] ?? "")
            if q.isEmpty {
                hits.append(SearchHit(id: meta.id, title: meta.title, snippet: "", folder: meta.folder))
                continue
            }
            if let r = text.range(of: q, options: .caseInsensitive) {
                let line = text[text.lineRange(for: r)]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                hits.append(SearchHit(
                    id: meta.id, title: meta.title,
                    snippet: String(line.prefix(64)), folder: meta.folder))
            } else if meta.title.range(of: q, options: .caseInsensitive) != nil {
                hits.append(SearchHit(id: meta.id, title: meta.title, snippet: "", folder: meta.folder))
            }
        }
        return hits
    }

    // open a note from search and remember where to scroll/flash
    func reveal(_ id: String, query: String) {
        searchShown = false
        saveNow()
        load(id, in: notes.first(where: { $0.id == id })?.folder, revealing: query)
    }

    private func plainTextForNote(_ id: String) -> String {
        let folder = folderOf(id)
        let rtf = rtfURL(id, in: folder)
        if FileManager.default.fileExists(atPath: rtf.path) { return plainText(of: rtf) }
        return plainText(of: txtURL(id, in: folder))
    }

    // A note's title is derived from its first line, so working it out means
    // opening the file and parsing the RTF. Cached against the modification
    // date it was read at, so a rescan only parses what has actually changed.
    //
    // This is load-bearing rather than an optimisation for its own sake:
    // `saveNow` ends in `refreshList`, and saves are debounced on typing, so
    // every pause of 300ms re-read and re-parsed *every note in the vault*.
    // The cost grew with the vault and landed on the one path that has to stay
    // cheap. Now a save re-parses the one file it just wrote.
    private var titleCache: [String: (modified: Date, title: String)] = [:]

    func refreshList() {
        let fm = FileManager.default
        var seen = Set<String>()
        var metas: [NoteMeta] = []
        var folderNames: [String] = []
        // Rebuilt rather than updated in place, so a note that has been deleted
        // or moved doesn't leave its entry behind for the life of the process.
        var freshTitles: [String: (modified: Date, title: String)] = [:]

        func scanFiles(in directory: URL, folder: String?) {
            let files = (try? fm.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            // rtf first so a leftover legacy .txt with the same id is ignored
            for url in files.sorted(by: { $0.pathExtension < $1.pathExtension }) {
                guard ["rtf", "txt"].contains(url.pathExtension) else { continue }
                let id = url.deletingPathExtension().lastPathComponent
                guard seen.insert(id).inserted else { continue }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let title: String
                if let hit = titleCache[url.path], hit.modified == modified {
                    title = hit.title
                } else {
                    title = Self.title(for: plainText(of: url))
                }
                freshTitles[url.path] = (modified, title)
                metas.append(NoteMeta(
                    id: id, title: title, modified: modified, folder: folder))
            }
        }

        let rootItems = (try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for item in rootItems {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir, !item.lastPathComponent.hasPrefix(".") {
                folderNames.append(item.lastPathComponent)
                scanFiles(in: item, folder: item.lastPathComponent)
            }
        }
        scanFiles(in: dir, folder: nil)

        titleCache = freshTitles
        folders = folderNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        notes = metas.sorted { $0.modified > $1.modified }
    }

    private func plainText(of url: URL) -> String {
        if url.pathExtension == "rtf",
           let data = try? Data(contentsOf: url),
           let parsed = NSAttributedString(rtf: data, documentAttributes: nil) {
            return parsed.string
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func title(for text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        if firstLine.isEmpty { return "Untitled" }
        return String(firstLine.prefix(42))
    }

    private func loadAttr(_ id: String, in folder: String?) -> NSAttributedString {
        if let data = try? Data(contentsOf: rtfURL(id, in: folder)),
           let parsed = NSAttributedString(rtf: data, documentAttributes: nil) {
            // Rebuild the paragraph styles rather than trusting the file.
            // Notes saved before a spacing change carry the old metrics, and on
            // a ruled page that is not a small difference: any gap that isn't a
            // whole number of pitches walks the type off the ruling, a little
            // further with every paragraph.
            //
            // Per line, not in one sweep. Applying Style.paragraph to the whole
            // document — which is what this did — flattened every bullet into
            // prose, so lists came back from disk sitting a full blank rule
            // apart instead of on consecutive ones.
            //
            // Classified by the line's own text, because that is what is
            // actually true about it. Reading it off headIndent, the way
            // normalizeFonts does at runtime, would mean deciding from the very
            // attribute being rebuilt.
            let restyled = NSMutableAttributedString(attributedString: parsed)
            let lines = restyled.string as NSString
            var cursor = 0
            while cursor < lines.length {
                let lineRange = lines.lineRange(for: NSRange(location: cursor, length: 0))
                let isBullet = lines.substring(with: lineRange).hasPrefix(Style.bulletPrefix)
                restyled.addAttribute(
                    .paragraphStyle,
                    value: isBullet ? Style.bulletParagraph : Style.paragraph,
                    range: lineRange)
                cursor = NSMaxRange(lineRange)
            }
            restyled.addAttribute(
                .foregroundColor, value: Style.ink,
                range: NSRange(location: 0, length: restyled.length))
            // migrate old fixed-width "───…" rules to the drawn marker
            let ns = restyled.string as NSString
            var hrRanges: [NSRange] = []
            var lineStart = 0
            while lineStart < ns.length {
                let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
                let content = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
                if content.count >= 3, content.allSatisfy({ $0 == "─" }) {
                    hrRanges.append(NSRange(
                        location: lineRange.location, length: (content as NSString).length))
                }
                lineStart = NSMaxRange(lineRange)
            }
            for range in hrRanges.reversed() {
                restyled.replaceCharacters(
                    in: range,
                    with: NSAttributedString(string: Style.hrMarker, attributes: Style.base))
            }
            Style.applyFont(to: restyled)
            return restyled
        }
        if let legacy = try? String(contentsOf: txtURL(id, in: folder), encoding: .utf8) {
            return NSAttributedString(string: legacy, attributes: Style.base)
        }
        return NSAttributedString()
    }

    // MARK: Getting a document into the editor
    //
    // Every route in goes through `load` or `loadBlank`, so none of them can
    // forget a step. There were four copies of this sequence — open, reveal,
    // delete-the-open-note, new — and `docVersion` has to be bumped last, after
    // `pendingReveal` is set, or the text view reloads before it can read it.

    private func load(_ id: String, in folder: String?, revealing query: String? = nil) {
        currentID = id
        currentFolder = folder
        attr = loadAttr(id, in: folder)
        stickies = loadStickies(id, in: folder)
        updateWordCount()
        if let query {
            let q = query.trimmingCharacters(in: .whitespaces)
            let range = (attr.string as NSString).range(of: q, options: .caseInsensitive)
            pendingReveal = (!q.isEmpty && range.location != NSNotFound) ? range : nil
        }
        docVersion += 1
    }

    /// A blank page. Nothing reaches disk until something is typed into it.
    private func loadBlank(in folder: String?) {
        currentID = UUID().uuidString
        currentFolder = folder
        attr = NSAttributedString()
        stickies = []
        updateWordCount()
        docVersion += 1
    }

    /// Whatever was written most recently, or a blank page if the vault is now
    /// empty — where the editor lands when the open note is deleted under it.
    private func openMostRecentOrBlank() {
        if let latest = notes.first {
            load(latest.id, in: latest.folder)
        } else {
            loadBlank(in: nil)
        }
    }

    func open(_ id: String) {
        saveNow()
        load(id, in: notes.first(where: { $0.id == id })?.folder)
    }

    func delete(_ id: String) {
        let losingCurrent = id == currentID
        if losingCurrent { saveWork?.cancel() } // a pending save would resurrect the file
        let folder = folderOf(id)
        let fm = FileManager.default
        try? fm.removeItem(at: rtfURL(id, in: folder))
        try? fm.removeItem(at: txtURL(id, in: folder))
        try? fm.removeItem(at: stickiesURL(id, in: folder))
        refreshList()
        if losingCurrent { openMostRecentOrBlank() }
    }

    func newNote() {
        hiddenShown = false
        saveNow()
        // land in the panel's current location if it's open, else stay in the
        // open note's folder
        loadBlank(in: panelContext ?? currentFolder)
    }

    private func rtfURL(_ id: String, in folder: String?) -> URL {
        baseDir(folder).appendingPathComponent(id).appendingPathExtension("rtf")
    }

    private func txtURL(_ id: String, in folder: String?) -> URL {
        baseDir(folder).appendingPathComponent(id).appendingPathExtension("txt")
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        let fm = FileManager.default
        let url = rtfURL(currentID, in: currentFolder)
        let hadFile = fm.fileExists(atPath: url.path)
            || fm.fileExists(atPath: txtURL(currentID, in: currentFolder).path)
        // Don't create a file for a note that was never typed into.
        if attr.length == 0 && !hadFile { return }
        try? fm.createDirectory(at: baseDir(currentFolder), withIntermediateDirectories: true)
        guard let data = attr.rtf(from: NSRange(location: 0, length: attr.length)) else { return }
        try? data.write(to: url, options: .atomic)
        // migrate away from the legacy plain-text file
        try? fm.removeItem(at: txtURL(currentID, in: currentFolder))
        let sURL = stickiesURL(currentID, in: currentFolder)
        if stickies.isEmpty {
            try? fm.removeItem(at: sURL)
        } else if let stickyData = try? JSONEncoder().encode(stickies) {
            try? stickyData.write(to: sURL, options: .atomic)
        }
        refreshList()
    }
}

// MARK: - Sticky annotation views

var stickyNSColor: NSColor { Style.theme.sticky }

// MARK: - Smooth caret (MS Word 2013-style glide)

// Shared by every text view in the app (the note editor and each sticky's
// editor) so the caret always glides to its new position instead of jumping,
// staying solid while moving/typing and blinking only when idle.
final class SmoothCaret {
    private weak var view: NSTextView?
    private let layer = CALayer()
    private var configured = false

    init(view: NSTextView) {
        self.view = view
    }

    func attachIfNeeded() {
        guard !configured, let view, view.window != nil else { return }
        configured = true
        view.wantsLayer = true
        // house ink, not the system accent — the caret is the one thing on the
        // page that never stops moving, so it has to be in palette
        layer.backgroundColor = Style.ink.cgColor
        applyTheme()
        layer.cornerRadius = 1
        view.layer?.addSublayer(layer)
        view.insertionPointColor = .clear // native caret off; this layer draws it
        update(animated: false)
    }

    func applyTheme() {
        guard configured else { return }
        layer.backgroundColor = Style.ink.cgColor
    }

    func update(animated: Bool) {
        guard configured, let view else { return }
        view.subviews.compactMap { $0 as? NSTextInsertionIndicator }
            .forEach { $0.displayMode = .hidden }
        let sel = view.selectedRange()
        guard let window = view.window, window.firstResponder === view,
              view.isEditable, sel.length == 0 else {
            layer.isHidden = true
            return
        }
        let screenRect = view.firstRect(forCharacterRange: sel, actualRange: nil)
        guard screenRect.height > 0 else {
            layer.isHidden = true
            return
        }
        var rect = view.convert(window.convertFromScreen(screenRect), from: nil)
        // AppKit's rect for the insertion point is the whole line fragment, and
        // a fragment is [glyphs][leading]. On a 48pt band that drew a 48pt
        // caret — most of it hanging below the letters it sits among, reaching
        // down toward the next line.
        //
        // Sized off the ink box rather than off that rect, for the reason
        // `Style.inkOffset` gives: the rect's height is 19pt on the last line of
        // the document and 48 elsewhere, so the old `min` against a fixed clamp
        // let the caret change height from line to line and sit a little high in
        // both. Now it is one height everywhere, centred on the letters.
        rect.origin.y += Style.inkOffset - Style.caretOvershoot
        rect.size = NSSize(width: 2, height: Style.inkHeight + Style.caretOvershoot * 2)
        layer.isHidden = false
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.10)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        layer.frame = rect
        CATransaction.commit()
        restartBlink()
    }

    // solid while moving/typing, blinks only when idle
    private func restartBlink() {
        layer.removeAnimation(forKey: "blink")
        layer.opacity = 1
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 1, 0, 0, 1]
        blink.keyTimes = [0, 0.45, 0.55, 0.95, 1]
        blink.duration = 1.1
        blink.beginTime = CACurrentMediaTime() + 0.45
        blink.repeatCount = .infinity
        layer.add(blink, forKey: "blink")
    }
}

// The sticky's editor: right-click gets the sticky's menu, not the text menu.
final class StickyTextView: NSTextView {
    var menuProvider: (() -> NSMenu)?
    // Told when the sticky gains or loses focus, a hop later — once the
    // window's first responder says so — which is what shows and hides its
    // buttons.
    var onFocusChange: (() -> Void)?
    private lazy var smoothCaret = SmoothCaret(view: self)

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        smoothCaret.attachIfNeeded()
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {}

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        smoothCaret.update(animated: true)
    }

    override func didChangeText() {
        super.didChangeText()
        smoothCaret.update(animated: true)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        DispatchQueue.main.async { [weak self] in self?.smoothCaret.update(animated: false) }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in
            self?.smoothCaret.update(animated: false)
            self?.onFocusChange?()
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        DispatchQueue.main.async { [weak self] in
            self?.smoothCaret.update(animated: false)
            self?.onFocusChange?()
        }
        return ok
    }

    func applyTheme() {
        insertionPointColor = Style.ink
        applyStyle()
        smoothCaret.applyTheme()
    }

    func applyFont() { applyStyle() }

    // A stamp is a small surface, so its writing sits a step down the scale
    // from the page's — same relationship whatever family is chosen. It was 13
    // on the system's default leading, which read cramped on gold paper; the
    // phone took it up a step and opened the lines out to 140%, and this
    // follows it, so a sticky reads the same on either.
    static let textSize: CGFloat = 14
    static let leading: CGFloat = 1.4 // line height as a multiple of the type size

    static var attributes: [NSAttributedString.Key: Any] {
        let font = Style.font(textSize)
        let line = (textSize * leading).rounded()
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = line
        p.maximumLineHeight = line
        return [
            .font: font, .foregroundColor: Style.ink, .paragraphStyle: p,
            // A fixed line puts its extra height above the glyphs; this
            // centres the type in its line instead.
            .baselineOffset: (line - NSLayoutManager().defaultLineHeight(for: font)) / 2,
        ]
    }

    /// The sticky's one style, over everything in it and whatever is typed
    /// next. A plain-text view keeps one set of attributes for its whole
    /// string, so this is rewritten wholesale — on a theme, a font, or a new
    /// string arriving — as an attribute-only edit that leaves the undo stack
    /// and the selection alone.
    func applyStyle() {
        let attrs = Self.attributes
        font = attrs[.font] as? NSFont
        textColor = Style.ink
        defaultParagraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
        typingAttributes = attrs
        if let storage = textStorage, storage.length > 0 {
            storage.beginEditing()
            storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
    }
}

final class StickyView: NSView, NSTextViewDelegate {
    // The system's flourish, rasterised from the file's own vector with its
    // rotation and flip already baked in — see CLAUDE.md on why the transform
    // is baked at build time rather than applied here.
    // The same stop-motion frames the rest of the app uses, at the sticky's
    // angle. The card draws its flourish on every time it is opened, once the
    // crumpled sheet has lain flat (see Crumple.swift) — never while it unfolds.
    private static var frames: [NSImage] { AnimatedFlourish.frames(.sticky) }

    // The flourish is a single-colour silhouette with a clean alpha channel, so
    // it can be recoloured wholesale to follow the theme. SwiftUI does that with
    // .renderingMode(.template); here the drawing is by hand, so the tint is
    // baked into a copy — sourceAtop over the source directly would catch the
    // sticky's own background, which is already opaque behind it.
    //
    // Cached per frame, for the current theme only — and built only as each
    // frame is reached, so a sticky that never animates still costs exactly one.
    //
    // Held to one theme because every entry is a whole decoded bitmap rather
    // than a reference to the source: the tint has to be baked in. Thirty
    // frames of a ~366×405 stamp is around 18MB, and keying by theme *and*
    // frame meant changing mood *added* a set instead of replacing one — six
    // moods and one animated sticky reached about 106MB, none of it reachable
    // again. Dropping the lot on a theme change costs nothing visible: the same
    // image is rebuilt the same way from the same frame, and the only tint ever
    // asked for is the one currently in force.
    private static var flowerCache: [Int: NSImage] = [:]
    private static var flowerCacheTheme: String?

    private static func flower(_ index: Int, for theme: Theme) -> NSImage? {
        let all = frames
        guard all.indices.contains(index) else { return nil }
        if flowerCacheTheme != theme.id {
            flowerCache.removeAll()
            flowerCacheTheme = theme.id
        }
        if let hit = flowerCache[index] { return hit }
        let src = all[index]
        let out = NSImage(size: src.size)
        out.lockFocus()
        src.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        // #ECDBBE in the system, which is the panel token — not sheet, which is
        // what the old flower used.
        theme.panel.set()
        NSRect(origin: .zero, size: src.size).fill(using: .sourceAtop)
        out.unlockFocus()
        flowerCache[index] = out
        return out
    }

    let stickyID: UUID
    private let noteView = StickyTextView()
    // bottom band reserved for the flower; text never enters it
    // The flourish, as fractions of the stamp's *width*.
    //
    // Width and not height, and anchored to the bottom edge rather than placed
    // at a fraction down the stamp. Placing it proportionally meant a tall
    // sticky pushed it up into the middle of the note and stretched it; the
    // flourish is a fixed mark in the corner of the paper, so it scales with
    // how wide the paper is and stays where it is put. The system has it
    // hanging 18 units past a 316-unit stamp, which is this 0.058.
    //
    // Smaller than the system's 0.40, as on the phone: at that size its blooms
    // reached up into the last lines of writing. Its right-hand edge stays
    // where the system puts it (0.6281 + 0.4034), so it shrinks into the
    // corner rather than away from it, and it keeps the same overhang.
    private static let flourishWidth: CGFloat = 0.30
    private static let flourishLeft: CGFloat = 1.0315 - flourishWidth
    private static let flourishOverhang: CGFloat = 0.0575
    // Clear paper between the last line and the top of the flourish, over and
    // above the text view's own inset — the phone's 18 plus its 4pt inset,
    // which is what reads as the writing having finished before the mark.
    private static let flourishGap: CGFloat = 22
    private static var flourishAspect: CGFloat {
        // the artwork's own, read from the frames rather than written down
        1 / max(AnimatedFlourish.aspect(.sticky), 0.01)
    }

    private func flourishRect() -> NSRect {
        let w = bounds.width * Self.flourishWidth
        let h = w * Self.flourishAspect
        return NSRect(x: bounds.width * Self.flourishLeft,
                      y: -(bounds.width * Self.flourishOverhang),
                      width: w, height: h)
    }

    // Text never enters the flourish's band. Derived from the flourish rather
    // than fixed at 38, which the artwork outgrew — the words were running
    // straight over the flowers on any sticky wide enough. The text view's
    // bottom inset is part of the gap, so it comes off it here.
    private var bottomReserve: CGFloat {
        max(flourishRect().maxY + Self.flourishGap - Self.textInset.height, 24)
    }
    static let textInset = NSSize(width: 14, height: 12) // clear of the perforations
    var onTextChange: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onLayoutNeeded: (() -> Void)?
    /// The sticky's text gained or lost focus.
    var onFocusChange: (() -> Void)?

    // Which frame of the flourish is showing, when it shows at all. Until the
    // card has opened out flat there is no flourish on it; then it draws itself
    // on from the first frame to the last, which is the finished drawing.
    private var flourishIndex: Int
    private var flourishTimer: Timer?
    private var showsFlourish = false

    init(id: UUID, text: String) {
        stickyID = id
        flourishIndex = max(0, Self.frames.count - 1)
        super.init(frame: .zero)
        noteView.isRichText = false
        noteView.insertionPointColor = Style.ink
        noteView.drawsBackground = false
        noteView.textContainerInset = Self.textInset
        noteView.textContainer?.widthTracksTextView = true
        noteView.isAutomaticQuoteSubstitutionEnabled = false
        noteView.isAutomaticDashSubstitutionEnabled = false
        noteView.isAutomaticTextReplacementEnabled = false
        noteView.allowsUndo = true
        noteView.string = text
        noteView.applyStyle()
        noteView.delegate = self
        noteView.menuProvider = { [weak self] in self?.stickyMenu() ?? NSMenu() }
        noteView.onFocusChange = { [weak self] in self?.onFocusChange?() }
        addSubview(noteView)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func layout() {
        super.layout()
        noteView.frame = NSRect(
            x: 0, y: bottomReserve,
            width: bounds.width, height: max(bounds.height - bottomReserve, 0))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true // perforation count depends on the size
    }

    // Postage-stamp background: the rectangle with semicircular perforations
    // punched out of every edge, evenly distributed for whatever size the
    // note currently is.
    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 4
        let pitch: CGFloat = 15
        let cornerGap: CGFloat = 6 // perforations start this far from each vertex
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.appendRect(bounds)
        func punch(along length: CGFloat, _ point: (CGFloat) -> NSPoint) {
            let usable = length - cornerGap * 2
            guard usable >= pitch else { return }
            let count = max(1, Int((usable / pitch).rounded()))
            let step = usable / CGFloat(count)
            for i in 0..<count {
                let center = point(cornerGap + (CGFloat(i) + 0.5) * step)
                path.appendOval(in: NSRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2))
            }
        }
        punch(along: bounds.width) { NSPoint(x: $0, y: 0) }
        punch(along: bounds.width) { NSPoint(x: $0, y: bounds.height) }
        punch(along: bounds.height) { NSPoint(x: 0, y: $0) }
        punch(along: bounds.height) { NSPoint(x: bounds.width, y: $0) }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).setClip() // keep the outer half-circles from painting
        stickyNSColor.setFill()
        path.fill()
        // Paper, clipped to the stamp's own perforated outline — so the grain
        // stops exactly where the paper does, including inside every punch,
        // rather than squaring off at the bounds behind them.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        Surface.sticky.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()
        // The flourish, bottom-right and running off the edge — placed as
        // fractions of the stamp, which is how the system positions it
        // (198.82/316.53 across, 208.64/330.24 down, 127.68 wide on a 316.53
        // stamp; drawn a little smaller here, see `flourishWidth`). It reaches
        // past the bottom edge by about 5% and is cut off by the clip above,
        // which is deliberate in the design.
        //
        // Width drives the height through the artwork's own aspect rather than
        // both coming from the stamp, so a sticky that isn't the system's
        // proportions doesn't stretch the flowers.
        // Multiplied, not painted on. The artwork is #ECDBBE — the panel token —
        // but the system draws it *through* whatever it sits on, so on gold it
        // comes out a deep tan rather than a pale cream. Painted opaque it was
        // far too light, and the SVG's fill attribute gives no hint of this: a
        // blend mode doesn't survive that export.
        if showsFlourish {
            Self.flower(flourishIndex, for: Style.theme)?.draw(
                in: flourishRect(), from: .zero, operation: .multiply, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // Stepped by a timer rather than animated, like every other playing of this
    // sequence: stop-motion is discrete, and interpolating between frames would
    // take the character out of it. Added in .common mode so it keeps going
    // while the page is scrolled.
    /// Draws the flourish on from its first frame — the card has just opened.
    func playFlourish() {
        flourishTimer?.invalidate()
        showsFlourish = true
        flourishIndex = 0
        needsDisplay = true
        startFlourish()
    }

    /// The flourish finished, at once — for a picture of the card being put
    /// away, which has had its flourish all the while it was open.
    func finishFlourish() {
        flourishTimer?.invalidate()
        showsFlourish = true
        flourishIndex = max(0, Self.frames.count - 1)
        needsDisplay = true
    }

    /// The card as it looks now, at twice its points, for the crumpled sheet
    /// to be printed with. Drawn by the view itself — paper, flourish and
    /// words — so the hand-over between sheet and card can't be seen. The
    /// caret is a layer and stays out of it.
    func picture() -> NSImage {
        layoutSubtreeIfNeeded()
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((bounds.width * scale).rounded(.up)),
            pixelsHigh: Int((bounds.height * scale).rounded(.up)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = bounds.size
        // A card waiting for its sheet to land is hidden, and a hidden view
        // draws nothing; shown for the length of this call, which no screen
        // update can fall inside.
        let wasHidden = isHidden
        isHidden = false
        cacheDisplay(in: bounds, to: rep)
        isHidden = wasHidden
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func startFlourish() {
        guard Self.frames.count > 1 else { return }
        let timer = Timer.scheduledTimer(
            withTimeInterval: AnimatedFlourish.frameDuration, repeats: true
        ) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if self.flourishIndex < Self.frames.count - 1 {
                self.flourishIndex += 1
                self.needsDisplay = true
            } else {
                t.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        flourishTimer = timer
    }

    deinit { flourishTimer?.invalidate() }

    func applyTheme() {
        noteView.applyTheme()
        needsDisplay = true // the stamp body and its flourish are drawn by hand
    }

    // A different family means a different line height, so the stamp has to be
    // re-measured — it sizes itself to its text.
    func applyFont() {
        noteView.applyFont()
        onLayoutNeeded?()
    }

    private func stickyMenu() -> NSMenu {
        let menu = NSMenu()
        let delete = NSMenuItem(title: "Delete Note", action: #selector(deleteSticky), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        return menu
    }

    @objc private func deleteSticky() { onDelete?() }

    override func menu(for event: NSEvent) -> NSMenu? { stickyMenu() }

    // When not editing, a click anywhere on the stamp puts the caret in it;
    // while editing, clicks go to the text as usual. It used to be draggable
    // out onto the page, too — that went with the crumpled ball: a sticky put
    // away is a ball beside its line, and one out on the page would have no
    // line to go back to.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if view != nil, !isEditing { return self }
        return view
    }

    override func mouseDown(with event: NSEvent) { focus() }

    var noteText: String { noteView.string }
    var isEditing: Bool { window?.firstResponder === noteView }

    func setText(_ text: String) {
        if noteView.string != text {
            noteView.string = text
            noteView.applyStyle()
        }
    }

    // Square by default — height matches width — growing only when the
    // content needs more room.
    var desiredHeight: CGFloat {
        guard let lm = noteView.layoutManager, let tc = noteView.textContainer else {
            return bounds.width
        }
        // Freshly created views (opening a past note) haven't had a layout
        // pass yet, so the text would measure against a zero-width container.
        // Size the inner text view synchronously before measuring.
        if noteView.frame.width != bounds.width {
            noteView.frame = NSRect(
                x: 0, y: bottomReserve,
                width: bounds.width, height: max(bounds.height - bottomReserve, 100))
        }
        lm.ensureLayout(for: tc)
        return max(lm.usedRect(for: tc).height + Self.textInset.height * 2 + bottomReserve, bounds.width)
    }

    func focus() { window?.makeFirstResponder(noteView) }

    func textDidChange(_ notification: Notification) {
        onTextChange?(noteView.string)
        onLayoutNeeded?()
    }

    // A sticky that was never typed into vanishes when clicked away from —
    // the page decides that as it puts the card away (`putAwaySticky`), so
    // that it crumples to nothing rather than back into a ball.
}

// The flat square that appears above an active selection.
final class SelectionIconView: NSView {
    var onClick: (() -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        wantsLayer = true
        layer?.cornerRadius = 2
        layer?.borderWidth = 2
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func applyTheme() {
        layer?.backgroundColor = stickyNSColor.cgColor
        layer?.borderColor = Style.sheet.cgColor
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

// MARK: - The sticky put away

// A sticky, put away, is a small crumpled ball of sticky paper in its margin,
// beside the line it is anchored to — the same crumpled sheet the opening
// starts from (Crumple.swift), rendered once per mood. Clicking it opens it out
// into the card.
//
// The view is larger than the ball it draws, so the pointer can find it.
final class StickyBallView: NSView {
    let stickyID: UUID
    var onClick: (() -> Void)?
    var onDelete: (() -> Void)?

    static let hitSize = NSSize(width: 30, height: 40)

    init(id: UUID) {
        stickyID = id
        super.init(frame: NSRect(origin: .zero, size: Self.hitSize))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Sticky note")
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    // The ball for the current mood. A blank card crumpled is the same for
    // every sticky, so there is one picture, rebuilt only when the mood
    // changes — the font doesn't reach it, since there are no words on it.
    private static var ball: NSImage?
    private static var ballTheme: String?

    private static func current() -> NSImage? {
        if ballTheme != Style.theme.id {
            ballTheme = Style.theme.id
            let side = PlainTextView.cardWidth
            ball = CrumpleArt.ball(from: PlainTextView.blankCard(size: NSSize(width: side, height: side)),
                                   scale: 2)
        }
        return ball
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ball = Self.current() else { return }
        ball.draw(in: NSRect(x: (bounds.width - ball.size.width) / 2,
                             y: (bounds.height - ball.size.height) / 2,
                             width: ball.size.width, height: ball.size.height))
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let delete = NSMenuItem(title: "Delete Note", action: #selector(deleteSticky), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        return menu
    }

    @objc private func deleteSticky() { onDelete?() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    func applyTheme() { needsDisplay = true }
}

// MARK: - The stamp's buttons

// Delete and done, under a sticky while it is being written in: the hand-drawn
// marks from the Figma system (node 330:433), the same ones the phone shows. A
// sticky that is only being looked at is just the stamp, and the right-click
// menu still has both — these are for the moment the hand is already on the
// keyboard and the pointer is nearby.
//
// The marks are the system's own vectors, composed into its 60 × 60 tile and
// rasterised by `Art/render-marks.swift` (see build.sh), so each lands exactly
// where the frame places it. They ship white and are tinted at draw time, in
// the ink's muted step — the system draws them in #967654, which is that step
// (see CLAUDE.md, "Where the system and the ink ladder disagree") — so they
// follow every theme as the ink does.
final class StampButton: NSView {
    enum Kind: String {
        case delete = "StickyDelete", done = "StickyDone"
    }

    // The system's tile is 60, and the app scales the system by 16/22 — the
    // other icon buttons are 44 for the same reason.
    static let side: CGFloat = 44
    static var scale: CGFloat { side / 60 }
    // Wider than the system's 17 (scaled to 12.5), so the two marks read as two
    // choices rather than a pair.
    static let gap: CGFloat = 28
    // Clear air between the stamp and the buttons hanging under it.
    static let drop: CGFloat = 14
    // A faint tile behind each mark: a tone, not a colour — black at 6% is a
    // multiply by 0.94, a soft step down from whatever it sits on in every
    // theme, much lighter than the system's papered panel tile.
    static let tileTone = NSColor(white: 0, alpha: 0.06)

    let kind: Kind
    var onClick: (() -> Void)?
    private var pressed = false { didSet { needsDisplay = true } }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(kind == .delete ? "Delete sticky note" : "Done")
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    // Tinted copies for the current theme only, rebuilt on a change — the same
    // shape as `StickyView`'s flourish cache, for the same reason.
    private static var marks: [Kind: NSImage] = [:]
    private static var marksTheme: String?

    private static func mark(_ kind: Kind) -> NSImage? {
        if marksTheme != Style.theme.id {
            marks.removeAll()
            marksTheme = Style.theme.id
        }
        if let hit = marks[kind] { return hit }
        guard let url = Bundle.main.url(
                forResource: kind.rawValue, withExtension: "png", subdirectory: "StickyButtons"),
              let src = NSImage(contentsOf: url) else { return nil }
        let out = NSImage(size: src.size)
        out.lockFocus()
        src.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        Style.ink.withAlphaComponent(0.55).set() // inkMuted
        NSRect(origin: .zero, size: src.size).fill(using: .sourceAtop)
        out.unlockFocus()
        marks[kind] = out
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        // Under the pointer the mark settles a little, as the phone's does
        // under the finger.
        let tile = pressed ? bounds.insetBy(dx: bounds.width * 0.05, dy: bounds.height * 0.05) : bounds
        Self.tileTone.setFill()
        let radius = 14 * Self.scale * tile.width / bounds.width
        NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius).fill()
        Self.mark(kind)?.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
    }

    // Fires on release inside, like a button, and never takes focus — the
    // sticky keeps it until the action decides where it goes.
    override func mouseDown(with event: NSEvent) {
        pressed = true
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let inside = bounds.contains(convert(next.locationInWindow, from: nil))
            if next.type == .leftMouseUp {
                pressed = false
                if inside { onClick?() }
                break
            }
            pressed = inside
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    func applyTheme() { needsDisplay = true }
}

// MARK: - Text view

// Every selection background fill — active or inactive — is forced to the
// house cream, so the selection never turns system gray when focus moves
// elsewhere (e.g. into a sticky note).
final class SelectionColorLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
        forCharacterRange charRange: NSRange, color: NSColor
    ) {
        // Filled here rather than handed to super, because the rects AppKit
        // provides are whole line fragments and a fragment is [glyphs][leading].
        // With most of a 48pt band being leading, the highlight ran from the
        // words down to the next line — reading as a block of colour with words
        // sitting at the top of it rather than as words being marked.
        //
        // **Only the horizontal extent and the origin come from the rect.** The
        // height is the ink box plus air, computed the same for every line.
        //
        // Taking the height from the rect is what broke this. It read
        // `min(fragment.height, lineHeight + padding * 2)` — a clamp written to
        // defend against a tall fragment — while still lifting the box by
        // `padding`. That holds up only while the rect is taller than the clamp,
        // and on the last line of the document it is not: AppKit hands 19pt
        // there against 48 elsewhere, so the clamp did nothing, the lift stayed,
        // and the highlight drew 19pt starting 8pt *above* the words. It sat in
        // the air over the line and clipped the tops of the letters — visibly
        // broken, and only ever on the last line, which is why it looked
        // intermittent.
        Style.selectionTone.setFill()
        let height = Style.inkHeight + Style.selectionPadding * 2

        // Centred in the ruled band, not on the ink — the two are not the same
        // place, and the gap between them is visible.
        //
        // The ruling centres the font's *line height* in the pitch (see
        // `drawRuling`), and a line height is not symmetric around the ink it
        // carries: Courier 16 is 19pt tall around a 16pt ink box, and puts 2.94
        // of the difference above the glyphs and 0.06 below. So a band centred
        // on the ink lands 1.44 low in the ruling — 12.44pt to the rule above
        // against 9.56 to the rule below, which reads as the selection crowding
        // the line beneath it. Centring on the box the ruling itself centres
        // gives 11 and 11.
        //
        // This is why the placement asks `Style.ruledCentre` rather than working
        // from the ink: the *height* of the band is the ink plus air, but
        // *where* it sits is the ruling's business, and the ruling has never
        // been about the ink. It also has to be measured against the rules as
        // drawn, not as computed — see `Style.ruleY`.

        // One rect is not one line. AppKit coalesces the full-width interior of
        // a multi-line selection into a single tall block — select three lines
        // from the very start and the first two arrive as one rect three bands
        // tall — so drawing one fixed-height band per rect highlighted the
        // block's first line and silently missed the rest.
        //
        // The lines it covers are asked of the layout manager rather than
        // stepped over, because there is no single step to take: a line inside a
        // paragraph is 48 apart from the next and a line that ends one is 96.
        // Horizontal extent still comes from the rect, so AppKit keeps deciding
        // how far a continuing selection runs past the last word on a line.
        var lineTops: [CGFloat] = []
        if let origin = firstTextView?.textContainerOrigin {
            let glyphs = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, _, _ in
                lineTops.append(fragment.minY + origin.y)
            }
        }

        for i in 0..<rectCount {
            let rect = rectArray[i]
            let covered = lineTops.filter { $0 >= rect.minY - 1 && $0 < rect.maxY - 1 }
            // No layout to consult (or a rect that lines up with none of it):
            // fall back to treating the rect as the one line it usually is.
            for lineTop in covered.isEmpty ? [rect.minY] : covered {
                NSRect(x: rect.minX, y: Style.ruledCentre(forLineTop: lineTop) - height / 2,
                       width: rect.width, height: height).fill()
            }
        }
    }
}

// The text view's tracking area is purely geometric, so it keeps forcing the
// I-beam even when SwiftUI controls (icons, notes panel) are drawn on top of
// it. Those controls flip this flag while hovered; the text view yields.
enum ArrowZones {
    static var hoverCount = 0 {
        didSet { if hoverCount < 0 { hoverCount = 0 } }
    }
    static var active: Bool { hoverCount > 0 }
}

final class PlainTextView: NSTextView {
    // MARK: Sticky annotations
    //
    // A sticky put away is a crumpled ball in its margin, beside the line it is
    // anchored to; clicked, it lifts and opens out flat into its card, there in
    // the margin; clicked away from, it crushes back into the ball. One is out
    // at a time. The fold itself is Crumple.swift's — this is where the page
    // decides what is out, where the ball and the card sit, and when the real
    // card is on screen.

    weak var notesStore: NotesStore?
    private var balls: [UUID: StickyBallView] = [:]
    /// The card that is out, or on its way back in. Made fresh for every
    /// opening, so its flourish draws itself on every time.
    private var card: StickyView?
    /// The sticky that is out — opening, or open. Nil once it is being put away.
    private var openID: UUID?
    private lazy var crumple: CrumpleDirector = {
        let director = CrumpleDirector()
        director.onCardLanded = { [weak self] id in self?.cardLanded(id) }
        director.onCardLeft = { [weak self] id in self?.cardLeft(id) }
        director.onFlight = { [weak self] in self?.showFlight() }
        return director
    }()
    private var washedRanges: [[Int]] = []
    private let deleteButton = StampButton(kind: .delete)
    private let doneButton = StampButton(kind: .done)
    private let selectionIcon = SelectionIconView()
    private var annotationsConfigured = false

    static let cardWidth: CGFloat = 172

    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func configureAnnotations() {
        guard !annotationsConfigured else { return }
        annotationsConfigured = true
        selectionIcon.isHidden = true
        selectionIcon.onClick = { [weak self] in self?.createStickyFromSelection() }
        addSubview(selectionIcon)
        for button in [deleteButton, doneButton] {
            button.isHidden = true
            addSubview(button)
        }
        // Either way the note gets focus back, with its caret where it was —
        // what a click in the margin does.
        deleteButton.onClick = { [weak self] in
            guard let self, let id = self.openID else { return }
            self.putAwaySticky(id, deleted: true)
            self.window?.makeFirstResponder(self)
        }
        doneButton.onClick = { [weak self] in
            guard let self else { return } // losing focus puts it away
            self.window?.makeFirstResponder(self)
        }
        // The sheet is drawn over everything else on the page, cards included.
        addSubview(crumple.view)
        // Compiled now, a beat after the page is up, not on the first click.
        DispatchQueue.main.async { [weak self] in
            self?.crumple.prepare(paper: Self.blankCard(size: NSSize(width: 40, height: 40)))
        }
    }

    /// The back of a card, and the paper a ball is crumpled from: a stamp with
    /// nothing on it.
    static func blankCard(size: NSSize) -> NSImage {
        let view = StickyView(id: UUID(), text: "")
        view.frame = NSRect(origin: .zero, size: size)
        return view.picture()
    }

    /// The open card gets its buttons hung under it while it is written in.
    private func placeStampButtons() {
        guard let card, card.stickyID == openID, !card.isHidden, card.isEditing else {
            deleteButton.isHidden = true
            doneButton.isHidden = true
            return
        }
        let side = StampButton.side
        let left = card.frame.midX - side - StampButton.gap / 2
        let top = card.frame.maxY + StampButton.drop
        deleteButton.frame = NSRect(x: left, y: top, width: side, height: side)
        doneButton.frame = NSRect(x: left + side + StampButton.gap, y: top, width: side, height: side)
        deleteButton.isHidden = false
        doneButton.isHidden = false
    }

    // A selection in the left half of the window sends its sticky to the left
    // margin; right half to the right margin.
    private func selectionTargetsLeft(_ rect: NSRect) -> Bool {
        rect.midX + textContainerInset.width < bounds.width / 2
    }

    // The flat square floats just above the selection, anchored to the edge
    // matching the margin the sticky will land in.
    func updateSelectionIcon() {
        let sel = selectedRange()
        guard isEditable, sel.length > 0,
              let lm = layoutManager, let tc = textContainer else {
            selectionIcon.isHidden = true
            return
        }
        let glyphRange = lm.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
        let rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        let x = selectionTargetsLeft(rect)
            ? rect.minX + textContainerInset.width
            : rect.maxX + textContainerInset.width - 20
        let y = max(rect.minY + textContainerInset.height - 26, 2)
        selectionIcon.frame = NSRect(x: x, y: y, width: 20, height: 20)
        selectionIcon.isHidden = false
    }

    // A sticky just made has nothing to read yet: it comes out of its ball
    // straight to writing.
    private func createStickyFromSelection() {
        guard let store = notesStore else { return }
        let sel = selectedRange()
        guard sel.length > 0, let lm = layoutManager, let tc = textContainer else { return }
        let glyphRange = lm.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
        let rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        let id = store.addSticky(range: sel, left: selectionTargetsLeft(rect))
        selectionIcon.isHidden = true
        syncStickies()
        openSticky(id)
    }

    // MARK: Taking a sticky out, and putting it away

    func openSticky(_ id: UUID) {
        guard let sticky = notesStore?.stickies.first(where: { $0.id == id }) else { return }
        if openID == id {
            card?.focus()
            return
        }
        // One out at a time: whatever else is out goes straight back.
        if let current = openID { putAwaySticky(current, animated: false) }
        dropCard()

        let view = StickyView(id: id, text: sticky.text)
        view.onTextChange = { [weak self] text in self?.notesStore?.updateStickyText(id, text) }
        view.onDelete = { [weak self] in
            guard let self else { return }
            self.putAwaySticky(id, deleted: true)
            self.window?.makeFirstResponder(self)
        }
        view.onLayoutNeeded = { [weak self] in self?.syncStickies() }
        view.onFocusChange = { [weak self] in self?.cardFocusChanged(id) }
        view.isHidden = true // until the sheet has opened out flat in its place
        addSubview(view, positioned: .below, relativeTo: crumple.view)
        card = view
        openID = id
        syncStickies() // places the card

        guard !reducesMotion, let mark = ballCentre(id) else {
            cardLanded(id)
            return
        }
        // Off with the words already on it, and without its flourish, which
        // draws itself on only once the card is flat.
        crumple.open(id, face: view.picture(), back: Self.blankCard(size: view.frame.size),
                     frame: view.frame, mark: mark, stage: stageFrame(card: view.frame, mark: mark))
    }

    /// Puts `id`'s card away into its ball — or, if it was deleted or never
    /// written in, crumples it to nothing where it is and deletes the sticky.
    func putAwaySticky(_ id: UUID, deleted: Bool = false, animated: Bool = true) {
        guard openID == id, let card, card.stickyID == id else { return }
        openID = nil
        let text = card.noteText
        let gone = deleted || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if gone {
            notesStore?.removeSticky(id)
        } else {
            notesStore?.updateStickyText(id, text)
        }
        syncStickies()
        let mark = gone ? nil : ballCentre(id)
        if !animated || reducesMotion {
            if !animated { crumple.reset() }
            dropCard()
            syncStickies()
            return
        }
        if card.isHidden {
            // Still opening: the sheet turns back, and there is no card to
            // hand over from.
            crumple.close(id, face: card.picture(), back: Self.blankCard(size: card.frame.size),
                          frame: card.frame, mark: mark, stage: stageFrame(card: card.frame, mark: mark))
            dropCard()
            return
        }
        card.finishFlourish()
        crumple.close(id, face: card.picture(), back: Self.blankCard(size: card.frame.size),
                      frame: card.frame, mark: mark, stage: stageFrame(card: card.frame, mark: mark))
        placeStampButtons()
    }

    /// The sheet has opened out flat: the real card takes its place, draws its
    /// flourish on, and takes the caret.
    private func cardLanded(_ id: UUID) {
        guard openID == id, let card, card.stickyID == id else { return }
        card.isHidden = false
        card.playFlourish()
        card.focus()
        syncStickies()
    }

    /// The sheet has taken over from a card going back into its ball.
    private func cardLeft(_ id: UUID) {
        guard let card, card.stickyID == id, openID != id else { return }
        dropCard()
    }

    private func dropCard() {
        card?.removeFromSuperview()
        card = nil
        placeStampButtons()
    }

    /// Clicked away from, the card goes back into its ball.
    private func cardFocusChanged(_ id: UUID) {
        if let card, card.stickyID == id, openID == id, !card.isHidden, !card.isEditing {
            putAwaySticky(id)
        }
        syncStickies()
    }

    /// The ball of the sticky that is out is the one in the air, not the one
    /// in the margin.
    private func showFlight() {
        for (id, ball) in balls {
            ball.isHidden = id == crumple.flyingID || (id == openID && reducesMotion)
        }
    }

    private func ballCentre(_ id: UUID) -> CGPoint? {
        guard let ball = balls[id] else { return nil }
        return CGPoint(x: ball.frame.midX, y: ball.frame.midY)
    }

    /// Room on the page for the sheet's whole flight — the ball, the card, the
    /// arc between and the tumble on the way.
    private func stageFrame(card: NSRect, mark: CGPoint?) -> NSRect {
        var area = card
        if let mark { area = area.union(NSRect(x: mark.x, y: mark.y, width: 0, height: 0)) }
        return area.insetBy(dx: -110, dy: -110).integral
    }

    // MARK: Placing balls and the card

    /// Where line `top`'s ball sits for a sticky in this margin: just past the
    /// end of the ruling, where the rule runs out into the margin — close
    /// enough to read as belonging to the line.
    private func ballX(left: Bool) -> CGFloat {
        let reach = Style.ruleOverhang + 18
        return left ? Style.sideMargin - reach : bounds.width - Style.sideMargin + reach
    }

    // Rebuild/reposition the balls, and the card that is out, from their
    // anchors. Called on every layout pass, edit, and model change, so they
    // track reflow and resize.
    func syncStickies() {
        guard annotationsConfigured, let store = notesStore else { return }
        let list = store.stickies
        // The wash is painted with the page, so it has to be asked for again
        // whenever a sticky is made, deleted or has its words moved under it.
        let washed = list.map { [$0.start, $0.length] }
        if washed != washedRanges {
            washedRanges = washed
            needsDisplay = true
        }
        for (id, ball) in balls where !list.contains(where: { $0.id == id }) {
            ball.removeFromSuperview()
            balls[id] = nil
        }
        // A different note loaded, or the sticky gone from under it: whatever
        // was out goes, without a fold.
        if let id = openID, !list.contains(where: { $0.id == id }) {
            openID = nil
            crumple.reset()
            dropCard()
        }
        guard let lm = layoutManager else { return }
        let textLength = (string as NSString).length
        let size = StickyBallView.hitSize
        var perLine: [CGFloat: Int] = [:]
        for sticky in list.sorted(by: { $0.start < $1.start }) {
            let ball = balls[sticky.id] ?? {
                let b = StickyBallView(id: sticky.id)
                b.onClick = { [weak self] in self?.openSticky(sticky.id) }
                b.onDelete = { [weak self] in self?.notesStore?.removeSticky(sticky.id) }
                addSubview(b, positioned: .below, relativeTo: crumple.view)
                balls[sticky.id] = b
                return b
            }()
            var top = textContainerOrigin.y
            if lm.numberOfGlyphs > 0 {
                let glyph = lm.glyphIndexForCharacter(at: max(0, min(sticky.start, textLength - 1)))
                top += lm.lineFragmentRect(forGlyphAt: min(glyph, lm.numberOfGlyphs - 1),
                                           effectiveRange: nil).minY
            }
            let left = sticky.left == true
            // Two stickies on one line stack like stamps on an envelope, each a
            // little lower and further out than the last, rather than covering
            // one another.
            let stacked = CGFloat(perLine[top, default: 0])
            perLine[top, default: 0] += 1
            let centre = CGPoint(x: ballX(left: left) + (left ? -2 : 2) * stacked,
                                 y: Style.ruledCentre(forLineTop: top) + 6 * stacked)
            ball.frame = NSRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
                                width: size.width, height: size.height)

            // The card that is out opens where its ball was: its top level with
            // the ball's, across the margin the ball sits in.
            if let card, card.stickyID == sticky.id, openID == sticky.id {
                if !card.isEditing { card.setText(sticky.text) }
                let width = Self.cardWidth
                card.frame.size.width = width // set width before measuring wrap height
                let x = left ? Style.sideMargin - width - 14 : bounds.width - Style.sideMargin + 14
                let y = max(8, centre.y - CGFloat(CrumpleSheet.ballDiameter) / 2)
                card.frame = NSRect(x: x, y: y, width: width, height: card.desiredHeight)
            }
        }
        showFlight()
        placeStampButtons()
    }

    override func layout() {
        super.layout()
        syncStickies()
        updateSelectionIcon()
    }

    // MARK: Theme

    // Recolour everything AppKit owns, in place. The ink is baked into the text
    // storage's attributes, so it has to be rewritten — but as an attribute-only
    // edit that leaves the selection, scroll position and undo stack alone.
    func applyTheme() {
        if let storage = textStorage, storage.length > 0 {
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: Style.ink, range: full)
            storage.endEditing()
            // Let the store pick the recoloured text up and save it — but not
            // on this turn of the loop. `applyTheme` is called from
            // `updateNSView`, so we are inside a SwiftUI update pass, and
            // `didChangeText` runs the delegate straight through to
            // `store.textChanged` → `updateWordCount`, which writes a
            // `@Published`. Publishing from inside an update is not allowed;
            // deferring by one hop puts the write after the pass instead.
            DispatchQueue.main.async { [weak self] in self?.didChangeText() }
        }
        var attrs = typingAttributes
        attrs[.foregroundColor] = Style.ink
        typingAttributes = attrs
        // The colour here is never drawn — `SelectionColorLayoutManager` fills
        // with `Style.selectionTone` and ignores what it is handed. Setting it
        // is still what tells AppKit there *is* a selection background to fill,
        // and so what gets the override called at all. Don't remove it as dead.
        selectedTextAttributes = [.backgroundColor: Style.selection]
        smoothCaret.applyTheme()
        selectionIcon.applyTheme()
        card?.applyTheme()
        balls.values.forEach { $0.applyTheme() }
        deleteButton.applyTheme()
        doneButton.applyTheme()
        // the cream dots covering the traffic lights live in the title bar, well
        // outside this view's tree
        if let titlebar = window?.standardWindowButton(.closeButton)?.superview {
            titlebar.subviews.compactMap { $0 as? TrafficDotsOverlay }
                .forEach { $0.needsDisplay = true }
        }
        needsDisplay = true // the page, its paper and its ruling are all drawn
    }

    // The family the reader picked in settings, pushed into everything AppKit
    // owns — which for the note is the text storage itself, reloaded by
    // `docVersion`, and for the stickies is each stamp's own editor. Without
    // this fan-out a sticky already on screen kept its old family until the
    // note was closed and reopened.
    func applyFont() {
        card?.applyFont()
    }

    // MARK: Smooth caret (MS Word-style glide)

    private lazy var smoothCaret = SmoothCaret(view: self)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        smoothCaret.attachIfNeeded()
    }

    // suppress legacy caret drawing too
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {}

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        smoothCaret.update(animated: true)
        // The selection is painted a little outside the rects AppKit hands to
        // the layout manager — it reaches `selectionPadding` above each line
        // fragment, so the highlight has air on both sides of the type rather
        // than only below it.
        //
        // AppKit works out what to repaint from those same fragment rects, so
        // the strip above them is never invalidated, and clearing or shrinking
        // a selection left its top edge behind as a torn line of stale colour.
        // Worst on the last line, where nothing below it ever redraws over the
        // remains.
        //
        // Repainting the visible rect costs what a scroll tick already costs:
        // one cached image draw and a few dozen hairlines.
        setNeedsDisplay(visibleRect)
    }

    override func didChangeText() {
        super.didChangeText()
        smoothCaret.update(animated: true)
        syncStickies()
        updateSelectionIcon()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self) // margin rects follow the width
        DispatchQueue.main.async { [weak self] in self?.smoothCaret.update(animated: false) }
    }

    var retainedStorage: NSTextStorage? // manual TextKit 1 setup: keep the storage alive

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.smoothCaret.update(animated: false) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.smoothCaret.update(animated: false) }
        return ok
    }

    // Paste is always plain text: the string is inserted with the editor's
    // own typing attributes, so outside styling never comes along. Falls back
    // to extracting the raw string from rich-only clipboards.
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        var plain = pb.string(forType: .string)
        if plain == nil,
           let objects = pb.readObjects(forClasses: [NSAttributedString.self]) as? [NSAttributedString],
           let first = objects.first {
            plain = first.string
        }
        guard let str = plain, !str.isEmpty else {
            NSSound.beep()
            return
        }
        let range = selectedRange()
        if shouldChangeText(in: range, replacementString: str) {
            insertText(str, replacementRange: range)
        }
    }

    override func keyDown(with event: NSEvent) {
        // Shift+Return: line break within the same paragraph (no paragraph gap)
        if event.keyCode == 36, event.modifierFlags.contains(.shift) {
            insertLineBreak(nil)
            return
        }
        super.keyDown(with: event)
    }

    // Clicking empty margin space while a sticky is being edited just ends
    // the sticky editing and puts the caret back where it was in the note,
    // instead of jumping it to the click position.
    // Margin clicks never reposition the caret: they only end whatever else
    // was being edited (a sticky) and hand focus back to the note, with the
    // caret exactly where it last was.
    // the dead space either side of the text column
    func isInMargin(_ windowPoint: NSPoint) -> Bool {
        let point = convert(windowPoint, from: nil)
        return point.x < textContainerInset.width
            || point.x > bounds.width - textContainerInset.width
    }

    override func mouseDown(with event: NSEvent) {
        let inMargin = isInMargin(event.locationInWindow)
        if inMargin {
            if window?.firstResponder !== self {
                window?.makeFirstResponder(self) // selectedRange is preserved
            }
            return
        }
        super.mouseDown(with: event)
    }

    // Typing "- " at the start of a line turns it into a bullet.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let s = string as? String, s == " ", let storage = textStorage {
            let sel = selectedRange()
            let ns = storage.string as NSString
            if sel.length == 0, sel.location > 0, sel.location <= ns.length {
                let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
                if sel.location - lineRange.location == 1,
                   ns.character(at: lineRange.location) == unichar(0x2D) { // "-"
                    let dashRange = NSRange(location: lineRange.location, length: 1)
                    if shouldChangeText(in: dashRange, replacementString: Style.bulletPrefix) {
                        var attrs = typingAttributes
                        attrs[.paragraphStyle] = Style.bulletParagraph
                        storage.replaceCharacters(
                            in: dashRange,
                            with: NSAttributedString(string: Style.bulletPrefix, attributes: attrs))
                        let paraRange = (storage.string as NSString)
                            .lineRange(for: NSRange(location: lineRange.location, length: 0))
                        storage.addAttribute(.paragraphStyle, value: Style.bulletParagraph, range: paraRange)
                        didChangeText()
                        typingAttributes = attrs
                        setSelectedRange(
                            NSRange(location: lineRange.location + Style.bulletPrefix.utf16.count, length: 0))
                        return
                    }
                }
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    // Return continues a bullet list; Return on an empty bullet exits it.
    override func insertNewline(_ sender: Any?) {
        if let storage = textStorage {
            let ns = storage.string as NSString
            let sel = selectedRange()
            if sel.length == 0, sel.location <= ns.length {
                let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
                let line = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
                // "---" + Return used to become a horizontal rule. Removed: on a
                // ruled page the rule had nothing left to do — a page that is
                // already lined cannot use one more line to mean "a break", and
                // the two read as the same mark at a glance.
                //
                // Typing "---" now simply leaves "---" on the page.
                if line.trimmingCharacters(in: .whitespaces) == "•" {
                    // empty bullet → remove it and drop back to normal text
                    let deleteRange = NSRange(location: lineRange.location, length: (line as NSString).length)
                    if shouldChangeText(in: deleteRange, replacementString: "") {
                        storage.deleteCharacters(in: deleteRange)
                        didChangeText()
                    }
                    var attrs = typingAttributes
                    attrs[.paragraphStyle] = Style.paragraph
                    typingAttributes = attrs
                    setSelectedRange(NSRange(location: lineRange.location, length: 0))
                    return
                }
                if line.hasPrefix(Style.bulletPrefix) {
                    super.insertNewline(sender)
                    super.insertText(Style.bulletPrefix, replacementRange: selectedRange())
                    // Say what the paragraph is rather than hoping it inherited
                    // it. This used to rely on typingAttributes carrying
                    // bulletParagraph forward from the line above, and that
                    // chain is broken by anything that reloads the document —
                    // switching notes, ⌘K revealing a hit, a theme change that
                    // bumps docVersion — all of which reset typingAttributes to
                    // Style.base, whose paragraph style is *prose*.
                    //
                    // A bullet wearing the prose style still looks like a
                    // bullet, but prose carries a whole pitch of paragraphSpacing
                    // after it, so the list silently grew a blank rule between
                    // items from that point on. Nothing was inserted; the gap
                    // was spacing, which is why it could not be deleted.
                    //
                    // The line just left is restyled too: if the chain was
                    // already broken, it is wearing prose as well.
                    let text = storage.string as NSString
                    let caret = min(selectedRange().location, text.length)
                    let current = text.lineRange(for: NSRange(location: caret, length: 0))
                    storage.addAttribute(
                        .paragraphStyle, value: Style.bulletParagraph, range: current)
                    if current.location > 0 {
                        let previous = text.lineRange(
                            for: NSRange(location: current.location - 1, length: 0))
                        storage.addAttribute(
                            .paragraphStyle, value: Style.bulletParagraph, range: previous)
                    }
                    var attrs = typingAttributes
                    attrs[.paragraphStyle] = Style.bulletParagraph
                    typingAttributes = attrs
                    return
                }
            }
        }
        super.insertNewline(sender)
    }

    // Draw horizontal rules: any paragraph holding just the hr marker gets a
    // 1pt line across the full text column, at whatever the current width is.
    // The ruled page.
    //
    // Drawn here, in the text view, rather than behind it with the paper —
    // because ruling is the thing the eye tracks, and it has to travel with the
    // words when the page scrolls. The paper grain doesn't: nobody reads grain
    // as a landmark, so it stays with the window and only the ruling moves.
    //
    // Fixed pitch means it does not consult the text at all beyond finding
    // where the first line sits. It rules the empty part of the page exactly as
    // densely as the written part, which is the whole difference between paper
    // and a text decoration.
    private func drawRuling(in rect: NSRect) {
        guard let tc = textContainer,
              let ctx = NSGraphicsContext.current else { return }
        let pitch = Style.linePitch
        guard pitch > 1 else { return }

        let origin = textContainerOrigin

        // The grid is anchored to the top of the text container, and to nothing
        // else. It must not be measured off a line fragment, which is what it
        // used to do, for two reasons that both showed up as broken ruling:
        //
        // A fragment's height is not the pitch. AppKit adds paragraphSpacing to
        // the *last* line of a paragraph, so a one-line paragraph — a title,
        // most obviously — reports a box a whole extra band tall, and the grid
        // started 48pt low.
        //
        // And a fragment moves. Editing changes its height, but typing only
        // invalidates the lines it touched, so the rest of the page keeps rules
        // drawn against the previous anchor. That is the double ruling: two
        // grids at once, most visible out in the overhang past the text column,
        // which a text edit never invalidates at all.
        //
        // Derived from the container, the anchor cannot move, so every partial
        // repaint agrees with every other one.
        //
        // Centring: AppKit puts leading *below* the glyphs, so a band is
        // [glyphs][leading] and the glyphs sit at its top. The rules want half
        // a leading of air on each side, which is the ruling moving up rather
        // than the text moving down — no baseline changes, so selection, the
        // caret and sticky anchors all stay where the layout manager put them.
        let anchor = origin.y - Style.lineSpacing / 2
        let left = origin.x + tc.lineFragmentPadding - Style.ruleOverhang
        let right = origin.x + tc.size.width - tc.lineFragmentPadding + Style.ruleOverhang
        guard right > left else { return }

        // Start at the first rule at or above the dirty rect rather than at the
        // top of the document — on a long note that is the difference between
        // drawing a dozen lines and drawing thousands on every scroll tick.
        let steps = max(0, ((rect.minY - anchor) / pitch).rounded(.down))
        var y = anchor + steps * pitch

        let path = NSBezierPath()
        path.lineWidth = 1
        while y <= rect.maxY + 1 {
            if y >= rect.minY - 1 {
                let py = Style.ruleY(y) // land on the pixel, not across two
                path.move(to: NSPoint(x: left, y: py))
                path.line(to: NSPoint(x: right, y: py))
            }
            y += pitch
        }

        ctx.saveGraphicsState()
        ctx.cgContext.setBlendMode(.multiply)
        Style.ruleTone.setStroke()
        path.stroke()
        ctx.restoreGraphicsState()
    }

    // The page is painted here — colour, then paper, then ruling — rather than
    // behind the text view in SwiftUI.
    //
    // It has to be. A blend can only see what is already in its own graphics
    // context, and this view composites into a transparent layer of its own, so
    // a multiply drawn here against a background living *behind* the view finds
    // nothing to darken and paints its source colour flat instead. That failed
    // in the most misleading way available: the ruling came out as pale lines
    // over the paper rather than faint creases in it, which reads as a colour
    // mistake and isn't one.
    //
    // The paper is pinned to the viewport rather than to the document. Grain is
    // not something the eye tracks, so a sheet that stays put while the words
    // move over it looks like a page being written on; grain that scrolls looks
    // like a roll of paper, and would have to stretch a photograph over the
    // whole height of a long note. The ruling does the opposite and travels
    // with the text, because ruling is exactly what the eye does track.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        Style.sheet.setFill()
        rect.fill()
        Surface.page.draw(in: enclosingScrollView?.documentVisibleRect ?? bounds)
        drawRuling(in: rect)
        drawStickyWash(in: rect)
    }

    // MARK: The sticky wash

    // Words with a sticky attached carry a faint wash of the sticky's colour,
    // like a highlighter run over them — the stamp in the margin says *that*
    // there is a note, the wash says *which words* it is about.
    //
    // Painted here with the page, beneath the text, and never as a background
    // attribute in the storage: an attribute would be written into the RTF, and
    // `normalizeFonts` strips anything like it on the way in anyway. Each band is
    // sized and placed exactly as the selection's is — the ink box plus air,
    // centred in the ruled band — so a wash and a selection over the same words
    // are the same shape, and one drawn over the other reads as one mark.
    //
    // A tint, not a fill: at about a quarter the sticky colour is unmistakably
    // the sticky's, and the ink, the grain and the ruling all read through it.
    static let stickyWashAlpha: CGFloat = 0.26

    private func drawStickyWash(in rect: NSRect) {
        guard let store = notesStore, !store.stickies.isEmpty else { return }
        let bands = store.stickies.flatMap(washBands(for:)).filter { $0.intersects(rect) }
        guard !bands.isEmpty else { return }
        stickyNSColor.withAlphaComponent(Self.stickyWashAlpha).setFill()
        for band in bands {
            NSBezierPath(roundedRect: band, xRadius: 3, yRadius: 3).fill()
        }
    }

    /// One band per line the sticky's words cover. The horizontal extent is
    /// the words' own on that line; the height and placement are the
    /// selection's. A sticky whose words have all been deleted has nothing
    /// left to wash.
    private func washBands(for sticky: Sticky) -> [NSRect] {
        guard let lm = layoutManager, let tc = textContainer else { return [] }
        let text = string as NSString
        let start = min(max(sticky.start, 0), text.length)
        let end = min(start + max(sticky.length, 0), text.length)
        guard end > start else { return [] }
        let glyphs = lm.glyphRange(
            forCharacterRange: NSRange(location: start, length: end - start),
            actualCharacterRange: nil)
        let origin = textContainerOrigin
        let height = Style.inkHeight + Style.selectionPadding * 2
        var bands: [NSRect] = []
        lm.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, lineGlyphs, _ in
            var covered = NSIntersectionRange(lineGlyphs, glyphs)
            // Trailing spaces and the line's newline carry no ink to mark.
            while covered.length > 0 {
                let ch = lm.characterIndexForGlyph(at: NSMaxRange(covered) - 1)
                guard ch < text.length,
                      let scalar = Unicode.Scalar(text.character(at: ch)),
                      CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
                covered.length -= 1
            }
            guard covered.length > 0 else { return }
            let ink = lm.boundingRect(forGlyphRange: covered, in: tc)
            let top = fragment.minY + origin.y
            bands.append(NSRect(
                x: ink.minX + origin.x - 2,
                y: Style.ruledCentre(forLineTop: top) - height / 2,
                width: ink.width + 4, height: height))
        }
        return bands
    }

    override func mouseMoved(with event: NSEvent) {
        if ArrowZones.active || isInMargin(event.locationInWindow) {
            NSCursor.arrow.set()
            return
        }
        super.mouseMoved(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        if ArrowZones.active || isInMargin(event.locationInWindow) {
            NSCursor.arrow.set()
            return
        }
        super.cursorUpdate(with: event)
    }

    // The margins are dead space for the caret, so they get the arrow rather
    // than the I-beam. Explicit cursor rects are what AppKit actually honours
    // here — NSTextView otherwise claims its whole bounds for the I-beam.
    override func resetCursorRects() {
        let inset = textContainerInset.width
        let column = max(bounds.width - inset * 2, 0)
        addCursorRect(NSRect(x: 0, y: 0, width: inset, height: bounds.height), cursor: .arrow)
        addCursorRect(
            NSRect(x: bounds.width - inset, y: 0, width: inset, height: bounds.height),
            cursor: .arrow)
        addCursorRect(
            NSRect(x: inset, y: 0, width: column, height: bounds.height), cursor: .iBeam)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "i" {
            toggleItalics()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func toggleItalics() {
        let fm = NSFontManager.shared
        let range = selectedRange()

        if range.length == 0 {
            var attrs = typingAttributes
            let font = (attrs[.font] as? NSFont) ?? Style.baseFont
            let isItalic = fm.traits(of: font).contains(.italicFontMask)
            attrs[.font] = isItalic
                ? fm.convert(font, toNotHaveTrait: .italicFontMask)
                : fm.convert(font, toHaveTrait: .italicFontMask)
            typingAttributes = attrs
            return
        }

        guard let storage = textStorage, shouldChangeText(in: range, replacementString: nil) else { return }
        var allItalic = true
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            let font = (value as? NSFont) ?? Style.baseFont
            if !fm.traits(of: font).contains(.italicFontMask) { allItalic = false }
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
            let font = (value as? NSFont) ?? Style.baseFont
            let newFont = allItalic
                ? fm.convert(font, toNotHaveTrait: .italicFontMask)
                : fm.convert(font, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: newFont, range: subRange)
        }
        storage.endEditing()
        didChangeText()
    }
}

// MARK: - House text field

// SwiftUI's TextField gives no way to set its selection colour: selections follow
// the view's tint, so tinting the caret to the house ink also painted selections
// in near-black ink and made the selected text almost unreadable. Configuring the
// window's shared field editor up front doesn't hold either — AppKit re-runs
// `setUpFieldEditorAttributes` each time a field takes focus and overwrites it
// (measured). That method is the hook it *does* honour, so the app brings its own
// cell and gets the same pale selection the note editor uses.
final class HouseTextFieldCell: NSTextFieldCell {
    // Set per field: the selection has to be a step away from whatever the field
    // is sitting on. See HouseField.Bed.
    var selectionColor: NSColor?

    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        if let tv = editor as? NSTextView {
            tv.selectedTextAttributes = [.backgroundColor: selectionColor ?? Style.selection]
            tv.insertionPointColor = Style.ink
            // typewriter input here too, so a name or folder title isn't
            // silently given curly quotes
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
        }
        return editor
    }
}

final class HouseNSTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { HouseTextFieldCell.self }
        set { _ = newValue }
    }
}

struct HouseField: NSViewRepresentable {
    // Which tone the field is sitting on. The editor selects in panel-on-sheet,
    // but that reads as nothing inside the ⌘K palette, whose own background is
    // already the panel colour — so a field on panel selects in sheet instead.
    // Either way the selection is one step away from its bed, which is the
    // relationship the editor actually has.
    enum Bed { case sheet, panel }

    @Binding var text: String
    var size: CGFloat = 13
    var alpha: Double = 1 // which step of the ink ladder the text sits at
    var bed: Bed = .sheet
    var centered = false
    var placeholder = ""
    // Which step of the ink ladder the placeholder sits at. `inkFaint` for
    // every field but ⌘K's, whose prompt is the muted step.
    var placeholderAlpha: Double = 0.4
    var focused = false
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}
    // Return true to swallow the key. Handling arrows here rather than with
    // SwiftUI's onKeyPress means ⌘K's arrow navigation works on macOS 13 too,
    // where onKeyPress isn't available.
    var onArrow: ((_ down: Bool) -> Bool)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> HouseNSTextField {
        let field = HouseNSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none // the pill behind it is the affordance
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: HouseNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        let font = Style.font(size) // the same resolution the rest of the app uses
        field.font = font
        field.textColor = Style.ink.withAlphaComponent(alpha)
        field.alignment = centered ? .center : .left
        (field.cell as? HouseTextFieldCell)?.selectionColor =
            bed == .sheet ? Style.selection : Style.sheet
        field.placeholderAttributedString = placeholder.isEmpty ? nil
            : NSAttributedString(string: placeholder, attributes: [
                .font: font,
                .foregroundColor: Style.ink.withAlphaComponent(placeholderAlpha),
            ])
        // Only on the false -> true transition, so an update pass can't steal
        // focus back after someone has clicked away.
        if focused != context.coordinator.wantsFocus {
            context.coordinator.wantsFocus = focused
            if focused {
                DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HouseField
        var wantsFocus = false
        init(_ parent: HouseField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl, textView: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.moveDown(_:)):
                return parent.onArrow?(true) ?? false
            case #selector(NSResponder.moveUp(_:)):
                return parent.onArrow?(false) ?? false
            default:
                return false
            }
        }
    }
}

struct RichTextEditor: NSViewRepresentable {
    @ObservedObject var store: NotesStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        // The paper is pinned to the viewport, so scrolling has to repaint the
        // whole visible background rather than shifting what is already there.
        // `copiesOnScroll` was the switch for this and has done nothing since
        // macOS 11 — AppKit now always minimises the invalidated area, and the
        // documented way to opt out is to invalidate by hand. Without this the
        // grain smears down the page as you scroll.
        //
        // Costs one cached image draw and a few dozen hairlines per scroll
        // tick, against a text view that is already relaying out.
        scroll.contentView.postsBoundsChangedNotifications = true

        // manual TextKit 1 stack so the custom layout manager controls
        // selection background drawing
        let storage = NSTextStorage()
        let lm = SelectionColorLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(lm)
        lm.addTextContainer(container)
        let tv = PlainTextView(frame: .zero, textContainer: container)
        tv.retainedStorage = storage
        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.allowsUndo = true
        // typewriter-style input: keep dashes and quotes exactly as typed
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.usesFontPanel = false
        tv.usesRuler = false
        tv.importsGraphics = false
        tv.drawsBackground = false
        tv.selectedTextAttributes = [.backgroundColor: Style.selection]
        tv.textContainerInset = NSSize(width: Style.sideMargin, height: 52)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true

        tv.textStorage?.setAttributedString(store.attr)
        tv.typingAttributes = Style.base
        tv.notesStore = store
        tv.configureAnnotations()
        context.coordinator.loadedVersion = store.docVersion
        scroll.documentView = tv

        // see postsBoundsChangedNotifications above — repaint the viewport-
        // pinned paper on every scroll, since AppKit will not
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView, queue: .main
        ) { [weak tv] _ in
            guard let tv = tv else { return }
            tv.setNeedsDisplay(tv.visibleRect)
        }

        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? PlainTextView else { return }
        if context.coordinator.wasHidden != store.editorBlocked {
            context.coordinator.wasHidden = store.editorBlocked
            tv.isEditable = !store.editorBlocked
            tv.isSelectable = !store.editorBlocked
            if store.editorBlocked {
                tv.window?.makeFirstResponder(nil)
            } else {
                tv.window?.makeFirstResponder(tv)
            }
        }
        if context.coordinator.wasSearch != store.searchShown {
            context.coordinator.wasSearch = store.searchShown
            if !store.searchShown, !store.hiddenShown {
                DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
            }
        }
        if context.coordinator.themeID != store.themeID {
            context.coordinator.themeID = store.themeID
            tv.applyTheme()
        }
        // Same shape as the theme fan-out above, and needed for the same
        // reason: the note's own text is restyled in the store and arrives via
        // docVersion, but a sticky's editor is an AppKit view holding a font.
        if context.coordinator.fontFamily != store.fontFamily {
            context.coordinator.fontFamily = store.fontFamily
            tv.applyFont()
        }
        if context.coordinator.loadedVersion != store.docVersion {
            tv.textStorage?.setAttributedString(store.attr)
            tv.typingAttributes = Style.base
            tv.undoManager?.removeAllActions()
            if let reveal = store.pendingReveal {
                store.pendingReveal = nil
                tv.setSelectedRange(NSRange(location: reveal.location, length: 0))
                tv.scrollRangeToVisible(reveal)
                DispatchQueue.main.async {
                    tv.window?.makeFirstResponder(tv)
                    tv.showFindIndicator(for: reveal)
                }
            } else {
                tv.setSelectedRange(NSRange(location: store.attr.length, length: 0))
                tv.scrollToEndOfDocument(nil)
            }
            context.coordinator.loadedVersion = store.docVersion
        }
        tv.syncStickies()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let store: NotesStore
        var loadedVersion = -1
        var wasHidden = false
        // held so it outlives makeNSView and dies with the editor
        var scrollObserver: NSObjectProtocol?

        deinit {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }
        var wasSearch = false
        var themeID = Style.theme.id
        var fontFamily = Style.fontFamily
        private var normalizing = false

        init(store: NotesStore) { self.store = store }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, !normalizing else { return }
            normalizing = true
            normalizeFonts(tv)
            normalizing = false
            store.textChanged(tv.attributedString())
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? PlainTextView else { return }
            tv.updateSelectionIcon()
        }

        // Keep sticky anchors tracking their text through every edit.
        func textView(
            _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if let replacement = replacementString {
                store.remapStickies(
                    edit: affectedCharRange,
                    replacementLength: (replacement as NSString).length)
            }
            return true
        }

        // Safety net for any content that slips in styled (drops, services…):
        // force Courier 16 + house paragraph style + ink color and strip every
        // decoration attribute, keeping only italic/bold traits.
        private func normalizeFonts(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let fm = NSFontManager.shared
            let full = NSRange(location: 0, length: storage.length)
            let banned: [NSAttributedString.Key] = [
                .underlineStyle, .strikethroughStyle, .backgroundColor,
                .link, .shadow, .strokeWidth, .baselineOffset,
            ]
            var fixes: [() -> Void] = []
            storage.enumerateAttributes(in: full) { attrs, range, _ in
                let font = attrs[.font] as? NSFont ?? Style.baseFont
                if font.familyName != Style.fontFamily || font.pointSize != 16 {
                    var fixed = fm.convert(font, toFamily: Style.fontFamily)
                    fixed = fm.convert(fixed, toSize: 16)
                    fixes.append { storage.addAttribute(.font, value: fixed, range: range) }
                }
                let para = attrs[.paragraphStyle] as? NSParagraphStyle
                // indented paragraphs are bullet items and keep their own style
                let target = (para?.headIndent ?? 0) > 0 ? Style.bulletParagraph : Style.paragraph
                if para == nil || para?.isEqual(target) == false {
                    fixes.append {
                        storage.addAttribute(.paragraphStyle, value: target, range: range)
                    }
                }
                if (attrs[.foregroundColor] as? NSColor) != Style.ink {
                    fixes.append {
                        storage.addAttribute(.foregroundColor, value: Style.ink, range: range)
                    }
                }
                for key in banned where attrs[key] != nil {
                    fixes.append { storage.removeAttribute(key, range: range) }
                }
            }
            guard !fixes.isEmpty else { return }
            storage.beginEditing()
            fixes.forEach { $0() }
            storage.endEditing()
        }
    }
}

// MARK: - Traffic lights

// Covers the close/minimize/zoom buttons with flat #ECDBBE dots;
// the real buttons fade in only while the pointer is over them.
final class TrafficDotsOverlay: NSView {
    var buttons: [NSButton] = []
    private var hovered = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil } // clicks go to the real buttons

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        ))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    func setHovered(_ hovering: Bool) {
        hovered = hovering
        buttons.forEach { $0.alphaValue = hovering ? 1 : 0 }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !hovered, let container = superview else { return }
        Style.selection.setFill()
        let diameter: CGFloat = 12 // matches the default macOS traffic light
        for button in buttons {
            let frame = convert(button.frame, from: container)
            let circle = NSRect(
                x: frame.midX - diameter / 2,
                y: frame.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            NSBezierPath(ovalIn: circle).fill()
        }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async {
            guard let window = probe.window,
                  let close = window.standardWindowButton(.closeButton),
                  let mini = window.standardWindowButton(.miniaturizeButton),
                  let zoom = window.standardWindowButton(.zoomButton),
                  let titlebar = close.superview,
                  !titlebar.subviews.contains(where: { $0 is TrafficDotsOverlay })
            else { return }
            let overlay = TrafficDotsOverlay()
            overlay.buttons = [close, mini, zoom]
            overlay.frame = close.frame.union(mini.frame).union(zoom.frame).insetBy(dx: -6, dy: -4)
            overlay.autoresizingMask = [.maxXMargin, .minYMargin]
            titlebar.addSubview(overlay, positioned: .above, relativeTo: zoom)
            overlay.setHovered(false)
        }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - UI

struct ArrowZoneModifier: ViewModifier {
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != inside else { return }
                inside = hovering
                ArrowZones.hoverCount += hovering ? 1 : -1
                if hovering { NSCursor.arrow.set() }
            }
            .onDisappear {
                // the view can vanish (panel dismissed) while still hovered,
                // in which case onHover(false) never fires
                if inside {
                    inside = false
                    ArrowZones.hoverCount -= 1
                }
            }
    }
}

extension View {
    func arrowCursorZone() -> some View { modifier(ArrowZoneModifier()) }

    // The recessed well a settings control sits in. Deliberately *not* papered:
    // it is a hole in the card rather than another surface raised off it, which
    // is the same call the ⌘K result rows and the folder hover state make.
    //
    // Applied inside a control's own label, so the whole well stays the click
    // target — moving it out to the row would leave only the text clickable.
    func settingsWell() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(sheetColor))
    }
}

// The vault picker, shared by onboarding and by settings — the same panel, the
// same prompt, the same message, which is what it was in both places. Returns
// nil when the sheet is cancelled; the caller decides what a choice means
// (onboarding remembers it until it finishes, settings acts on it at once).
func chooseVaultFolder(startingAt current: URL) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.directoryURL = current
    panel.prompt = "Use as Vault"
    panel.message = "Choose the folder where notes are stored"
    guard panel.runModal() == .OK else { return nil }
    return panel.url
}

struct IconButton: View {
    let systemName: String
    let help: String
    var active = false // keeps the hover background while whatever it toggles is open
    let action: () -> Void
    @State private var hovering = false

    // Both buttons take the same two tones — they are the same kind of control,
    // and drawing them at different weights (which the system does, and which
    // this followed) just read as one of them being broken.
    //
    // The glyph goes *darker* as its bed goes darker, so the raised state gains
    // contrast rather than trading it away: at rest it is a faint mark on bare
    // sheet, and under the pointer a firm one on a papered tile.
    private var tone: Color { hovering || active ? inkStrong : inkFaint }

    // 60 across with a 14 radius in the system, which is 44 and 10 here — the
    // same 16/22 the rest of it scales by.
    private let side: CGFloat = 44
    private let radius: CGFloat = 10

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tone)
                .frame(width: side, height: side)
                .background(
                    Group {
                        // papered, like every other raised surface — clipped to
                        // the button rather than left square behind it
                        if hovering || active {
                            panelColor.papered(.button)
                                .clipShape(RoundedRectangle(cornerRadius: radius))
                        }
                    }
                )
                .contentShape(RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

struct SearchPalette: View {
    @ObservedObject var store: NotesStore
    @State private var query = ""
    @State private var selected = 0
    @State private var focused = false

    private var hits: [SearchHit] { store.search(query) }

    // A command reads like a result and selects like one. The palette's rows are
    // the results followed by whichever commands are showing, in a single
    // selection space — so the arrows walk the whole list and Return fires
    // whatever is highlighted, note or command.
    private struct Command: Identifiable {
        let id: String
        let title: String
        let run: () -> Void
    }

    private var commands: [Command] {
        var out: [Command] = []
        if showOnboardAgain {
            out.append(Command(id: "onboard", title: "onboard again") {
                store.replayOnboarding()
            })
        }
        return out
    }

    // Two cards, not one divided card — as in the frames.
    //
    // It reads better than a rule across a single card because the two halves
    // are different kinds of thing: the field is what you act on, the results
    // are what happens *because* of it. Separating them also means the results
    // card can grow and shrink as you type without the field appearing to
    // resize along with it.
    var body: some View {
        let results = hits
        let cmds = commands
        VStack(spacing: 10) {
            queryCard(results, cmds)
            resultsCard(results, cmds)
        }
        .frame(width: 460)
        .arrowCursorZone()
        .onAppear { focused = true }
        .onExitCommand { store.searchShown = false }
        .onChange(of: query) { _, _ in selected = 0 }
    }

    private func queryCard(_ results: [SearchHit], _ cmds: [Command]) -> some View {
        HouseField(
            text: $query,
            size: 14,
            // Stays `.panel` even though the card is now built on the
            // sheet token. Bed is about the tone the field actually
            // sits on, not the token it started from: paper at 75%
            // takes the card down to roughly panel's own lightness, so
            // selecting in panel would be the invisible same-on-same
            // this setting exists to avoid. `.panel` selects in sheet,
            // which stays a clear step lighter than the card.
            bed: .panel,
            placeholder: "search",
            placeholderAlpha: 0.55, // inkMuted — the prompt is a step firmer here
            focused: focused,
            onSubmit: { activate(results, cmds) },
            onCancel: { store.searchShown = false },
            onArrow: { down in
                if down {
                    selected = min(selected + 1, max(results.count + cmds.count - 1, 0))
                } else {
                    selected = max(selected - 1, 0)
                }
                return true
            })
            .frame(height: 18)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        // Papered on the background rather than over the whole view: an overlay
        // would multiply the rows and their highlights too, printing ink that
        // is meant to sit *on* the card into it instead.
        .background(panelColor.papered(.palette))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func resultsCard(_ results: [SearchHit], _ cmds: [Command]) -> some View {
        VStack(spacing: 0) {
            if results.isEmpty {
                Text("no matches")
                    .font(houseFont(12))
                    .foregroundStyle(inkFaint)
                    .padding(14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, hit in
                                Button {
                                    store.reveal(hit.id, query: query)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            if let folder = hit.folder {
                                                Text("\(folder)/")
                                                    .font(houseFont(13))
                                                    .foregroundStyle(inkMuted)
                                                    .lineLimit(1)
                                            }
                                            Text(hit.title)
                                                .font(houseFont(13))
                                                .foregroundStyle(brownInk)
                                                .lineLimit(1)
                                        }
                                        if !hit.snippet.isEmpty {
                                            Text(hit.snippet)
                                                .font(houseFont(11))
                                                .foregroundStyle(inkMuted)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(index == selected ? sheetColor : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .id(index)
                                .onHover { if $0 { selected = index } }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(height: listHeight(results))
                    .onChange(of: selected) { _, new in
                        // command rows live outside the scroll view
                        if new < results.count { proxy.scrollTo(new) }
                    }
                }
            }

            // "onboard again" is properly hidden and needs to be typed for.
            // There used to be a "hide sticky notes" row here too; it went,
            // because a sticky is a small mark in the margin now and there is
            // nothing in the way to hide.
            if !cmds.isEmpty {
                Rectangle()
                    .fill(panelDividerColor)
                    .frame(height: 1)
                VStack(spacing: 0) {
                    ForEach(Array(cmds.enumerated()), id: \.element.id) { offset, cmd in
                        let index = results.count + offset
                        commandRow(cmd.title, selected: selected == index, action: cmd.run)
                            .onHover { if $0 { selected = index } }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(panelColor.papered(.palette))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // Needs three characters and a real prefix of "onboard", so it can't
    // surface by accident while someone is searching their notes. Matches
    // "onb…" through "onboard again", and "onboarding" too.
    private var showOnboardAgain: Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 3 else { return false }
        return "onboard again".hasPrefix(q) || q.hasPrefix("onboard")
    }

    // Carries the same highlight box as a result row, so it's visibly one of the
    // selectable things rather than a caption. Kept in the muted ink step, and a
    // shade shorter, so it still reads as furniture below the matches.
    private func commandRow(
        _ title: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(houseFont(12))
                    .foregroundStyle(inkMuted)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? sheetColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8) // matches result rows: 8 outer + 12 label inset
    }

    // hug the results instead of reserving empty space
    private func listHeight(_ results: [SearchHit]) -> CGFloat {
        let rows = results.reduce(CGFloat(0)) { $0 + ($1.snippet.isEmpty ? 33 : 49) }
        return min(rows + 16, 300)
    }

    // Return fires whatever is highlighted — a note opens, a command runs.
    private func activate(_ results: [SearchHit], _ cmds: [Command]) {
        if results.indices.contains(selected) {
            store.reveal(results[selected].id, query: query)
            return
        }
        let offset = selected - results.count
        if cmds.indices.contains(offset) { cmds[offset].run() }
    }
}

struct ContentView: View {
    @ObservedObject var store: NotesStore
    @State private var showNotes = false
    @State private var flourishHovering = false
    @State private var hoveredID: String?
    @State private var panelLocation: String? // nil = root, else drilled-in folder
    @State private var hoveredFolder: String?
    @State private var hoveredBack = false
    @State private var hoveredAdd = false
    @State private var renamingFolder: String?
    @State private var creatingFolder = false
    @State private var folderDraft = ""
    @State private var nameDraft = ""
    @State private var folderFieldFocused = false
    @Namespace private var highlightNS

    // Exactly one highlight lives in the panel at a time, so hovering a folder
    // never leaves a second box behind on a note.
    private enum PanelHighlight: Equatable {
        case none
        case note(String)
        case folder(String)
        case addFolder
        case back
    }

    // Hover wins over the resting position; a hovered folder owns the
    // highlight outright. At rest it sits on the open note, or — at root, when
    // that note is filed away — on the folder holding it.
    private var panelHighlight: PanelHighlight {
        if hoveredBack, panelLocation != nil {
            return .back
        }
        if hoveredAdd, panelLocation == nil {
            return .addFolder
        }
        if let hovered = hoveredFolder, store.folders.contains(hovered) {
            return .folder(hovered)
        }
        if let hovered = hoveredID, visiblePanelNotes.contains(where: { $0.id == hovered }) {
            return .note(hovered)
        }
        if visiblePanelNotes.contains(where: { $0.id == store.currentID }) {
            return .note(store.currentID)
        }
        if panelLocation == nil, let folder = store.currentFolder,
           store.folders.contains(folder) {
            return .folder(folder)
        }
        return .none
    }

    // Decoration, and the door in and out of the hidden page.
    //
    // Extracted from `body` because the type checker gave up on it: the stack
    // had grown past what it will infer in reasonable time, and the error names
    // the whole expression rather than the part that tipped it over. Pulling
    // any sizeable branch out fixes it; this was the newest.
    @ViewBuilder
    private var cornerFlourish: some View {
        if !AnimatedFlourish.frames(.corner).isEmpty {
            AnimatedFlourish(
                tint: flourishHovering ? flourishHovered : flourishRest,
                play: .onceInSession(key: "corner"))
                // Multiplied, like every other flourish in the app — and for the
                // same reason. Painted in `flourish` it was a hair off the sheet,
                // invisible enough on flat colour and completely invisible once
                // the page took paper. Panel drawn *through* the page reads as a
                // soft tan on it, and darkens further under the pointer.
                .blendMode(.multiply)
                // Height from the system's 186.1 units at 16/22; width follows
                // the artwork's own aspect.
                .frame(width: 135.4 * AnimatedFlourish.aspect(.corner), height: 135.4)
                .contentShape(Rectangle())
                .onHover { flourishHovering = $0 }
                .arrowCursorZone()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        store.hiddenShown.toggle()
                        showNotes = false
                    }
                }
                .padding(.leading, 31)
                .padding(.bottom, 38)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .ignoresSafeArea()
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Bare colour: the textured page is painted by the text view on
            // top of this, which is the only place a multiply can see what it
            // is blending against. This stays as the ground beneath it.
            sheetColor.ignoresSafeArea()

            RichTextEditor(store: store)
                .ignoresSafeArea()
                // 3 was enough to say "not this, the palette" and no more. The
                // rebuild's frames push the page properly out of focus, so the
                // card reads as sitting above the sheet rather than on it —
                // and the paper goes with it, since the page is painted inside
                // the text view now and blurs as one surface.
                .blur(radius: store.searchShown || store.onboardingShown ? 8 : 0)
                // Eased both ways over the same 0.6 the palette travels in, so
                // the page softening and the card arriving are one movement.
                // At 0.15 the page snapped out
                // of focus and back, which read as a glitch rather than as a
                // shift of attention — the palette is a change of mode, and the
                // page should recede into it and return from it.
                //
                // This modifier sits directly on the blurred editor and the
                // blur is the only thing here that changes with searchShown, so
                // the long curve stays on the blur alone. The palette's own
                // fade is driven separately and is not slowed to match: you
                // should be able to type the moment you hit ⌘K.
                .animation(.timingCurve(0, 0, 0.35, 1, duration: 0.6), value: store.searchShown)
                .animation(.easeOut(duration: 0.25), value: store.onboardingShown)

            // the hidden page: dedication + the app's settings
            if store.hiddenShown {
                // Papered like the page it replaces. It covers the whole
                // window, so leaving it as flat colour made the settings the
                // one screen in the app printed on nothing.
                sheetColor
                    .papered(.page)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {} // swallow clicks so the editor stays untouched
                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 26) {
                        Text(store.displayName.isEmpty
                             ? "Juilee's personal writing pad <3"
                             : "\(store.displayName)'s personal writing pad <3")
                            .font(houseFont(16))
                            .foregroundStyle(brownInk)
                        ThemePicker(store: store)
                    }
                    Spacer()
                    settingsBlock
                        .padding(.bottom, 70)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .transition(.opacity)
            }

            cornerFlourish

            if showNotes {
                // click anywhere outside the panel to dismiss it
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) { showNotes = false }
                    }

                notesPanel
                    .padding(.trailing, 14)
                    // Clears the controls and then some: they sit 10 from the
                    // bottom and are 44 tall, and the system leaves 26 units —
                    // 19 here — between the folder grid and them. This was 48,
                    // which cleared the old 30pt buttons and stopped clearing
                    // them the moment they were resized from the system.
                    .padding(.bottom, 10 + 44 + 19)
                    .transition(.opacity)
            }

            if !store.hiddenShown, !store.onboardingShown {
                // 12 between the buttons in the system and 36 before them (a
                // flex gap either side of a 12 spacer), which is 9 and 26 here.
                HStack(spacing: 9) {
                    Text("\(store.wordCount)")
                        .font(houseFont(14))
                        .foregroundStyle(inkFaint)
                        .padding(.trailing, 17)
                    IconButton(systemName: "text.justify.left", help: "Past notes",
                               active: showNotes) {
                        withAnimation(.easeOut(duration: 0.15)) { showNotes.toggle() }
                    }
                    IconButton(systemName: "plus", help: "New note (⌘N)") {
                        store.newNote()
                        withAnimation(.easeOut(duration: 0.15)) { showNotes = false }
                    }
                }
                .arrowCursorZone()
                .padding(.trailing, 12)
                .padding(.bottom, 10)
            }

            // first run: sits above everything, and nothing behind it is
            // reachable until it completes
            if store.onboardingShown {
                OnboardingView(store: store)
                    .transition(.opacity)
            }
        }
        // SwiftUI's own text fields (⌘K, the name and folder-name fields) draw
        // their caret in the system accent, so they were the last thing in the
        // app still going pink. NSTextView carets are handled by SmoothCaret.
        // ⌘K lives in an overlay, not in the ZStack.
        //
        // As siblings, the scrim and the palette took part in the stack's
        // layout, and the stack aligns .bottomTrailing — so the page shifted
        // by 10pt the moment the palette appeared and back again when it
        // closed. Measured: 9.9pt with both, 2.7pt with the scrim taken out,
        // which is how the two were told apart. An overlay is sized by the
        // view it covers and cannot move it.
        //
        // (The blur was the obvious suspect and is innocent — the shift is the
        // same with it switched off.)
        .overlay {
            // The stack is always here and only its contents come and go, so
            // the two halves can leave by different routes: the scrim fades
            // where the palette travels.
            ZStack(alignment: .top) {
                if store.searchShown {
                    // scrim dims the note; click anywhere on it to dismiss.
                    // Was 0.8, which washed the page almost flat and took the
                    // blur with it — the palette ended up a light card on a
                    // light nothing. At 0.55 the blurred page still reads as a
                    // page, so the card has something to sit above.
                    sheetColor.opacity(0.55)
                        .contentShape(Rectangle())
                        .onTapGesture { store.searchShown = false }
                        .transition(.opacity)

                    // Drops in from above the window and withdraws the same
                    // way. `move(edge: .top)` carries it clear of its own
                    // frame, and the stack ignores the safe area, so it starts
                    // and ends off the top of the screen rather than appearing
                    // to slide out of the title bar.
                    SearchPalette(store: store)
                        .padding(.top, 110)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .ignoresSafeArea()
            .animation(.timingCurve(0, 0, 0.35, 1, duration: 0.6), value: store.searchShown)
        }
        .tint(brownInk)
        .background(WindowConfigurator())
        .frame(minWidth: 640, minHeight: 400)
        .onChange(of: showNotes) { _, open in
            if open {
                panelLocation = store.currentFolder
                store.panelContext = .some(panelLocation)
            } else {
                store.panelContext = nil
                creatingFolder = false
                renamingFolder = nil
            }
        }
        .onChange(of: panelLocation) { _, location in
            if showNotes { store.panelContext = .some(location) }
        }
        .onChange(of: store.hiddenShown) { _, shown in
            // seed the field when settings opens, commit it when they leave
            if shown {
                nameDraft = store.displayName
            } else {
                store.setDisplayName(nameDraft)
            }
        }
    }

    private var visiblePanelNotes: [NoteMeta] {
        store.notes.filter { $0.folder == panelLocation }
    }

    // folders are laid out two-per-row above the notes
    // The grid is the folders followed by the add tile, so the tile flows with
    // them and lands in the next free half-width slot rather than needing a row
    // of its own.
    private enum FolderItem: Hashable {
        case folder(String)
        case add
    }

    private var folderRows: [[FolderItem]] {
        let items = store.folders.map { FolderItem.folder($0) } + [.add]
        return stride(from: 0, to: items.count, by: 2).map {
            Array(items[$0..<min($0 + 2, items.count)])
        }
    }

    // The grid is never empty now — the add tile is always in it — so the
    // divider only depends on there being notes under it.
    private var showsFolderDivider: Bool {
        panelLocation == nil && !visiblePanelNotes.isEmpty
    }

    private var panelHeight: CGFloat {
        var height: CGFloat = 16 // the content's vertical padding
        var rows = visiblePanelNotes.count
        if panelLocation == nil {
            if creatingFolder { rows += 1 }
            height += CGFloat(folderRows.count) * folderCellHeight
                + CGFloat(folderRows.count - 1) * 6 // grid row spacing
            if showsFolderDivider { height += 13 }
        } else {
            rows += 1 // back row
        }
        if visiblePanelNotes.isEmpty,
           panelLocation != nil || (store.folders.isEmpty && !creatingFolder) {
            rows += 1 // "no notes yet"
        }
        height += CGFloat(rows) * 34
        return min(max(height, 50), 420)
    }

    // MARK: Settings (on the hidden page)

    private var settingsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            // name — the same value onboarding collects; the hidden page reads it
            settingsRow("name") {
                HouseField(
                    text: $nameDraft, size: 12,
                    placeholder: "your name",
                    onSubmit: { store.setDisplayName(nameDraft) })
                    .frame(height: 16)
                    .settingsWell()
            }

            settingsRow("vault") {
                Button {
                    if let url = chooseVaultFolder(startingAt: store.dir) {
                        store.changeVault(to: url)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(store.vaultDisplay)
                            .font(houseFont(12))
                            .foregroundStyle(inkStrong)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .settingsWell()
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            settingsRow("font") {
                Menu {
                    ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in
                        Button(family) { store.setFont(family) }
                    }
                } label: {
                    HStack {
                        Text(store.fontFamily)
                            .font(houseFont(12))
                            .foregroundStyle(inkStrong)
                        Spacer(minLength: 0)
                    }
                    .settingsWell()
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
        }
        .frame(width: 480, alignment: .leading)
    }

    // One row shape, three times over: a fixed-width label and a control
    // filling the rest, on a papered card.
    //
    // Papered because these three were the last flat raised surfaces in the
    // app. The settings page itself takes the sheet stock, and the cards on it
    // did not — a screen printed on paper carrying cards printed on nothing.
    // They take the same stock and strength as the notes panel, because they
    // are the same thing: a panel-toned pane raised off the page. Colour, then
    // paper, then clip — the order every other papered surface uses, so the
    // grain stops at the corner radius instead of squaring off behind it.
    private func settingsRow<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(houseFont(12))
                .foregroundStyle(inkMuted)
                .frame(width: 44, alignment: .leading)
            content()
        }
        .padding(10)
        .background(
            panelColor.papered(.folderPanel)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        )
    }

    private var notesPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let location = panelLocation {
                    backRow(location)
                } else {
                    if creatingFolder { folderNameField }
                    folderGrid
                    if showsFolderDivider {
                        Rectangle()
                            .fill(panelDividerColor)
                            .frame(height: 1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                }
                if visiblePanelNotes.isEmpty,
                   panelLocation != nil || (store.folders.isEmpty && !creatingFolder) {
                    Text("no notes yet")
                        .font(houseFont(13))
                        .foregroundStyle(inkFaint)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 18)
                }
                ForEach(visiblePanelNotes) { noteRow($0) }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 260)
        .frame(height: panelHeight)
        .background(panelColor.papered(.folderPanel))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .arrowCursorZone()
        .contextMenu {
            Button("New Folder") {
                folderDraft = ""
                creatingFolder = true
                panelLocation = nil // folders are created at root
            }
        }
        .onDisappear {
            hoveredID = nil
            hoveredFolder = nil
            hoveredBack = false
            hoveredAdd = false
        }
    }

    private var folderGrid: some View {
        VStack(spacing: 6) {
            ForEach(Array(folderRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { item in
                        switch item {
                        case .folder(let name): folderCell(name)
                        case .add: addFolderCell
                        }
                    }
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity) // keep a lone tile half-width
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    // Same card as a folder, carrying the plus at the size the new-note button
    // uses, so the two ways of adding something read as the same gesture.
    private var addFolderCell: some View {
        Button {
            folderDraft = ""
            creatingFolder = true
            panelLocation = nil // folders are only ever made at root
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(inkFaint)
                .frame(maxWidth: .infinity,
                       minHeight: folderCellHeight - folderCellPadding * 2,
                       maxHeight: folderCellHeight - folderCellPadding * 2)
                .padding(.vertical, folderCellPadding)
                .padding(.horizontal, 10)
                .background(
                    (panelHighlight == .addFolder ? sheetColor : folderBaseColor)
                        .papered(.folderTile)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New folder")
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hoveredAdd = inside }
        }
    }

    private func noteRow(_ note: NoteMeta) -> some View {
        Button {
            store.open(note.id)
            withAnimation(.easeOut(duration: 0.15)) { showNotes = false }
        } label: {
            HStack(spacing: 8) {
                Text(note.title)
                    .font(houseFont(13))
                    .foregroundStyle(inkStrong)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle()
                    .fill(note.id == store.currentID ? openDotColor : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background {
                if panelHighlight == .note(note.id) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(sheetColor)
                        .matchedGeometryEffect(id: "row-highlight", in: highlightNS)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onDrag { NSItemProvider(object: note.id as NSString) }
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) {
                if inside {
                    hoveredID = note.id
                } else if hoveredID == note.id {
                    hoveredID = nil
                }
            }
        }
        .contextMenu {
            Menu("Move to") {
                if note.folder != nil {
                    Button("Unfiled") { store.moveNote(note.id, to: nil) }
                }
                ForEach(store.folders.filter { $0 != note.folder }, id: \.self) { folder in
                    Button(folder) { store.moveNote(note.id, to: folder) }
                }
            }
            Button("Delete", role: .destructive) {
                hoveredID = nil
                withAnimation(.easeOut(duration: 0.15)) { store.delete(note.id) }
            }
        }
    }

    private func folderCell(_ folder: String) -> some View {
        Button {
            guard renamingFolder != folder else { return }
            panelLocation = folder
        } label: {
            // Name along the bottom, air above it. The flourish used to sit
            // here as a small sprig in the flow; in the system it is a
            // watermark behind the whole tile, so it moved to the background
            // and this holds the space it used to occupy — the cell's height is
            // computed from these metrics.
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(width: folderMarkWidth, height: folderMarkHeight)
                Spacer(minLength: folderMarkGap)
                HStack(spacing: 6) {
                    if renamingFolder == folder {
                        HouseField(
                            text: $folderDraft, size: 13, alpha: 0.85,
                            focused: folderFieldFocused,
                            onSubmit: {
                                _ = store.renameFolder(folder, to: folderDraft)
                                renamingFolder = nil
                            },
                            onCancel: { renamingFolder = nil })
                            .frame(height: 16)
                            .onAppear { folderFieldFocused = true }
                            .onDisappear { folderFieldFocused = false }
                    } else {
                        Text(folder)
                            .font(houseFont(13))
                            .foregroundStyle(inkStrong)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Circle()
                            .fill(store.currentFolder == folder ? openDotColor : Color.clear)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .frame(maxWidth: .infinity,
                   minHeight: folderCellHeight - folderCellPadding * 2,
                   maxHeight: folderCellHeight - folderCellPadding * 2,
                   alignment: .leading)
            .padding(.vertical, folderCellPadding)
            .padding(.horizontal, 10)
            // Folder cards cross-fade rather than sliding a shared box around:
            // they differ in size from note rows, and morphing between the two
            // shapes read as an arc. Their own tint just lightens on hover.
            .background(
                (panelHighlight == .folder(folder) ? sheetColor : folderBaseColor)
                    .papered(.folderTile)
                    // The flourish is placed as fractions of the tile, the way
                    // the system places it (77.22/187 across, 132.84 wide on a
                    // 187 tile), and runs off the right and bottom edges — the
                    // clip below is what the design intends, not an accident.
                    .overlay(alignment: .topLeading) {
                        GeometryReader { geo in
                            let w = geo.size.width * 0.7104
                            AnimatedFlourish(
                                set: .folder,
                                tint: panelColor,
                                // A folder made in this session draws its mark
                                // on. Everything already on the shelf keeps
                                // still — otherwise opening the panel would set
                                // the whole grid going at once, which reads as
                                // a glitch rather than as a welcome.
                                play: store.freshFolders.contains(folder)
                                    ? .onceInSession(key: "folder-" + folder)
                                    : .never)
                                .frame(width: w,
                                       height: w / AnimatedFlourish.aspect(.folder))
                                .offset(x: geo.size.width * 0.4130,
                                        y: geo.size.height * 0.0036)
                                // drawn *through* the tile rather than onto it —
                                // see the note on the sticky's flourish
                                .blendMode(.multiply)
                        }
                    }
                    // scopes that multiply to the tile, so it darkens the card
                    // it belongs to and not the panel behind it
                    .compositingGroup()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) {
                if inside {
                    hoveredFolder = folder
                } else if hoveredFolder == folder {
                    hoveredFolder = nil
                }
            }
        }
        .contextMenu {
            Button("Rename") {
                folderDraft = folder
                renamingFolder = folder
            }
            Button("Delete Folder", role: .destructive) {
                store.deleteFolder(folder)
            }
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            dropNote(providers, into: folder)
        }
    }

    private func backRow(_ location: String) -> some View {
        Button {
            panelLocation = nil
        } label: {
            HStack(spacing: 8) {
                Text("‹ \(location)")
                    .font(houseFont(13))
                    .foregroundStyle(inkMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(panelHighlight == .back ? sheetColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hoveredBack = inside }
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            dropNote(providers, into: nil) // drag onto back = unfile
        }
    }

    private var folderNameField: some View {
        HouseField(
            text: $folderDraft, size: 13, alpha: 0.85, bed: .panel,
            placeholder: "folder name",
            focused: folderFieldFocused,
            onSubmit: {
                store.createFolder(folderDraft)
                creatingFolder = false
            },
            onCancel: { creatingFolder = false })
            .frame(height: 16)
            .onAppear { folderFieldFocused = true }
            .onDisappear { folderFieldFocused = false }
            .padding(.vertical, 9)
            .padding(.horizontal, 18)
    }

    private func dropNote(_ providers: [NSItemProvider], into folder: String?) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String else { return }
            DispatchQueue.main.async {
                store.moveNote(id, to: folder)
            }
        }
        return true
    }
}

@main
struct PlainEditorApp: App {
    @StateObject private var store = NotesStore()

    init() {
        // prepare() first: it clears any icon a previous run persisted onto the
        // bundle and captures the pristine artwork to recolour from.
        AppIcon.prepare()
        AppIcon.apply(Style.theme) // the saved theme's icon, from the first frame
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { store.newNote() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Search Notes") {
                    if store.searchShown {
                        store.searchShown = false
                    } else {
                        store.openSearch()
                    }
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}
