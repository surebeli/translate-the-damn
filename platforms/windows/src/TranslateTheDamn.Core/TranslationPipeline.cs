using TranslateTheDamn.Core.Backends;
using TranslateTheDamn.Core.Config;

namespace TranslateTheDamn.Core;

public enum TriggerSource { Clipboard, Hotkey }

/// <summary>
/// Orchestrates one translation: applies filters (empty / max-length / clipboard dedupe), serves a
/// recent-translation cache (up to 5 entries, most-recently-used order), resolves the active backend,
/// and supersedes any in-flight translation (a newer trigger cancels the older one). UI concerns live
/// in the App layer.
/// </summary>
public sealed class TranslationPipeline
{
    private const int CacheCapacity = 5;

    private readonly object _gate = new();
    private AppConfig _cfg;
    private TranslatorRegistry _registry;
    private string? _lastClipboardText;
    private CancellationTokenSource? _inflight;
    // Recent successful translations, newest first; key = text + backend + model. Guarded by _gate.
    private readonly List<CacheEntry> _cache = new();

    public TranslationPipeline(AppConfig cfg, TranslatorRegistry registry)
    {
        _cfg = cfg;
        _registry = registry;
    }

    /// <summary>Swap config + registry after the user edits settings (hot reload). Clears the cache.</summary>
    public void Update(AppConfig cfg, TranslatorRegistry registry)
    {
        lock (_gate) { _cfg = cfg; _registry = registry; _cache.Clear(); }
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
    /// Runs a translation with supersession and the recent-translation cache. Returns null if the
    /// trigger was filtered out or superseded; otherwise the backend's (or cached)
    /// <see cref="TranslationResult"/>.
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

            // Cache hit: identical source text under the SAME backend + model as a recent successful
            // translation returns instantly without calling the model (e.g. repeated hotkey on
            // unchanged clipboard content). A different backend/model is a different key -> re-translate.
            // A hit promotes its entry to the front, refreshing its recency (MRU order).
            var hit = _cache.FindIndex(e =>
                string.Equals(e.Text, text, StringComparison.Ordinal)
                && string.Equals(e.BackendId, backendId, StringComparison.OrdinalIgnoreCase)
                && string.Equals(e.Model, model, StringComparison.Ordinal));
            if (hit >= 0)
            {
                var entry = _cache[hit];
                _cache.RemoveAt(hit);
                _cache.Insert(0, entry);
                return entry.Result;
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
                lock (_gate)
                {
                    // Only the still-current request populates the cache: a request superseded while
                    // in flight must not write, even if its backend ignored cancellation and completed
                    // anyway (otherwise a stale result could clobber the newer one at the front).
                    if (_inflight == cts)
                    {
                        // Keep keys unique under the lock: drop any existing entry for this key (a
                        // concurrent run could have inserted it) before inserting at the front (most
                        // recent), then evict the least-recently-used entry past capacity.
                        _cache.RemoveAll(e =>
                            string.Equals(e.Text, text, StringComparison.Ordinal)
                            && string.Equals(e.BackendId, backendId, StringComparison.OrdinalIgnoreCase)
                            && string.Equals(e.Model, model, StringComparison.Ordinal));
                        _cache.Insert(0, new CacheEntry(text, backendId, model, result));
                        if (_cache.Count > CacheCapacity) _cache.RemoveAt(_cache.Count - 1);
                    }
                }
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

    /// <summary>
    /// Snapshot of recently translated entries as (source, translation) pairs, newest first, for the
    /// popup's history navigation. Reading never re-invokes the model.
    /// </summary>
    public IReadOnlyList<(string Source, string Translation)> RecentHistory()
    {
        lock (_gate)
            return _cache.Select(e => (e.Text, e.Result.Text)).ToList();
    }

    /// <summary>A recent successful translation, keyed by source text + backend + model.</summary>
    private sealed record CacheEntry(string Text, string BackendId, string Model, TranslationResult Result);
}
