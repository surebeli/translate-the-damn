import AppKit
import Foundation
import TranslateTheDamnCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pipeline: TranslationPipeline?
    private var clipboardWatcher: ClipboardWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.mainMenu = buildMainMenu()

        let config = ConfigService.defaultConfig()
        pipeline = TranslationPipeline(backend: config.general.activeBackend, translator: NoOpTranslator())

        let filter = ClipboardFilter(maxChars: config.translation.maxChars)
        clipboardWatcher = ClipboardWatcher(filter: filter) { [pipeline] text in
            let model = config.backends[config.general.activeBackend]?.model ?? ""
            _ = pipeline?.run(text: text, model: model)
        }

        if config.general.listenClipboard {
            clipboardWatcher?.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
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
