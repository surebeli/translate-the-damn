using System.Windows;   // Window, Thickness, TextWrapping, ResizeMode, SizeToContent, WindowStartupLocation
using TranslateTheDamn.Core;
// Alias the WPF types whose names collide with System.Windows.Forms (the App also uses WinForms for the tray).
using Button = System.Windows.Controls.Button;
using TextBox = System.Windows.Controls.TextBox;
using TextBlock = System.Windows.Controls.TextBlock;
using StackPanel = System.Windows.Controls.StackPanel;
using Orientation = System.Windows.Controls.Orientation;
using Color = System.Windows.Media.Color;
using Brushes = System.Windows.Media.Brushes;
using SolidColorBrush = System.Windows.Media.SolidColorBrush;
using FontFamily = System.Windows.Media.FontFamily;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace TranslateTheDamn.App.UI;

/// <summary>Minimal modal text-input dialog (WPF has no built-in InputBox). Returns the trimmed text, or null on cancel.</summary>
internal static class InputBox
{
    public static string? Show(Window owner, string title, string prompt, string initial = "")
    {
        var label = new TextBlock { Text = prompt, Foreground = new SolidColorBrush(Color.FromRgb(0xED, 0xED, 0xED)), TextWrapping = TextWrapping.Wrap };
        var box = new TextBox { Text = initial, Margin = new Thickness(0, 10, 0, 14), Height = 28, VerticalContentAlignment = VerticalAlignment.Center };

        var ok = new Button { Content = StringsLoader.Get("settings.button.add"), Width = 84, Height = 30, IsDefault = true, Margin = new Thickness(0, 0, 8, 0), Cursor = System.Windows.Input.Cursors.Hand, Background = new SolidColorBrush(Color.FromRgb(0x2E, 0xA0, 0x43)), Foreground = Brushes.White, BorderThickness = new Thickness(0) };
        var cancel = new Button { Content = StringsLoader.Get("settings.button.cancel"), Width = 80, Height = 30, IsCancel = true, Cursor = System.Windows.Input.Cursors.Hand };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(ok);
        buttons.Children.Add(cancel);

        var panel = new StackPanel { Margin = new Thickness(18) };
        panel.Children.Add(label);
        panel.Children.Add(box);
        panel.Children.Add(buttons);

        var win = new Window
        {
            Title = title,
            Width = 400,
            SizeToContent = SizeToContent.Height,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Owner = owner,
            ResizeMode = ResizeMode.NoResize,
            ShowInTaskbar = false,
            Background = new SolidColorBrush(Color.FromRgb(0x1B, 0x1B, 0x1B)),
            Foreground = new SolidColorBrush(Color.FromRgb(0xED, 0xED, 0xED)),
            FontFamily = new FontFamily("Segoe UI, Microsoft YaHei UI"),
            FontSize = 13,
            Content = panel
        };

        string? result = null;
        ok.Click += (_, _) => { result = box.Text; win.DialogResult = true; };
        win.Loaded += (_, _) => { box.Focus(); box.SelectAll(); };
        return win.ShowDialog() == true ? result?.Trim() : null;
    }
}
