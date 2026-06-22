using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using TranslateTheDamn.App.Interop;
using TranslateTheDamn.App.Services;
using TranslateTheDamn.Core.Backends;
using TranslateTheDamn.Core.Backends.Manifest;
using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.App.UI;

public partial class SettingsWindow : Window
{
    private static readonly string[] BackendOrder = { "claude", "codex", "copilot", "agy", "opencode", "kimi", "mimo", "google-v2", "doubao" };

    private readonly ConfigService _svc;
    private readonly AppConfig _config;
    private string? _currentBackendId;
    private bool _loaded;
    private CancellationTokenSource? _doctorCts;   // ties an in-flight doctor probe to the window lifetime
    private CancellationTokenSource? _modelsCts;   // ties an in-flight live model enumeration to the selected backend / window

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

    protected override void OnClosed(EventArgs e)
    {
        _doctorCts?.Cancel();   // stop any in-flight (deep) probe so it doesn't keep running after close
        _doctorCts?.Dispose();
        _modelsCts?.Cancel();   // stop any in-flight model enumeration
        _modelsCts?.Dispose();
        base.OnClosed(e);
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

        // unified target language (drives every prompt-based backend via {target})
        CmbTargetLang.Items.Clear();
        foreach (var lang in new[] { "简体中文", "繁體中文", "English", "日本語", "한국어", "Français", "Deutsch", "Español", "Русский", "Português" })
            CmbTargetLang.Items.Add(lang);
        CmbTargetLang.Text = string.IsNullOrWhiteSpace(_config.Translation.TargetLanguage) ? "简体中文" : _config.Translation.TargetLanguage;

        // backends — ordered doubao(API) -> google(API) -> other API -> CLI -> 暂不支持; Tag = raw id.
        CmbBackend.Items.Clear();
        foreach (var id in OrderedBackendIds())
            CmbBackend.Items.Add(new ComboBoxItem { Content = BackendDisplay(id), Tag = id });
        _currentBackendId = _config.Backends.ContainsKey(_config.General.ActiveBackend)
            ? _config.General.ActiveBackend
            : (CmbBackend.Items.Count > 0 ? (string?)((ComboBoxItem)CmbBackend.Items[0]!).Tag : null);
        SelectBackendItem(_currentBackendId);
        CmbBackend.SelectionChanged += CmbBackend_SelectionChanged;
        if (_currentBackendId is not null) LoadBackendFields(_currentBackendId);
    }

    /// <summary>Backend ids in display order: doubao(API), google(API), other API, CLI, then 暂不支持(agy).</summary>
    private IEnumerable<string> OrderedBackendIds()
    {
        int Rank(string id)
        {
            if (id == "agy") return 4;                                    // 暂不支持 last
            if (id == "doubao") return 0;
            if (id == "google-v2") return 1;
            return _config.Backends[id].Kind == BackendKind.Http ? 2 : 3; // other API, then CLI
        }
        return _config.Backends.Keys
            .OrderBy(Rank)
            .ThenBy(id => { var i = Array.IndexOf(BackendOrder, id); return i < 0 ? int.MaxValue : i; })
            .ThenBy(id => id, StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>Rebuild the backend dropdown and select <paramref name="selectId"/> (guards the selection event).</summary>
    private void RebuildBackendList(string? selectId)
    {
        _loaded = false;
        CmbBackend.Items.Clear();
        foreach (var id in OrderedBackendIds())
            CmbBackend.Items.Add(new ComboBoxItem { Content = BackendDisplay(id), Tag = id });
        SelectBackendItem(selectId);
        _currentBackendId = selectId;
        _loaded = true;
        if (selectId is not null) LoadBackendFields(selectId);
    }

    /// <summary>Dropdown label: backend name (without the cosmetic "-http" suffix) + a CLI/API tag (+ agy's note).</summary>
    private string BackendDisplay(string id)
    {
        var kind = _config.Backends[id].Kind == BackendKind.Http ? "API" : "CLI";
        var note = id == "agy" ? " · 暂不支持" : "";
        var name = id.EndsWith("-http", StringComparison.OrdinalIgnoreCase) ? id[..^5] : id;
        return $"{name}  ·  {kind}{note}";
    }

    private void SelectBackendItem(string? id)
    {
        foreach (ComboBoxItem item in CmbBackend.Items)
            if ((string?)item.Tag == id) { CmbBackend.SelectedItem = item; return; }
    }

    private void CmbBackend_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_loaded) return;
        if (_currentBackendId is not null) FlushBackendFields(_currentBackendId);
        _currentBackendId = (CmbBackend.SelectedItem as ComboBoxItem)?.Tag as string;
        if (_currentBackendId is not null) LoadBackendFields(_currentBackendId);
    }

