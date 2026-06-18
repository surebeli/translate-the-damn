import AppKit
import Foundation
import TranslateTheDamnCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pipeline: TranslationPipeline?
    private var clipboardWatcher: ClipboardWatcher?
    private var hotkeyService: HotkeyService?
    private var trayController: TrayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.mainMenu = buildMainMenu()

        let config = ConfigService.defaultConfig()
        pipeline = TranslationPipeline(backend: config.general.activeBackend, translator: NoOpTranslator())

        let filter = ClipboardFilter(maxChars: config.translation.maxChars)
        let watcher = ClipboardWatcher(filter: filter) { [pipeline] text in
            let model = config.backends[config.general.activeBackend]?.model ?? ""
            _ = pipeline?.run(text: text, model: model)
        }
        clipboardWatcher = watcher

        if config.general.listenClipboard {
            watcher.start()
        }

        trayController = TrayController(
            watcher: watcher,
            initialListenState: config.general.listenClipboard,
            openSettings: { [weak self] in self?.openSettings() }
        )

        hotkeyService = HotkeyService()
        registerHotkeys(from: config)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService?.unregister()
    }

    func reregisterHotkeys(config: AppConfig) {
        hotkeyService?.unregister()
        hotkeyService = HotkeyService()
        registerHotkeys(from: config)
    }

    private func registerHotkeys(from config: AppConfig) {
        let translateResult = hotkeyService?.register(hotkeyString: config.hotkey.translate) { [weak self] in
            self?.onTranslateHotkey()
        }
        if translateResult == false {
            NSLog("[AppDelegate] Failed to register translate hotkey '%@'", config.hotkey.translate)
        }

        let toggleListen = config.hotkey.toggleListen
        if !toggleListen.isEmpty {
            let toggleResult = hotkeyService?.registerToggleListen(hotkeyString: toggleListen) { [weak self] in
                self?.onToggleListenHotkey()
            }
            if toggleResult == false {
                NSLog("[AppDelegate] Failed to register toggle-listen hotkey '%@'", toggleListen)
            }
        }
    }

    private func onTranslateHotkey() {
        guard let pipeline = pipeline else { return }
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            NSLog("[AppDelegate] Translate hotkey: no text on clipboard")
            return
        }
        let config = ConfigService.defaultConfig()
        let model = config.backends[config.general.activeBackend]?.model ?? ""
        let result = pipeline.run(text: text, model: model)
        NSLog("[AppDelegate] Translate hotkey result: %@", result.text)
    }

    private func onToggleListenHotkey() {
        guard let tray = trayController else { return }
        tray.setListening(!tray.isListeningOn)
        NSLog("[AppDelegate] Toggle listen: %@", tray.isListeningOn ? "started" : "stopped")
    }

    private func openSettings() {
        // Settings window lands in a later task; for now the tray callback is wired.
        NSLog("[AppDelegate] Open settings requested")
    }

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu(title: "MainMenu")

        // App menu: About + Quit.
        let appMenu = NSMenu(title: "TranslateTheDamn")
        let appMenuItem = NSMenuItem(title: "TranslateTheDamn", action: nil, keyEquivalent: "")
        appMenuItem.submenu = appMenu

        appMenu.addItem(
            NSMenuItem(
                title: "Quit TranslateTheDamn",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        // Minimal Edit menu so text fields behave later.
        let editMenu = NSMenu(title: "Edit")
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(editMenuItem)
        return mainMenu
    }
}

// M3 stub: the real translator backends land in later tasks; for now the watcher wires into the
// pipeline so the assembly and clipboard path compile and run end-to-end.
private struct NoOpTranslator: Translator {
    func translate(text: String, model: String) -> TranslationResult {
        .successful(text)
    }
}
