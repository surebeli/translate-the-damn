import SwiftUI
import AppKit
import Carbon
import TranslateTheDamnCore

private let kCheckSignature: OSType = 0x5474_546B
private let kCheckHotKeyID = UInt32(99)
private let backendOrder = ["claude", "codex", "copilot", "agy", "opencode", "kimi", "mimo", "google-v2", "doubao"]

// MARK: - Window Controller

@MainActor
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

@MainActor
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

    @Published var targetLanguage: String     // unified target language (drives every prompt-based backend via {target})
    @Published var fetchedModels: [String] = []   // live /models result for the selected HTTP backend
    @Published var modelsFetching: Bool = false

    @Published var discovered: [DiscoveredCredential] = []   // credential auto-discovery results (consent checklist)
    @Published var showDetect: Bool = false
    @Published var detectSelection: Set<Int> = []

    @Published var modelText: String = ""
    @Published var apiKeyText: String = ""
    @Published var endpointText: String = ""
    @Published var protocolText: String = "openai"   // custom HTTP provider: "openai" | "anthropic"
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

    // Live auth lamp (spec §9 backend doctor): nil = not yet probed; otherwise the last probe verdict.
    @Published var doctorStatus: DoctorStatus? = nil
    @Published var doctorDetail: String = ""
    @Published var doctorRunning: Bool = false
    private let doctor = DoctorService()

    /// Display order (mirrors Windows OrderedBackendIds): doubao(API), google(API), other API, CLI, then 暂不支持(agy).
    var backendIds: [String] {
        func rank(_ id: String) -> Int {
            if id == "agy" { return 4 }                                  // 暂不支持 last
            if id == "doubao" { return 0 }
            if id == "google-v2" { return 1 }
            return (config.backends[id]?.isHttp ?? false) ? 2 : 3        // other API, then CLI
        }
        func orderIdx(_ id: String) -> Int { backendOrder.firstIndex(of: id) ?? Int.max }
        return config.backends.keys.sorted { a, b in
            let (ra, rb) = (rank(a), rank(b))
            if ra != rb { return ra < rb }
            let (oa, ob) = (orderIdx(a), orderIdx(b))
            if oa != ob { return oa < ob }
            return a < b
        }
    }

    /// Dropdown label: backend name (without the cosmetic "-http" suffix) + a CLI/API tag (+ agy's note).
    /// Mirrors Windows BackendDisplay.
    func backendDisplay(_ id: String) -> String {
        let kind = (config.backends[id]?.isHttp ?? false) ? "API" : "CLI"
        let note = id == "agy" ? " · 暂不支持" : ""
        let name = id.hasSuffix("-http") ? String(id.dropLast(5)) : id
        return "\(name)  ·  \(kind)\(note)"
    }

    /// A user-added generic HTTP provider (id not in the manifest/backendOrder): protocol is
    /// selectable and the provider is deletable. Built-in HTTP backends (google-v2/doubao) are not custom.
    var isCustomProvider: Bool {
        isHttp && !backendOrder.contains(selectedBackendId)
    }

    var availableModels: [String] {
        fetchedModels.isEmpty ? (config.modelCatalog[selectedBackendId] ?? []) : fetchedModels
    }

    /// A live "刷新模型" is available for HTTP backends (GET /models) AND for CLI backends that declare
    /// a `modelsCmd` in the manifest (e.g. mimo/opencode `models`). Mirrors Windows, which enumerates
    /// both kinds; macOS previously enumerated HTTP only.
    var canRefreshModels: Bool {
        if isHttp { return true }
        if let def = BackendManifest.backendDef(selectedBackendId),
           let mc = def["modelsCmd"] as? [Any], !mc.isEmpty { return true }
        return false
    }

    static let commonTargetLanguages = ["简体中文", "繁體中文", "English", "日本語", "한국어", "Français", "Deutsch", "Español", "Русский", "Português"]
    /// Picker options always include the stored value so a custom target stays selectable.
    var targetLanguageOptions: [String] {
        Self.commonTargetLanguages.contains(targetLanguage) ? Self.commonTargetLanguages : [targetLanguage] + Self.commonTargetLanguages
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
        targetLanguage = config.translation.targetLanguage.isEmpty ? "简体中文" : config.translation.targetLanguage
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
        doctorStatus = nil; doctorDetail = ""   // verdict is per-backend — clear on switch
        fetchedModels = []                      // live /models is per-backend — clear on switch
        loadBackend(newId)
    }

    /// Fetch the selected HTTP backend's models live from <baseURL>/models (current unsaved endpoint+key),
    /// off the main actor. Best-effort: empty result keeps the static catalog. Mirrors Windows RefreshModelsAsync.
    func refreshModels() {
        guard canRefreshModels, !modelsFetching else { return }
        modelsFetching = true
        let http = isHttp
        let ep = endpointText, key = apiKeyText, proto = protocolText
        let id = selectedBackendId, cmd = currentBackend?.command
        Task { @MainActor in
            let models = await Task.detached(priority: .userInitiated) {
                http ? ModelEnumerator.enumerate(endpoint: ep, apiKey: key, protocolName: proto)
                     : ModelEnumerator.enumerateCli(backendId: id, command: cmd)
            }.value
            self.fetchedModels = models
            self.modelsFetching = false
            if models.isEmpty {
                self.saveStatus = http ? "未拉取到模型(检查 Endpoint/Key)"
                                       : "未枚举到模型(该 CLI 可能不支持 models 子命令或未登录)"
            }
        }
    }

    /// Run the manifest-driven doctor for the selected backend off the main thread (it may spawn a
    /// CLI), then publish the verdict to the lamp. Never stores or shows the API key.
    func runDoctor() {
        guard !doctorRunning else { return }
        doctorRunning = true
        doctorDetail = ""
        let id = selectedBackendId
        let doctor = self.doctor
        // Probe off the main actor (it may spawn a CLI), then resume on the main actor to publish the
        // verdict. doctor/id/DoctorResult are all Sendable, so nothing unsafe crosses the boundary.
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { doctor.probe(backendId: id) }.value
            self.doctorStatus = result.status
            self.doctorDetail = result.detail
            self.doctorRunning = false
        }
    }

    /// Add a custom generic-HTTP provider (openai/anthropic). User then fills endpoint/key/model/
    /// protocol and saves. Mirrors Windows BtnAddProvider_Click.
    func addProvider(_ rawId: String) {
        let id = rawId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }
        guard config.backends[id] == nil else { saveStatus = "已存在:\(id)"; return }
        flushBackend()
        objectWillChange.send()
        config.backends[id] = BackendConfig(type: "http", model: "", timeoutSec: 30,
                                            endpoint: "", apiKey: "", protocol: "openai")
        selectedBackendId = id
        loadBackend(id)
        saveStatus = "已新增 \(id) · 填 Endpoint/Key/模型/协议后点保存"
    }

    /// Delete the selected custom provider (built-ins are protected). Mirrors BtnDeleteProvider_Click.
    func deleteProvider() {
        let id = selectedBackendId
        guard !backendOrder.contains(id) else { saveStatus = "内置后端不可删除"; return }
        objectWillChange.send()
        config.backends.removeValue(forKey: id)
        if config.general.activeBackend == id { config.general.activeBackend = "claude" }
        selectedBackendId = backendIds.first ?? "claude"
        loadBackend(selectedBackendId)
        saveStatus = "已删除 \(id)(保存后写入)"
    }

    /// Discover the user's OWN static API keys (env + opencode + codex) and show the consent checklist.
    /// Never reads OAuth stores; keys persist on save. Mirrors Windows BtnDetectKeys_Click.
    func detectKeys() {
        let found = CredentialDiscovery.scan()
        if found.isEmpty { saveStatus = "未发现可导入的静态密钥(env / opencode / codex)"; return }
        discovered = found
        detectSelection = Set(0..<found.count)   // default all checked
        showDetect = true
    }

    /// Import the checked discovered credentials as http backends (filled, ready). Persisted on save.
    func importSelected() {
        objectWillChange.send()
        var lastId: String?
        var n = 0
        for (i, c) in discovered.enumerated() where detectSelection.contains(i) {
            let id = uniqueBackendId(c.suggestedId)
            config.backends[id] = BackendConfig(type: "http", model: "", timeoutSec: 30,
                                                endpoint: c.baseUrl, apiKey: c.key, protocol: c.protocolName)
            lastId = id; n += 1
        }
        showDetect = false
        if let id = lastId { selectedBackendId = id; loadBackend(id) }
        saveStatus = "已导入 \(n) 个 provider(保存后写入)"
    }

    private func uniqueBackendId(_ base: String) -> String {
        if config.backends[base] == nil { return base }
        var i = 2
        while config.backends["\(base)-\(i)"] != nil { i += 1 }
        return "\(base)-\(i)"
    }

    func loadBackend(_ id: String) {
        guard let bc = config.backends[id] else { return }

        modelText = bc.model ?? ""
        apiKeyText = bc.apiKey ?? ""
        endpointText = bc.endpoint ?? ""
        protocolText = bc.`protocol` ?? "openai"

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
            } else {
                // custom generic HTTP provider → persist the protocol selector
                bc.`protocol` = protocolText.isEmpty ? "openai" : protocolText
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
        config.translation.targetLanguage = targetLanguage.trimmingCharacters(in: .whitespaces).isEmpty ? "简体中文" : targetLanguage
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
