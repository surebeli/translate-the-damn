using TranslateTheDamn.Core.Backends;
using TranslateTheDamn.Core.Config;

namespace TranslateTheDamn.Core;

public enum TriggerSource { Clipboard, Hotkey }

/// <summary>
/// Orchestrates one translation: applies filters (empty / max-length / clipboard dedupe),
/// resolves the active backend, and supersedes any in-flight translation (a newer trigger cancels
/// the older one). UI concerns (loading popup, presenting the result) live in the App layer.
/// </summary>
public sealed class TranslationPipeline
{
    private readonly object _gate = new();
    private AppConfig _cfg;
    private TranslatorRegistry _registry;
    private string? _lastClipboardText;
    private CancellationTokenSource? _inflight;

    public TranslationPipeline(AppConfig cfg, TranslatorRegistry registry)
    {
        _cfg = cfg;
        _registry = registry;
    }

    /// <summary>Swap config + registry after the user edits settings (hot reload).</summary>
    public void Update(AppConfig cfg, TranslatorRegistry registry)
    {
        lock (_gate) { _cfg = cfg; _registry = registry; }
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
    /// Runs a translation with supersession. Returns null if the trigger was filtered out or
    /// superseded by a newer one; otherwise the backend's <see cref="TranslationResult"/>.
    /// </summary>
    public async Task<TranslationResult?> RunAsync(string? rawText, TriggerSource source)
    {
        var text = Accept(rawText, source);
        if (text is null) return null;
        if (source == TriggerSource.Clipboard) _lastClipboardText = text;

        CancellationTokenSource cts;
        lock (_gate)
        {
            _inflight?.Cancel();
            _inflight = cts = new CancellationTokenSource();
        }

        ITranslator? translator;
        string backendId;
        lock (_gate)
        {
            backendId = _cfg.General.ActiveBackend;
            translator = _registry.Get(backendId);
        }
        if (translator is null)
            return TranslationResult.Failure(TranslateStatus.NotFound, $"未配置后端 “{backendId}”。");

        try
        {
            return await translator.TranslateAsync(new TranslationRequest(text), cts.Token);
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
}
