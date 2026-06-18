import SwiftUI
import AppKit
import TranslateTheDamnCore

/// Z-style settings — a *document-style* single-page form with a live preview hero.
///
/// Design identity (distinct from Classic's custom cards, ZP's plain grouped Form, O48's
/// TabView, and KM's sidebar split): a fixed preview hero at the top mirrors the Z popup
/// (hairline border + status pill + sample source/translation) and reacts live to the chosen
/// popup style — a "所见即所得" touch none of the other settings views have. Below it, the four
/// standard sections in a native grouped Form. Same `SettingsViewModel` as every other view, so
/// every field and binding behaves identically.
struct ZSettingsView: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZPreviewCard(style: vm.popupStyle)
                .padding(.top, 16)
                .padding(.horizontal, 16)

            Form {
                triggerSection
                backendSection
                popupSection
                generalSection
            }
            .formStyle(.grouped)

            Divider()
            bottomBar
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    // MARK: - Trigger

    private var triggerSection: some View {
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

    // MARK: - Backend

    private var backendSection: some View {
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

    // MARK: - Popup

    private var popupSection: some View {
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

    // MARK: - General

    private var generalSection: some View {
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
            .pickerStyle(.segmented)

            Toggle(StringsLoader["settings.field.startup"], isOn: $vm.startWithWindows)

            Text("配置保存在 ~/.translatethedamn/config.json，API Key 仅保存在本机。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

/// Live preview of the Z popup's look, reflecting the chosen popup style (acrylic / solid).
/// Cosmetic only — mirrors the Z popup identity (hairline border + status pill + sample text)
/// so the user sees the result of their style choice before saving.
private struct ZPreviewCard: View {
    let style: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                Text(StringsLoader["popup.header.result"])
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 7))

            Text("Hello, world")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("你好，世界")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var background: some View {
        if style == "solid" {
            Color(nsColor: .controlBackgroundColor)
        } else {
            Color.clear.background(.ultraThinMaterial)
        }
    }
}
