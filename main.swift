import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Every colour token reads through the active theme (Theme.swift), so changing
// theme repaints the whole app without a single call site knowing about it.
var sheetColor: Color { Color(nsColor: Style.theme.sheet) }
var panelColor: Color { Color(nsColor: Style.theme.panel) }
var openDotColor: Color { Color(nsColor: Style.theme.openDot) }
var flourishColor: Color { Color(nsColor: Style.theme.flourish) }
var flourishHoverColor: Color { Color(nsColor: Style.theme.flourishHover) }
var brownInk: Color { Color(nsColor: Style.theme.ink) }

// The ink ladder — four steps, and only these four. Everything written in the
// app is brownInk at one of them. Reaching for a fresh opacity adds a colour
// nobody chose; pick the step that matches the role instead.
var inkStrong: Color { brownInk.opacity(0.85) } // panel rows, settings values, folder names
var inkMuted: Color { brownInk.opacity(0.55) } // labels, snippets, secondary rows
var inkFaint: Color { brownInk.opacity(0.4) } // placeholders, empty states, icons, disabled

var dividerColor: Color { Color(nsColor: Style.theme.divider) }

// The hairline *inside* a papered surface, as a tone rather than a colour —
// the same reasoning as `Style.ruleTone`.
//
// `divider` above is a colour chosen to sit a step darker than the sheet, and
// it stopped working the moment the panels took their paper: at 93% the folder
// pane goes to #D0C1A7, which is darker than the #E6D4B5 hairline, so the
// divider inverted and read as a pale scratch across the card.
//
// Black at 12% over a base is arithmetically a multiply by 0.88 — no blend mode
// needed, since a black source at alpha `a` composites to exactly `base × (1−a)`.
// So this is always a darkening, on any surface, in any of the six themes, and
// it cannot invert the way a fixed colour can.
var panelDividerColor: Color { Color.black.opacity(0.12) }

// botanical sprig sitting atop each folder box
let folderSprigImage: NSImage? = {
    guard let url = Bundle.main.url(forResource: "FolderSprig", withExtension: "png")
    else { return nil }
    return NSImage(contentsOf: url)
}()
// The system's folder flourish — a watermark filling most of the tile from the
// top edge, not the small corner sprig it replaces. Rasterised from the file's
// vector with its rotation and flip baked in.
let folderFlourishImage: NSImage? = {
    guard let url = Bundle.main.url(forResource: "FolderFlourish", withExtension: "png")
    else { return nil }
    return NSImage(contentsOf: url)
}()
var folderBaseColor: Color { Color(nsColor: Style.theme.folderBase) }
let folderSprigHeight: CGFloat = 32
let folderSprigWidth: CGFloat = 32 * (181.0 / 271.0) // keep the artwork's aspect
let folderSprigGap: CGFloat = 14 // breathing room between sprig and name
let folderTitleHeight: CGFloat = 16
let folderCellPadding: CGFloat = 9
let folderCellHeight: CGFloat =
    folderSprigHeight + folderSprigGap + folderTitleHeight + folderCellPadding * 2

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
    static var baseFont: NSFont {
        NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: 5, size: 16)
            ?? NSFont(name: "Courier", size: 16)
            ?? .monospacedSystemFont(ofSize: 16, weight: .regular)
    }

    // force every font run to the chosen family/size, keeping italic/bold traits
    static func applyFont(to text: NSMutableAttributedString) {
        let manager = NSFontManager.shared
        let full = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.font, in: full) { value, range, _ in
            let font = value as? NSFont ?? baseFont
            if font.familyName != fontFamily || font.pointSize != 16 {
                var fixed = manager.convert(font, toFamily: fontFamily)
                fixed = manager.convert(fixed, toSize: 16)
                text.addAttribute(.font, value: fixed, range: range)
            }
        }
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

    // How far a selection reaches past the glyphs it covers. AppKit hands the
    // whole line fragment to the selection fill, and a fragment is
    // [glyphs][leading] — so on a ruled page, where the leading is most of the
    // band, the highlight trailed a slab of colour under every line and ran
    // down to the next one. The selection marks the words; this is the air
    // around them.
    static let selectionPadding: CGFloat = 5

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
// When pinX/pinY are set the user has dragged it to a fixed spot on the canvas
// (document coordinates, so it scrolls with the text).
struct Sticky: Identifiable, Codable, Equatable {
    let id: UUID
    var start: Int
    var length: Int
    var text: String
    var pinX: Double?
    var pinY: Double?
    var rotation: Double? // slight tilt, only while pinned
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
        let tokens = attr.string.split { $0.isWhitespace || $0.isNewline }
        // bullets and rule markers aren't words
        wordCount = tokens.filter { $0 != "•" && !$0.allSatisfy { $0 == "─" } }.count
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
    @Published var stickiesHidden = false

