using System.Drawing;
using System.Windows.Forms;

namespace TranslateTheDamn.App.Services;

/// <summary>System-tray icon + context menu (toggle listening, open settings, exit).</summary>
internal sealed class TrayIconController : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly ToolStripMenuItem _toggleItem;
    private Icon? _currentIcon;

    public event Action? ToggleListenRequested;
    public event Action? OpenSettingsRequested;
    public event Action? ExitRequested;

    public TrayIconController()
    {
        _toggleItem = new ToolStripMenuItem("监听剪贴板", null, (_, _) => ToggleListenRequested?.Invoke());

        var menu = new ContextMenuStrip();
        menu.Items.Add(_toggleItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("打开设置…", null, (_, _) => OpenSettingsRequested?.Invoke()));
        menu.Items.Add(new ToolStripMenuItem("退出", null, (_, _) => ExitRequested?.Invoke()));

        _currentIcon = BuildIcon(true);
        _icon = new NotifyIcon
        {
            Text = "translate-the-damn",
            Visible = true,
            ContextMenuStrip = menu,
            Icon = _currentIcon
        };
        _icon.DoubleClick += (_, _) => OpenSettingsRequested?.Invoke();
    }

    public void SetListening(bool on)
    {
        _toggleItem.Checked = on;
        var old = _currentIcon;
        _currentIcon = BuildIcon(on);
        _icon.Icon = _currentIcon;
        old?.Dispose();
        _icon.Text = on ? "translate-the-damn(监听中)" : "translate-the-damn(已暂停)";
    }

    public void Notify(string title, string message)
    {
        try
        {
            _icon.BalloonTipTitle = title;
            _icon.BalloonTipText = message;
            _icon.ShowBalloonTip(2500);
        }
        catch { /* balloon tips can fail silently on some configs */ }
    }

    private static Icon BuildIcon(bool on)
    {
        using var bmp = new Bitmap(16, 16);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            using var bg = new SolidBrush(on ? Color.FromArgb(46, 160, 67) : Color.FromArgb(120, 120, 120));
            g.FillEllipse(bg, 0, 0, 15, 15);
            using var f = new Font("Segoe UI", 9, FontStyle.Bold, GraphicsUnit.Pixel);
            g.DrawString("T", f, Brushes.White, 3, 2);
        }
        var hicon = bmp.GetHicon();
        return Icon.FromHandle(hicon);
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
        _currentIcon?.Dispose();
    }
}