    private void LoadBackendFields(string id)
    {
        var bc = _config.Backends[id];
        var http = bc.Kind == BackendKind.Http;
        var isAgy = id == "agy";
        var isGoogle = id == "google-v2";
        var isDoubao = id == "doubao";
        var tiers = EffortTiersFor(id);

        Show(RowModel, !isGoogle);                 // google v2 = NMT, no model picker
        Show(RowEndpoint, http);
        Show(RowApiKey, http);
        // Target field only feeds google-v2 ({target}) / doubao ({targetLanguage}) request bodies.
        // openai-http/anthropic-http (and CLI backends) get their target from the promptTemplate, so the
        // field is irrelevant there — hide it to avoid the "empty target language" confusion.
        Show(RowTarget, isGoogle || isDoubao);
        Show(RowReasoning, tiers.Count > 0);       // effort selector wherever the manifest declares tiers (Law-6; was hardcoded isCodex)
        Show(RowFallback, isAgy);
        Show(RowTimeout, !http);
        Show(RowDoctor, !http);                    // doctor = CLI vendors only (excludes google-v2/doubao)
        var isCustomApi = http && !isGoogle && !isDoubao;   // generic openai/anthropic provider -> protocol selectable
        Show(RowProtocol, isCustomApi);
        BtnDeleteProvider.IsEnabled = !BackendOrder.Contains(id);   // only custom (non-builtin) backends are deletable
        TxtDoctorResult.Visibility = Visibility.Collapsed;

        // protocol selector (custom api providers)
        CmbProtocol.Items.Clear();
        CmbProtocol.Items.Add(new ComboBoxItem { Content = "OpenAI (/chat/completions)", Tag = "openai" });
        CmbProtocol.Items.Add(new ComboBoxItem { Content = "Anthropic (/messages)", Tag = "anthropic" });
        CmbProtocol.SelectedIndex = string.Equals(bc.Protocol, "anthropic", StringComparison.OrdinalIgnoreCase) ? 1 : 0;

        // model catalog — show the static snapshot instantly, then refresh live (opencode/mimo `models`)
        CmbModel.Items.Clear();
        if (_config.ModelCatalog.TryGetValue(id, out var models))
            foreach (var m in models) CmbModel.Items.Add(m);
        CmbModel.Text = bc.Model ?? string.Empty;
        _ = RefreshModelsAsync(id);   // no-op for backends without a modelsCmd; replaces the catalog when live ids arrive

        TxtEndpoint.Text = bc.Endpoint ?? string.Empty;
        TxtApiKey.Password = bc.ApiKey ?? string.Empty;   // masked (PasswordBox)
        TxtTarget.Text = isGoogle ? (bc.Target ?? string.Empty) : (bc.TargetLanguage ?? string.Empty);
        CmbReasoning.Items.Clear();
        foreach (var t in tiers) CmbReasoning.Items.Add(t);
        CmbReasoning.Text = bc.Reasoning ?? string.Empty;
        TxtFallback.Text = bc.FallbackCommand ?? string.Empty;
        TxtTimeout.Text = bc.TimeoutSec.ToString();

        LblAuth.Text = AuthHint(id, bc);
    }

    /// <summary>Replace the model dropdown with the backend's LIVE model list (manifest <c>modelsCmd</c>),
    /// preserving the user's current selection. Guarded so a slow enumeration can't clobber the dropdown
    /// after the user switched backends or closed the window; on any failure the static catalog stays.</summary>
    private Task RefreshModelsAsync(string id) => RefreshModelsAsync(id, _config.Backends[id]);

    private async Task RefreshModelsAsync(string id, BackendConfig cfg)
    {
        _modelsCts?.Cancel();
        _modelsCts?.Dispose();
        _modelsCts = new CancellationTokenSource();
        var token = _modelsCts.Token;
        try
        {
            var live = await ModelEnumerator.EnumerateAsync(id, cfg, null, token);
            if (token.IsCancellationRequested || _currentBackendId != id || !IsLoaded || live.Count == 0) return;
            var keep = CmbModel.Text;   // preserve the user's current selection / typed value
            CmbModel.Items.Clear();
            foreach (var m in live) CmbModel.Items.Add(m);
            CmbModel.Text = keep;
        }
        catch { /* keep the static catalog */ }
    }