    private func stickiesURL(_ id: String, in folder: String?) -> URL {
        baseDir(folder).appendingPathComponent("\(id).stickies.json")
    }

    private func loadStickies(_ id: String, in folder: String?) -> [Sticky] {
        guard let data = try? Data(contentsOf: stickiesURL(id, in: folder)) else { return [] }
        return (try? JSONDecoder().decode([Sticky].self, from: data)) ?? []
    }

    func addSticky(range: NSRange, left: Bool) -> UUID {
        var sticky = Sticky(id: UUID(), start: range.location, length: range.length, text: "")
        sticky.left = left
        stickies.append(sticky)
        stickiesHidden = false
        scheduleSave()
        return sticky.id
    }

    func pinSticky(_ id: UUID, x: Double, y: Double, rotation: Double) {
        guard let i = stickies.firstIndex(where: { $0.id == id }) else { return }
        stickies[i].pinX = x
        stickies[i].pinY = y
        stickies[i].rotation = rotation
        scheduleSave()
    }

    func unpinSticky(_ id: UUID) {
        guard let i = stickies.firstIndex(where: { $0.id == id }) else { return }
        stickies[i].pinX = nil
        stickies[i].pinY = nil
        stickies[i].rotation = nil
        scheduleSave()
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

    @Published var searchShown = false
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
        refreshList()
        return candidate
    }

    @discardableResult
    func renameFolder(_ name: String, to newName: String) -> String? {
        let clean = sanitizeFolderName(newName)
        guard !clean.isEmpty, clean != name else { return name }
        let fm = FileManager.default
        var candidate = clean
        var counter = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            candidate = "\(clean) \(counter)"
            counter += 1
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

    // Deleting a folder never deletes writing: its notes slide back to unfiled.
    func deleteFolder(_ name: String) {
        let fm = FileManager.default
        let folderURL = dir.appendingPathComponent(name, isDirectory: true)
        if let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
            for file in files where ["rtf", "txt", "json"].contains(file.pathExtension) {
                let dest = dir.appendingPathComponent(file.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.moveItem(at: file, to: dest)
                }
            }
        }
        try? fm.removeItem(at: folderURL)
        if currentFolder == name { currentFolder = nil }
        refreshList()
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
        let folder = notes.first(where: { $0.id == id })?.folder
        currentID = id
        currentFolder = folder
        attr = loadAttr(id, in: folder)
        stickies = loadStickies(id, in: folder)
        updateWordCount()
        let q = query.trimmingCharacters(in: .whitespaces)
        let range = (attr.string as NSString).range(of: q, options: .caseInsensitive)
        pendingReveal = (!q.isEmpty && range.location != NSNotFound) ? range : nil
        docVersion += 1
    }

    private func plainTextForNote(_ id: String) -> String {
        let folder = folderOf(id)
        let rtf = rtfURL(id, in: folder)
        if FileManager.default.fileExists(atPath: rtf.path) { return plainText(of: rtf) }
        return plainText(of: txtURL(id, in: folder))
    }

