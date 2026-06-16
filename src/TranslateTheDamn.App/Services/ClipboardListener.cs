using System.Windows;
using TranslateTheDamn.App.Interop;

namespace TranslateTheDamn.App.Services;

/// <summary>
/// Listens for clipboard changes via AddClipboardFormatListener. Carries a self-write guard so the
/// app's own clipboard writes (copy button / overwrite mode) don't loop back as a new translation.
/// </summary>
internal sealed class ClipboardListener : IDisposable
{
    private readonly IntPtr _hwnd;
    private bool _registered;
    private string? _selfWriteText;

    public event Action<string>? TextCopied;

    public ClipboardListener(IntPtr hwnd) => _hwnd = hwnd;

    public bool IsListening => _registered;

    public void Start()
    {
        if (_registered) return;
        _registered = NativeMethods.AddClipboardFormatListener(_hwnd);
    }

    public void Stop()
    {
        if (!_registered) return;
        NativeMethods.RemoveClipboardFormatListener(_hwnd);
        _registered = false;
    }

    /// <summary>Record text the app is about to place on the clipboard so the resulting update is ignored.</summary>
    public void MarkSelfWrite(string text) => _selfWriteText = text;

    public void OnClipboardUpdate()
    {
        var text = TryGetText();
        if (string.IsNullOrEmpty(text)) return;

        if (_selfWriteText is not null && string.Equals(text, _selfWriteText, StringComparison.Ordinal))
        {
            _selfWriteText = null; // consume the guard once
            return;
        }

        TextCopied?.Invoke(text);
    }

    private static string? TryGetText()
    {
        for (var attempt = 0; attempt < 3; attempt++)
        {
            try { return Clipboard.ContainsText() ? Clipboard.GetText() : null; }
            catch { Thread.Sleep(30); } // clipboard momentarily locked by another app
        }
        return null;
    }

    public void Dispose() => Stop();
}
