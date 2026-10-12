import SwiftUI
import AppKit

// The home screen's sketch: the wide Valley, growing itself onto the page.
//
// It grows the way Strain grows it (DrawOn/, copied from Strain): a few seeds
// land at random, growth runs fast along lines and creeps slowly across bare
// paper, and the whole drawing is down in `duration` seconds. New seeds every
// play, so no two are alike.
//
// Home shows it in two places:
// - **An empty vault** — no notes and no folders: it grows into the space the
//   list would fill, every time home opens like that.
// - **The first visit** — the first time home is ever opened with notes in
//   it: it grows across the page on its own, holds a moment, then gives way
//   to the notes. A click or Escape skips it. `homeSketchSeen` remembers it
//   has been shown; an empty vault's first visit counts too.
//
// Drawn in the mood's ink at the muted step, on home's own paper: the
// artwork's colours and its paper are ignored, so it follows all six moods.
// Reduce Motion shows it whole, and skips the intro.
final class HomeSketch: ObservableObject {
    static let shared = HomeSketch()

    /// Seconds from the first mark to the last.
    static let duration: Double = 6
    /// How long the finished intro holds before the notes come in.
    static let introHold: Double = 1
    /// The artwork is 2000 wide with 1.6 lines; shown at home's width that
    /// would thin to half a point, so lines are kept at least this thick.
    static let minimumLineWidth: CGFloat = 1.1

    static let url = Bundle.main.url(forResource: "valley", withExtension: "svg",
                                     subdirectory: "HomeSketch")

    @Published private(set) var art: Artwork?
    @Published private(set) var growth: Growth?
    /// When the current growth started; nil until one is ready.
    @Published private(set) var startedAt: Date?
    /// The first-visit intro is up, and home's notes wait behind it.
    @Published private(set) var introShown = false

    private var art_: Artwork? // read off the main thread
    private var generation = 0

    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Grows the sketch again from new seeds. The first play also reads the
    /// artwork; both happen off the main thread, and the growth starts when
    /// they are done.
    func play() {
        guard let url = Self.url else { return }
        generation += 1
        let gen = generation
        let known = art_
        startedAt = nil
        DispatchQueue.global(qos: .userInitiated).async {
            guard let art = known ?? (try? Artwork(svgAt: url)) else { return }
            var settings = GrowthSettings()
            settings.duration = Self.duration
            let growth = Growth.grow(art, settings: settings)
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                self.art_ = art
                self.art = art
                self.growth = growth
                // Whole at once under Reduce Motion: started long ago.
                self.startedAt = self.reducesMotion ? .distantPast : Date()
                if self.introShown { self.endIntro(after: Self.duration + Self.introHold, gen) }
            }
        }
    }

    /// The first visit's intro: home's notes wait while the sketch grows.
    func playIntro() {
        guard Self.url != nil, !reducesMotion else { return }
        introShown = true
        play()
    }

    func skipIntro() {
        guard introShown else { return }
        withAnimation(.easeOut(duration: 0.6)) { introShown = false }
    }

    private func endIntro(after seconds: Double, _ gen: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard gen == self.generation else { return }
            self.skipIntro()
        }
    }

    func time(at date: Date) -> Double {
        guard let startedAt else { return 0 }
        return date.timeIntervalSince(startedAt)
    }
}

/// The sketch at the size it is given, its frame the drawing's own shape.
struct HomeSketchView: View {
    @ObservedObject var sketch: HomeSketch
    /// The mood's ink, handed in by a view that watches the mood.
    let ink: CGColor

    /// Stops asking for frames once the last mark is down.
    @State private var finished = false

    var body: some View {
        if let art = sketch.art, let growth = sketch.growth {
            TimelineView(.animation(paused: finished || sketch.startedAt == nil)) { tl in
                GrowthView(art: art, growth: growth, time: sketch.time(at: tl.date),
                           paper: false, ink: ink,
                           minimumLineWidth: HomeSketch.minimumLineWidth)
            }
            .aspectRatio(art.size.width / max(art.size.height, 1), contentMode: .fit)
            .task(id: sketch.startedAt) {
                finished = false
                guard let start = sketch.startedAt else { return }
                let left = HomeSketch.duration - Date().timeIntervalSince(start)
                if left > 0 { try? await Task.sleep(for: .seconds(left + 0.1)) }
                if !Task.isCancelled { finished = true }
            }
        } else {
            // Not read yet: hold the drawing's room so nothing jumps when it is.
            Color.clear.aspectRatio(2000.0 / 1298.0, contentMode: .fit)
        }
    }
}
