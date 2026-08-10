import SwiftUI
import AppKit

// First run, as drawn in Figma (node 243:120 — Screens One to Four): a letter
// tucked into an envelope. The title shows through the flap's V; after a beat
// the letter slides up out of the envelope to reveal the controls, and the
// remaining steps swap the letter's contents.
//
// Geometry is transcribed from the design in its own pixel units (see `D`) and
// multiplied by one scale factor, so the composition keeps the design's
// aspect ratio at whatever size the window allows. Colours defer to the app's
// existing tokens wherever the design was within a shade of them; only the
// envelope and the letter are new.

let envelopeColor = Color(red: 235 / 255, green: 206 / 255, blue: 163 / 255) // #EBCEA3
let letterColor = Color(red: 255 / 255, green: 250 / 255, blue: 243 / 255) // #FFFAF3

let onboardingLogo: NSImage? = {
    guard let url = Bundle.main.url(forResource: "OnboardingLogo", withExtension: "png")
    else { return nil }
    return NSImage(contentsOf: url)
}()

// Design values, verbatim from the Figma frames.
private enum D {
    static let envW: CGFloat = 915
    static let envH: CGFloat = 593
    static let notch: CGFloat = 250 // depth of the flap's V, apex on centre

    static let letterW: CGFloat = 882
    static let letterH: CGFloat = 777
    static let letterX: CGFloat = 16
    static let letterTucked: CGFloat = -184 // Screen One
    static let letterRaised: CGFloat = -465 // Screens Two–Four

    static let contentX: CGFloat = 166
    static let contentW: CGFloat = 551
    static let contentY: CGFloat = 223
    static let contentGap: CGFloat = 32
    static let primaryY: CGFloat = 457
    static let backY: CGFloat = 531
    static let controlH: CGFloat = 55

    static let radius: CGFloat = 16 // design's pill roundness, as a ratio of height

    static let sprigW: CGFloat = 105.877
    static let sprigH: CGFloat = 158.092
    static let sprigCX: CGFloat = 458
    static let sprigCY: CGFloat = 427

    // tallest the composition ever gets: raised letter above the envelope
    static var assemblyH: CGFloat { -letterRaised + envH }
}

// Type and control sizing come from the app's own scale (main.swift uses
// 10/11/12/13/14/16), not from the mock's 34/24 — the design was drawn on a
// 1600px canvas, so lifting its numbers literally made onboarding shout next
// to the editor. Held at fixed point sizes so they read identically to the
// rest of the app, easing down only if the window gets too small to fit them.
private enum T {
    static let title: CGFloat = 16 // the app's largest text, same as the editor body
    static let control: CGFloat = 13 // panels, search rows, stickies
    static let back: CGFloat = 12 // settings labels
    static let controlH: CGFloat = 30
    static let controlRadius: CGFloat = 8
    static let controlPadH: CGFloat = 16
    static let referenceScale: CGFloat = 0.7 // scene scale at a normal window
}

private var prefersReducedMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