    /// <summary>On opening the model dropdown for an HTTP/API backend, fetch models from the CURRENT
    /// (possibly unsaved) baseURL+key via GET /models — so a freshly-typed custom provider populates
    /// without needing a save + reselect. CLI backends already enumerate on selection.</summary>
    private async void CmbModel_DropDownOpened(object sender, EventArgs e)
    {
        if (_currentBackendId is null) return;
        var bc = _config.Backends[_currentBackendId];
        if (bc.Kind != BackendKind.Http) return;
        var probe = new BackendConfig
        {
            Type = "http",
            Endpoint = NullIfEmpty(TxtEndpoint.Text),
            ApiKey = TxtApiKey.Password,
            Protocol = (CmbProtocol.SelectedItem as ComboBoxItem)?.Tag as string ?? bc.Protocol
        };
        if (string.IsNullOrWhiteSpace(probe.Endpoint) || string.IsNullOrWhiteSpace(probe.ApiKey)) return;
        await RefreshModelsAsync(_currentBackendId, probe);
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
            bc.ApiKey = TxtApiKey.Password;   // PasswordBox.Password is never null
            if (isGoogle) bc.Target = NullIfEmpty(TxtTarget.Text);
            else if (id == "doubao") bc.TargetLanguage = NullIfEmpty(TxtTarget.Text);
            else bc.Protocol = (CmbProtocol.SelectedItem as ComboBoxItem)?.Tag as string ?? bc.Protocol ?? "openai";  // custom openai/anthropic provider
        }
        else
        {
            bc.Reasoning = NullIfEmpty(CmbReasoning.Text);
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
        _config.Translation.TargetLanguage = NullIfEmpty(CmbTargetLang.Text) ?? "简体中文";
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

    /// <summary>Add a custom API provider (generic openai/anthropic http backend). User fills endpoint/key/model/protocol then saves.</summary>
    private void BtnAddProvider_Click(object sender, RoutedEventArgs e)
    {
        var name = InputBox.Show(this, "新增 API provider", "provider 名称(英文 id,例如 my-deepseek):");
        if (string.IsNullOrWhiteSpace(name)) return;
        var id = name.Trim();
        if (_config.Backends.ContainsKey(id)) { LblSaveStatus.Text = $"已存在:{id}"; return; }
        if (_currentBackendId is not null) FlushBackendFields(_currentBackendId);
        _config.Backends[id] = new BackendConfig { Type = "http", Protocol = "openai", Endpoint = "", ApiKey = "", Model = "", TimeoutSec = 30 };
        RebuildBackendList(id);
        LblSaveStatus.Text = $"已新增 {id} · 填 Endpoint/Key/模型/协议后点保存";
    }

    /// <summary>Discover the user's OWN static API keys (env + opencode + codex), show a consent checklist,
    /// and import the selected ones as http backends. Never reads OAuth stores; keys persist on save.</summary>
    private void BtnDetectKeys_Click(object sender, RoutedEventArgs e)
    {
        IReadOnlyList<DiscoveredCredential> found;
        try { found = CredentialDiscovery.Scan(); }
        catch (Exception ex) { LblSaveStatus.Text = "检测失败(" + ex.GetType().Name + ")"; return; }
        if (found.Count == 0) { LblSaveStatus.Text = "未在本机发现可导入的静态密钥(env / opencode / codex)"; return; }

        var selected = CredentialImportDialog.Show(this, found);
        if (selected is null || selected.Count == 0) return;
        if (_currentBackendId is not null) FlushBackendFields(_currentBackendId);

        string? lastId = null;
        var n = 0;
        foreach (var c in selected)
        {
            var id = UniqueBackendId(c.SuggestedId);
            _config.Backends[id] = new BackendConfig { Type = "http", Protocol = c.Protocol, Endpoint = c.BaseUrl, ApiKey = c.Key, Model = "", TimeoutSec = 30 };
            lastId = id; n++;
        }
        RebuildBackendList(lastId);
        LblSaveStatus.Text = $"已导入 {n} 个 provider(点保存写入 config.json)";
    }

    private string UniqueBackendId(string baseId)
    {
        if (!_config.Backends.ContainsKey(baseId)) return baseId;
        for (var i = 2; ; i++) { var id = $"{baseId}-{i}"; if (!_config.Backends.ContainsKey(id)) return id; }
    }

    /// <summary>Delete the selected CUSTOM provider (built-in backends are protected). Persisted on save.</summary>
    private void BtnDeleteProvider_Click(object sender, RoutedEventArgs e)
    {
        var id = _currentBackendId;
        if (id is null) return;
        if (BackendOrder.Contains(id)) { LblSaveStatus.Text = "内置后端不可删除"; return; }
        _config.Backends.Remove(id);
        if (string.Equals(_config.General.ActiveBackend, id, StringComparison.OrdinalIgnoreCase))
            _config.General.ActiveBackend = "claude";
        RebuildBackendList(OrderedBackendIds().FirstOrDefault());
        LblSaveStatus.Text = $"已删除 {id}(保存后写入)";
    }

    /// <summary>Run the manifest-driven doctor for the selected backend (async, off the UI thread via
    /// ProcessRunner). Probes the user's UNSAVED values; never echoes the API key into the results.</summary>
    private async void BtnDoctor_Click(object sender, RoutedEventArgs e)
    {
        if (_currentBackendId is null) return;
        FlushBackendFields(_currentBackendId);            // probe sees the user's unsaved Command/Model/Reasoning

        // Tie the probe to the window lifetime: closing the window cancels it (a deep -p probe must not
        // keep running / spending after the dialog is gone).
        _doctorCts?.Cancel();
        _doctorCts?.Dispose();
        _doctorCts = new CancellationTokenSource();
        var token = _doctorCts.Token;

        var id = _currentBackendId;
        var bc = _config.Backends[id];
        var deep = ChkDeep.IsChecked == true;

        BtnDoctor.IsEnabled = false;
        TxtDoctorResult.Visibility = Visibility.Visible;
        TxtDoctorResult.Text = deep ? "诊断中(含联网探测)…" : "诊断中…";
        try
        {
            var doctor = new DoctorService(_config.Translation.PromptTemplate);
            var report = await doctor.RunAsync(id, bc, deep, token);
            if (!token.IsCancellationRequested) RenderDoctor(report);
        }
        catch (OperationCanceledException) { /* window closed mid-probe */ }
        catch (Exception ex)
        {
            // Doctor is CLI-only (RowDoctor is hidden for http backends), so no API key is in scope;
            // still surface only the exception type, never a raw message, to keep the no-leak guarantee.
            if (!token.IsCancellationRequested) TxtDoctorResult.Text = "诊断失败(" + ex.GetType().Name + ")";
        }
        finally
        {
            if (IsLoaded && !token.IsCancellationRequested) BtnDoctor.IsEnabled = true;
        }
    }

    private void RenderDoctor(DoctorReport report)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"{Glyph(report.Overall)} {report.BackendId} — 总体:{StatusZh(report.Overall)}");
        foreach (var c in report.Checks)
            sb.AppendLine($"  {Glyph(c.Status)} {c.Name}:{c.Detail}");
        TxtDoctorResult.Text = sb.ToString().TrimEnd();

        // drive the (previously static) auth lamp live from the doctor's auth row
        var auth = report.Checks.FirstOrDefault(c => c.Name.StartsWith("认证", StringComparison.Ordinal));
        LblAuth.Text = auth is not null ? $"{Glyph(auth.Status)} {auth.Detail}" : $"{Glyph(report.Overall)} {StatusZh(report.Overall)}";
    }

    private static List<string> EffortTiersFor(string id) =>
        BackendManifest.Load().Backends.TryGetValue(id, out var def) ? (def.EffortTiers ?? new List<string>()) : new List<string>();

    private static string Glyph(DoctorStatus s) => s switch
    {
        DoctorStatus.Ok => "✓",
        DoctorStatus.Degraded => "▲",
        DoctorStatus.Fail => "✗",
        _ => "●"
    };

    private static string StatusZh(DoctorStatus s) => s switch
    {
        DoctorStatus.Ok => "正常",
        DoctorStatus.Degraded => "可用(有警告)",
        DoctorStatus.Fail => "失败",
        _ => "未知"
    };

    private static void Show(UIElement el, bool visible) => el.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;

    private static string? NullIfEmpty(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}
