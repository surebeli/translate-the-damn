using TranslateTheDamn.Core.Backends;
using TranslateTheDamn.Core.Config;

namespace TranslateTheDamn.Core;

public enum TriggerSource { Clipboard, Hotkey }

/// <summary>
/// Orchestrates one translation: applies filters (empty / max-length / clipboard dedupe), serves a
/// one-entry "last translation" cache, resolves the active backend, and supersedes any in-flight
/// translation (a newer trigger cancels the older one). UI concerns live in the App layer.
/// </summary>
public sealed class TranslationPipeline
{
    private readonly object _gate = new();
    private AppConfig _cfg;
    private TranslatorRegistry _registry;
    private string? _lastClipboardText;
    private CancellationTokenSource? _inflight;
    private CacheEntry? _cache;

    public TranslationPipeline(AppConfig cfg, TranslatorRegistry registry)
    {
        _cfg = cfg;
        _registry = registry;
    }

    /// <summary>Swap config + registry after the user edits settings (hot reload). Clears the cache.</summary>
    public void Update(AppConfig cfg, TranslatorRegistry registry)
    {
        lock (_gate) { _cfg = cfg; _registry = registry; _cache = null; }
    }

    public string ActiveBackendId => _cfg.General.ActiveBackend;

    /// <summary>Pure filter: returns the (possibly truncated) text to translate, or null to skip.</summary>
    public string? Accept(string? rawText, TriggerSource source)
    {
        if (string.IsNullOrWhiteSpace(rawText)) return null;

        var text = rawText;
        var max = _cfg.Translation.MaxChars;
        if (max > 0 && text.Length > max) text = text[..max];

        if (source == TriggerSource.Clipboard &&
            string.Equals(text, _lastClipboardText, StringComparison.Ordinal))
            return null; // dedupe identical consecutive clipboard content

        return text;
    }

    /// <summary>Records text the app itself put on the clipboard so the watcher won't re-translate it.</summary>
    public void NoteClipboardText(string? text) => _lastClipboardText = text;

    /// <summary>
    /// Runs a translation with supersession and a one-entry cache. Returns null if the trigger was
    /// filtered out or superseded; otherwise the backend's (or cached) <see cref="TranslationResult"/>.
    /// </summary>
    public async Task<TranslationResult?> RunAsync(string? rawText, TriggerSource source)
    {
        var text = Accept(rawText, source);
        if (text is null) return null;
        if (source == TriggerSource.Clipboard) _lastClipboardText = text;

        ITranslator? translator;
        string backendId;
        string model;
        lock (_gate)
        {
            backendId = _cfg.General.ActiveBackend;
            translator = _registry.Get(backendId);
            model = ResolveModel(backendId);

            // Cache hit: identical source text under the SAME backend + model as the last successful
            // translation returns instantly without calling the model (e.g. repeated hotkey on
            // unchanged clipboard content). A different backend/model is a different key -> re-translate.
            if (_cache is not null && _cache.Result.Ok
                && string.Equals(_cache.Text, text, StringComparison.Ordinal)
                && string.Equals(_cache.BackendId, backendId, StringComparison.OrdinalIgnoreCase)
                && string.Equals(_cache.Model, model, StringComparison.Ordinal))
            {
                return _cache.Result;
            }
        }

        if (translator is null)
            return TranslationResult.Failure(TranslateStatus.NotFound, $"未配置后端 “{backendId}”。");

        CancellationTokenSource cts;
        lock (_gate)
        {
            _inflight?.Cancel();
            _inflight = cts = new CancellationTokenSource();
        }

        try
        {
            var result = await translator.TranslateAsync(new TranslationRequest(text), cts.Token);
            if (result.Ok)
                lock (_gate) { _cache = new CacheEntry(text, backendId, model, result); }
            return result;
        }
        catch (OperationCanceledException)
        {
            return null;
        }
        finally
        {
            lock (_gate) { if (_inflight == cts) _inflight = null; }
            cts.Dispose();
        }
    }

    private string ResolveModel(string backendId) =>
        _cfg.Backends.TryGetValue(backendId, out var bc) ? (bc.Model ?? string.Empty) : string.Empty;

    /// <summary>The single most-recent successful translation, keyed by source text + backend + model.</summary>
    private sealed record CacheEntry(string Text, string BackendId, string Model, TranslationResult Result);
}
