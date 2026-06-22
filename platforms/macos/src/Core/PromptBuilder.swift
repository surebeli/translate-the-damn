import Foundation

/// Substitutes the source text into the configurable prompt template (spec §5).
///
/// Behaviour (pinned by `conformance/prompt-builder.json`):
/// - empty template ⇒ return content verbatim
/// - template contains `{content}` ⇒ replace the placeholder
/// - no placeholder ⇒ append the content after the rules, separated by `\n\n`
public enum PromptBuilder {
    public static let placeholder = "{content}"
    public static let targetPlaceholder = "{target}"

    public static func build(template: String, content: String) -> String {
        if template.isEmpty {
            return content
        }
        if let range = template.range(of: placeholder) {
            return template.replacingCharacters(in: range, with: content)
        }
        return template + "\n\n" + content
    }

    /// Resolve the unified target language into the template's `{target}` placeholder. Done ONCE (before
    /// `build` substitutes `{content}`), so every prompt-driven backend shares the same target. A template
    /// without `{target}` is returned unchanged. Mirrors the Windows `PromptBuilder.WithTarget`.
    public static func withTarget(_ template: String, _ target: String?) -> String {
        template.isEmpty ? template : template.replacingOccurrences(of: targetPlaceholder, with: target ?? "")
    }
}
