using System.Windows;

namespace TranslateTheDamn.App;

/// <summary>
/// Tray-resident application entry point. No main window: the app lives in the system tray and
/// shows transient popups. All wiring lives in <see cref="AppController"/>.
/// </summary>
public partial class App : System.Windows.Application
{
    private AppController? _controller;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // One-shot icon generator (build tooling): TranslateTheDamn.exe --gen-icon <path>
        if (e.Args.Length >= 2 && e.Args[0] == "--gen-icon")
        {
            try { UI.AppIcon.WriteIcoFile(e.Args[1]); Shutdown(0); }
            catch (Exception ex) { MessageBox.Show(ex.ToString()); Shutdown(1); }
            return;
        }

        // Dev-only visual-walkthrough harness (env-gated on TTD_SHOT_KIND; mirrors the macOS
        // ScreenshotHarness). Shows ONE window in a requested state and stays alive; inert otherwise.
        if (ScreenshotHarness.RunIfRequested()) return;

        try
        {
            _controller = new AppController();
        }
        catch (Exception ex)
        {
            MessageBox.Show("启动失败:\n" + ex, "translate-the-damn", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _controller?.Dispose();
        base.OnExit(e);
    }
}
