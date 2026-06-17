using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using TranslateTheDamn.App.Interop;
using TranslateTheDamn.App.Services;
using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.App.UI;

public partial class SettingsWindow : Window
{
    private static readonly string[] BackendOrder = { "claude", "codex", "copilot", "agy", "google-v2", "doubao" };

    private readonly ConfigService _svc;
    private readonly AppConfig _config;
    private string? _currentBackendId;
    private bool _loaded;

    /// <summary>Raised after a successful save with the persisted config (host hot-reloads).</summary>
    public event Action<AppConfig>? Saved;

    public SettingsWindow(ConfigService svc)
    {
        _svc = svc;
        _config = svc.LoadOrBootstrap();
        InitializeComponent();
        Icon = AppIcon.Window();   // match the tray glyph
        var v = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
        if (v is not null) Title = $"translate-the-damn · 设置   v{v.Major}.{v.Minor}.{v.Build}";
        PopulateGeneral();
        _loaded = true;
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        WindowEffects.EnableMica(new WindowInteropHelper(this).Handle, dark: true);
    }

    private void PopulateGeneral()
    {
        ChkListen.IsChecked = _config.General.ListenClipboard;
        TxtHotkey.Text = _config.Hotkey.Translate;
        TxtHotkey.TextChanged += (_, _) => ValidateHotkey();
        ValidateHotkey();

        // popup style
        CmbStyle.Items.Clear();
        CmbStyle.Items.Add(new ComboBoxItem { Content = "毛玻璃(Acrylic)", Tag = "acrylic" });
        CmbStyle.Items.Add(new ComboBoxItem { Content = "纯色半透明", Tag = "solid" });
        CmbStyle.SelectedIndex = string.Equals(_config.Popup.Style, "solid", StringComparison.OrdinalIgnoreCase) ? 1 : 0;

        SldDismiss.Value = Math.Clamp(_config.Popup.AutoDismissSeconds, 2, 30);
        LblDismiss.Text = $"{(int)SldDismiss.Value} s";
        SldDismiss.ValueChanged += (_, _) => LblDismiss.Text = $"{(int)SldDismiss.Value} s";
        ChkHover.IsChecked = _config.Popup.KeepOnHover;
        ChkStartup.IsChecked = _config.General.StartWithWindows;

        // backends
        CmbBackend.Items.Clear();
        foreach (var id in BackendOrder)
            if (_config.Backends.ContainsKey(id))
                CmbBackend.Items.Add(id);
        _currentBackendId = _config.Backends.ContainsKey(_config.General.ActiveBackend)
            ? _config.General.ActiveBackend
            : (CmbBackend.Items.Count > 0 ? (string)CmbBackend.Items[0]! : null);
        CmbBackend.SelectedItem = _currentBackendId;
        CmbBackend.SelectionChanged += CmbBackend_SelectionChanged;
        if (_currentBackendId is not null) LoadBackendFields(_currentBackendId);
    }

