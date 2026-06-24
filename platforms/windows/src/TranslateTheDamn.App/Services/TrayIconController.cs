using System.Drawing;
using System.Windows.Forms;
using TranslateTheDamn.App.UI;
using TranslateTheDamn.Core;

namespace TranslateTheDamn.App.Services;

/// <summary>System-tray icon + context menu (toggle listening, open settings, exit).
/// Menu labels + tooltip come from the shared locale catalog (<see cref="StringsLoader"/>); call
/// <see cref="RefreshLocalizedText"/> after a Display-language hot-switch to re-render them in place.</summary>
internal sealed class TrayIconController : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly ToolStripMenuItem _toggleItem;
    private readonly ToolStripMenuItem _settingsItem;
    private readonly ToolStripMenuItem _exitItem;
    private Icon? _currentIcon;
    private bool _listening = true;   // mirrors the tray glyph/tooltip state so RefreshLocalizedText can re-pick the tooltip

    public event Action? ToggleListenRequested;
    public event Action? OpenSettingsRequested;
    public event Action? ExitRequested;

    public TrayIconController()
    {
        _toggleItem = new ToolStripMenuItem(StringsLoader.Get("tray.menu.listen"), null, (_, _) => ToggleListenRequested?.Invoke());
        _settingsItem = new ToolStripMenuItem(StringsLoader.Get("tray.menu.settings"), null, (_, _) => OpenSettingsRequested?.Invoke());
        _exitItem = new ToolStripMenuItem(StringsLoader.Get("tray.menu.exit"), null, (_, _) => ExitRequested?.Invoke());

        var menu = new ContextMenuStrip();
        menu.Items.Add(_toggleItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_settingsItem);
        menu.Items.Add(_exitItem);

        _currentIcon = AppIcon.Tray(true);
        _icon = new NotifyIcon
        {
            Text = StringsLoader.Get("tray.tooltip.listening"),
            Visible = true,
            ContextMenuStrip = menu,
            Icon = _currentIcon
        };
        _icon.DoubleClick += (_, _) => OpenSettingsRequested?.Invoke();
    }

    public void SetListening(bool on)
    {
        _listening = on;
        _toggleItem.Checked = on;
        var old = _currentIcon;
        _currentIcon = AppIcon.Tray(on);
        _icon.Icon = _currentIcon;
        old?.Dispose();
        _icon.Text = on ? StringsLoader.Get("tray.tooltip.listening") : StringsLoader.Get("tray.tooltip.paused");
    }

    /// <summary>Re-apply localized menu labels + tooltip after a Display-language hot-switch (the host
    /// wires this to <c>SettingsWindow.LocaleChanged</c>). The catalog was already reconfigured + reloaded
    /// by the settings window before raising the event, so this just re-reads it.</summary>
    public void RefreshLocalizedText()
    {
        _toggleItem.Text = StringsLoader.Get("tray.menu.listen");
        _settingsItem.Text = StringsLoader.Get("tray.menu.settings");
        _exitItem.Text = StringsLoader.Get("tray.menu.exit");
        _icon.Text = _listening ? StringsLoader.Get("tray.tooltip.listening") : StringsLoader.Get("tray.tooltip.paused");
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
