import Foundation

public final class TranslatorRegistry {
    private var map: [String: Translator] = [:]

    public init() {}

    public func register(_ translator: Translator, for id: String) {
        map[id.lowercased()] = translator
    }

    public func translator(for backend: String, config: BackendConfig, promptTemplate: String = "", runner: ProcessRunner = ProcessRunner()) -> Translator? {
        let key = backend.lowercased()
        if let existing = map[key] { return existing }

        // Built-in backends resolve by id. A CUSTOM provider (id absent from the manifest) resolves a
        // generic HTTP template by its declared protocol — so user-typed base_url+key providers work with
        // no per-vendor manifest entry and no switch(id) (Constitution Law 6). Mirrors Windows.
        var def = BackendManifest.backendDef(backend)
        var defId = backend
        if def == nil {
            let tmplId: String?
            switch (config.`protocol` ?? "").trimmingCharacters(in: .whitespaces).lowercased() {
            case "anthropic": tmplId = "anthropic-http"
            case "openai": tmplId = "openai-http"
            default: tmplId = nil
            }
            if let t = tmplId { def = BackendManifest.backendDef(t); defId = t }
        }
        guard let resolvedDef = def else { return nil }
        let kind = resolvedDef["kind"] as? String ?? ""

        let translator: Translator?

        switch kind.lowercased() {
        case "cli":
            translator = ProcessTranslator(id: backend, config: config, promptTemplate: promptTemplate, runner: runner)
        case "http":
            translator = HttpTranslator(id: backend, config: config, defId: defId, promptTemplate: promptTemplate)
        default:
            translator = nil
        }

        if let t = translator {
            map[key] = t
        }
        return translator
    }

    public var ids: [String] {
        return Array(map.keys)
    }
}
