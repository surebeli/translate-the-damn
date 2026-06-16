using System.Windows;

namespace TranslateTheDamn.App;

/// <summary>
/// Tray-resident application entry point. There is no main window; the app lives in the
/// system tray and shows transient popups. Full wiring (tray, pipeline, clipboard, hotkey)
/// is added in later build phases.
/// </summary>
public partial class App : System.Windows.Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // P4+: construct ConfigService, TranslatorRegistry, TranslationPipeline,
        // TrayIconController, ClipboardListener, HotkeyService here.
    }
}
