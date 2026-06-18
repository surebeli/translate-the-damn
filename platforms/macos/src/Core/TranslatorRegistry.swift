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

        guard let def = BackendManifest.backendDef(backend) else { return nil }
        let kind = def["kind"] as? String ?? ""

        let translator: Translator?

        switch kind.lowercased() {
        case "cli":
            translator = ProcessTranslator(id: backend, config: config, promptTemplate: promptTemplate, runner: runner)
        case "http":
            translator = HttpTranslator(id: backend, config: config)
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
