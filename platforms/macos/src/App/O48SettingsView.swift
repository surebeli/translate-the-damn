import SwiftUI
import AppKit
import TranslateTheDamnCore

/// O48-style settings — a *paginated, System-Settings-style* window.
///
/// Design identity (distinct from ZP's single grouped Form and Classic's custom cards):
///   • A native macOS `TabView` splits settings into four switchable pages
///     (触发 / 后端 / 浮窗 / 通用), each a grouped `Form` — the literal "设置页面切换".
///   • A persistent bottom save bar stays put across pages.
///   • System colors / fonts / controls only; no custom styling.
///   • Reuses the exact same `SettingsViewModel` as the ZP and Classic views, so every
///     field, binding, and conditional behaves identically — this view is purely a re-layout.
struct O48SettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var tab: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                triggerPage
                    .tabItem { Label(StringsLoader["settings.group.trigger"], systemImage: "keyboard") }
                    .tag(0)
                backendPage
                    .tabItem { Label(StringsLoader["settings.group.backend"], systemImage: "cpu") }
                    .tag(1)
                popupPage
                    .tabItem { Label(StringsLoader["settings.group.popup"], systemImage: "macwindow") }
                    .tag(2)
                generalPage
                    .tabItem { Label(StringsLoader["settings.group.general"], systemImage: "gearshape") }
                    .tag(3)
            }
            .padding([.horizontal, .top], 12)

            Divider()
            bottomBar
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    // MARK: - 触发

    private var triggerPage: some View {
        Form {
            Section(StringsLoader["settings.group.trigger"]) {
                Toggle(StringsLoader["settings.field.listen"], isOn: $vm.listenClipboard)

                HStack {
                    Text(StringsLoader["settings.field.hotkey"])
                    TextField("Ctrl+Alt+T", text: $vm.hotkeyText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: vm.hotkeyText) { _, _ in vm.checkHotkey() }
                }
                hotkeyStatus

                Text("按下热键时翻译当前剪贴板内容。注册失败说明热键已被占用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var hotkeyStatus: some View {
        if vm.hotkeyValid && vm.hotkeyConflict {
            Label("✗ \(vm.hotkeyDisplay) 热键已被占用", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        } else if vm.hotkeyValid {
            Label("✓ \(vm.hotkeyDisplay) 可用", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else if !vm.hotkeyText.trimmingCharacters(in: .whitespaces).isEmpty {
            Label("✗ 格式无效", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    // MARK: - 后端

    private var backendPage: some View {
        Form {
            Section(StringsLoader["settings.group.backend"]) {
                Picker(StringsLoader["settings.field.backend"], selection: Binding(
                    get: { vm.selectedBackendId },
                    set: { vm.onBackendChange($0) }
                )) {
                    ForEach(vm.backendIds, id: \.self) { Text($0).tag($0) }
                }

                if !vm.authHint.isEmpty {
                    Text(vm.authHint).font(.caption).foregroundStyle(.secondary)
                }

                if vm.showModel {
                    Picker(StringsLoader["settings.field.model"], selection: $vm.modelText) {
                        ForEach(vm.availableModels, id: \.self) { Text($0).tag($0) }
                    }
                }

                if vm.isHttp {
                    SecureField(StringsLoader["settings.field.apiKey"], text: $vm.apiKeyText)
                    TextField(StringsLoader["settings.field.endpoint"], text: $vm.endpointText)

                    if vm.isGoogleV2 {
                        TextField(StringsLoader["settings.field.target"], text: $vm.targetText)
                        TextField("源语言(可选)", text: $vm.sourceText)
                    } else if vm.isDoubao {
                        TextField("目标语言", text: $vm.targetText)
                        TextField("源语言(可选)", text: $vm.sourceText)
                    }
                } else {
                    if vm.isCodex {
                        TextField("推理强度", text: $vm.reasoningText)
                    }
                    if vm.isAgy {
                        TextField("回退命令", text: $vm.fallbackText)
                    }
                    if vm.showTimeout {
                        TextField(StringsLoader["settings.field.timeout"], text: $vm.timeoutText)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 浮窗

    private var popupPage: some View {
        Form {
            Section(StringsLoader["settings.group.popup"]) {
                Picker(StringsLoader["settings.field.style"], selection: $vm.popupStyle) {
                    Text("毛玻璃(Acrylic)").tag("acrylic")
                    Text("纯色半透明").tag("solid")
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(StringsLoader["settings.field.autodismiss"])
                    Slider(value: $vm.autoDismissSeconds, in: 2...30, step: 1)
                    Text("\(Int(vm.autoDismissSeconds))s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Toggle(StringsLoader["settings.field.keephover"], isOn: $vm.keepOnHover)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 通用

    private var generalPage: some View {
        Form {
            Section(StringsLoader["settings.group.general"]) {
            Picker("界面风格", selection: $vm.uiStyle) {
                Text("DS（清晰）").tag("DS")
                Text("Z（文档）").tag("Z")
                Text("KM（侧栏）").tag("km")
                Text("ZP（磨砂）").tag("ZP")
                Text("Classic（经典）").tag("classic")
                Text("O48（聚焦）").tag("O48")
                Text("MM（简洁）").tag("MM")
            }
                .pickerStyle(.menu)

                Toggle(StringsLoader["settings.field.startup"], isOn: $vm.startWithWindows)

                Text("配置保存在 ~/.translatethedamn/config.json，API Key 仅保存在本机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            if !vm.saveStatus.isEmpty {
                Text(vm.saveStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(StringsLoader["settings.button.close"]) { NSApp.keyWindow?.close() }
            Button(StringsLoader["settings.button.save"]) { vm.save() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
