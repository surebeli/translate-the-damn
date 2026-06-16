using TranslateTheDamn.App.Interop;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.App.Services;

/// <summary>
/// Registers a single global hotkey via RegisterHotKey (conflict-detecting) and raises an event
/// when it fires. The hotkey string is parsed by the testable <see cref="HotkeyParser"/>.
/// </summary>
internal sealed class HotkeyService : IDisposable
{
    public const int HotkeyId = 0xB001;

    private readonly IntPtr _hwnd;
    private bool _registered;

    public event Action? HotkeyPressed;

    public HotkeyService(IntPtr hwnd) => _hwnd = hwnd;

    /// <summary>Register (replacing any prior registration). Returns null on success, else an error.</summary>
    public string? Register(string? hotkeyText)
    {
        Unregister();

        var spec = HotkeyParser.Parse(hotkeyText);
        if (!spec.IsValid) return spec.Error;

        if (!NativeMethods.RegisterHotKey(_hwnd, HotkeyId, spec.Modifiers, spec.VirtualKey))
            return $"热键 “{spec.Display}” 注册失败,可能已被其它程序占用。";

        _registered = true;
        return null;
    }

    public void Unregister()
    {
        if (!_registered) return;
        NativeMethods.UnregisterHotKey(_hwnd, HotkeyId);
        _registered = false;
    }

    public void OnHotkey(int id)
    {
        if (id == HotkeyId) HotkeyPressed?.Invoke();
    }

    public void Dispose() => Unregister();
}
