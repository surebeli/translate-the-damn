using System.Drawing;
using System.IO;
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

    /// <summary>
    /// Writes a multi-resolution .ico of the same glyph for use as the exe's ApplicationIcon, so the
    /// Explorer / taskbar / Alt-Tab icon matches the tray + window icons. Run once via
    /// <c>TranslateTheDamn.exe --gen-icon &lt;path&gt;</c>; the result is committed and embedded at build.
    /// </summary>
    public static void WriteIcoFile(string path)
    {
        int[] sizes = { 16, 24, 32, 48, 64, 128, 256 };
        var images = new List<byte[]>(sizes.Length);
        foreach (var s in sizes)
        {
            using var bmp = Draw(true, s);
            using var ms = new MemoryStream();
            bmp.Save(ms, System.Drawing.Imaging.ImageFormat.Png); // PNG entries (Vista+); 256px must be PNG
            images.Add(ms.ToArray());
        }

        using var fs = File.Create(path);
        using var bw = new BinaryWriter(fs);
        bw.Write((short)0);              // reserved
        bw.Write((short)1);              // type = icon
        bw.Write((short)sizes.Length);   // image count

        var offset = 6 + 16 * sizes.Length;
        for (var i = 0; i < sizes.Length; i++)
        {
            var s = sizes[i];
            bw.Write((byte)(s >= 256 ? 0 : s)); // width  (0 => 256)
            bw.Write((byte)(s >= 256 ? 0 : s)); // height (0 => 256)
            bw.Write((byte)0);                  // palette
            bw.Write((byte)0);                  // reserved
            bw.Write((short)1);                 // colour planes
            bw.Write((short)32);                // bits per pixel
            bw.Write(images[i].Length);         // bytes of image data
            bw.Write(offset);                   // offset of image data
            offset += images[i].Length;
        }
        foreach (var img in images) bw.Write(img);
    }
}
