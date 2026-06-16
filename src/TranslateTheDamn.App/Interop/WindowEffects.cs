using System.Runtime.InteropServices;
using static TranslateTheDamn.App.Interop.NativeMethods;

namespace TranslateTheDamn.App.Interop;

/// <summary>Higher-level helpers over the DWM / composition interop.</summary>
internal static class WindowEffects
{
    /// <summary>Make a window never take focus / activation and hide it from Alt-Tab.</summary>
    public static void MakeNoActivate(IntPtr hwnd)
    {
        var ex = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
        ex |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(ex));
    }

    /// <summary>Acrylic (frosted-glass) blur behind a layered window. Tint is 0xAABBGGRR.</summary>
    public static void EnableAcrylic(IntPtr hwnd, uint tintAbgr = 0xCC1A1A1A)
    {
        var accent = new AccentPolicy
        {
            AccentState = AccentState.ACCENT_ENABLE_ACRYLICBLURBEHIND,
            GradientColor = tintAbgr
        };
        var size = Marshal.SizeOf(accent);
        var ptr = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(accent, ptr, false);
            var data = new WindowCompositionAttributeData { Attribute = WCA_ACCENT_POLICY, Data = ptr, SizeOfData = size };
            SetWindowCompositionAttribute(hwnd, ref data);
        }
        finally { Marshal.FreeHGlobal(ptr); }
    }

    /// <summary>Win11 Mica backdrop for a persistent (non-layered) window. Best-effort.</summary>
    public static void EnableMica(IntPtr hwnd, bool dark = true)
    {
        int darkVal = dark ? 1 : 0;
        DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ref darkVal, sizeof(int));
        int backdrop = DWMSBT_MAINWINDOW;
        DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, ref backdrop, sizeof(int));
    }

    public static void RoundCorners(IntPtr hwnd)
    {
        int pref = DWMWCP_ROUND;
        DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref pref, sizeof(int));
    }
}
