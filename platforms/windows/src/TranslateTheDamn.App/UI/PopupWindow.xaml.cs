using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using TranslateTheDamn.App.Interop;
using TranslateTheDamn.Core.Config;

namespace TranslateTheDamn.App.UI;

/// <summary>
/// Transient translation popup: never steals focus (WS_EX_NOACTIVATE + ShowActivated=false),
/// floats top-centre of the primary monitor, acrylic backdrop, pauses its dismiss timer while
/// hovered, and exposes a copy action.
/// </summary>
public partial class PopupWindow : Window
{
    private readonly PopupConfig _cfg;
    private readonly DispatcherTimer _dismissTimer;
    private string _translation = string.Empty;

    /// <summary>Raised when the user clicks 复制译文; the host writes the clipboard (with self-write guard).</summary>
    public event Action<string>? CopyRequested;

    public PopupWindow(PopupConfig cfg)
    {
        _cfg = cfg;
        InitializeComponent();

        _dismissTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(Math.Max(2, cfg.AutoDismissSeconds)) };
        _dismissTimer.Tick += (_, _) => { _dismissTimer.Stop(); Hide(); };

        if (string.Equals(cfg.Style, "solid", StringComparison.OrdinalIgnoreCase))
            Root.Background = new System.Windows.Media.SolidColorBrush(
                System.Windows.Media.Color.FromArgb(0xF2, 0x1C, 0x1C, 0x1C));
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var hwnd = new WindowInteropHelper(this).Handle;
        WindowEffects.MakeNoActivate(hwnd);
        WindowEffects.RoundCorners(hwnd);
        if (!string.Equals(_cfg.Style, "solid", StringComparison.OrdinalIgnoreCase))
            WindowEffects.EnableAcrylic(hwnd);
    }

    public void ShowLoading(string sourceText, string backendId)
    {
        HeaderText.Text = "翻译中…";
        StatusText.Text = backendId;
        SourceText.Text = Shorten(sourceText, 400);
        TranslationText.Text = "正在翻译,请稍候…";
        TranslationText.Foreground = new System.Windows.Media.SolidColorBrush(
            System.Windows.Media.Color.FromArgb(0xCC, 0xCC, 0xCC, 0xCC));
        CopyButton.Visibility = Visibility.Collapsed;
        _dismissTimer.Stop();
        ShowAndPlace();
    }

    public void ShowResult(string sourceText, string translation, string backendId)
    {
        _translation = translation;
        HeaderText.Text = "翻译";
        StatusText.Text = backendId;
        SourceText.Text = Shorten(sourceText, 400);
        TranslationText.Text = translation;
        TranslationText.Foreground = new System.Windows.Media.SolidColorBrush(
            System.Windows.Media.Color.FromArgb(0xFF, 0xF2, 0xF2, 0xF2));
        CopyButton.Visibility = Visibility.Visible;
        CopyButton.Content = "复制译文";
        ShowAndPlace();
        if (!IsMouseOverContent()) RestartDismiss();
    }

    public void ShowError(string sourceText, string error, string backendId)
    {
        HeaderText.Text = "翻译失败";
        StatusText.Text = backendId;
        SourceText.Text = Shorten(sourceText, 400);
        TranslationText.Text = error;
        TranslationText.Foreground = new System.Windows.Media.SolidColorBrush(
            System.Windows.Media.Color.FromArgb(0xFF, 0xFF, 0xB4, 0xA9));
        CopyButton.Visibility = Visibility.Collapsed;
        ShowAndPlace();
        if (!IsMouseOverContent()) RestartDismiss();
    }

    private void ShowAndPlace()
    {
        if (!IsVisible) Show();
        UpdateLayout();
        TranslationScroll.ScrollToTop();
        PlaceTopCentre();
        Topmost = true;
    }

    private void PlaceTopCentre()
    {
        var wa = SystemParameters.WorkArea; // primary monitor, DIPs
        Left = wa.Left + Math.Max(0, (wa.Width - ActualWidth) / 2);
        Top = wa.Top + 64;
    }

    private void RestartDismiss()
    {
        if (_cfg.AutoDismissSeconds <= 0) return;
        _dismissTimer.Stop();
        _dismissTimer.Start();
    }

    private void Root_MouseEnter(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (_cfg.KeepOnHover) _dismissTimer.Stop();
    }

    private void Root_MouseLeave(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (_cfg.KeepOnHover) RestartDismiss();
    }

    private bool IsMouseOverContent() => IsMouseOver;

    private void CopyButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_translation)) return;
        CopyRequested?.Invoke(_translation);
        CopyButton.Content = "已复制 ✓";
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        _dismissTimer.Stop();
        Hide();
    }

    // The popup never takes focus (WS_EX_NOACTIVATE), so route wheel events to the scroller
    // ourselves whenever they arrive (Win11 "scroll inactive windows on hover" delivers them).
    private void TranslationScroll_PreviewMouseWheel(object sender, System.Windows.Input.MouseWheelEventArgs e)
    {
        TranslationScroll.ScrollToVerticalOffset(TranslationScroll.VerticalOffset - e.Delta);
        e.Handled = true;
    }

    private static string Shorten(string s, int max) =>
        string.IsNullOrEmpty(s) ? string.Empty : (s.Length <= max ? s : s[..max] + "…");
}
