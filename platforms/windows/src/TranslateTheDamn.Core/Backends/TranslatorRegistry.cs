using TranslateTheDamn.Core.Backends.Manifest;
using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Core.Backends;

/// <summary>
/// Builds the backend id → <see cref="ITranslator"/> map by pairing the user's config with the
/// embedded declarative manifest (Constitution Q2): each backend is a generic
/// <see cref="ManifestCliBackend"/> / <see cref="ManifestHttpBackend"/> reading its definition from
/// <c>spec/backends.json</c>. Adding a backend = add a manifest entry (+ a config entry); no new code.
/// </summary>
public sealed class TranslatorRegistry
{
    private readonly Dictionary<string, ITranslator> _map = new(StringComparer.OrdinalIgnoreCase);

    public static TranslatorRegistry Build(AppConfig cfg)
    {
        var reg = new TranslatorRegistry();
        var manifest = BackendManifest.Load();
        // Resolve the unified target language once: {target} -> translation.targetLanguage. Every
        // prompt-driven backend (CLI + openai-http/anthropic-http) then shares the same target.
        var tmpl = PromptBuilder.WithTarget(cfg.Translation.PromptTemplate, cfg.Translation.TargetLanguage);

        foreach (var (id, bc) in cfg.Backends)
        {
            // Built-in backends resolve by id. A CUSTOM provider (id absent from the manifest) resolves a
            // generic HTTP template by its declared protocol — so user-typed base_url+key providers work
            // with no per-vendor manifest entry and no switch(id) (Constitution Law 6).
            if (!manifest.Backends.TryGetValue(id, out var def))
            {
                var tmplId = bc.Protocol?.Trim().ToLowerInvariant() switch
                {
                    "anthropic" => "anthropic-http",
                    "openai" => "openai-http",
                    _ => null
                };
                if (tmplId is null || !manifest.Backends.TryGetValue(tmplId, out def)) continue;
            }
            ITranslator? t = def.Kind.ToLowerInvariant() switch
            {
                "http" => new ManifestHttpBackend(id, def, bc, tmpl),
                "cli" => new ManifestCliBackend(id, def, bc, tmpl),
                _ => null
            };
            if (t is not null) reg._map[id] = t;
        }

        return reg;
    }

    /// <summary>Register or replace a translator (used for composition and tests).</summary>
    public void Add(ITranslator translator) => _map[translator.Id] = translator;

    public ITranslator? Get(string id) =>
        !string.IsNullOrEmpty(id) && _map.TryGetValue(id, out var t) ? t : null;

    public IReadOnlyCollection<string> Ids => _map.Keys;
}
