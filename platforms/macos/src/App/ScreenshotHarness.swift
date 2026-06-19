import AppKit
import Foundation
import TranslateTheDamnCore

/// Dev-only screenshot harness for the UI-style review doc.
///
/// Activated ONLY when `TTD_SHOT_KIND` is present in the environment (wired from
/// `AppDelegate.main()`); a normal launch never instantiates it, so production behavior is
/// unchanged. It renders exactly one window — a settings window or one popup — for a given
/// `uiStyle`, then writes that window's CGWindowID to `TTD_SHOT_READY` and stays alive so an
/// external `screencapture -l<id>` can grab the real composited window (titlebar + vibrancy).
///
/// Env contract:
///   TTD_SHOT_KIND        "settings" | "popup"
///   TTD_SHOT_STYLE       uiStyle: classic | ZP | km | O48 | Z | MM | DS
///   TTD_SHOT_POPUP_STYLE "acrylic" | "solid"  (popup kind only)
///   TTD_SHOT_READY       file path; harness writes the windowNumber here once on-screen
@MainActor
final class ScreenshotHarness: NSObject, NSApplicationDelegate {
    private let kind: String
    private let style: String
    private let popupStyle: String
    private let readyPath: String?
    private var settingsController: SettingsWindowController?
    private var popup: TranslationPopupUI?

    private let sampleSource = "The quick brown fox jumps over the lazy dog. A good translation tool stays invisible until you need it — then it is instantly useful, never in the way."
    private let sampleTranslation = "敏捷的棕色狐狸跳过那只懒狗。好的翻译工具在你需要之前保持隐形——需要时立即可用,从不碍事。"

    init(kind: String, style: String, popupStyle: String, readyPath: String?) {
        self.kind = kind
        self.style = style
        self.popupStyle = popupStyle
        self.readyPath = readyPath
    }

    /// Returns true (and runs the app to completion) when a screenshot run was requested.
    static func runIfRequested() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard let kind = env["TTD_SHOT_KIND"] else { return false }
        let app = NSApplication.shared
        let harness = ScreenshotHarness(
            kind: kind,
            style: env["TTD_SHOT_STYLE"] ?? "O48",
            popupStyle: env["TTD_SHOT_POPUP_STYLE"] ?? "acrylic",
            readyPath: env["TTD_SHOT_READY"]
        )
        app.delegate = harness
        app.setActivationPolicy(.regular)
        app.run()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        var config = ConfigService.defaultConfig()
        config.general.uiStyle = style
        config.popup.style = popupStyle
        // Keep the real default autoDismissSeconds (6s): capture happens ~1.4s after launch, well
        // before the dismiss timer fires, so the popup/settings render with their true defaults.

        NSApp.activate(ignoringOtherApps: true)

        if kind == "popup" {
            let p = makePopup(cfg: config.popup)
            p.showResult(translation: sampleTranslation, source: sampleSource)
            popup = p
        } else {
            let controller = SettingsWindowController(
                config: config,
                configPath: NSTemporaryDirectory() + "ttd-shot-config.json",
                onSave: { _ in }
            )
            controller.show()
            settingsController = controller
        }

        // Let layout + vibrancy compositing settle, then publish the window id for the capturer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.publishWindowID()
        }
    }

    private func publishWindowID() {
        let windowNumber: Int
        if kind == "popup", let panel = popup as? NSPanel {
            windowNumber = panel.windowNumber
        } else if let win = NSApp.windows.first(where: { $0.isVisible && $0.title == StringsLoader["settings.title"] }) {
            // Resize the settings window to its full natural content height so the entire page
            // (including the 通用 section's 界面风格 picker) is captured without a scroll fold.
            // Single-page Forms can be tall; clamp so a runaway layout can't produce a giant image.
            if let content = win.contentView {
                let fit = content.fittingSize
                let h = min(max(fit.height, 360), 1500)
                let w = max(fit.width, 560)
                win.setContentSize(NSSize(width: w, height: h))
                win.center()
            }
            windowNumber = win.windowNumber
        } else {
            windowNumber = NSApp.windows.first(where: { $0.isVisible })?.windowNumber ?? -1
        }
        if let path = readyPath {
            try? "\(windowNumber)".write(toFile: path, atomically: true, encoding: .utf8)
        }
        NSLog("[ScreenshotHarness] kind=%@ style=%@ popupStyle=%@ windowNumber=%d", kind, style, popupStyle, windowNumber)
    }

    private func makePopup(cfg: PopupConfig) -> TranslationPopupUI {
        let onCopy: (String) -> Void = { _ in }
        switch style {
        case "classic": return TranslationPopup(cfg: cfg) { onCopy($0) }
        case "ZP":      return ZPPopup(cfg: cfg) { onCopy($0) }
        case "Z":       return ZPopup(cfg: cfg) { onCopy($0) }
        case "km":      return KMPopup(cfg: cfg) { onCopy($0) }
        case "MM":      return MMPopup(cfg: cfg) { onCopy($0) }
        case "DS":      return DSPopup(cfg: cfg) { onCopy($0) }
        default:        return O48Popup(cfg: cfg) { onCopy($0) }
        }
    }
}
