using System.Windows.Interop;

namespace TranslateTheDamn.App.Services;

/// <summary>
/// A hidden message-only window (HWND_MESSAGE) used to receive WM_CLIPBOARDUPDATE and WM_HOTKEY.
/// Created on the WPF UI thread; raises <see cref="MessageReceived"/> for each window message.
/// </summary>
internal sealed class NativeMessageWindow : IDisposable
{
    private readonly HwndSource _source;

    public IntPtr Handle => _source.Handle;
    public event Action<int, IntPtr, IntPtr>? MessageReceived;

    public NativeMessageWindow()
    {
        var p = new HwndSourceParameters("TranslateTheDamnMsgWindow")
        {
            Width = 0,
            Height = 0,
            WindowStyle = 0,
            ParentWindow = new IntPtr(-3) // HWND_MESSAGE
        };
        _source = new HwndSource(p);
        _source.AddHook(WndProc);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        MessageReceived?.Invoke(msg, wParam, lParam);
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }
}