    func refreshList() {
        let fm = FileManager.default
        var seen = Set<String>()
        var metas: [NoteMeta] = []
        var folderNames: [String] = []

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
                metas.append(NoteMeta(
                    id: id, title: Self.title(for: plainText(of: url)),
                    modified: modified, folder: folder))
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

    func open(_ id: String) {
        saveNow()
        let folder = notes.first(where: { $0.id == id })?.folder
        currentID = id
        currentFolder = folder
        attr = loadAttr(id, in: folder)
        stickies = loadStickies(id, in: folder)
        updateWordCount()
        docVersion += 1
    }

    func delete(_ id: String) {
        if id == currentID { saveWork?.cancel() } // a pending save would resurrect the file
        let folder = folderOf(id)
        let fm = FileManager.default
        try? fm.removeItem(at: rtfURL(id, in: folder))
        try? fm.removeItem(at: txtURL(id, in: folder))
        try? fm.removeItem(at: stickiesURL(id, in: folder))
        refreshList()
        if id == currentID {
            if let latest = notes.first {
                currentID = latest.id
                currentFolder = latest.folder
                attr = loadAttr(latest.id, in: latest.folder)
                stickies = loadStickies(latest.id, in: latest.folder)
            } else {
                currentID = UUID().uuidString
                currentFolder = nil
                attr = NSAttributedString()
                stickies = []
            }
            updateWordCount()
            docVersion += 1
        }
    }

    func newNote() {
        hiddenShown = false
        saveNow()
        currentID = UUID().uuidString
        // land in the panel's current location if it's open, else stay in the
        // open note's folder
        if let context = panelContext { currentFolder = context }
        attr = NSAttributedString()
        stickies = []
        updateWordCount()
        docVersion += 1
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
        if #available(macOS 14.0, *) {
            view.subviews.compactMap { $0 as? NSTextInsertionIndicator }
                .forEach { $0.displayMode = .hidden }
        }
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
        rect.size.width = 2
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
        DispatchQueue.main.async { [weak self] in self?.smoothCaret.update(animated: false) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.smoothCaret.update(animated: false) }
        return ok
    }

    func applyTheme() {
        textColor = Style.ink
        insertionPointColor = Style.ink
        smoothCaret.applyTheme()
    }
}

final class StickyView: NSView, NSTextViewDelegate {
    // The system's flourish, rasterised from the file's own vector with its
    // rotation and flip already baked in — see CLAUDE.md on why the transform
    // is baked at build time rather than applied here.
    private static let flowerSource: NSImage? = {
        guard let url = Bundle.main.url(forResource: "StickyFlourish", withExtension: "png")
        else { return nil }
        return NSImage(contentsOf: url)
    }()

    // The flower is a single-colour silhouette with a clean alpha channel, so it
    // can be recoloured wholesale to follow the theme. SwiftUI does this with
    // .renderingMode(.template); here the drawing is by hand, so the tint is
    // baked into a copy — sourceAtop over the source directly would catch the
    // sticky's own background, which is already opaque behind it. Cached per
    // theme so it isn't rebuilt on every draw pass.
    private static var flowerCache: [String: NSImage] = [:]

