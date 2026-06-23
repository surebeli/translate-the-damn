import AppKit
import SwiftUI
import Foundation
import TranslateTheDamnCore

/// Dev-only visual-walkthrough harness. Inert unless `TTD_SHOT_KIND` is set (wired from
/// AppDelegate.main); a normal launch never touches it. Renders ONE window in a requested state +
/// appearance, writes its CGWindowID to `TTD_SHOT_READY`, and stays alive so an external
/// `screencapture -l<id>` grabs the real composited window (titlebar + vibrancy).
///
/// Env: TTD_SHOT_KIND (see switch), TTD_SHOT_APPEARANCE = light|dark, TTD_SHOT_READY = path.
@MainActor
final class ScreenshotHarness: NSObject, NSApplicationDelegate {
    private let kind: String
    private let appearance: String
    private let readyPath: String?
    private var settingsWindow: NSWindow?
    private var popup: TranslationPopupUI?

    private let srcShort = "A good translation tool stays invisible until you need it — then it is instantly useful."
    private let zhShort = "好的翻译工具在你需要之前保持隐形——需要时立即可用。"
    private let srcLong = String(repeating: "The quick brown fox jumps over the lazy dog, and a good translation tool stays out of your way until the very moment you need it. ", count: 5)
    private let zhLong = String(repeating: "敏捷的棕色狐狸跳过那只懒狗;好的翻译工具会一直避开你,直到你真正需要它的那一刻才出现。", count: 5)

    init(kind: String, appearance: String, readyPath: String?) {
        self.kind = kind; self.appearance = appearance; self.readyPath = readyPath
        super.init()
    }

    static func runIfRequested() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let kind = env["TTD_SHOT_KIND"] else { return false }
        let app = NSApplication.shared
        let h = ScreenshotHarness(kind: kind, appearance: env["TTD_SHOT_APPEARANCE"] ?? "light", readyPath: env["TTD_SHOT_READY"])
        app.delegate = h
        app.setActivationPolicy(.regular)
        app.run()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        NSApp.activate(ignoringOtherApps: true)
        var cfg = ConfigService.defaultConfig()
        cfg.popup.style = "acrylic"

        if kind.hasPrefix("popup") {
            let p = makePopup(cfg.popup)
            popup = p
            switch kind {
            case "popup-loading": p.showLoading()
            case "popup-large":   p.showResult(translation: zhLong, source: srcLong)
            case "popup-error":   p.showError(message: "翻译失败:claude 未登录或网络不可用(可在设置里「检测」后端)")
            case "popup-history":
                p.showResults([
                    PopupHistoryEntry(source: srcShort, translation: zhShort),
                    PopupHistoryEntry(source: "Second most recent source line.", translation: "第二近的源文本行。"),
                    PopupHistoryEntry(source: "Oldest cached entry.", translation: "最旧的缓存条目。"),
                ], index: 1)
            default:              p.showResult(translation: zhShort, source: srcShort)
            }
        } else {
            settingsWindow = makeSettingsWindow(&cfg)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.publish() }
    }

    private func makePopup(_ cfg: PopupConfig) -> TranslationPopupUI {
        let p = DSPopup(cfg: cfg, onCopy: { _ in })
        p.backendName = "claude"   // show the translation-source hint (header right) in the screenshots
        return p
    }

    private func makeSettingsWindow(_ cfg: inout AppConfig) -> NSWindow {
        switch kind {
        case "settings-http":
            cfg.general.activeBackend = "doubao"
        case "settings-custom", "settings-lamp-checking", "settings-lamp-ok", "settings-lamp-fail":
            cfg.backends["my-llm"] = BackendConfig(type: "http", model: "gpt-4o-mini", timeoutSec: 30,
                                                   endpoint: "https://api.example.com/v1", apiKey: "sk-secret",
                                                   protocol: "openai")
            cfg.general.activeBackend = "my-llm"
        default:
            cfg.general.activeBackend = "claude"  // settings-builtin
        }
        let vm = SettingsViewModel(config: cfg, configPath: NSTemporaryDirectory() + "ttd-shot.json", onSave: { _ in })
        switch kind {
        case "settings-lamp-checking": vm.doctorRunning = true; vm.doctorDetail = ""
        case "settings-lamp-ok":   vm.doctorStatus = .ok;   vm.doctorDetail = "已登录(本地凭据;未做联网验证)"
        case "settings-lamp-fail": vm.doctorStatus = .fail; vm.doctorDetail = "未登录(本地凭据检查未通过)"
        default: break
        }
        let hosting = NSHostingView(rootView: AnyView(DSSettingsView(vm: vm)))
        let size = hosting.fittingSize
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: max(560, size.width), height: max(560, size.height)),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let version = ProcessInfo.processInfo.environment["TTD_SHOT_VERSION"] ?? "0.3.1"
        win.title = "translate-the-damn · 设置   v" + version
        win.contentView = hosting
        win.center()
        win.makeKeyAndOrderFront(nil)
        return win
    }

    private func publish() {
        let n: Int
        if let panel = popup as? NSPanel { n = panel.windowNumber }
        else if let w = settingsWindow { n = w.windowNumber }
        else { n = NSApp.windows.first(where: { $0.isVisible })?.windowNumber ?? -1 }
        if let path = readyPath { try? "\(n)".write(toFile: path, atomically: true, encoding: .utf8) }
        NSLog("[ScreenshotHarness] kind=%@ appearance=%@ windowNumber=%d", kind, appearance, n)
    }
}
