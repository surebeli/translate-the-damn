using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using TranslateTheDamn.App.Interop;
using TranslateTheDamn.App.Services;
using TranslateTheDamn.Core;
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

    /// <summary>Raised when the UI DISPLAY language is hot-switched, so the host re-localizes the tray.</summary>
    public event Action? LocaleChanged;

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
        // Derive the example from the actual default so it never drifts; the occupied-key note is shown
        // only on the live status line (LblHotkeyStatus), so it isn't repeated here.
        LblHotkeyExample.Text = $"例:{HotkeyConfig.DefaultTranslate}。按下热键翻译当前剪贴板内容。";
        TxtHotkey.TextChanged += (_, _) => ValidateHotkey();
        ValidateHotkey();

        // popup style
        CmbStyle.Items.Clear();
        CmbStyle.Items.Add(new ComboBoxItem { Content = StringsLoader.Get("settings.style.acrylic"), Tag = "acrylic" });
        CmbStyle.Items.Add(new ComboBoxItem { Content = StringsLoader.Get("settings.style.solid"), Tag = "solid" });
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
        // UI DISPLAY language (spec §4): "Follow system" + the available locales — SEPARATE from the
        // translation target above. Selecting it hot-reloads the UI (Relocalize) + tray (LocaleChanged).
        CmbUiLang.Items.Clear();
        CmbUiLang.Items.Add(new ComboBoxItem { Content = StringsLoader.Get("settings.uilang.system"), Tag = "" });
        foreach (var id in LocaleResolver.Available)
            CmbUiLang.Items.Add(new ComboBoxItem { Content = UiLanguageDisplayName(id), Tag = id });
        SelectUiLangItem(_config.General.UiLanguage);
        CmbUiLang.SelectionChanged += CmbUiLang_SelectionChanged;

        // Keep the translation target consistent with the resolved display language (the two reviewed
        // fixes): follow-system -> system language (fallback 简体中文); explicit display -> its target name.
        CmbTargetLang.Text = TargetForDisplay();

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

        Relocalize();   // apply localized strings to the static labels/buttons/title
    }

    // ===== i18n: UI display language (separate from translation target) =====

    private static string UiLanguageDisplayName(string id) => id switch
    {
        "zh-CN" => "简体中文",
        "en" => "English",
        "ja" => "日本語",
        "ko" => "한국어",
        _ => id
    };

    private void SelectUiLangItem(string id)
    {
        var want = id ?? string.Empty;
        foreach (ComboBoxItem item in CmbUiLang.Items)
            if (((string?)item.Tag ?? string.Empty) == want) { CmbUiLang.SelectedItem = item; return; }
    }

    /// <summary>Hot-switch the UI DISPLAY language: persist the selection, reconfigure the catalog,
    /// re-localize the open window in place (state preserved), re-derive the target, and ask the host
    /// to re-localize the tray. The translation target is kept consistent (the two reviewed fixes).</summary>
    private void CmbUiLang_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_loaded) return;
        var id = (CmbUiLang.SelectedItem as ComboBoxItem)?.Tag as string ?? string.Empty;
        _config.General.UiLanguage = id;
        StringsLoader.Configure(LocaleResolver.Resolve(id, LocaleResolver.SystemLocaleId()));
        StringsLoader.Reload();
        Relocalize();
        CmbTargetLang.Text = TargetForDisplay();   // target follows display
        LocaleChanged?.Invoke();                    // host re-localizes the tray
    }

    /// <summary>Translation target consistent with the resolved DISPLAY language: explicit display ->
    /// its matching target name; "follow system" -> the system language mapped onto the (broader) target
    /// list, falling back to 简体中文 when unobtainable/unsupported. Mirrors the macOS VM logic.</summary>
    private string TargetForDisplay() => (_config.General.UiLanguage ?? string.Empty).Trim() switch
    {
        "zh-CN" => "简体中文",
        "en" => "English",
        "ja" => "日本語",
        "ko" => "한국어",
        _ => SystemTargetLanguageName()   // "" follow-system (or anything unexpected)
    };

    private static string SystemTargetLanguageName()
    {
        var sys = LocaleResolver.SystemLocaleId().ToLowerInvariant();
        var lang = sys.Split('-', '_')[0];
        if (lang == "zh")
            return (sys.Contains("hant") || sys.Contains("tw") || sys.Contains("hk") || sys.Contains("mo")) ? "繁體中文" : "简体中文";
        return lang switch
        {
            "en" => "English",
            "ja" => "日本語",
            "ko" => "한국어",
            "fr" => "Français",
            "de" => "Deutsch",
            "es" => "Español",
            "ru" => "Русский",
            "pt" => "Português",
            _ => "简体中文"   // unobtainable / unsupported -> Chinese (product default)
        };
    }

    /// <summary>Re-apply localized strings to the static UI (initial load + display-language hot-switch),
    /// preserving window state. Only labels with an existing shared key are set here; Windows-specific
    /// strings without a macOS counterpart (LblGroupTranslate "翻译", LblTargetHint, ChkDeep, the doctor
    /// result rendering, SetStatus/AuthHint messages) still need new shared keys — see the handoff.</summary>
    private void Relocalize()
    {
        var v = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
        Title = v is not null
            ? $"{StringsLoader.Get("settings.title")}   v{v.Major}.{v.Minor}.{v.Build}"
            : StringsLoader.Get("settings.title");

        LblGroupTrigger.Text = StringsLoader.Get("settings.group.trigger");
        LblGroupTranslate.Text = StringsLoader.Get("settings.group.translate");
        LblGroupBackend.Text = StringsLoader.Get("settings.group.backend");
        LblGroupPopup.Text = StringsLoader.Get("settings.group.popup");
        LblGroupGeneral.Text = StringsLoader.Get("settings.group.general");

        ChkListen.Content = StringsLoader.Get("settings.field.listen");
        LblHotkey.Text = StringsLoader.Get("settings.field.hotkey");
        LblHotkeyExample.Text = StringsLoader.Get("settings.hotkey.hint");
        LblTarget.Text = StringsLoader.Get("settings.field.target");
        LblTargetHint.Text = StringsLoader.Get("settings.target.hint");
        LblUiLang.Text = StringsLoader.Get("settings.field.uilang");
        LblBackend.Text = StringsLoader.Get("settings.field.backend");
        LblModel.Text = StringsLoader.Get("settings.field.model");
        LblProtocol.Text = StringsLoader.Get("settings.field.protocol");
        LblReasoning.Text = StringsLoader.Get("settings.field.reasoning");
        LblFallback.Text = StringsLoader.Get("settings.field.fallback");
        LblTimeout.Text = StringsLoader.Get("settings.field.timeout");
        LblStyle.Text = StringsLoader.Get("settings.field.style");
        LblAutoDismiss.Text = StringsLoader.Get("settings.field.autodismiss");
        ChkHover.Content = StringsLoader.Get("settings.field.keephover");
        ChkStartup.Content = StringsLoader.Get("settings.field.startup");
        LblConfigHint.Text = StringsLoader.Get("settings.general.configHint");

        BtnDoctor.Content = StringsLoader.Get("settings.doctor.button");
        ChkDeep.Content = StringsLoader.Get("settings.doctor.deep");
        BtnAddProvider.Content = StringsLoader.Get("settings.provider.add");
        BtnDeleteProvider.Content = StringsLoader.Get("settings.provider.delete");
        BtnDetectKeys.Content = StringsLoader.Get("settings.provider.detectKeys");
        BtnSave.Content = StringsLoader.Get("settings.button.save");
        BtnClose.Content = StringsLoader.Get("settings.button.close");

        ValidateHotkey();   // re-render the hotkey status line in the new language
        if (_currentBackendId is not null) SetAuthLamp(_currentBackendId, _config.Backends[_currentBackendId]);
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
        CmbReasoning.Items.Clear();
        foreach (var t in tiers) CmbReasoning.Items.Add(t);
        CmbReasoning.Text = bc.Reasoning ?? string.Empty;
        TxtFallback.Text = bc.FallbackCommand ?? string.Empty;
        TxtTimeout.Text = bc.TimeoutSec.ToString();

        SetAuthLamp(id, bc);
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
            // google-v2 / doubao target language is derived from the unified target in SyncTranslationApiTargets().
            if (!isGoogle && id != "doubao") bc.Protocol = (CmbProtocol.SelectedItem as ComboBoxItem)?.Tag as string ?? bc.Protocol ?? "openai";  // custom openai/anthropic provider
        }
        else
        {
            bc.Reasoning = NullIfEmpty(CmbReasoning.Text);
            bc.FallbackCommand = NullIfEmpty(TxtFallback.Text);
            if (int.TryParse(TxtTimeout.Text, out var secs) && secs > 0) bc.TimeoutSec = secs;
        }
    }

    private static (string Text, bool Ready) AuthHint(string id, BackendConfig bc)
    {
        if (bc.Kind == BackendKind.Http)
            return string.IsNullOrWhiteSpace(bc.ApiKey)
                ? (StringsLoader.Get("settings.auth.httpMissing"), false)
                : (StringsLoader.Get("settings.auth.httpReady"), true);

        var paths = id == "agy"
            ? new[] { System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "agy", "bin", "agy.exe") }
            : Array.Empty<string>();
        var resolved = PathResolver.Resolve(bc.Command ?? id, paths);
        var cmd = bc.Command ?? id;
        return resolved is null
            ? (StringsLoader.Get("settings.auth.cliMissing").Replace("{command}", cmd), false)
            : (StringsLoader.Get("settings.auth.cliReady").Replace("{command}", cmd), true);
    }

    /// <summary>Set the per-backend auth lamp text AND colour it by readiness: a missing key / missing CLI
    /// reads as an error (red), a ready backend as green. Without the colour the ● glyph alone is the only
    /// pass/fail cue and it renders the same dim gray in both states.</summary>
    private void SetAuthLamp(string id, BackendConfig bc)
    {
        var (text, ready) = AuthHint(id, bc);
        LblAuth.Text = text;
        LblAuth.Foreground = ready ? StatusOkBrush : StatusErrorBrush;
    }

    private void ValidateHotkey()
    {
        var spec = HotkeyParser.Parse(TxtHotkey.Text);
        // Mirror the macOS hotkey status keys: valid -> "✓ {hotkey} available", invalid -> "✗ Invalid format".
        LblHotkeyStatus.Text = spec.IsValid
            ? StringsLoader.Get("settings.hotkey.ok").Replace("{hotkey}", spec.Display)
            : StringsLoader.Get("settings.hotkey.invalid");
        LblHotkeyStatus.Foreground = spec.IsValid ? StatusOkBrush : StatusErrorBrush;
    }

    private void BtnSave_Click(object sender, RoutedEventArgs e)
    {
        if (_currentBackendId is not null) FlushBackendFields(_currentBackendId);

        _config.General.ListenClipboard = ChkListen.IsChecked == true;
        _config.General.StartWithWindows = ChkStartup.IsChecked == true;
        _config.General.UiLanguage = (CmbUiLang.SelectedItem as ComboBoxItem)?.Tag as string ?? "";
        if (_currentBackendId is not null) _config.General.ActiveBackend = _currentBackendId;
        _config.Hotkey.Translate = TxtHotkey.Text.Trim();
        _config.Translation.TargetLanguage = NullIfEmpty(CmbTargetLang.Text) ?? "简体中文";
        SyncTranslationApiTargets();   // the single 目标语言 also drives google-v2 / doubao (no per-backend field)
        _config.Popup.Style = (CmbStyle.SelectedItem as ComboBoxItem)?.Tag as string ?? "acrylic";
        _config.Popup.AutoDismissSeconds = (int)SldDismiss.Value;
        _config.Popup.KeepOnHover = ChkHover.IsChecked == true;

        try
        {
            _svc.Save(_config);
            StartupManager.Apply(_config.General.StartWithWindows);
            SetStatus(StringsLoader.Get("settings.status.saved"), StatusKind.Ok);
            Saved?.Invoke(_config);
            if (_currentBackendId is not null) SetAuthLamp(_currentBackendId, _config.Backends[_currentBackendId]);
        }
        catch (Exception ex)
        {
            SetStatus("保存失败:" + ex.Message, StatusKind.Error);
        }
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    /// <summary>Semantic colour for the save-status line: success=green, error=red, neutral info=gray.
    /// Keeps the status text legible against the dark theme and makes failures read as failures (a green
    /// "保存失败" looked like success). Colours match the popup error/loading palette for consistency.</summary>
    private enum StatusKind { Ok, Error, Info }

    private static readonly System.Windows.Media.Brush StatusOkBrush =
        new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0x8F, 0xE3, 0xC0));  // calm green
    private static readonly System.Windows.Media.Brush StatusErrorBrush =
        new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0xFF, 0xB4, 0xA9));  // warm red — single-sourced with popup error #FFB4A9
    private static readonly System.Windows.Media.Brush StatusInfoBrush =
        new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0xC9, 0xC9, 0xC9));  // neutral gray
    private static readonly System.Windows.Media.Brush StatusWarnBrush =
        new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0xE8, 0xC0, 0x7A));  // amber (degraded)

    private void SetStatus(string text, StatusKind kind)
    {
        LblSaveStatus.Text = text;
        LblSaveStatus.Foreground = kind switch
        {
            StatusKind.Ok => StatusOkBrush,
            StatusKind.Error => StatusErrorBrush,
            _ => StatusInfoBrush,
        };
    }

    /// <summary>Add a custom API provider (generic openai/anthropic http backend). User fills endpoint/key/model/protocol then saves.</summary>
    private void BtnAddProvider_Click(object sender, RoutedEventArgs e)
    {
        var name = InputBox.Show(this, StringsLoader.Get("settings.provider.addTitle"), StringsLoader.Get("settings.provider.idPlaceholder"));
        if (string.IsNullOrWhiteSpace(name)) return;
        var id = name.Trim();
        if (_config.Backends.ContainsKey(id)) { SetStatus($"已存在:{id}", StatusKind.Error); return; }
        if (_currentBackendId is not null) FlushBackendFields(_currentBackendId);
        _config.Backends[id] = new BackendConfig { Type = "http", Protocol = "openai", Endpoint = "", ApiKey = "", Model = "", TimeoutSec = 30 };
        RebuildBackendList(id);
        SetStatus($"已新增 {id} · 填 Endpoint/Key/模型/协议后点保存", StatusKind.Info);
    }

    /// <summary>Discover the user's OWN static API keys (env + opencode + codex), show a consent checklist,
    /// and import the selected ones as http backends. Never reads OAuth stores; keys persist on save.</summary>
    private void BtnDetectKeys_Click(object sender, RoutedEventArgs e)
    {
        IReadOnlyList<DiscoveredCredential> found;
        try { found = CredentialDiscovery.Scan(); }
        catch (Exception ex) { SetStatus("检测失败(" + ex.GetType().Name + ")", StatusKind.Error); return; }
        if (found.Count == 0) { SetStatus("未在本机发现可导入的静态密钥(env / opencode / codex)", StatusKind.Info); return; }

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
        SetStatus($"已导入 {n} 个 provider(点保存写入 config.json)", StatusKind.Ok);
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
        if (BackendOrder.Contains(id)) { SetStatus("内置后端不可删除", StatusKind.Error); return; }
        _config.Backends.Remove(id);
        if (string.Equals(_config.General.ActiveBackend, id, StringComparison.OrdinalIgnoreCase))
            _config.General.ActiveBackend = "claude";
        RebuildBackendList(OrderedBackendIds().FirstOrDefault());
        SetStatus($"已删除 {id}(保存后写入)", StatusKind.Info);
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
        TxtDoctorResult.Foreground = StatusInfoBrush;     // transient "诊断中" reads as neutral, not pass/fail
        TxtDoctorResult.Text = deep ? StringsLoader.Get("settings.doctor.checkingDeep") : StringsLoader.Get("settings.doctor.checking");
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
            if (!token.IsCancellationRequested) { TxtDoctorResult.Foreground = StatusErrorBrush; TxtDoctorResult.Text = StringsLoader.Get("settings.doctor.failed") + "(" + ex.GetType().Name + ")"; }
        }
        finally
        {
            if (IsLoaded && !token.IsCancellationRequested) BtnDoctor.IsEnabled = true;
        }
    }

    /// <summary>Screenshot-harness hook: render a doctor verdict (result panel + auth lamp) without
    /// running a probe. Used only by <see cref="ScreenshotHarness"/>; no effect on normal use.</summary>
    internal void ApplyShotDoctor(DoctorReport report)
    {
        TxtDoctorResult.Visibility = Visibility.Visible;
        RenderDoctor(report);
    }

    private void RenderDoctor(DoctorReport report)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"{Glyph(report.Overall)} {report.BackendId} — {StringsLoader.Get("settings.doctor.overall")}:{StatusZh(report.Overall)}");
        foreach (var c in report.Checks)
            sb.AppendLine($"  {Glyph(c.Status)} {c.Name}:{c.Detail}");
        TxtDoctorResult.Foreground = report.Overall switch
        {
            DoctorStatus.Ok => StatusOkBrush,
            DoctorStatus.Degraded => StatusWarnBrush,
            DoctorStatus.Fail => StatusErrorBrush,
            _ => StatusInfoBrush,
        };
        TxtDoctorResult.Text = sb.ToString().TrimEnd();

        // drive the (previously static) auth lamp live from the doctor's auth row — colour it by the
        // auth check's own verdict (fall back to Overall when no auth row exists) so a failed auth reads red.
        var auth = report.Checks.FirstOrDefault(c => c.Name.StartsWith("认证", StringComparison.Ordinal));
        var lampStatus = auth?.Status ?? report.Overall;
        LblAuth.Text = auth is not null ? $"{Glyph(auth.Status)} {auth.Detail}" : $"{Glyph(report.Overall)} {StatusZh(report.Overall)}";
        LblAuth.Foreground = lampStatus switch
        {
            DoctorStatus.Ok => StatusOkBrush,
            DoctorStatus.Degraded => StatusWarnBrush,
            DoctorStatus.Fail => StatusErrorBrush,
            _ => StatusInfoBrush,
        };
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

    // Locale-aware doctor status word (kept the legacy name to avoid churn at the two call sites).
    private static string StatusZh(DoctorStatus s) => s switch
    {
        DoctorStatus.Ok => StringsLoader.Get("settings.doctor.status.ok"),
        DoctorStatus.Degraded => StringsLoader.Get("settings.doctor.status.degraded"),
        DoctorStatus.Fail => StringsLoader.Get("settings.doctor.status.fail"),
        _ => StringsLoader.Get("settings.doctor.status.unknown")
    };

    private static void Show(UIElement el, bool visible) => el.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;

    /// The single 目标语言 picker also drives the dedicated translation APIs: derive google-v2 / doubao's
    /// language code from the unified target so they don't need a separate per-backend target field.
    private void SyncTranslationApiTargets()
    {
        var lang = _config.Translation.TargetLanguage ?? "简体中文";
        if (_config.Backends.TryGetValue("google-v2", out var g)) g.Target = TranslationApiCode("google-v2", lang, g.Target);
        if (_config.Backends.TryGetValue("doubao", out var d)) d.TargetLanguage = TranslationApiCode("doubao", lang, d.TargetLanguage);
    }

    private static string TranslationApiCode(string backendId, string displayName, string? fallback)
    {
        var l = (displayName ?? string.Empty).Trim();
        string? code = l switch
        {
            "简体中文" => backendId == "google-v2" ? "zh-CN" : "zh",   // Google wants region codes for Chinese
            "繁體中文" => backendId == "google-v2" ? "zh-TW" : "zh-Hant",
            "English" => "en",
            "日本語" => "ja",
            "한국어" => "ko",
            "Français" => "fr",
            "Deutsch" => "de",
            "Español" => "es",
            "Русский" => "ru",
            "Português" => "pt",
            _ => null
        };
        if (code is not null) return code;
        var fb = (fallback ?? string.Empty).Trim();
        return fb.Length > 0 ? fb : l;
    }

    private static string? NullIfEmpty(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
}
