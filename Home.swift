import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The home screen: every note and folder, on the same paper as the page.
//
// Ported from the phone (`JUI-iOS/JUI/Sources/HomeView.swift`), where it is
// where the app opens. Here it sits beside the notes tray rather than
// replacing it: the tray is for hopping between notes mid-sentence, home is a
// whole window to look over everything. Reached from its button by the
// controls or ⇧⌘H; left by opening a note, Escape, or the button again.
//
// At the root, folders sit three to a row above the notes, with an add tile
// flowing after them — three rather than the phone's two, so a tile keeps the
// phone's proportions across a column twice its width. A folder opens as the
// same screen standing inside it, its name as the heading, which is also the
// way back out and where a note is dropped to unfile it. Notes are gathered
// under the day they were last written in. Right-click for the tray's menus;
// drag a note onto a folder to file it.
//
// Search and a new note sit at the foot with the other controls (drawn by
// ContentView, as are the corner flourish and the settings page above it).
struct HomeView: View {
    @ObservedObject var store: NotesStore

    @State private var hoveredNote: String?
    @State private var hoveredFolder: String?
    @State private var hoveredAdd = false
    @State private var hoveredHeader = false
    @State private var dropTarget: String??
    @State private var renamingFolder: String?
    @State private var creatingFolder = false
    @State private var folderDraft = ""
    @State private var fieldFocused = false
    @State private var confirmingDelete: String?
    @State private var escapeMonitor: Any?

    private var location: String? { store.homeFolder }

    // The column notes are read in. Folders three across at this width come
    // out at the phone's tile size; past it the page just has more margin.
    private static let columnWidth: CGFloat = 600
    private static let topInset: CGFloat = 56 // clear of the traffic lights

    private var visibleNotes: [NoteMeta] {
        store.notes.filter { $0.folder == location }
    }

    private enum FolderItem: Hashable {
        case folder(String)
        case add
    }

