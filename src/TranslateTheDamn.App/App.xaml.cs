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
