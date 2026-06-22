import AppKit
import Foundation
import TranslateTheDamnCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // SwiftPM executable has no main.storyboard/nib, so @main's synthesized
    // NSApplicationMain would run NSApplication WITHOUT setting this class as the
    // delegate ⇒ applicationDidFinishLaunching would never fire (no tray/hotkey/etc.).
    // Provide an explicit main() that wires the delegate + activation policy + run loop.
    static func main() {
        // Dev-only visual-walkthrough harness — inert unless TTD_SHOT_KIND is set.
        if ScreenshotHarness.runIfRequested() { return }
        // Dev-only live end-to-end check (mirrors Windows --live): translate once via one backend, exit.
        let cliArgs = CommandLine.arguments
        if let i = cliArgs.firstIndex(of: "--live") {
            let backendId = (i + 1 < cliArgs.count) ? cliArgs[i + 1] : "claude"
            let extra = cliArgs[(i + 2)...].joined(separator: " ")
            let sample = extra.isEmpty ? "Hello, world. The TranslationPipeline supersedes any in-flight request." : extra
            LiveCheck.run(backendId: backendId, sample: sample)
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
    private var pipeline: TranslationPipeline?
    // The model the retained pipeline was built with — bound to the pipeline's lifetime so the
    // cache key (text+backend+model) is STABLE across presses. Mirrors Windows (model lives on the
    // retained pipeline's config); re-reading it from disk per press decoupled the key from the
    // pipeline's frozen backend and could defeat the recent-translation cache (spec §4.1 main case:
    // repeated hotkey on unchanged content must be a HIT, not a re-translate).
    private var pipelineModel: String = ""
    private var registry: TranslatorRegistry?
    private var clipboardWatcher: ClipboardWatcher?
    private var hotkeyService: HotkeyService?
    private var trayController: TrayController?
    private var settingsWindowController: SettingsWindowController?
    private var popup: TranslationPopupUI?
    private let configPath = ConfigService.defaultConfigPath
    private let loginService = LoginService.shared
    private let translationQueue = DispatchQueue(label: "com.translatethedamn.translation", qos: .userInitiated)
    private var currentTranslationId: UUID = UUID()
    private let translationLock = NSLock()
    private let processRunner = ProcessRunner()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let app = NSApplication.shared
        app.mainMenu = buildMainMenu()

        ensureSandboxDirectory()

        let config = ConfigService.load(from: configPath) ?? ConfigService.defaultConfig()

        registry = TranslatorRegistry()
        pipeline = buildPipeline(from: config, registry: registry!)

        popup = createPopup(config: config)

        let filter = ClipboardFilter(maxChars: config.translation.maxChars)
        let watcher = ClipboardWatcher(filter: filter) { [weak self] text in
            self?.translate(text: text)
        }
        clipboardWatcher = watcher

        if config.general.listenClipboard {
            watcher.start()
        }

        loginService.setEnabled(config.general.startWithWindows)

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
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            NSLog("[AppDelegate] Translate hotkey: no text on clipboard")
            return
        }
        translate(text: text)
    }

    private func onToggleListenHotkey() {
        guard let tray = trayController else { return }
        tray.setListening(!tray.isListeningOn)
        NSLog("[AppDelegate] Toggle listen: %@", tray.isListeningOn ? "started" : "stopped")
    }

    private func translate(text: String) {
        guard let currentPipeline = pipeline, let currentPopup = popup else { return }

        processRunner.cancelCurrentProcess()

        currentPopup.showLoading()

        let id = UUID()
        translationLock.lock()
        currentTranslationId = id
        translationLock.unlock()

        // Use the pipeline-bound model (set in buildPipeline), NOT a fresh per-press disk reload —
        // the cache key must stay stable so an identical repeat press HITS the cache (spec §4.1).
        let model = pipelineModel

        let runner = PipelineRunner(pipeline: currentPipeline)

        translationQueue.async { [weak self] in
            let result = runner.pipeline.run(text: text, model: model)
            let ok = result.ok
            let resultText = result.text
            let resultStatus = result.status
            let resultDetail = result.detail
            // Snapshot the recent-translation cache (newest first) on this serial queue, so the
            // popup can offer ◀ ▶ history navigation (spec §4.1/§8).
            let history = runner.pipeline.recentHistory()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.translationLock.lock()
                let isCurrent = self.currentTranslationId == id
                self.translationLock.unlock()

                guard isCurrent else { return }

                let finalResult = TranslationResult(ok: ok, text: resultText, status: resultStatus, detail: resultDetail)
                if finalResult.ok {
                    let entries = history.map { PopupHistoryEntry(source: $0.source, translation: $0.translation) }
                    self.popup?.showResults(entries, index: 0)
                } else {
                    self.popup?.showError(message: finalResult.text)
                }
            }
        }
    }

    private func openSettings() {
        // Create a fresh controller from the latest on-disk config so re-opening
        // settings reflects prior saves (the previous controller is replaced).
        settingsWindowController = SettingsWindowController(
            config: ConfigService.load(from: configPath) ?? ConfigService.defaultConfig(),
            configPath: configPath,
            onSave: { [weak self] config in
                self?.hotReload(config: config)
            }
        )
        settingsWindowController?.show()
    }

    private func hotReload(config: AppConfig) {
        loginService.setEnabled(config.general.startWithWindows)
        reregisterHotkeys(config: config)
        if config.general.listenClipboard {
            clipboardWatcher?.start()
        } else {
            clipboardWatcher?.stop()
        }
        pipeline = buildPipeline(from: config, registry: registry!)
        // Dismiss the old popup (if visible) to avoid a ghost window, then recreate it so
        // style/autoDismiss/keepOnHover changes take effect immediately.
        popup?.dismiss()
        popup = createPopup(config: config)
    }

    private func buildPipeline(from config: AppConfig, registry: TranslatorRegistry) -> TranslationPipeline {
        let backendId = config.general.activeBackend
        // Bind the cache-key model to this pipeline build (stable across presses until a settings
        // save rebuilds the pipeline — at which point a fresh cache is expected anyway).
        pipelineModel = config.backends[backendId]?.model ?? ""
        // Resolve the unified target language ONCE ({target} -> translation.targetLanguage) before the
        // template reaches the translators — mirrors Windows TranslatorRegistry.Build. Without this the
        // prompt would contain a literal "{target}".
        let resolvedTemplate = PromptBuilder.withTarget(config.translation.promptTemplate, config.translation.targetLanguage)
        if let backendConfig = config.backends[backendId],
           let translator = registry.translator(for: backendId, config: backendConfig, promptTemplate: resolvedTemplate, runner: processRunner) {
            return TranslationPipeline(backend: backendId, translator: translator)
        }
        return TranslationPipeline(backend: backendId, translator: MissingTranslator(backendId: backendId))
    }

    private func ensureSandboxDirectory() {
        let sandboxPath = NSTemporaryDirectory() + "ttd-sandbox"
        try? FileManager.default.createDirectory(atPath: sandboxPath, withIntermediateDirectories: true, attributes: nil)
    }

    private func createPopup(config: AppConfig) -> TranslationPopupUI {
        // Single finalized UI ("clean" style). The other six styles and the uiStyle switch
        // were removed; config.general.uiStyle is retained (nil-default) only for back-compat.
        let onCopy: (String) -> Void = { [weak self] text in
            self?.clipboardWatcher?.markSelfWrite(text)
        }
        return DSPopup(cfg: config.popup) { onCopy($0) }
    }

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu(title: "MainMenu")

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

private struct MissingTranslator: Translator {
    let backendId: String
    func translate(text: String, model: String) -> TranslationResult {
        .failed(.notFound, "未找到后端 \(backendId) 的翻译器，请在设置中重选后端。")
    }
}

private struct PipelineRunner: @unchecked Sendable {
    let pipeline: TranslationPipeline
}

extension TranslationPipeline: @unchecked Sendable {}
extension TranslationResult: @unchecked Sendable {}
