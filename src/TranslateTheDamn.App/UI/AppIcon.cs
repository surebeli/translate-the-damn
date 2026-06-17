using System.Drawing;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using TranslateTheDamn.App.Interop;

namespace TranslateTheDamn.App.UI;

/// <summary>
/// Single source for the app glyph (a "T" in a filled circle) so the tray icon and the settings
/// window title-bar icon are visually identical. Green = listening, grey = paused.
/// </summary>
internal static class AppIcon
{
    private static Bitmap Draw(bool on, int size)
    {
        var bmp = new Bitmap(size, size);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;

        using var bg = new SolidBrush(on ? Color.FromArgb(46, 160, 67) : Color.FromArgb(120, 120, 120));
        g.FillEllipse(bg, 0, 0, size - 1, size - 1);

        using var font = new Font("Segoe UI", size * 0.6f, System.Drawing.FontStyle.Bold, GraphicsUnit.Pixel);
        using var fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        g.DrawString("T", font, Brushes.White, new RectangleF(0, -size * 0.04f, size, size), fmt);
        return bmp;
    }

    /// <summary>16px tray icon. Caller owns the returned <see cref="Icon"/>.</summary>
    public static Icon Tray(bool listening)
    {
        using var bmp = Draw(listening, 16);
        var hicon = bmp.GetHicon();
        var icon = (Icon)Icon.FromHandle(hicon).Clone();
        NativeMethods.DestroyIcon(hicon);
        return icon;
    }

    /// <summary>32px WPF window icon (frozen, brand/green variant).</summary>
    public static System.Windows.Media.ImageSource Window()
    {
        using var bmp = Draw(true, 32);
        var hbitmap = bmp.GetHbitmap();
        try
        {
            var source = Imaging.CreateBitmapSourceFromHBitmap(
                hbitmap, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            source.Freeze();
            return source;
        }
        finally { NativeMethods.DeleteObject(hbitmap); }
    }
}
