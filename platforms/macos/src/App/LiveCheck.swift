import Foundation
import TranslateTheDamnCore

/// Dev-only opt-in live end-to-end check, mirroring the Windows runner's `--live`. Loads the REAL
/// user config (incl. custom http providers), builds the translator for one backend via the same
/// registry/manifest path the app uses, runs a single translation, prints status/text/elapsed, and
/// exits. Never part of a normal launch (gated on `--live` in AppDelegate.main).
///
/// Usage: TranslateTheDamn --live <backendId> [sample text...]
enum LiveCheck {
    static func run(backendId: String, sample: String) {
        let cfg = ConfigService.load(from: ConfigService.defaultConfigPath) ?? ConfigService.defaultConfig()
        guard let bc = cfg.backends[backendId] else {
            FileHandle.standardError.write(Data("unknown backend: \(backendId)\n".utf8))
            exit(2)
        }
        // Resolve {target} once, exactly as AppDelegate.buildPipeline does.
        let template = PromptBuilder.withTarget(cfg.translation.promptTemplate, cfg.translation.targetLanguage)
        let registry = TranslatorRegistry()
        guard let translator = registry.translator(for: backendId, config: bc,
                                                    promptTemplate: template, runner: ProcessRunner()) else {
            FileHandle.standardError.write(Data("no translator for \(backendId) (type=\(bc.type) protocol=\(bc.`protocol` ?? "-"))\n".utf8))
            exit(2)
        }
        let model = bc.model ?? ""
        print("# LIVE \(backendId)  type=\(bc.type)  model=\(model.isEmpty ? "-" : model)")
        let t0 = Date()
        let r = translator.translate(text: sample, model: model)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        print("status = \(r.status.rawValue)   ok=\(r.ok)   (\(ms) ms)")
        print("source = \(sample)")
        print("text   = \(r.text)")
        if !r.detail.isEmpty { print("detail = \(r.detail)") }
        exit(r.ok ? 0 : 2)
    }
}
