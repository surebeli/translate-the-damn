import AppKit
import Foundation
import TranslateTheDamnCore

/// Menu-bar tray icon + context menu for translate-the-damn.
/// Owns the global "listen clipboard" switch: toggling persists to config and
/// starts/stops the clipboard watcher.
@MainActor
final class TrayController {
    private let statusItem: NSStatusItem
    private let listenMenuItem: NSMenuItem
    private let settingsMenuItem: NSMenuItem
    private let exitMenuItem: NSMenuItem
    private let watcher: ClipboardWatcher
    private let configPath: String
    private let openSettings: () -> Void

    private(set) var isListeningOn: Bool

    /// - Parameters:
    ///   - watcher: the clipboard watcher to start/stop.
    ///   - configPath: path used to persist the listen state.
    ///   - initialListenState: initial on/off state (mirrors `config.general.listenClipboard`).
    ///   - openSettings: callback invoked when the user chooses "打开设置…".
    init(
        watcher: ClipboardWatcher,
        configPath: String = ConfigService.defaultConfigPath,
        initialListenState: Bool,
        openSettings: @escaping () -> Void
    ) {
        self.watcher = watcher
        self.configPath = configPath
        self.openSettings = openSettings
        self.isListeningOn = initialListenState

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        listenMenuItem = NSMenuItem(
            title: StringsLoader["tray.menu.listen"],
            action: #selector(toggleListening(_:)),
            keyEquivalent: ""
        )
        settingsMenuItem = NSMenuItem(
            title: StringsLoader["tray.menu.settings"],
            action: #selector(openSettingsAction(_:)),
            keyEquivalent: ""
        )
        exitMenuItem = NSMenuItem(
            title: StringsLoader["tray.menu.exit"],
            action: #selector(terminate(_:)),
            keyEquivalent: ""
        )

        listenMenuItem.target = self
        settingsMenuItem.target = self
        exitMenuItem.target = self

        let menu = NSMenu(title: StringsLoader["tray.menu.listen"])
        menu.addItem(listenMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(settingsMenuItem)
        menu.addItem(exitMenuItem)

        statusItem.menu = menu
        // Colored "T" circle (green = listening / grey = paused), set per-state in updateState —
        // matches the Windows tray/app glyph (UI/AppIcon.cs).

        updateState(to: initialListenState, persist: false)
    }

    /// Re-apply localized text (menu item titles + state tooltip) after a UI-language hot-switch. Menu
    /// items are retained (state/targets preserved); only their StringsLoader-derived titles and the
    /// current-state tooltip are refreshed. Mirrors the settings window's locale hot-reload.
    func refreshLocalizedText() {
        listenMenuItem.title = StringsLoader["tray.menu.listen"]
        settingsMenuItem.title = StringsLoader["tray.menu.settings"]
        exitMenuItem.title = StringsLoader["tray.menu.exit"]
        statusItem.button?.toolTip = isListeningOn
            ? StringsLoader["tray.tooltip.listening"]
            : StringsLoader["tray.tooltip.paused"]
    }

    /// Programmatically turns listening on or off, persisting the change.
    func setListening(_ on: Bool) {
        guard on != isListeningOn else { return }
        updateState(to: on, persist: true)
    }

    private func updateState(to on: Bool, persist: Bool) {
        isListeningOn = on
        listenMenuItem.state = on ? .on : .off
        statusItem.button?.toolTip = on
            ? StringsLoader["tray.tooltip.listening"]
            : StringsLoader["tray.tooltip.paused"]
        statusItem.button?.image = TrayController.makeTrayImage(listening: on)

        if on {
            watcher.start()
        } else {
            watcher.stop()
        }

        if persist {
            persistListeningState(on: on)
        }
    }

    private func persistListeningState(on: Bool) {
        var cfg = ConfigService.load(from: configPath) ?? ConfigService.defaultConfig()
        cfg.general.listenClipboard = on
        try? ConfigService.save(cfg, to: configPath)
    }

    @objc private func toggleListening(_ sender: Any?) {
        setListening(!isListeningOn)
    }

    @objc private func openSettingsAction(_ sender: Any?) {
        openSettings()
    }

    @objc private func terminate(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    /// Tray glyph aligned with Windows (UI/AppIcon.cs `AppIcon.Tray`): a bold white "T" in a filled
    /// circle — green (#2EA043) when listening, grey (#787878) when paused. Colored (non-template)
    /// so the green/grey state reads the same as on Windows.
    private static func makeTrayImage(listening: Bool) -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let fill = listening
                ? NSColor(srgbRed: 46.0 / 255, green: 160.0 / 255, blue: 67.0 / 255, alpha: 1)
                : NSColor(srgbRed: 120.0 / 255, green: 120.0 / 255, blue: 120.0 / 255, alpha: 1)
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size * 0.6, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let str = NSAttributedString(string: "T", attributes: attrs)
            let s = str.size()
            str.draw(at: NSPoint(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2))
            return true
        }
        image.isTemplate = false  // colored green/grey like Windows, not a monochrome menu-bar template
        return image
    }
}
