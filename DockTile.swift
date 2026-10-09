import AppKit

// The Dock tile plug-in: draws JUI's icon in the Dock while JUI isn't running.
//
// The icon follows the mood (`AppIcon` in Theme.swift). While the app runs it
// sets its own tile, but once it quits the Dock goes back to a picture of the
// icon it cached — the previous mood's, if the mood changed. The only public
// way to clear that cache is to restart the Dock, which made the whole Dock
// vanish for a moment on every quit after a change of mood. A Dock tile
// plug-in is Apple's mechanism for exactly this: the Dock loads it for the
// app's tile and lets it draw the tile while the app is not running.
//
// Built by build.sh into Contents/PlugIns/JUIDockTile.docktileplugin and named
// by the app's NSDockTilePlugIn key. It runs inside the Dock, not inside JUI,
// so everything it needs is read from where the app leaves it: the mood from
// the app's preferences, the icons from the app's bundle. The app also posts a
// distributed notification when the mood changes, carrying it, so the tile
// keeps up without waiting on preferences to sync.
@objc(JUIDockTilePlugIn)
final class JUIDockTilePlugIn: NSObject, NSDockTilePlugIn {
    static let moodChanged = Notification.Name("com.nidhin.jui.moodChanged")

    private var tile: NSDockTile?
    private var observer: NSObjectProtocol?

    // The app this plug-in sits in: …/JUI.app/Contents/PlugIns/<this>.
    private lazy var app: Bundle? = {
        let url = Bundle(for: JUIDockTilePlugIn.self).bundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // JUI.app
        return Bundle(url: url)
    }()

    func setDockTile(_ dockTile: NSDockTile?) {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        tile = dockTile
        guard dockTile != nil else { return }
        NSLog("JUIDockTile: loaded for %@", app?.bundlePath ?? "?")
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.moodChanged, object: nil, queue: .main
        ) { [weak self] note in
            self?.draw(mood: note.userInfo?["mood"] as? String)
        }
        draw(mood: nil)
    }

    /// The mood the app last saved, read fresh from its preferences.
    private func savedMood() -> String? {
        guard let id = app?.bundleIdentifier else { return nil }
        CFPreferencesAppSynchronize(id as CFString)
        return CFPreferencesCopyAppValue("themeID" as CFString, id as CFString) as? String
    }

    private func draw(mood given: String?) {
        guard let tile else { return }
        let mood = given ?? savedMood() ?? "cream"
        guard let url = app?.url(forResource: mood, withExtension: "png", subdirectory: "AppIcons")
                ?? app?.url(forResource: "cream", withExtension: "png", subdirectory: "AppIcons"),
              let image = NSImage(contentsOf: url) else {
            NSLog("JUIDockTile: no icon for %@", mood)
            return
        }
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        tile.contentView = view
        tile.display()
        NSLog("JUIDockTile: drew %@", mood)
    }
}
