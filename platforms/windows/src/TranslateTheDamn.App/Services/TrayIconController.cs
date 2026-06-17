using System.Drawing;
using System.Windows.Forms;
using TranslateTheDamn.App.UI;

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

        _currentIcon = AppIcon.Tray(true);
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
        _currentIcon = AppIcon.Tray(on);
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

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
        _currentIcon?.Dispose();
    }
}
