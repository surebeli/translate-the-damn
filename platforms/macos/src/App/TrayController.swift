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
        let settingsMenuItem = NSMenuItem(
            title: StringsLoader["tray.menu.settings"],
            action: #selector(openSettingsAction(_:)),
            keyEquivalent: ""
        )
        let exitMenuItem = NSMenuItem(
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
        statusItem.button?.image = TrayController.makeTemplateImage()
        statusItem.button?.imagePosition = .imageOnly

        updateState(to: initialListenState, persist: false)
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

    private static func makeTemplateImage() -> NSImage {
        if #available(macOS 11.0, *) {
            if let image = NSImage(
                systemSymbolName: "character",
                accessibilityDescription: StringsLoader["tray.menu.listen"]
            ) {
                image.isTemplate = true
                return image
            }
        }

        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            let str = NSAttributedString(string: "文", attributes: attrs)
            let size = str.size()
            let point = NSPoint(
                x: (rect.width - size.width) / 2,
                y: (rect.height - size.height) / 2
            )
            str.draw(at: point)
            return true
        }
        image.isTemplate = true
        return image
    }
}
