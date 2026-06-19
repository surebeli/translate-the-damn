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

    // Two fixed window specs (spec §8). large = 2x width x 1.5x height — derived from the shared
    // PopupSizing factors so the rule stays single-sourced with the conformance vector.
    private const double NormalWidth = 440;
    private const double NormalHeight = 360;

    // Recent-translation history for ◀ ▶ navigation (newest first); fed from TranslationPipeline.
    private readonly List<(string Source, string Translation)> _history = new();
    private int _index;
    private string _statusLabel = string.Empty;

    // Session-sticky popup position: once the user drags the card, later popups reuse this spot
    // (clamped to the work area) until the app restarts. Null = default top-center placement.
    private System.Windows.Point? _userPosition;

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
        _history.Clear();
        _index = 0;
        HeaderText.Text = "翻译中…";
        StatusText.Text = backendId;
        SourceText.Text = Shorten(sourceText, 400);
        TranslationText.Text = "正在翻译,请稍候…";
        TranslationText.Foreground = new System.Windows.Media.SolidColorBrush(
            System.Windows.Media.Color.FromArgb(0xCC, 0xCC, 0xCC, 0xCC));
        CopyButton.Visibility = Visibility.Collapsed;
        UpdateHistoryControls();                 // no history yet -> nav stays hidden
        ApplySize(sourceText?.Length ?? 0);      // size by the incoming source -> no resize on result
        _dismissTimer.Stop();
        ShowAndPlace();
    }

    /// <summary>Show a single result (no history navigation).</summary>
    public void ShowResult(string sourceText, string translation, string backendId) =>
        ShowResults(new[] { (sourceText, translation) }, 0, backendId);

    /// <summary>
    /// Show results with browsable history (newest first); <paramref name="index"/> 0 = newest =
    /// just-queried. ◀ ▶ navigation appears when history has more than one entry; navigating
    /// re-renders from this snapshot and never re-invokes the model.
    /// </summary>
    public void ShowResults(IReadOnlyList<(string Source, string Translation)> history, int index, string backendId)
    {
        _history.Clear();
        _history.AddRange(history);
        _statusLabel = backendId;
        if (_history.Count == 0) return;
        _index = Math.Clamp(index, 0, _history.Count - 1);
        RenderCurrent();
        if (!IsMouseOverContent()) RestartDismiss();
    }

    public void ShowError(string sourceText, string error, string backendId)
    {
        _history.Clear();
        _index = 0;
        HeaderText.Text = "翻译失败";
        StatusText.Text = backendId;
        SourceText.Text = Shorten(sourceText, 400);
        TranslationText.Text = error;
        TranslationText.Foreground = new System.Windows.Media.SolidColorBrush(
            System.Windows.Media.Color.FromArgb(0xFF, 0xFF, 0xB4, 0xA9));
        CopyButton.Visibility = Visibility.Collapsed;
        UpdateHistoryControls();
        ApplySize(0);
        ShowAndPlace();
        if (!IsMouseOverContent()) RestartDismiss();
    }

    /// <summary>Render the currently selected history entry (source + translation + nav + size).
    /// Reused by <see cref="ShowResults"/> and ◀/▶ navigation; never calls the model.</summary>
    private void RenderCurrent()
    {
        if (_history.Count == 0) return;
        _index = Math.Clamp(_index, 0, _history.Count - 1);
        var (source, translation) = _history[_index];
        _translation = translation;
        HeaderText.Text = "翻译";
        StatusText.Text = _statusLabel;
        SourceText.Text = Shorten(source, 400);
        TranslationText.Text = translation;
        TranslationText.Foreground = new System.Windows.Media.SolidColorBrush(
            System.Windows.Media.Color.FromArgb(0xFF, 0xF2, 0xF2, 0xF2));
        CopyButton.Visibility = Visibility.Visible;
        CopyButton.Content = "复制译文";
        UpdateHistoryControls();
        ApplySize(source.Length);                // recompute the fixed size for THIS entry's source
        ShowAndPlace();
    }

    private void UpdateHistoryControls()
    {
        var multi = _history.Count > 1;
        var vis = multi ? Visibility.Visible : Visibility.Collapsed;
        PrevButton.Visibility = vis;
        NextButton.Visibility = vis;
        HistoryIndicator.Visibility = vis;
        if (!multi) return;
        HistoryIndicator.Text = $"{_index + 1} / {_history.Count}";
        PrevButton.IsEnabled = _index < _history.Count - 1;   // an older entry exists
        NextButton.IsEnabled = _index > 0;                    // a newer entry exists
    }

    /// <summary>Snap the window to exactly one of the two fixed specs based on the displayed source
    /// length (spec §8, strict &gt; 500 → large). Content adapts inside; never an in-between size.</summary>
    private void ApplySize(int sourceChars)
    {
        var large = PopupSizing.SizeClass(sourceChars) == "large";
        Width = large ? NormalWidth * PopupSizing.LargeWidthFactor : NormalWidth;
        Height = large ? NormalHeight * PopupSizing.LargeHeightFactor : NormalHeight;
    }

    private void PrevButton_Click(object sender, RoutedEventArgs e)   // ◀ older
    {
        if (_index >= _history.Count - 1) return;
        _index++;
        RenderCurrent();
        if (!IsMouseOverContent()) RestartDismiss();
    }

    private void NextButton_Click(object sender, RoutedEventArgs e)   // ▶ newer
    {
        if (_index <= 0) return;
        _index--;
        RenderCurrent();
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
        if (_userPosition is { } p)
        {
            // Session-sticky: keep the user's dragged spot, clamped so the window stays on-screen.
            Left = Math.Clamp(p.X, wa.Left, Math.Max(wa.Left, wa.Right - ActualWidth));
            Top = Math.Clamp(p.Y, wa.Top, Math.Max(wa.Top, wa.Bottom - ActualHeight));
        }
        else
        {
            Left = wa.Left + Math.Max(0, (wa.Width - ActualWidth) / 2);
            Top = wa.Top + 64;
        }
    }

    // Drag the card to reposition. The action buttons (Copy/Close/◀/▶) handle their own mouse-down
    // and mark it handled, so this never fires on them; the scrollbar likewise keeps its drag. The
    // WS_EX_NOACTIVATE window moves without taking focus. DragMove blocks until the mouse is released;
    // afterwards we remember the spot so later popups reuse it (session-sticky, see PlaceTopCentre).
    private void Root_MouseLeftButtonDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        _dismissTimer.Stop();
        var before = new System.Windows.Point(Left, Top);
        try { DragMove(); } catch { /* primary button already released — nothing to drag */ }
        // Only become session-sticky after a REAL move: a plain click (or a DragMove that threw)
        // leaves the position unchanged and must not pin the popup away from its default placement.
        if (Left != before.X || Top != before.Y)
            _userPosition = new System.Windows.Point(Left, Top);
        if (!IsMouseOverContent()) RestartDismiss();
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
