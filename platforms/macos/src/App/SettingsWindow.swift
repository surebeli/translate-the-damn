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
            let root: AnyView
            switch viewModel.uiStyle {
            case "classic": root = AnyView(SettingsView(vm: viewModel))
            case "ZP":      root = AnyView(ZPSettingsView(vm: viewModel))
            case "Z":       root = AnyView(ZSettingsView(vm: viewModel))
            case "km":      root = AnyView(KMSettingsView(vm: viewModel))
            case "MM":      root = AnyView(MMSettingsView(vm: viewModel))
            case "DS":      root = AnyView(DSSettingsView(vm: viewModel))
            default:        root = AnyView(O48SettingsView(vm: viewModel))  // "O48" + unknown → default
            }
            let hostingView = NSHostingView(rootView: root)
            hostingView.frame.size = hostingView.fittingSize

            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                               styleMask: [.titled, .closable, .miniaturizable],
                               backing: .buffered,
                               defer: false)
            win.title = StringsLoader["settings.title"]
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
    @Published var uiStyle: String = "O48"

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
        uiStyle = config.general.uiStyle ?? "O48"
        // Clamp unknown/hand-edited values so the segmented Picker always has a matching tag
        // (mirrors the selectedBackendId clamp below). The picker can only emit valid tags, so this
        // only normalizes config.json that was edited by hand to a stray value.
        if !["O48", "Z", "ZP", "km", "classic", "MM", "DS"].contains(uiStyle) { uiStyle = "O48" }

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
        config.general.uiStyle = uiStyle
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

// MARK: - SwiftUI View

struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    triggerGroup
                    backendGroup
                    popupGroup
                    generalGroup
                }
                .padding(18)
            }

            bottomBar
        }
        .frame(width: 560)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Trigger Group

    private var triggerGroup: some View {
        CardView {
            Text(StringsLoader["settings.group.trigger"])
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.bottom, 2)

            Toggle(isOn: $vm.listenClipboard) {
                Text(StringsLoader["settings.field.listen"])
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            .padding(.bottom, 10)

            HStack(alignment: .top) {
                Text(StringsLoader["settings.field.hotkey"])
                    .frame(width: labelWidth, alignment: .leading)
                    .font(.system(size: 13))

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Ctrl+Alt+T", text: $vm.hotkeyText)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 28)
                        .onChange(of: vm.hotkeyText) { _, _ in
                            vm.checkHotkey()
                        }

                    hotkeyStatusLabel
                }
            }

            Text("例:Ctrl+Alt+T。按下热键时翻译当前剪贴板内容。注册失败说明热键被占用。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var hotkeyStatusLabel: some View {
        if vm.hotkeyValid {
            if vm.hotkeyConflict {
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("✗ \(vm.hotkeyDisplay) 热键已被占用")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            } else {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("✓ \(vm.hotkeyDisplay) 可用")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
            }
        } else if !vm.hotkeyText.trimmingCharacters(in: .whitespaces).isEmpty {
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("✗ 格式无效")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Backend Group

    private var backendGroup: some View {
        CardView {
            Text(StringsLoader["settings.group.backend"])
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.bottom, 2)

            HStack {
                Text(StringsLoader["settings.field.backend"])
                    .frame(width: labelWidth, alignment: .leading)
                    .font(.system(size: 13))
                Picker("", selection: Binding(
                    get: { vm.selectedBackendId },
                    set: { vm.onBackendChange($0) }
                )) {
                    ForEach(vm.backendIds, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
                .frame(height: 28)
            }
            .padding(.bottom, 2)

            authHintLabel
                .padding(.bottom, 8)

            if vm.showModel {
                HStack {
                    Text(StringsLoader["settings.field.model"])
                        .frame(width: labelWidth, alignment: .leading)
                        .font(.system(size: 13))
                    Picker("", selection: $vm.modelText) {
                        ForEach(vm.availableModels, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    .frame(height: 28)
                }
            }

            if vm.isHttp {
                HStack {
                    Text(StringsLoader["settings.field.endpoint"])
                        .frame(width: labelWidth, alignment: .leading)
                        .font(.system(size: 13))
                    TextField("", text: $vm.endpointText)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 28)
                }

                HStack {
                    Text(StringsLoader["settings.field.apiKey"])
                        .frame(width: labelWidth, alignment: .leading)
                        .font(.system(size: 13))
                    SecureField("", text: $vm.apiKeyText)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 28)
                }

                HStack {
                    Text(StringsLoader["settings.field.target"])
                        .frame(width: labelWidth, alignment: .leading)
                        .font(.system(size: 13))
                    TextField("", text: $vm.targetText)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 28)
                }

                if vm.showSource {
                    HStack {
                        Text("源语言")
                            .frame(width: labelWidth, alignment: .leading)
                            .font(.system(size: 13))
                        TextField("", text: $vm.sourceText)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: 28)
                    }
                }
            } else {
                if vm.isCodex {
                    HStack {
                        Text("推理强度")
                            .frame(width: labelWidth, alignment: .leading)
                            .font(.system(size: 13))
                        TextField("low", text: $vm.reasoningText)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: 28)
                    }
                }

                if vm.isAgy {
                    HStack {
                        Text("回退命令")
                            .frame(width: labelWidth, alignment: .leading)
                            .font(.system(size: 13))
                        TextField("", text: $vm.fallbackText)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: 28)
                    }
                }

                if vm.showTimeout {
                    HStack {
                        Text(StringsLoader["settings.field.timeout"])
                            .frame(width: labelWidth, alignment: .leading)
                            .font(.system(size: 13))
                        TextField("30", text: $vm.timeoutText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80, height: 28)
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var authHintLabel: some View {
        if !vm.authHint.isEmpty {
            Text(vm.authHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Popup Group

    private var popupGroup: some View {
        CardView {
            Text(StringsLoader["settings.group.popup"])
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.bottom, 2)

            HStack {
                Text(StringsLoader["settings.field.style"])
                    .frame(width: labelWidth, alignment: .leading)
                    .font(.system(size: 13))
                Picker("", selection: $vm.popupStyle) {
                    Text("毛玻璃(Acrylic)").tag("acrylic")
                    Text("纯色半透明").tag("solid")
                }
                .frame(height: 28)
                .frame(width: 200)
                Spacer()
            }
            .padding(.bottom, 6)

            HStack {
                Text(StringsLoader["settings.field.autodismiss"])
                    .frame(width: labelWidth, alignment: .leading)
                    .font(.system(size: 13))
                Slider(value: $vm.autoDismissSeconds, in: 2...30, step: 1)
                Text("\(Int(vm.autoDismissSeconds)) s")
                    .font(.system(size: 13))
                    .frame(width: 46, alignment: .trailing)
            }
            .padding(.bottom, 4)

            Toggle(isOn: $vm.keepOnHover) {
                Text(StringsLoader["settings.field.keephover"])
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
        }
    }

    // MARK: - General Group

    private var generalGroup: some View {
        CardView {
            Text(StringsLoader["settings.group.general"])
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.bottom, 2)

            Picker("界面风格", selection: $vm.uiStyle) {
                Text("DS（清晰）").tag("DS")
                Text("Z（文档）").tag("Z")
                Text("KM（侧栏）").tag("km")
                Text("ZP（磨砂）").tag("ZP")
                Text("Classic（经典）").tag("classic")
                Text("O48（聚焦）").tag("O48")
                Text("MM（简洁）").tag("MM")
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)

            Toggle(isOn: $vm.startWithWindows) {
                Text(StringsLoader["settings.field.startup"])
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)

            Text("配置保存在 ~/.translatethedamn/config.json,API Key 仅保存在本机。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if !vm.saveStatus.isEmpty {
                Text(vm.saveStatus)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
            }
            Spacer()
            Button(StringsLoader["settings.button.close"]) {
                NSApp.keyWindow?.close()
            }
            .frame(width: 80, height: 32)

            Button(StringsLoader["settings.button.save"]) {
                vm.save()
            }
            .frame(width: 92, height: 32)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: NSColor.controlBackgroundColor.blended(withFraction: 0.3, of: .black) ?? NSColor.controlBackgroundColor))
    }

    private let labelWidth: CGFloat = 110
}

// MARK: - Card View

private struct CardView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
