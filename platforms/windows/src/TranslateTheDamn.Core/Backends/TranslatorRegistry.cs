using TranslateTheDamn.Core.Backends.Cli;
using TranslateTheDamn.Core.Backends.Http;
using TranslateTheDamn.Core.Config;

namespace TranslateTheDamn.Core.Backends;

/// <summary>
/// Static map of backend id → <see cref="ITranslator"/>, built from config (hopper's registry
/// pattern). Adding a backend = add a class + one switch arm here. No dynamic discovery.
/// </summary>
public sealed class TranslatorRegistry
{
    private readonly Dictionary<string, ITranslator> _map = new(StringComparer.OrdinalIgnoreCase);

    public static TranslatorRegistry Build(AppConfig cfg)
    {
        var reg = new TranslatorRegistry();
        var tmpl = cfg.Translation.PromptTemplate;
        foreach (var (id, bc) in cfg.Backends)
        {
            ITranslator? t = id.ToLowerInvariant() switch
            {
                "claude" => new ClaudeTranslator(bc, tmpl),
                "codex" => new CodexTranslator(bc, tmpl),
                "copilot" => new CopilotTranslator(bc, tmpl),
                "agy" => new AgyTranslator(bc, tmpl),
                "google-v2" => new GoogleV2Translator(bc),
                "doubao" => new DoubaoTranslator(bc),
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
