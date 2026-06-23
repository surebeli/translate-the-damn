import SwiftUI
import AppKit
import TranslateTheDamnCore

/// The app's settings window — a clean single-page grouped Form (the finalized "clean" UI).
///
/// Pure native `Form` + `Section`, comfortable spacing, no accent rails / tabs / sidebar.
/// (Originally the "DS" style; kept as the single UI after consolidating away the other six.)
struct DSSettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var showAddProvider = false
    @State private var newProviderId = ""

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
                // Empty label + labelsHidden: the leading Text is the label. Passing the value as the
                // TextField title rendered it a SECOND time on macOS (visible label, not placeholder).
                TextField("", text: $vm.hotkeyText)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: vm.hotkeyText) { _, _ in vm.checkHotkey() }
            }
            hotkeyStatus

            Text(StringsLoader["settings.hotkey.hint"])
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var hotkeyStatus: some View {
        if vm.hotkeyValid && vm.hotkeyConflict {
            Label(StringsLoader["settings.hotkey.conflict"].replacingOccurrences(of: "{hotkey}", with: vm.hotkeyDisplay),
                  systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        } else if vm.hotkeyValid {
            Label(StringsLoader["settings.hotkey.ok"].replacingOccurrences(of: "{hotkey}", with: vm.hotkeyDisplay),
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else if !vm.hotkeyText.trimmingCharacters(in: .whitespaces).isEmpty {
            Label(StringsLoader["settings.hotkey.invalid"], systemImage: "xmark.circle.fill")
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

    // Single auth row: doctor verdict if probed, else the static auth hint, else the unchecked label.
    private var lampText: String {
        if vm.doctorRunning { return StringsLoader["settings.doctor.checking"] }
        if !vm.doctorDetail.isEmpty { return vm.doctorDetail }
        // authHint carries its own leading "● " bullet — strip it so it doesn't double up with the
        // status Circle drawn beside it.
        if !vm.authHint.isEmpty { return vm.authHint.trimmingCharacters(in: CharacterSet(charactersIn: "●•◦ \t")) }
        return StringsLoader["settings.doctor.unchecked"]
    }
    private var lampTextColor: Color { vm.doctorStatus == .fail ? .red : .secondary }

    private var backendSection: some View {
        Section(StringsLoader["settings.group.backend"]) {
            // Unified target language — drives every prompt-based backend (CLI + API) via {target}.
            // This is the TRANSLATION target, distinct from the UI display language in the General group.
            Picker(StringsLoader["settings.field.target"], selection: $vm.targetLanguage) {
                ForEach(vm.targetLanguageOptions, id: \.self) { Text($0).tag($0) }
            }

            Picker(StringsLoader["settings.field.backend"], selection: Binding(
                get: { vm.selectedBackendId },
                set: { vm.onBackendChange($0) }
            )) {
                ForEach(vm.backendIds, id: \.self) { Text(vm.backendDisplay($0)).tag($0) }
            }

            // Live auth lamp (spec §9 backend doctor): ONE row — spinner while probing, else a status
            // dot; the doctor verdict (or the static auth hint until probed); and the probe button.
            HStack(spacing: 8) {
                if vm.doctorRunning {
                    ProgressView().controlSize(.small).scaleEffect(0.55).frame(width: 11, height: 11)
                } else {
                    Circle().fill(doctorColor).frame(width: 9, height: 9)
                }
                Text(lampText).font(.caption).foregroundStyle(lampTextColor)
                Spacer()
                Button(StringsLoader["settings.doctor.button"]) { vm.runDoctor() }.disabled(vm.doctorRunning)
            }

            if vm.showModel {
                if vm.isHttp {
                    // API backends: free-entry model + live /models fetch (Picker can't be edited).
                    HStack {
                        TextField(StringsLoader["settings.field.model"], text: $vm.modelText)
                        Button(vm.modelsFetching ? StringsLoader["settings.model.fetching"] : StringsLoader["settings.model.refresh"]) { vm.refreshModels() }
                            .disabled(vm.modelsFetching)
                    }
                    if !vm.fetchedModels.isEmpty {
                        Picker(StringsLoader["settings.model.options"], selection: $vm.modelText) {
                            ForEach(vm.fetchedModels, id: \.self) { Text($0).tag($0) }
                        }
                    }
                } else {
                    // CLI backends: pick from the catalog, plus a live refresh-models for those that declare
                    // a manifest modelsCmd (mimo/opencode) — runs the subcommand and merges the result.
                    HStack {
                        Picker(StringsLoader["settings.field.model"], selection: $vm.modelText) {
                            ForEach(vm.availableModels, id: \.self) { Text($0).tag($0) }
                        }
                        if vm.canRefreshModels {
                            Button(vm.modelsFetching ? StringsLoader["settings.model.fetching"] : StringsLoader["settings.model.refresh"]) { vm.refreshModels() }
                                .disabled(vm.modelsFetching)
                        }
                    }
                }
            }

            if vm.isHttp {
                SecureField(StringsLoader["settings.field.apiKey"], text: $vm.apiKeyText)
                TextField(StringsLoader["settings.field.endpoint"], text: $vm.endpointText)

                if vm.isGoogleV2 || vm.isDoubao {
                    // Target language comes from the unified 目标语言 picker above (synced to the API's
                    // language code on save) — no separate per-backend target field. Source stays optional.
                    TextField(StringsLoader["settings.field.source"], text: $vm.sourceText)
                } else if vm.isCustomProvider {
                    Picker(StringsLoader["settings.field.protocol"], selection: $vm.protocolText) {
                        Text("OpenAI (/chat/completions)").tag("openai")
                        Text("Anthropic (/messages)").tag("anthropic")
                    }
                    .pickerStyle(.segmented)
                }
            } else {
                if vm.isCodex {
                    TextField(StringsLoader["settings.field.reasoning"], text: $vm.reasoningText)
                }
                if vm.isAgy {
                    TextField(StringsLoader["settings.field.fallback"], text: $vm.fallbackText)
                }
                if vm.showTimeout {
                    TextField(StringsLoader["settings.field.timeout"], text: $vm.timeoutText)
                }
            }

            // Custom (generic HTTP) provider management — add an openai/anthropic provider, or delete
            // the selected custom one (built-ins are protected).
            HStack {
                Button(StringsLoader["settings.provider.add"]) { newProviderId = ""; showAddProvider = true }
                Button(StringsLoader["settings.provider.detectKeys"]) { vm.detectKeys() }
                Spacer()
                Button(StringsLoader["settings.provider.delete"], role: .destructive) { vm.deleteProvider() }
                    .disabled(!vm.isCustomProvider)
            }
        }
        .alert(StringsLoader["settings.provider.addTitle"], isPresented: $showAddProvider) {
            TextField(StringsLoader["settings.provider.idPlaceholder"], text: $newProviderId)
            Button(StringsLoader["settings.button.add"]) { vm.addProvider(newProviderId) }
            Button(StringsLoader["settings.button.cancel"], role: .cancel) { }
        } message: {
            Text(StringsLoader["settings.provider.addMessage"])
        }
        .sheet(isPresented: $vm.showDetect) { detectSheet }
    }

    /// Credential auto-discovery consent checklist: each discovered STATIC key (provider · protocol ·
    /// masked · provenance) with a toggle; import the selected ones as http backends.
    private var detectSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(StringsLoader["settings.detect.header"].replacingOccurrences(of: "{count}", with: String(vm.discovered.count)))
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(vm.discovered.enumerated()), id: \.offset) { idx, c in
                        Toggle(isOn: Binding(
                            get: { vm.detectSelection.contains(idx) },
                            set: { on in if on { vm.detectSelection.insert(idx) } else { vm.detectSelection.remove(idx) } }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(c.provider)  ·  \(c.protocolName)  ·  \(c.keyMasked)")
                                Text("\(c.baseUrl)   [\(c.source)]")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
            Text(StringsLoader["settings.detect.note"])
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(StringsLoader["settings.button.cancel"]) { vm.showDetect = false }
                Button(StringsLoader["settings.detect.import"]) { vm.importSelected() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 240)
    }

    // MARK: - Popup

    private var popupSection: some View {
        Section(StringsLoader["settings.group.popup"]) {
            Picker(StringsLoader["settings.field.style"], selection: $vm.popupStyle) {
                Text(StringsLoader["settings.style.acrylic"]).tag("acrylic")
                Text(StringsLoader["settings.style.solid"]).tag("solid")
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
            // Display (UI) language — SEPARATE from the translation target language in the backend
            // group above. Switching it hot-reloads the catalog + re-renders the window/tray.
            Picker(StringsLoader["settings.field.uilang"], selection: $vm.uiLanguage) {
                ForEach(vm.uiLanguageOptions, id: \.id) { Text($0.label).tag($0.id) }
            }
            .onChange(of: vm.uiLanguage) { _, _ in vm.onUiLanguageChange() }

            Toggle(StringsLoader["settings.field.startup"], isOn: $vm.startWithWindows)

            Text(StringsLoader["settings.general.configHint"])
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
