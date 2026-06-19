import AppKit
import SwiftUI
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
///   TTD_SHOT_APPEARANCE  "light" | "dark"     (default light; forces NSApp.appearance)
///   TTD_SHOT_PAGE        "0".."3"             (O48 tab / KM sidebar page; ignored otherwise)
///   TTD_SHOT_READY       file path; harness writes the windowNumber here once on-screen
@MainActor
final class ScreenshotHarness: NSObject, NSApplicationDelegate {
    private let kind: String
    private let style: String
    private let popupStyle: String
    private let appearance: String
    private let page: Int
    private let readyPath: String?
    private var settingsWindow: NSWindow?
    private var popup: TranslationPopupUI?

    private let sampleSource = "The quick brown fox jumps over the lazy dog. A good translation tool stays invisible until you need it — then it is instantly useful, never in the way."
    private let sampleTranslation = "敏捷的棕色狐狸跳过那只懒狗。好的翻译工具在你需要之前保持隐形——需要时立即可用,从不碍事。"

    init(kind: String, style: String, popupStyle: String, appearance: String, page: Int, readyPath: String?) {
        self.kind = kind
        self.style = style
        self.popupStyle = popupStyle
        self.appearance = appearance
        self.page = page
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
            appearance: env["TTD_SHOT_APPEARANCE"] ?? "light",
            page: Int(env["TTD_SHOT_PAGE"] ?? "0") ?? 0,
            readyPath: env["TTD_SHOT_READY"]
        )
        app.delegate = harness
        app.setActivationPolicy(.regular)
        app.run()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force a deterministic appearance so dark-mode shots don't depend on the host system.
        NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)

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
            settingsWindow = makeSettingsWindow(config: config)
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
        } else if let win = settingsWindow {
            windowNumber = win.windowNumber
        } else {
            windowNumber = NSApp.windows.first(where: { $0.isVisible })?.windowNumber ?? -1
        }
        if let path = readyPath {
            try? "\(windowNumber)".write(toFile: path, atomically: true, encoding: .utf8)
        }
        NSLog("[ScreenshotHarness] kind=%@ style=%@ popupStyle=%@ appearance=%@ page=%d windowNumber=%d",
              kind, style, popupStyle, appearance, page, windowNumber)
    }

    /// Build the settings window directly (mirrors SettingsWindowController.show) so we can inject
    /// the appearance + initial page (O48 tab / KM sidebar) and resize to full content height.
    private func makeSettingsWindow(config: AppConfig) -> NSWindow {
        let vm = SettingsViewModel(config: config,
                                   configPath: NSTemporaryDirectory() + "ttd-shot-config.json",
                                   onSave: { _ in })
        let root: AnyView
        switch style {
        case "classic": root = AnyView(SettingsView(vm: vm))
        case "ZP":      root = AnyView(ZPSettingsView(vm: vm))
        case "Z":       root = AnyView(ZSettingsView(vm: vm))
        case "km":      root = AnyView(KMSettingsView(vm: vm, initialPage: page))
        case "MM":      root = AnyView(MMSettingsView(vm: vm))
        case "DS":      root = AnyView(DSSettingsView(vm: vm))
        default:        root = AnyView(O48SettingsView(vm: vm, initialTab: page))
        }
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame.size = hostingView.fittingSize

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                           styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = StringsLoader["settings.title"]
        win.contentView = hostingView
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)

        // Resize to natural content height so a single shot shows the whole page (clamped).
        if let content = win.contentView {
            let fit = content.fittingSize
            let h = min(max(fit.height, 360), 1500)
            let w = max(fit.width, 560)
            win.setContentSize(NSSize(width: w, height: h))
        }
        win.center()
        return win
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
