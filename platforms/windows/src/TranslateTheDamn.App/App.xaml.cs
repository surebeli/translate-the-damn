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

        // Dev affordance for UI/visual walkthrough: show the popup with sample content and stay alive
        // (no tray, no backend). TranslateTheDamn.exe --demo-popup [error]
        if (e.Args.Length >= 1 && e.Args[0] == "--demo-popup")
        {
            var cfg = new Core.Config.PopupConfig { Style = "acrylic", AutoDismissSeconds = 0, KeepOnHover = true, Position = "top-center" };
            var popup = new UI.PopupWindow(cfg);
            const string src = "Hello world — this is a sample source sentence used to inspect the popup chrome: rounded corners, the single border, and the frosted-glass backdrop.";
            const string zh = "你好世界——这是一段用于检查浮窗外观的示例文本:圆角、单层边框,以及毛玻璃背景质感。译文长度适中,方便观察排版与对比度。";
            if (e.Args.Length >= 2 && e.Args[1] == "error") popup.ShowError(src, "示例错误:后端不可用(演示用)", "claude · 演示");
            else popup.ShowResult(src, zh, "claude · 演示");
            return;
        }

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
