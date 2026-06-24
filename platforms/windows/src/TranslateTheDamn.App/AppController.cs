using System.Windows;
using TranslateTheDamn.App.Interop;
using TranslateTheDamn.App.Services;
using TranslateTheDamn.App.UI;
using TranslateTheDamn.Core;
using TranslateTheDamn.Core.Backends;
using TranslateTheDamn.Core.Config;

namespace TranslateTheDamn.App;

/// <summary>
/// Composition root + coordinator: owns the tray, the hidden message window, the clipboard and
/// hotkey services, the translation pipeline and the popup. Runs on the WPF UI thread.
/// </summary>
internal sealed class AppController : IDisposable
{
    private readonly ConfigService _configService;
    private readonly NativeMessageWindow _msgWindow;
    private readonly ClipboardListener _clipboard;
    private readonly HotkeyService _hotkey;
    private readonly TrayIconController _tray;

    private AppConfig _config;
    private TranslationPipeline _pipeline;
    private PopupWindow? _popup;
    private SettingsWindow? _settings;
    private int _requestSeq;

    public AppController()
    {
        _configService = new ConfigService();
        _config = _configService.LoadOrBootstrap();

        // Resolve the UI DISPLAY language BEFORE building the tray/popup/settings, so every piece of UI
        // is created in the right locale. SEPARATE from translation.TargetLanguage — never conflate.
        StringsLoader.Configure(LocaleResolver.Resolve(_config.General.UiLanguage, LocaleResolver.SystemLocaleId()));

        _pipeline = new TranslationPipeline(_config, TranslatorRegistry.Build(_config));

        _msgWindow = new NativeMessageWindow();
        _msgWindow.MessageReceived += OnWindowMessage;

        _clipboard = new ClipboardListener(_msgWindow.Handle);
        _clipboard.TextCopied += text => Trigger(text, TriggerSource.Clipboard);

        _hotkey = new HotkeyService(_msgWindow.Handle);
        _hotkey.HotkeyPressed += OnHotkeyPressed;

        _tray = new TrayIconController();
        _tray.ToggleListenRequested += ToggleListening;
        _tray.OpenSettingsRequested += OpenSettings;
        _tray.ExitRequested += () => Application.Current.Shutdown();

        ApplyConfig(initial: true);
    }

    private void OnWindowMessage(int msg, IntPtr wParam, IntPtr lParam)
    {
        switch (msg)
        {
            case NativeMethods.WM_CLIPBOARDUPDATE:
                _clipboard.OnClipboardUpdate();
                break;
            case NativeMethods.WM_HOTKEY:
                _hotkey.OnHotkey(wParam.ToInt32());
                break;
        }
    }

    private void OnHotkeyPressed()
    {
        string? text = null;
        try { if (Clipboard.ContainsText()) text = Clipboard.GetText(); } catch { }
        if (!string.IsNullOrWhiteSpace(text)) Trigger(text!, TriggerSource.Hotkey);
    }

    private async void Trigger(string text, TriggerSource source)
    {
        // Skip work the pipeline would filter out (avoids a flash of the loading popup).
        if (_pipeline.Accept(text, source) is null) return;

        var id = ++_requestSeq;
        var backend = _pipeline.ActiveBackendId;
        var popup = EnsurePopup();
        popup.ShowLoading(text, backend);

        TranslationResult? result;
        try { result = await _pipeline.RunAsync(text, source); }
        catch (Exception ex) { result = TranslationResult.Failure(TranslateStatus.UnknownFail, ex.Message); }

        if (id != _requestSeq) return;       // superseded by a newer trigger
        if (result is null) return;           // filtered / canceled

        // Feed the recent-translation history (newest first) so the popup offers ◀ ▶ navigation
        // over the cache; index 0 = the just-queried entry. Navigation never re-invokes the model.
        if (result.Ok) popup.ShowResults(_pipeline.RecentHistory(), 0, backend);
        else popup.ShowError(text, result.Error ?? "翻译失败", backend);
    }

    private PopupWindow EnsurePopup()
    {
        if (_popup is not null) return _popup;
        _popup = new PopupWindow(_config.Popup);
        _popup.CopyRequested += OnCopyRequested;
        return _popup;
    }

    private void OnCopyRequested(string translation)
    {
        try
        {
            _clipboard.MarkSelfWrite(translation);   // don't re-translate our own write
            _pipeline.NoteClipboardText(translation);
            Clipboard.SetText(translation);
        }
        catch { /* clipboard busy */ }
    }

    private void ToggleListening()
    {
        _config.General.ListenClipboard = !_config.General.ListenClipboard;
        ApplyListening();
        _configService.Save(_config);
    }

    private void ApplyListening()
    {
        if (_config.General.ListenClipboard) _clipboard.Start();
        else _clipboard.Stop();
        _tray.SetListening(_config.General.ListenClipboard);
    }

    private void ApplyConfig(bool initial)
    {
        ApplyListening();

        var err = _hotkey.Register(_config.Hotkey.Translate);
        if (err is not null) _tray.Notify("热键未注册", err);

        if (initial && _config.General.StartWithWindows)
            StartupManager.Apply(true);
    }

    private void OpenSettings()
    {
        if (_settings is not null)
        {
            // Single instance: surface the existing settings window instead of opening a second one.
            try
            {
                if (_settings.WindowState == WindowState.Minimized)
                    _settings.WindowState = WindowState.Normal;   // Activate() won't un-minimize
                _settings.Activate();
                _settings.Topmost = true;    // win the foreground race from a tray-only app,
                _settings.Topmost = false;   // then drop topmost so it stays a normal window
                _settings.Focus();
                return;
            }
            catch
            {
                _settings = null;   // stale reference (window already gone) -> recreate below
            }
        }
        _settings = new SettingsWindow(_configService);
        _settings.Saved += OnSettingsSaved;
        // Display-language hot-switch: re-localize the tray menu/tooltip in place (the catalog is already
        // reconfigured by the settings window before it raises this). A full save still recreates the popup.
        _settings.LocaleChanged += () => _tray.RefreshLocalizedText();
        _settings.Closed += (_, _) => _settings = null;
        _settings.Show();
        _settings.Activate();
    }

    private void OnSettingsSaved(AppConfig newConfig)
    {
        _config = newConfig;
        _pipeline = new TranslationPipeline(_config, TranslatorRegistry.Build(_config));

        // popup config may have changed -> recreate lazily
        if (_popup is not null)
        {
            _popup.CopyRequested -= OnCopyRequested;
            try { _popup.Close(); } catch { }
            _popup = null;
        }

        ApplyConfig(initial: false);
    }

    public void Dispose()
    {
        _hotkey.Dispose();
        _clipboard.Dispose();
        _tray.Dispose();
        _msgWindow.Dispose();
        try { _popup?.Close(); } catch { }
    }
}
