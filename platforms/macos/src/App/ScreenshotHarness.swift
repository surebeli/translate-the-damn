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

    // Every popup that shows text demonstrates the built-in rule "English source → keep professional
    // terms in English, translate the rest", spread across CS / medical / legal domains.
    private let srcShort = "If the OAuth token is expired, the API returns 401 — refresh it before retrying the request."   // CS
    private let zhShort = "如果 OAuth token 过期,API 会返回 401——重试请求前先刷新它。"
    private let srcMed = "Start atorvastatin 20 mg nightly, then recheck LDL-C and ALT after eight weeks."                    // medical
    private let zhMed = "每晚服用 atorvastatin 20 mg,八周后复查 LDL-C 和 ALT。"
    private let srcLegal = "Under GDPR Article 17, the data subject may request erasure, and the controller must comply without undue delay."  // legal (short)
    private let zhLegal = "根据 GDPR Article 17,data subject 可请求删除,controller 须无不当拖延地执行。"
    private let srcLong = "Pursuant to Section 12 of the Agreement, the indemnifying Party shall hold the Indemnitee harmless from any liability arising under the SLA, provided that written notice is delivered within thirty (30) days. This clause survives termination and is governed by the laws of the State of Delaware."  // legal (long)
    private let zhLong = "根据本协议第 12 条(Section 12),赔偿方应使 Indemnitee 免于因 SLA 产生的任何责任,前提是在三十(30)日内送达书面通知。本条款在终止后依然有效,并受 Delaware 州法律管辖。"

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
        // Dev harness locale: default zh-CN so the promo screenshot pipeline stays Chinese; set
        // TTD_SHOT_LOCALE=en|ja|ko to render the localized UI for i18n verification.
        StringsLoader.configure(localeId: ProcessInfo.processInfo.environment["TTD_SHOT_LOCALE"] ?? "zh-CN")
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
                    PopupHistoryEntry(source: srcShort, translation: zhShort),   // CS (newest)
                    PopupHistoryEntry(source: srcMed, translation: zhMed),        // medical (shown)
                    PopupHistoryEntry(source: srcLegal, translation: zhLegal),    // legal (oldest)
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
        case "settings-backends":
            cfg.backends["my-llm"] = BackendConfig(type: "http", model: "gpt-4o-mini", timeoutSec: 30,
                                                   endpoint: "https://api.example.com/v1", apiKey: "sk-secret",
                                                   protocol: "openai")
            cfg.general.activeBackend = "claude"   // open dropdown: show the full list, claude (CLI) checked
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
        let rootView: AnyView = kind == "settings-backends"
            ? AnyView(BackendDropdownShowcase(vm: vm))
            : AnyView(DSSettingsView(vm: vm))
        let hosting = NSHostingView(rootView: rootView)
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

/// Screenshot-only: the real config page (DSSettingsView) with the 后端 selector shown OPEN over it —
/// so the shot reads as "the settings page, backend dropdown popped", highlighting the many backends.
/// The menu uses the real `backendIds` / `backendDisplay`, so it mirrors the actual list.
private struct BackendDropdownShowcase: View {
    let vm: SettingsViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            DSSettingsView(vm: vm)
            Color.black.opacity(0.16).allowsHitTesting(false)       // dim so the open menu reads as "on top"
            BackendMenu(vm: vm)
                .frame(width: 300)
                .offset(x: 232, y: 214)                             // sits just under the 后端 picker
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        }
        .frame(width: 560, height: 760)
    }
}

/// The open, NSMenu-style list of every available backend (real `backendIds` / `backendDisplay`).
private struct BackendMenu: View {
    let vm: SettingsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(vm.backendIds.enumerated()), id: \.element) { _, id in
                let sel = id == vm.selectedBackendId
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                        .opacity(sel ? 1 : 0).frame(width: 13)
                    Text(vm.backendDisplay(id)).font(.system(size: 13))
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(sel ? Color.white : Color.primary)
                .background(sel ? Color.accentColor : Color.clear)
            }
        }
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.18)))
    }
}
