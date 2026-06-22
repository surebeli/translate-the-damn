using System.Linq;
using System.Windows;
using TranslateTheDamn.Core.Config;
// Alias the WPF types whose names collide with System.Windows.Forms (the App also uses WinForms for the tray).
using Button = System.Windows.Controls.Button;
using CheckBox = System.Windows.Controls.CheckBox;
using StackPanel = System.Windows.Controls.StackPanel;
using TextBlock = System.Windows.Controls.TextBlock;
using ScrollViewer = System.Windows.Controls.ScrollViewer;
using Orientation = System.Windows.Controls.Orientation;
using ScrollBarVisibility = System.Windows.Controls.ScrollBarVisibility;
using Color = System.Windows.Media.Color;
using SolidColorBrush = System.Windows.Media.SolidColorBrush;
using Brushes = System.Windows.Media.Brushes;
using FontFamily = System.Windows.Media.FontFamily;
using HorizontalAlignment = System.Windows.HorizontalAlignment;

namespace TranslateTheDamn.App.UI;

/// <summary>Consent checklist for credential auto-discovery: shows each discovered STATIC key (provider,
/// protocol, masked value, provenance) with a checkbox; returns the user-selected ones to import.</summary>
internal static class CredentialImportDialog
{
    public static IReadOnlyList<DiscoveredCredential>? Show(Window owner, IReadOnlyList<DiscoveredCredential> found)
    {
        var ed = new SolidColorBrush(Color.FromRgb(0xED, 0xED, 0xED));
        var list = new StackPanel();
        var rows = new List<(CheckBox box, DiscoveredCredential cred)>();
        foreach (var c in found)
        {
            var cb = new CheckBox { IsChecked = true, Margin = new Thickness(0, 6, 0, 6), Foreground = ed, Content = $"{c.Provider}  ·  {c.Protocol}  ·  {c.KeyMasked}\n      {c.BaseUrl}   [{c.Source}]" };
            list.Children.Add(cb);
            rows.Add((cb, c));
        }

        var import = new Button { Content = "导入选中", Width = 96, Height = 30, IsDefault = true, Margin = new Thickness(0, 0, 8, 0), Background = new SolidColorBrush(Color.FromRgb(0x2E, 0xA0, 0x43)), Foreground = Brushes.White, BorderThickness = new Thickness(0), Cursor = System.Windows.Input.Cursors.Hand };
        var cancel = new Button { Content = "取消", Width = 80, Height = 30, IsCancel = true, Cursor = System.Windows.Input.Cursors.Hand };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(import);
        buttons.Children.Add(cancel);

        var panel = new StackPanel { Margin = new Thickness(18) };
        panel.Children.Add(new TextBlock { Text = $"在本机发现 {found.Count} 个可导入的静态 API key(不含订阅 OAuth)。勾选要导入的:", Foreground = ed, TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MaxHeight = 320, Margin = new Thickness(0, 8, 0, 10) });
        panel.Children.Add(new TextBlock { Text = "注意:导入的 Key 以明文保存在 config.json(与现有 key 一致)。", Foreground = new SolidColorBrush(Color.FromRgb(0x9A, 0x9A, 0x9A)), FontSize = 11, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) });
        panel.Children.Add(buttons);

        var win = new Window
        {
            Title = "检测已有密钥",
            Width = 540,
            SizeToContent = SizeToContent.Height,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Owner = owner,
            ResizeMode = ResizeMode.NoResize,
            ShowInTaskbar = false,
            Background = new SolidColorBrush(Color.FromRgb(0x1B, 0x1B, 0x1B)),
            Foreground = ed,
            FontFamily = new FontFamily("Segoe UI, Microsoft YaHei UI"),
            FontSize = 13,
            Content = panel
        };

        IReadOnlyList<DiscoveredCredential>? result = null;
        import.Click += (_, _) => { result = rows.Where(r => r.box.IsChecked == true).Select(r => r.cred).ToList(); win.DialogResult = true; };
        return win.ShowDialog() == true ? result : null;
    }
}