    private static func flower(for theme: Theme) -> NSImage? {
        if let hit = flowerCache[theme.id] { return hit }
        guard let src = flowerSource else { return nil }
        let out = NSImage(size: src.size)
        out.lockFocus()
        src.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        // #ECDBBE in the system, which is the panel token — not sheet, which is
        // what the old flower used.
        theme.panel.set()
        NSRect(origin: .zero, size: src.size).fill(using: .sourceAtop)
        out.unlockFocus()
        flowerCache[theme.id] = out
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
    private static let flourishWidth: CGFloat = 0.4034
    private static let flourishLeft: CGFloat = 0.6281
    private static let flourishOverhang: CGFloat = 0.0575
    private static let flourishAspect: CGFloat = 529.0 / 484.0 // the artwork's own

    private func flourishRect() -> NSRect {
        let w = bounds.width * Self.flourishWidth
        let h = w * Self.flourishAspect
        return NSRect(x: bounds.width * Self.flourishLeft,
                      y: -(bounds.width * Self.flourishOverhang),
                      width: w, height: h)
    }

    // Text never enters the flourish's band. Derived from the flourish rather
    // than fixed at 38, which the artwork outgrew — the words were running
    // straight over the flowers on any sticky wide enough.
    private var bottomReserve: CGFloat { max(flourishRect().maxY + 6, 24) }
    var onTextChange: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onLayoutNeeded: (() -> Void)?
    var onPinned: ((NSPoint, Double) -> Void)?
    var onUnpin: (() -> Void)?
    var isPinned: (() -> Bool)?

    init(id: UUID, text: String) {
        stickyID = id
        super.init(frame: .zero)
        noteView.isRichText = false
        noteView.font = NSFont(name: "Courier", size: 13)
        noteView.textColor = Style.ink
        noteView.insertionPointColor = Style.ink
        noteView.drawsBackground = false
        noteView.textContainerInset = NSSize(width: 14, height: 12) // clear of the perforations
        noteView.textContainer?.widthTracksTextView = true
        noteView.isAutomaticQuoteSubstitutionEnabled = false
        noteView.isAutomaticDashSubstitutionEnabled = false
        noteView.isAutomaticTextReplacementEnabled = false
        noteView.allowsUndo = true
        noteView.string = text
        noteView.delegate = self
        noteView.menuProvider = { [weak self] in self?.stickyMenu() ?? NSMenu() }
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
        // stamp). It reaches past the bottom edge by about 5% and is cut off by
        // the clip above, which is deliberate in the design.
        //
        // Width drives the height through the artwork's own aspect rather than
        // both coming from the stamp, so a sticky that isn't the system's
        // proportions doesn't stretch the flowers.
        // Multiplied, not painted on. The artwork is #ECDBBE — the panel token —
        // but the system draws it *through* whatever it sits on, so on gold it
        // comes out a deep tan rather than a pale cream. Painted opaque it was
        // far too light, and the SVG's fill attribute gives no hint of this: a
        // blend mode doesn't survive that export.
        Self.flower(for: Style.theme)?.draw(
            in: flourishRect(), from: .zero, operation: .multiply, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    func applyTheme() {
        noteView.applyTheme()
        needsDisplay = true // the stamp body and its flower are drawn by hand
    }

    private func stickyMenu() -> NSMenu {
        let menu = NSMenu()
        let delete = NSMenuItem(title: "Delete Note", action: #selector(deleteSticky), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        if isPinned?() == true {
            let unpin = NSMenuItem(
                title: "Return to Margin", action: #selector(unpinSticky), keyEquivalent: "")
            unpin.target = self
            menu.addItem(unpin)
        }
        return menu
    }

    @objc private func deleteSticky() { onDelete?() }
    @objc private func unpinSticky() { onUnpin?() }

    override func menu(for event: NSEvent) -> NSMenu? { stickyMenu() }

    // When not editing, the whole sticky is a drag/focus target; while editing
    // clicks go to the text as usual.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if view != nil, !isEditing { return self }
        return view
    }

    // Drag to pin anywhere on the canvas; a plain click focuses for typing.
    override func mouseDown(with event: NSEvent) {
        let startWindow = event.locationInWindow
        let startOrigin = frame.origin
        var dragged = false
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let dx = next.locationInWindow.x - startWindow.x
            let dy = next.locationInWindow.y - startWindow.y
            if !dragged, abs(dx) > 3 || abs(dy) > 3 {
                dragged = true
                // the tilt happens as the note leaves for the canvas — rolled
                // once, on its first ever drag, and kept from then on
                if isPinned?() != true, frameCenterRotation == 0 {
                    frameCenterRotation = CGFloat(Double.random(in: -2...2))
                }
            }
            if dragged {
                // superview is flipped, window coords are not; keep the note
                // fully inside the canvas while dragging
                let maxX = max(8, (superview?.bounds.width ?? .greatestFiniteMagnitude) - frame.width - 8)
                let x = min(max(startOrigin.x + dx, 8), maxX)
                let y = max(startOrigin.y - dy, 8)
                frame.origin = NSPoint(x: x, y: y)
            }
        }
        if dragged {
            onPinned?(frame.origin, Double(frameCenterRotation))
        } else {
            focus()
        }
    }

    var noteText: String { noteView.string }
    var isEditing: Bool { window?.firstResponder === noteView }

    func setText(_ text: String) {
        if noteView.string != text { noteView.string = text }
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
        return max(lm.usedRect(for: tc).height + 24 + bottomReserve, bounds.width)
    }

    func focus() { window?.makeFirstResponder(noteView) }

    func textDidChange(_ notification: Notification) {
        onTextChange?(noteView.string)
        onLayoutNeeded?()
    }

    // A sticky that was never typed into vanishes when clicked away from.
    func textDidEndEditing(_ notification: Notification) {
        if noteView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.async { [weak self] in self?.onDelete?() }
        }
    }
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
        // Trimmed to the glyphs plus a little air. The top edge is the
        // fragment's own, since that is where the glyphs start.
        Style.selection.setFill()
        let height = Style.lineHeight + Style.selectionPadding * 2
        for i in 0..<rectCount {
            let fragment = rectArray[i]
            NSRect(x: fragment.minX,
                   y: fragment.minY - Style.selectionPadding,
                   width: fragment.width,
                   height: min(fragment.height, height)).fill()
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

    weak var notesStore: NotesStore?
    private var stickyViews: [UUID: StickyView] = [:]
    private let selectionIcon = SelectionIconView()
    private var annotationsConfigured = false

    func configureAnnotations() {
        guard !annotationsConfigured else { return }
        annotationsConfigured = true
        selectionIcon.isHidden = true
        selectionIcon.onClick = { [weak self] in self?.createStickyFromSelection() }
        addSubview(selectionIcon)
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

    private func createStickyFromSelection() {
        guard let store = notesStore else { return }
        let sel = selectedRange()
        guard sel.length > 0, let lm = layoutManager, let tc = textContainer else { return }
        let glyphRange = lm.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
        let rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        let id = store.addSticky(range: sel, left: selectionTargetsLeft(rect))
        selectionIcon.isHidden = true
        syncStickies()
        stickyViews[id]?.focus()
    }

    // Rebuild/reposition the margin notes from their anchors. Called on every
    // layout pass, edit, and model change, so notes track reflow and resize.
    func syncStickies() {
        guard annotationsConfigured, let store = notesStore else { return }
        let list = store.stickies
        for (id, view) in stickyViews where !list.contains(where: { $0.id == id }) {
            view.removeFromSuperview()
            stickyViews[id] = nil
        }
        guard let lm = layoutManager, let tc = textContainer else { return }
        let textLength = (string as NSString).length
        let width: CGFloat = 172
        let rightX = bounds.width - Style.sideMargin + 14
        let leftX = Style.sideMargin - width - 14
        var placed: [(view: StickyView, anchorY: CGFloat, isLeft: Bool)] = []
        let hidden = store.stickiesHidden
        for sticky in list.sorted(by: { $0.start < $1.start }) {
            let view = stickyViews[sticky.id] ?? {
                let v = StickyView(id: sticky.id, text: sticky.text)
                v.onTextChange = { [weak self] text in
                    self?.notesStore?.updateStickyText(sticky.id, text)
                }
                v.onDelete = { [weak self] in
                    self?.notesStore?.removeSticky(sticky.id)
                }
                v.onLayoutNeeded = { [weak self] in self?.syncStickies() }
                v.onPinned = { [weak self] origin, rotation in
                    self?.notesStore?.pinSticky(
                        sticky.id, x: origin.x, y: origin.y, rotation: rotation)
                }
                v.onUnpin = { [weak self] in self?.notesStore?.unpinSticky(sticky.id) }
                v.isPinned = { [weak self] in
                    self?.notesStore?.stickies.first(where: { $0.id == sticky.id })?.pinX != nil
                }
                addSubview(v)
                stickyViews[sticky.id] = v
                return v
            }()
            if !view.isEditing { view.setText(sticky.text) }
            view.isHidden = hidden
            if let pinX = sticky.pinX, let pinY = sticky.pinY {
                // pinned: fixed document position, outside the margin flow.
                // Displayed position clamps to the window so the note can hit
                // the wall and ride it, without losing its remembered spot.
                view.frameCenterRotation = 0 // frames are only reliable unrotated
                view.frame.size.width = width
                let height = view.desiredHeight
                let maxX = max(8, bounds.width - width - 8)
                let x = min(max(CGFloat(pinX), 8), maxX)
                let y = max(CGFloat(pinY), 8)
                view.frame = NSRect(x: x, y: y, width: width, height: height)
                view.frameCenterRotation = CGFloat(sticky.rotation ?? 0)
                continue
            }
            let loc = max(0, min(sticky.start, textLength))
            let len = max(0, min(sticky.length, textLength - loc))
            let glyphRange = lm.glyphRange(
                forCharacterRange: NSRange(location: loc, length: len), actualCharacterRange: nil)
            var anchorY = textContainerInset.height
            if glyphRange.length > 0 {
                anchorY = lm.boundingRect(forGlyphRange: glyphRange, in: tc).minY
                    + textContainerInset.height
            } else if lm.numberOfGlyphs > 0 {
                let glyphIndex = min(glyphRange.location, lm.numberOfGlyphs - 1)
                anchorY = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil).minY
                    + textContainerInset.height
            }
            placed.append((view, anchorY, sticky.left == true))
        }
        // nudge overlapping notes downward in anchor order, per margin
        var lastBottomLeft: CGFloat = -.greatestFiniteMagnitude
        var lastBottomRight: CGFloat = -.greatestFiniteMagnitude
        for (view, anchorY, isLeft) in placed {
            view.frameCenterRotation = 0 // margin notes sit straight
            view.frame.size.width = width // set width before measuring wrap height
            let height = view.desiredHeight
            let lastBottom = isLeft ? lastBottomLeft : lastBottomRight
            let y = max(anchorY, lastBottom == -.greatestFiniteMagnitude ? anchorY : lastBottom + 6)
            view.frame = NSRect(x: isLeft ? leftX : rightX, y: y, width: width, height: height)
            if isLeft {
                lastBottomLeft = y + height
            } else {
                lastBottomRight = y + height
            }
        }
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
            didChangeText() // let the store pick the recoloured text up and save it
        }
        var attrs = typingAttributes
        attrs[.foregroundColor] = Style.ink
        typingAttributes = attrs
        selectedTextAttributes = [.backgroundColor: Style.selection]
        smoothCaret.applyTheme()
        selectionIcon.applyTheme()
        stickyViews.values.forEach { $0.applyTheme() }
        // the cream dots covering the traffic lights live in the title bar, well
        // outside this view's tree
        if let titlebar = window?.standardWindowButton(.closeButton)?.superview {
            titlebar.subviews.compactMap { $0 as? TrafficDotsOverlay }
                .forEach { $0.needsDisplay = true }
        }
        needsDisplay = true // horizontal rules are drawn, not stored
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
                let trimmed = line.trimmingCharacters(in: .whitespaces)
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
                let py = y.rounded() + 0.5 // land on the pixel, not across two
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
        let font = NSFont(name: Style.fontFamily, size: size)
            ?? NSFont(name: "Courier", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        field.font = font
        field.textColor = Style.ink.withAlphaComponent(alpha)
        field.alignment = centered ? .center : .left
        (field.cell as? HouseTextFieldCell)?.selectionColor =
            bed == .sheet ? Style.selection : Style.sheet
        field.placeholderAttributedString = placeholder.isEmpty ? nil
            : NSAttributedString(string: placeholder, attributes: [
                .font: font,
                .foregroundColor: Style.ink.withAlphaComponent(0.4), // inkFaint
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
        if showStickyToggle {
            out.append(Command(
                id: "sticky",
                title: store.stickiesHidden ? "show sticky notes" : "hide sticky notes"
            ) {
                store.stickiesHidden.toggle()
                store.searchShown = false
            })
        }
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
        .onChange(of: query) { _ in selected = 0 }
    }

    private func queryCard(_ results: [SearchHit], _ cmds: [Command]) -> some View {
        Group {
            ZStack(alignment: .leading) {
                // macOS ignores prompt styling, so the placeholder is drawn manually
                if query.isEmpty {
                    Text("search")
                        .font(.custom("Courier", size: 14))
                        .foregroundStyle(inkMuted)
                        .allowsHitTesting(false)
                }
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
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
                    .font(.custom("Courier", size: 12))
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
                                                    .font(.custom("Courier", size: 13))
                                                    .foregroundStyle(inkMuted)
                                                    .lineLimit(1)
                                            }
                                            Text(hit.title)
                                                .font(.custom("Courier", size: 13))
                                                .foregroundStyle(brownInk)
                                                .lineLimit(1)
                                        }
                                        if !hit.snippet.isEmpty {
                                            Text(hit.snippet)
                                                .font(.custom("Courier", size: 11))
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
                    .onChange(of: selected) { new in
                        // command rows live outside the scroll view
                        if new < results.count { proxy.scrollTo(new) }
                    }
                }
            }

            // The sticky toggle shows on an empty query or one about stickies;
            // "onboard again" is properly hidden and needs to be typed for.
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

    private var showStickyToggle: Bool {
        guard !store.stickies.isEmpty else { return false }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || "sticky notes".contains(q) || q.contains("sticky")
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
                    .font(.custom("Courier", size: 12))
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
                .animation(.easeOut(duration: 0.15), value: store.searchShown)
                .animation(.easeOut(duration: 0.25), value: store.onboardingShown)

            // the hidden page: dedication + the app's settings
            if store.hiddenShown {
                sheetColor
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {} // swallow clicks so the editor stays untouched
                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 26) {
                        Text(store.displayName.isEmpty
                             ? "Juilee's personal writing pad <3"
                             : "\(store.displayName)'s personal writing pad <3")
                            .font(.custom("Courier", size: 16))
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

            // corner flourish: decoration, and the door in and out of the hidden page
            if let url = Bundle.main.url(forResource: "Flourish", withExtension: "png"),
               let flourish = NSImage(contentsOf: url) {
                Image(nsImage: flourish)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(flourishHovering ? flourishHoverColor : flourishColor)
                    .frame(width: 72.4, height: 108.4)
                    .contentShape(Rectangle())
                    .onHover { flourishHovering = $0 }
                    .arrowCursorZone()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            store.hiddenShown.toggle()
                            showNotes = false
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .ignoresSafeArea()
            }

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

            if store.searchShown {
                // scrim dims the note; click anywhere on it to dismiss
                sheetColor.opacity(0.8)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { store.searchShown = false }
                    .transition(.opacity)

                SearchPalette(store: store)
                    .padding(.top, 110)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }

            if !store.hiddenShown, !store.onboardingShown {
                // 12 between the buttons in the system and 36 before them (a
                // flex gap either side of a 12 spacer), which is 9 and 26 here.
                HStack(spacing: 9) {
                    Text("\(store.wordCount)")
                        .font(.custom("Courier", size: 14))
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
        .tint(brownInk)
        .background(WindowConfigurator())
        .frame(minWidth: 640, minHeight: 400)
        .onChange(of: showNotes) { open in
            if open {
                panelLocation = store.currentFolder
                store.panelContext = .some(panelLocation)
            } else {
                store.panelContext = nil
                creatingFolder = false
                renamingFolder = nil
            }
        }
        .onChange(of: panelLocation) { location in
            if showNotes { store.panelContext = .some(location) }
        }
        .onChange(of: store.hiddenShown) { shown in
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
            HStack(spacing: 12) {
                Text("name")
                    .font(.custom("Courier", size: 12))
                    .foregroundStyle(inkMuted)
                    .frame(width: 44, alignment: .leading)
                ZStack(alignment: .leading) {
                    if nameDraft.isEmpty {
                        Text("your name")
                            .font(.custom("Courier", size: 12))
                            .foregroundStyle(inkFaint)
                            .allowsHitTesting(false)
                    }
                    HouseField(
                        text: $nameDraft, size: 12,
                        onSubmit: { store.setDisplayName(nameDraft) })
                        .frame(height: 16)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(sheetColor))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(panelColor))

            // vault
            HStack(spacing: 12) {
                Text("vault")
                    .font(.custom("Courier", size: 12))
                    .foregroundStyle(inkMuted)
                    .frame(width: 44, alignment: .leading)
                Button {
                    chooseVault()
                } label: {
                    HStack(spacing: 10) {
                        Text(store.vaultDisplay)
                            .font(.custom("Courier", size: 12))
                            .foregroundStyle(inkStrong)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6).fill(sheetColor))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(panelColor))

            // font
            HStack(spacing: 12) {
                Text("font")
                    .font(.custom("Courier", size: 12))
                    .foregroundStyle(inkMuted)
                    .frame(width: 44, alignment: .leading)
                Menu {
                    ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in
                        Button(family) { store.setFont(family) }
                    }
                } label: {
                    HStack {
                        Text(store.fontFamily)
                            .font(.custom("Courier", size: 12))
                            .foregroundStyle(inkStrong)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6).fill(sheetColor))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(panelColor))
        }
        .frame(width: 480, alignment: .leading)
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = store.dir
        panel.prompt = "Use as Vault"
        panel.message = "Choose the folder where notes are stored"
        if panel.runModal() == .OK, let url = panel.url {
            store.changeVault(to: url)
        }
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
                        .font(.custom("Courier", size: 13))
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
                    .font(.custom("Courier", size: 13))
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
                    .frame(width: folderSprigWidth, height: folderSprigHeight)
                Spacer(minLength: folderSprigGap)
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
                        Text(folder.uppercased())
                            .font(.custom("Courier", size: 13))
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
                            if let art = folderFlourishImage {
                                let w = geo.size.width * 0.7104
                                Image(nsImage: art)
                                    .resizable()
                                    .renderingMode(.template)
                                    .foregroundStyle(panelColor)
                                    .frame(width: w,
                                           height: w * (art.size.height / art.size.width))
                                    .offset(x: geo.size.width * 0.4130,
                                            y: geo.size.height * 0.0036)
                                    // drawn *through* the tile rather than onto
                                    // it — see the note on the sticky's flourish
                                    .blendMode(.multiply)
                            }
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
                Text("‹ \(location.uppercased())")
                    .font(.custom("Courier", size: 13))
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
