import SwiftUI
import AppKit
import TranslateTheDamnCore

/// The app's settings window — a clean single-page grouped Form (the finalized "clean" UI).
///
/// Pure native `Form` + `Section`, comfortable spacing, no accent rails / tabs / sidebar.
/// (Originally the "DS" style; kept as the single UI after consolidating away the other six.)
struct DSSettingsView: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
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
                TextField("Ctrl+Shift+C", text: $vm.hotkeyText)
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

    private var doctorColor: Color {
        switch vm.doctorStatus {
        case .ok: return .green
        case .fail: return .red
        case .unknown: return .orange
        case .notInstalled, nil: return .secondary
        }
    }

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

            // Live auth lamp (spec §9 backend doctor): a manifest-driven, non-interactive probe.
            HStack(spacing: 8) {
                Circle()
                    .fill(doctorColor)
                    .frame(width: 9, height: 9)
                if vm.doctorRunning {
                    Text("检测中…").font(.caption).foregroundStyle(.secondary)
                } else if !vm.doctorDetail.isEmpty {
                    Text(vm.doctorDetail).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("未检测").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("检测") { vm.runDoctor() }.disabled(vm.doctorRunning)
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
