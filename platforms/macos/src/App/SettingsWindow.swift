import SwiftUI
import AppKit
import Carbon
import TranslateTheDamnCore

private let kCheckSignature: OSType = 0x5474_546B
private let kCheckHotKeyID = UInt32(99)
private let backendOrder = ["claude", "codex", "copilot", "agy", "google-v2", "doubao"]

// MARK: - Window Controller

final class SettingsWindowController {
    private var window: NSWindow?
    private let viewModel: SettingsViewModel

    init(config: AppConfig, configPath: String, onSave: @escaping (AppConfig) -> Void) {
        viewModel = SettingsViewModel(config: config, configPath: configPath, onSave: onSave)
    }

    @MainActor func show() {
        if window == nil {
            // Single finalized UI ("clean" style). Other style views + uiStyle switching removed.
            let root = AnyView(DSSettingsView(vm: viewModel))
            let hostingView = NSHostingView(rootView: root)
            hostingView.frame.size = hostingView.fittingSize

            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                               styleMask: [.titled, .closable, .miniaturizable],
                               backing: .buffered,
                               defer: false)
            // Caption shows the app version, aligned with Windows (SettingsWindow.xaml.cs:
            // "translate-the-damn · 设置   v{Major}.{Minor}.{Build}"). Version is single-sourced from
            // the bundle's CFBundleShortVersionString (Info.plist), matching the Windows csproj <Version>.
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
            win.title = StringsLoader["settings.title"] + "   v" + version
            win.contentView = hostingView
            win.center()
            win.isReleasedWhenClosed = false

            window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - ViewModel

final class SettingsViewModel: ObservableObject {
    private let configPath: String
    private let onSave: (AppConfig) -> Void
    private var config: AppConfig
    private var loaded = false
    private let pathResolver = PathResolver()

    @Published var listenClipboard: Bool
    @Published var hotkeyText: String
    @Published var hotkeyValid: Bool = false
    @Published var hotkeyConflict: Bool = false
    @Published var hotkeyDisplay: String = ""

    @Published var selectedBackendId: String

    @Published var modelText: String = ""
    @Published var apiKeyText: String = ""
    @Published var endpointText: String = ""
    @Published var targetText: String = ""
    @Published var sourceText: String = ""
    @Published var reasoningText: String = ""
    @Published var fallbackText: String = ""
    @Published var timeoutText: String = ""

    @Published var popupStyle: String
    @Published var autoDismissSeconds: Double
    @Published var keepOnHover: Bool
    @Published var startWithWindows: Bool

    @Published var saveStatus: String = ""
    @Published var authHint: String = ""

    var backendIds: [String] {
        backendOrder.filter { config.backends[$0] != nil }
    }

    var availableModels: [String] {
        config.modelCatalog[selectedBackendId] ?? []
    }

    var currentBackend: BackendConfig? {
        config.backends[selectedBackendId]
    }

    var isHttp: Bool {
        currentBackend?.isHttp ?? false
    }

    var isCodex: Bool {
        selectedBackendId == "codex"
    }

    var isAgy: Bool {
        selectedBackendId == "agy"
    }

    var isGoogleV2: Bool {
        selectedBackendId == "google-v2"
    }

    var isDoubao: Bool {
        selectedBackendId == "doubao"
    }

    var showModel: Bool {
        !isGoogleV2
    }

    var showTimeout: Bool {
        !isHttp
    }

    var showSource: Bool {
        isGoogleV2 || isDoubao
    }

    init(config: AppConfig, configPath: String, onSave: @escaping (AppConfig) -> Void) {
        self.configPath = configPath
        self.onSave = onSave
        self.config = config

        listenClipboard = config.general.listenClipboard
        hotkeyText = config.hotkey.translate
        selectedBackendId = config.general.activeBackend
        popupStyle = config.popup.style
        autoDismissSeconds = Double(config.popup.autoDismissSeconds)
        keepOnHover = config.popup.keepOnHover
        startWithWindows = config.general.startWithWindows

        if !backendIds.contains(selectedBackendId), let first = backendIds.first {
            selectedBackendId = first
        }

        loadBackend(selectedBackendId)
        checkHotkey()
        loaded = true
    }

    func onBackendChange(_ newId: String) {
        guard loaded, newId != selectedBackendId else { return }
        flushBackend()
        selectedBackendId = newId
        loadBackend(newId)
    }

    func loadBackend(_ id: String) {
        guard let bc = config.backends[id] else { return }

        modelText = bc.model ?? ""
        apiKeyText = bc.apiKey ?? ""
        endpointText = bc.endpoint ?? ""

        if isGoogleV2 {
            targetText = bc.target ?? ""
        } else if isDoubao {
            targetText = bc.targetLanguage ?? ""
        } else {
            targetText = ""
        }
        sourceText = (isGoogleV2 ? (bc.source ?? "") : (bc.sourceLanguage ?? ""))

        reasoningText = bc.reasoning ?? ""
        fallbackText = bc.fallbackCommand ?? ""
        timeoutText = bc.timeoutSec.map(String.init) ?? ""

        refreshAuthHint()
    }

    func flushBackend() {
        guard var bc = config.backends[selectedBackendId] else { return }

        if showModel {
            let trimmed = modelText.trimmingCharacters(in: .whitespaces)
            bc.model = trimmed.isEmpty ? nil : trimmed
        }
        if isHttp {
            let ep = endpointText.trimmingCharacters(in: .whitespaces)
            bc.endpoint = ep.isEmpty ? nil : ep
            bc.apiKey = apiKeyText
            if isGoogleV2 {
                let t = targetText.trimmingCharacters(in: .whitespaces)
                bc.target = t.isEmpty ? nil : t
                let s = sourceText.trimmingCharacters(in: .whitespaces)
                bc.source = s.isEmpty ? nil : s
            } else if isDoubao {
                let t = targetText.trimmingCharacters(in: .whitespaces)
                bc.targetLanguage = t.isEmpty ? nil : t
                let s = sourceText.trimmingCharacters(in: .whitespaces)
                bc.sourceLanguage = s.isEmpty ? nil : s
            }
        } else {
            let r = reasoningText.trimmingCharacters(in: .whitespaces)
            bc.reasoning = r.isEmpty ? nil : r
            let f = fallbackText.trimmingCharacters(in: .whitespaces)
            bc.fallbackCommand = f.isEmpty ? nil : f
            if let secs = Int(timeoutText), secs > 0 {
                bc.timeoutSec = secs
            }
        }
        config.backends[selectedBackendId] = bc
    }

    func checkHotkey() {
        let trimmed = hotkeyText.trimmingCharacters(in: .whitespaces)
        let result = HotkeyParser.parse(trimmed)
        hotkeyValid = result.isValid
        hotkeyDisplay = result.isValid ? result.display : ""

        guard result.isValid else {
            hotkeyConflict = false
            return
        }
        // Skip the conflict check if this is the currently-registered hotkey —
        // the app already holds it, so tryRegisterHotkey would false-positive.
        if trimmed.lowercased() == config.hotkey.translate.lowercased() {
            hotkeyConflict = false
            return
        }
        hotkeyConflict = !Self.tryRegisterHotkey(result: result)
    }

    private static func tryRegisterHotkey(result: HotkeyResult) -> Bool {
        guard let carbonKeyCode = CarbonKeyMap.carbonKeyCode(fromVK: result.virtualKey) else {
            return false
        }
        let modifiers = CarbonKeyMap.carbonModifiers(
            hasControl: result.hasControl,
            hasAlt: result.hasAlt,
            hasShift: result.hasShift,
            hasWin: result.hasWin
        )
        let hotKeyID = EventHotKeyID(signature: kCheckSignature, id: kCheckHotKeyID)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(carbonKeyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            return true
        }
        return false
    }

    func refreshAuthHint() {
        guard let bc = currentBackend else { return }
        if isHttp {
            if apiKeyText.trimmingCharacters(in: .whitespaces).isEmpty {
                authHint = "● 未配置 API Key(请在下方填写)"
            } else {
                authHint = "● 已配置 API Key"
            }
        } else {
            let cmd = bc.command ?? selectedBackendId
            let found = pathResolver.resolve(cmd) != nil
            if found {
                authHint = "● 已检测到 \(cmd)(认证在首次翻译时确认)"
            } else {
                authHint = "● 未找到命令 \"\(cmd)\""
            }
        }
    }

    @MainActor
    func save() {
        flushBackend()

        config.general.listenClipboard = listenClipboard
        config.general.activeBackend = selectedBackendId
        config.general.startWithWindows = startWithWindows
        config.hotkey.translate = hotkeyText.trimmingCharacters(in: .whitespaces)
        config.popup.style = popupStyle
        config.popup.autoDismissSeconds = Int(autoDismissSeconds)
        config.popup.keepOnHover = keepOnHover

        do {
            try ConfigService.save(config, to: configPath)
            LoginService.shared.setEnabled(config.general.startWithWindows)
            saveStatus = StringsLoader["settings.status.saved"]
            refreshAuthHint()
            onSave(config)
        } catch {
            saveStatus = "保存失败: \(error.localizedDescription)"
        }
    }
}