    private void CmbBackend_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_loaded) return;
        if (_currentBackendId is not null) FlushBackendFields(_currentBackendId);
        _currentBackendId = CmbBackend.SelectedItem as string;
        if (_currentBackendId is not null) LoadBackendFields(_currentBackendId);
    }

    private void LoadBackendFields(string id)
    {
        var bc = _config.Backends[id];
        var http = bc.Kind == BackendKind.Http;
        var isCodex = id == "codex";
        var isAgy = id == "agy";
        var isGoogle = id == "google-v2";

        Show(RowModel, !isGoogle);                 // google v2 = NMT, no model picker
        Show(RowEndpoint, http);
        Show(RowApiKey, http);
        Show(RowTarget, http);                     // target/targetLanguage
        Show(RowReasoning, isCodex);
        Show(RowFallback, isAgy);
        Show(RowTimeout, !http);

        // model catalog
        CmbModel.Items.Clear();
        if (_config.ModelCatalog.TryGetValue(id, out var models))
            foreach (var m in models) CmbModel.Items.Add(m);
        CmbModel.Text = bc.Model ?? string.Empty;

        TxtEndpoint.Text = bc.Endpoint ?? string.Empty;
        TxtApiKey.Text = bc.ApiKey ?? string.Empty;
        TxtTarget.Text = isGoogle ? (bc.Target ?? string.Empty) : (bc.TargetLanguage ?? string.Empty);
        TxtReasoning.Text = bc.Reasoning ?? string.Empty;
        TxtFallback.Text = bc.FallbackCommand ?? string.Empty;
        TxtTimeout.Text = bc.TimeoutSec.ToString();

        LblAuth.Text = AuthHint(id, bc);
    }

    private void FlushBackendFields(string id)
    {
        var bc = _config.Backends[id];
        var http = bc.Kind == BackendKind.Http;
        var isGoogle = id == "google-v2";

        if (!isGoogle) bc.Model = NullIfEmpty(CmbModel.Text);
        if (http)
        {
            bc.Endpoint = NullIfEmpty(TxtEndpoint.Text);
            bc.ApiKey = TxtApiKey.Text ?? string.Empty;
            if (isGoogle) bc.Target = NullIfEmpty(TxtTarget.Text);
            else bc.TargetLanguage = NullIfEmpty(TxtTarget.Text);
        }
        else
        {
            bc.Reasoning = NullIfEmpty(TxtReasoning.Text);
            bc.FallbackCommand = NullIfEmpty(TxtFallback.Text);
            if (int.TryParse(TxtTimeout.Text, out var secs) && secs > 0) bc.TimeoutSec = secs;
        }
    }

    private static string AuthHint(string id, BackendConfig bc)
    {
        if (bc.Kind == BackendKind.Http)
            return string.IsNullOrWhiteSpace(bc.ApiKey) ? "● 未配置 API Key(请在下方填写)" : "● 已配置 API Key";

        var paths = id == "agy"
            ? new[] { System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "agy", "bin", "agy.exe") }
            : Array.Empty<string>();
        var resolved = PathResolver.Resolve(bc.Command ?? id, paths);
        return resolved is null ? $"● 未找到命令 “{bc.Command ?? id}”" : $"● 已检测到 {bc.Command ?? id}(认证在首次翻译时确认)";
    }

    private void ValidateHotkey()
    {
        var spec = HotkeyParser.Parse(TxtHotkey.Text);
        LblHotkeyStatus.Text = spec.IsValid ? $"✓ {spec.Display}(保存时注册;若被占用会提示)" : $"✗ {spec.Error}";
    }

    private void BtnSave_Click(object sender, RoutedEventArgs e)
    {
        if (_currentBackendId is not null) FlushBackendFields(_currentBackendId);

        _config.General.ListenClipboard = ChkListen.IsChecked == true;
        _config.General.StartWithWindows = ChkStartup.IsChecked == true;
        if (_currentBackendId is not null) _config.General.ActiveBackend = _currentBackendId;
        _config.Hotkey.Translate = TxtHotkey.Text.Trim();
        _config.Popup.Style = (CmbStyle.SelectedItem as ComboBoxItem)?.Tag as string ?? "acrylic";
        _config.Popup.AutoDismissSeconds = (int)SldDismiss.Value;
        _config.Popup.KeepOnHover = ChkHover.IsChecked == true;

        try
        {
            _svc.Save(_config);
            StartupManager.Apply(_config.General.StartWithWindows);
            LblSaveStatus.Text = "已保存 ✓";
            Saved?.Invoke(_config);
            if (_currentBackendId is not null) LblAuth.Text = AuthHint(_currentBackendId, _config.Backends[_currentBackendId]);
        }
        catch (Exception ex)
        {
            LblSaveStatus.Text = "保存失败:" + ex.Message;
        }
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    private static void Show(UIElement el, bool visible) => el.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;

    private static string? NullIfEmpty(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}