// The envelope's front: a rectangle with a triangular notch taken out of the
// top, so the letter behind shows through the opening.
struct EnvelopeFront: Shape {
    let notchDepth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + notchDepth))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct OnboardingView: View {
    @ObservedObject var store: NotesStore

    private enum Step { case welcome, name, vault }

    @State private var step: Step = .welcome
    @State private var presented = false // the envelope has risen into place
    @State private var letterRaised = false
    @State private var finishing = false
    @State private var closing = false // the envelope is sinking back out
    @State private var sceneOpacity: Double = 0
    @State private var name = ""
    @State private var chosenVault: URL?
    @FocusState private var nameFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let s = scale(for: geo.size)
            ZStack {
                // Same dim as the ⌘K palette; it also swallows every click so
                // nothing behind can be reached until this is finished.
                sheetColor.opacity(0.8)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}

                // Wrapped in a full-size container so the scale anchors on the
                // window's centre rather than the envelope's own frame.
                ZStack {
                    envelope(s)
                        .offset(y: envelopeOffset(s))
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(sceneScale)
                .offset(y: sceneTravel(geo.size.height))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Flatten before fading, or the half-transparent layers let the
            // controls behind the envelope ghost through mid-animation.
            .compositingGroup()
            .opacity(sceneOpacity)
            .allowsHitTesting(!finishing)
        }
        .ignoresSafeArea()
        .onExitCommand {} // Escape must not skip onboarding
        .onAppear(perform: runIntro)
    }

    // Arrives from below at half size and grows into place; leaves the same way
    // in reverse.
    private var sceneScale: CGFloat {
        if closing { return 0.5 }
        return presented ? 1 : 0.5
    }

    private func sceneTravel(_ height: CGFloat) -> CGFloat {
        if closing { return height * 0.55 }
        return presented ? 0 : height * 0.55
    }

    // Point sizes hold steady at normal window sizes so they match the app
    // exactly; they only ease down when the scene itself is squeezed.
    private func type(_ base: CGFloat, _ s: CGFloat) -> CGFloat {
        base * min(1, s / T.referenceScale)
    }

    // MARK: Composition

    private func envelope(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // the envelope's inside, visible once the letter has risen past it
            Rectangle()
                .fill(envelopeColor)
                .frame(width: D.envW * s, height: D.envH * s)

            letter(s)
                .offset(x: D.letterX * s, y: letterOffset * s)

            EnvelopeFront(notchDepth: D.notch * s)
                .fill(envelopeColor)
                .frame(width: D.envW * s, height: D.envH * s)

            if let sprig = onboardingLogo {
                Image(nsImage: sprig)
                    .resizable()
                    .frame(width: D.sprigW * s, height: D.sprigH * s)
                    .offset(
                        x: (D.sprigCX - D.sprigW / 2) * s,
                        y: (D.sprigCY - D.sprigH / 2) * s)
            }
        }
        .frame(width: D.envW * s, height: D.envH * s, alignment: .topLeading)
    }

    private func letter(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(letterColor)
                .frame(width: D.letterW * s, height: D.letterH * s)

            // On the way out the letter goes back in blank, like it's being
            // put away.
            Group {
                switch step {
                case .welcome:
                    title("a calm place\nto write", s)
                        .frame(width: D.letterW * s)
                        .offset(y: D.contentY * s)
                case .name:
                    VStack(spacing: D.contentGap * s) {
                        title("let’s start\nwith your name,", s)
                        nameField(s)
                    }
                    .frame(width: D.contentW * s)
                    .offset(x: D.contentX * s, y: D.contentY * s)
                case .vault:
                    VStack(spacing: D.contentGap * s) {
                        title("where should\nyour notes live?", s)
                        vaultPill(s)
                    }
                    .frame(width: D.contentW * s)
                    .offset(x: D.contentX * s, y: D.contentY * s)
                }

                primaryButton(s)
                    .frame(width: D.letterW * s, alignment: .center)
                    .offset(y: D.primaryY * s)

                if step != .welcome {
                    backButton(s)
                        .frame(width: D.letterW * s, alignment: .center)
                        .offset(y: D.backY * s)
                }
            }
            .opacity(finishing ? 0 : 1)
        }
        .frame(width: D.letterW * s, height: D.letterH * s, alignment: .topLeading)
    }

    // MARK: Pieces

    private func title(_ text: String, _ s: CGFloat) -> some View {
        Text(text)
            .font(.custom("Courier", size: type(T.title, s)))
            .foregroundStyle(brownInk)
            .multilineTextAlignment(.center)
            .lineSpacing(type(4, s))
            .fixedSize(horizontal: false, vertical: true)
    }

    // macOS ignores TextField prompt styling, so the placeholder is drawn by
    // hand — same trick as the search palette.
    private func nameField(_ s: CGFloat) -> some View {
        ZStack {
            if name.isEmpty {
                Text("your name")
                    .font(.custom("Courier", size: type(T.control, s)))
                    .foregroundStyle(brownInk.opacity(0.4))
                    .allowsHitTesting(false)
            }
            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(.custom("Courier", size: type(T.control, s)))
                .foregroundStyle(brownInk)
                .multilineTextAlignment(.center)
                .focused($nameFocused)
                .onSubmit { if canAdvance { advance() } }
        }
        .padding(.horizontal, type(T.controlPadH, s))
        .frame(width: D.contentW * s, height: type(T.controlH, s))
        .background(
            RoundedRectangle(cornerRadius: type(T.controlRadius, s)).fill(sheetColor))
    }

    // The pill itself opens the folder picker, as the settings vault card does.
    private func vaultPill(_ s: CGFloat) -> some View {
        Button(action: pickVault) {
            Text(vaultDisplay)
                .font(.custom("Courier", size: type(T.control, s)))
                .foregroundStyle(brownInk)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, type(T.controlPadH, s))
                .frame(width: D.contentW * s, height: type(T.controlH, s))
                .background(
                    RoundedRectangle(cornerRadius: type(T.controlRadius, s)).fill(sheetColor))
                .contentShape(RoundedRectangle(cornerRadius: type(T.controlRadius, s)))
        }
        .buttonStyle(.plain)
        .arrowCursorZone()
    }

    private func primaryButton(_ s: CGFloat) -> some View {
        OnboardingPill(
            title: primaryTitle,
            fontSize: type(T.control, s),
            height: type(T.controlH, s),
            radius: type(T.controlRadius, s),
            padH: type(T.controlPadH, s),
            enabled: canAdvance,
            action: advance)
        .keyboardShortcut(step == .name ? nil : KeyboardShortcut.defaultAction)
    }

    private func backButton(_ s: CGFloat) -> some View {
        Button(action: goBack) {
            Text("back")
                .font(.custom("Courier", size: type(T.back, s)))
                .foregroundStyle(brownInk.opacity(0.55))
                .padding(.vertical, type(6, s))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .arrowCursorZone()
    }

    // MARK: Layout maths

    // One factor for the whole scene, so the design's proportions survive at
    // any window size.
    private func scale(for size: CGSize) -> CGFloat {
        let byWidth = (size.width * 0.82) / D.envW
        let byHeight = (size.height * 0.84) / D.assemblyH
        return max(min(byWidth, byHeight), 0.2)
    }

    private var letterOffset: CGFloat {
        letterRaised ? D.letterRaised : D.letterTucked
    }

    // Keeps the letter-plus-envelope composition centred, which is why the
    // envelope drifts down as the letter rises (exactly as the frames do).
    // The envelope's own frame is centred by the ZStack, so shifting it by half
    // the letter's overhang puts the midpoint of the whole assembly on centre.
    private func envelopeOffset(_ s: CGFloat) -> CGFloat {
        -letterOffset * s / 2
    }

    // MARK: State

    private var primaryTitle: String {
        switch step {
        case .welcome: return "begin"
        case .name: return "next"
        case .vault: return "next"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .welcome, .vault: return true
        case .name: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var vaultDisplay: String {
        let url = chosenVault ?? NotesStore.defaultVaultDir
        return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: Behaviour

    // The envelope rises into view first, then — Screen One → Two — the letter
    // is drawn up out of it.
    private func runIntro() {
        if prefersReducedMotion {
            presented = true
            letterRaised = true
            sceneOpacity = 1
            return
        }
        withAnimation(.easeOut(duration: 0.55)) {
            presented = true
            sceneOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 0.75)) { letterRaised = true }
        }
    }

    private func advance() {
        guard canAdvance else { return }
        switch step {
        case .welcome:
            transition(to: .name)
        case .name:
            store.setDisplayName(name)
            transition(to: .vault)
        case .vault:
            finish()
        }
    }

    private func goBack() {
        switch step {
        case .welcome: break // step one never rewinds into the animation
        case .name: transition(to: .welcome)
        case .vault: transition(to: .name)
        }
    }

    private func transition(to next: Step) {
        if prefersReducedMotion {
            step = next
        } else {
            withAnimation(.easeInOut(duration: 0.22)) { step = next }
        }
        DispatchQueue.main.async { nameFocused = (next == .name) }
    }

    private func pickVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = chosenVault ?? NotesStore.defaultVaultDir
        panel.prompt = "Use as Vault"
        panel.message = "Choose the folder where notes are stored"
        if panel.runModal() == .OK, let url = panel.url {
            chosenVault = url
        }
    }

    // The flow closes the way it opened, in reverse: the letter slides back
    // into the envelope, then the envelope sinks away and shrinks as it fades.
    private func finish() {
        guard !finishing else { return }
        store.setDisplayName(name)
        // Only relocate when they actually chose somewhere else — otherwise the
        // existing vault is left exactly as it is.
        if let chosen = chosenVault, chosen != store.dir {
            store.changeVault(to: chosen)
        }
        guard !prefersReducedMotion else {
            store.completeOnboarding()
            return
        }
        finishing = true
        nameFocused = false
        withAnimation(.easeInOut(duration: 0.7)) { letterRaised = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeIn(duration: 0.5)) {
                closing = true
                sceneOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                store.completeOnboarding()
            }
        }
    }
}

// The design's pill button, with the folder cards' hover tint so it behaves
// like the rest of the app's furniture.
struct OnboardingPill: View {
    let title: String
    let fontSize: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let padH: CGFloat
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("Courier", size: fontSize))
                .foregroundStyle(brownInk.opacity(enabled ? 1 : 0.3))
                .padding(.horizontal, padH)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: radius)
                        .fill(background)
                )
                .contentShape(RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 && enabled }
        .arrowCursorZone()
    }

    private var background: Color {
        guard enabled else { return folderBaseColor.opacity(0.5) }
        return hovering ? sheetColor : folderBaseColor
    }
}