    private var folderRows: [[FolderItem]] {
        let items = store.folders.map { FolderItem.folder($0) } + [.add]
        return stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0..<min($0 + 3, items.count)])
        }
    }

    var body: some View {
        GeometryReader { geo in
            page(foot: footClearance(geo.size))
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.15), value: store.notes)
        .animation(.easeOut(duration: 0.15), value: store.folders)
        .onChange(of: store.homeFolder) { _, _ in
            hoveredNote = nil
            hoveredFolder = nil
            hoveredHeader = false
            endEditing()
        }
        .onAppear(perform: watchEscape)
        .onDisappear {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
            hoveredNote = nil
            hoveredFolder = nil
            hoveredAdd = false
            hoveredHeader = false
        }
        .confirmationDialog(
            confirmingDelete.map { "Delete \u{201C}\($0)\u{201D} and the notes in it?" } ?? "",
            isPresented: Binding(get: { confirmingDelete != nil },
                                 set: { if !$0 { confirmingDelete = nil } })
        ) {
            Button("Delete Folder", role: .destructive) {
                if let name = confirmingDelete { store.deleteFolder(name) }
                confirmingDelete = nil
            }
        } message: {
            Text("There is no trash, so this can't be undone.")
        }
    }

    private func page(foot: CGFloat) -> some View {
        ZStack {
            // Papered like the page it covers, and like the settings page:
            // a whole-window screen printed on the sheet stock.
            sheetColor
                .papered(.page)
                .contentShape(Rectangle())
                .onTapGesture { endEditing() } // and keeps clicks off the editor

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if location == nil {
                        if creatingFolder { folderNameField }
                        folderGrid
                        if !visibleNotes.isEmpty {
                            Rectangle()
                                .fill(panelDividerColor)
                                .frame(height: 1)
                                .padding(.horizontal, 26)
                                .padding(.vertical, 18)
                        }
                    }
                    if visibleNotes.isEmpty, location != nil || store.folders.isEmpty {
                        Text("no notes yet")
                            .font(houseFont(13))
                            .foregroundStyle(inkFaint)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 26)
                    }
                    ForEach(Array(noteDays.enumerated()), id: \.element.day) { index, group in
                        if index > 0 { daySeparator }
                        dayTitle(group.day)
                        ForEach(group.notes) { noteRow($0) }
                    }
                }
                .frame(maxWidth: Self.columnWidth, alignment: .leading)
                .frame(maxWidth: .infinity) // centred in the window
                .padding(.top, Self.topInset)
                // lets the last row rise clear of whatever the foot fades under
                .padding(.bottom, foot + Self.footFade + 12)
            }
            .scrollIndicators(.never)
            .mask(listMask(foot: foot))
            .arrowCursorZone()
        }
    }

    // MARK: Escape

    // Escape steps out: from a folder to the root, from the root back to the
    // note. A monitor rather than `onExitCommand`, which only reaches a view
    // holding focus, and nothing on this screen does until a field is opened.
    // A field's own Escape (cancel the name) and the palette's (close it) are
    // left to them.
    private func watchEscape() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, // Escape
                  store.homeShown, !store.searchShown, !store.hiddenShown,
                  !store.onboardingShown,
                  !(event.window?.firstResponder is NSText) // a field is editing
            else { return event }
            withAnimation(.easeOut(duration: 0.2)) {
                if store.homeFolder != nil {
                    store.homeFolder = nil
                } else {
                    store.homeShown = false
                }
            }
            return nil
        }
    }

    // MARK: Soft edges

    // The list fades out as it scrolls up under the title bar, and fades out
    // at the foot before it reaches whatever sits there, starting a clear band
    // above it. At rest nothing is faded: the heading starts below the top
    // fade, and the list's foot padding lets its last row rise clear.
    //
    // What sits at the foot depends on the window. On the phone the list runs
    // the full width, so it always fades at the top of the flourish. Here the
    // column is centred, and in all but a narrow window it clears the flourish
    // entirely — fading there would hide most of a short window's notes for
    // nothing — so it only has to clear the buttons. The flourish's numbers
    // are ContentView's: 135.4 tall, 31 in and 38 off the foot.
    private static let topFade: CGFloat = 44
    private static let footFade: CGFloat = 24

    private func footClearance(_ size: CGSize) -> CGFloat {
        let columnLeft = max((size.width - Self.columnWidth) / 2, 0) + 14
        let flourishRight = 31 + 135.4 * AnimatedFlourish.aspect(.corner)
        return columnLeft < flourishRight + 12
            ? 38 + 135.4 // over the flourish's top
            : 10 + 44 + 8 // over the buttons
    }

    private func listMask(foot: CGFloat) -> some View {
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            let bottom = max(Self.topFade, h - foot)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 28 / h),
                    .init(color: .black, location: Self.topFade / h),
                    .init(color: .black, location: max(Self.topFade, bottom - Self.footFade) / h),
                    .init(color: .clear, location: bottom / h),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Header

    // At the root, whose writing pad this is. In a folder, its name behind a
    // back mark — the phone goes back by its edge swipe, and a Mac has none —
    // and a drop target that unfiles a note.
    @ViewBuilder
    private var header: some View {
        if let location {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { store.homeFolder = nil }
            } label: {
                Text("‹ \(location)")
                    .font(houseFont(16))
                    .foregroundStyle(inkStrong)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredHeader || dropTarget == .some(nil)
                                  ? panelColor : Color.clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to all notes (Esc)")
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.15)) { hoveredHeader = inside }
            }
            .onDrop(of: [UTType.plainText], isTargeted: dropBinding(nil)) { providers in
                dropNote(providers, into: nil)
            }
            .padding(.horizontal, 16) // the name lines up with the root's heading
            .padding(.bottom, 14)
        } else {
            Text(store.displayName.isEmpty ? "notes" : "\(store.displayName)'s notes")
                .font(houseFont(16))
                .foregroundStyle(brownInk)
                .frame(minHeight: 40)
                .padding(.horizontal, 26)
                .padding(.bottom, 14)
        }
    }

    // MARK: Folders

    private var folderGrid: some View {
        VStack(spacing: 8) {
            ForEach(Array(folderRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        switch item {
                        case .folder(let name): folderCell(name)
                        case .add: addFolderCell
                        }
                    }
                    // keep a short last row's tiles a third wide
                    ForEach(0..<(3 - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // The tile's own tint, folderBase on its paper, stepping down to panel
    // under the pointer or as a drop target — the phone's TileStyle.
    private func tileBackground(_ highlighted: Bool) -> some View {
        (highlighted ? panelColor : folderBaseColor)
            .papered(.folderTile)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var addFolderCell: some View {
        Button {
            folderDraft = ""
            creatingFolder = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(inkFaint)
                .frame(maxWidth: .infinity,
                       minHeight: folderCellHeight - folderCellPadding * 2,
                       maxHeight: folderCellHeight - folderCellPadding * 2)
                .padding(.vertical, folderCellPadding)
                .padding(.horizontal, 10)
                .background(tileBackground(hoveredAdd))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New folder")
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hoveredAdd = inside }
        }
    }

    private func folderCell(_ folder: String) -> some View {
        Button {
            guard renamingFolder != folder else { return }
            withAnimation(.easeOut(duration: 0.2)) { store.homeFolder = folder }
        } label: {
            // The name on the tile's foot, wrapping into all the room the tile
            // has before it is cut short — the tray's tile, larger.
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 6) {
                    if renamingFolder == folder {
                        HouseField(
                            text: $folderDraft, size: 13, alpha: 0.85,
                            focused: fieldFocused,
                            onSubmit: { finishRenaming(folder, to: folderDraft) },
                            onCancel: { renamingFolder = nil })
                            .frame(height: 16)
                            .onAppear { fieldFocused = true }
                            .onDisappear { fieldFocused = false }
                    } else {
                        Text(folder)
                            .font(houseFont(13))
                            .foregroundStyle(inkStrong)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .bottomLeading)
                        Circle()
                            .fill(store.currentFolder == folder ? openDotColor : Color.clear)
                            .frame(width: 6, height: 6)
                            .padding(.bottom, 5) // level with the last line's letters
                    }
                }
            }
            .frame(maxWidth: .infinity,
                   minHeight: folderCellHeight - folderCellPadding * 2,
                   maxHeight: folderCellHeight - folderCellPadding * 2,
                   alignment: .bottomLeading)
            .padding(.vertical, folderCellPadding)
            .padding(.horizontal, 10)
            .background(tileBackground(hoveredFolder == folder || dropTarget == .some(folder)))
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
                // The tray deletes outright; with a whole window of notes in
                // view, a folder holding some asks first, as on the phone.
                let holdsNotes = store.notes.contains { $0.folder == folder }
                if holdsNotes { confirmingDelete = folder } else { store.deleteFolder(folder) }
            }
        }
        .onDrop(of: [UTType.plainText], isTargeted: dropBinding(folder)) { providers in
            dropNote(providers, into: folder)
        }
    }

    private var folderNameField: some View {
        HouseField(
            text: $folderDraft, size: 13, alpha: 0.85,
            placeholder: "folder name",
            focused: fieldFocused,
            onSubmit: { finishCreatingFolder(folderDraft) },
            onCancel: {
                creatingFolder = false
                folderDraft = ""
            })
            .frame(height: 16)
            .onAppear { fieldFocused = true }
            .onDisappear { fieldFocused = false }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(tileBackground(false))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    // A name makes the folder; no name means it was never made.
    private func finishCreatingFolder(_ name: String) {
        guard creatingFolder else { return }
        creatingFolder = false
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.createFolder(name)
        }
        folderDraft = ""
    }

    // A rename left empty, or unchanged, keeps the old name.
    private func finishRenaming(_ folder: String, to name: String) {
        guard renamingFolder == folder else { return }
        renamingFolder = nil
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, clean != folder { _ = store.renameFolder(folder, to: clean) }
        folderDraft = ""
    }

    // A click on bare page ends a naming the way Return does.
    private func endEditing() {
        if creatingFolder { finishCreatingFolder(folderDraft) }
        if let folder = renamingFolder { finishRenaming(folder, to: folderDraft) }
    }

    // MARK: Notes

    // Gathered under the day they were last written in — made that day, or
    // edited then — newest day first, with a hairline between days. Reading a
    // note doesn't move it: only an edit changes its date.
    private var noteDays: [(day: Date, notes: [NoteMeta])] {
        let calendar = Calendar.current
        var days: [(day: Date, notes: [NoteMeta])] = []
        for note in visibleNotes { // already newest first
            let day = calendar.startOfDay(for: note.modified)
            if let last = days.indices.last, days[last].day == day {
                days[last].notes.append(note)
            } else {
                days.append((day, [note]))
            }
        }
        return days
    }

    private func dayTitle(_ day: Date) -> some View {
        Text(Self.dayName(day))
            .font(houseFont(12))
            .foregroundStyle(inkMuted)
            .padding(.horizontal, 26)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    private var daySeparator: some View {
        Rectangle()
            .fill(panelDividerColor)
            .frame(height: 1)
            .padding(.horizontal, 26)
            .padding(.vertical, 12)
    }

    // "today", "yesterday", the weekday within the last week, then the date —
    // with the year only when it isn't this one. Lowercase, like the rest of
    // the app's own words.
    private static func dayName(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "today" }
        if calendar.isDateInYesterday(day) { return "yesterday" }
        let today = calendar.startOfDay(for: .now)
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        let name: String
        if (2...6).contains(daysAgo) {
            name = day.formatted(.dateTime.weekday(.wide))
        } else if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
            name = day.formatted(.dateTime.day().month(.wide))
        } else {
            name = day.formatted(.dateTime.day().month(.wide).year())
        }
        return name.lowercased()
    }

    // The title; the day is in the heading above it. The open note keeps its
    // dot, as in the tray; the panel-toned box comes up under the pointer.
    private func noteRow(_ note: NoteMeta) -> some View {
        Button {
            store.open(note.id)
        } label: {
            HStack(spacing: 10) {
                Text(note.title)
                    .font(houseFont(14))
                    .foregroundStyle(inkStrong)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Circle()
                    .fill(note.id == store.currentID ? openDotColor : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoveredNote == note.id ? panelColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .onDrag { NSItemProvider(object: note.id as NSString) }
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) {
                if inside {
                    hoveredNote = note.id
                } else if hoveredNote == note.id {
                    hoveredNote = nil
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
                hoveredNote = nil
                withAnimation(.easeOut(duration: 0.15)) { store.delete(note.id) }
            }
        }
    }

    // MARK: Dragging a note

    private func dropBinding(_ folder: String?) -> Binding<Bool> {
        Binding(
            get: { dropTarget == .some(folder) },
            set: { targeted in
                withAnimation(.easeOut(duration: 0.15)) {
                    if targeted {
                        dropTarget = .some(folder)
                    } else if dropTarget == .some(folder) {
                        dropTarget = nil
                    }
                }
            })
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
