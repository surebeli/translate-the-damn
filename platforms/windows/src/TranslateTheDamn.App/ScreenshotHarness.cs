using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using TranslateTheDamn.App.UI;
using TranslateTheDamn.Core;            // DoctorReport / DoctorCheck / DoctorStatus
using TranslateTheDamn.Core.Config;

namespace TranslateTheDamn.App;

/// <summary>
/// Dev-only visual-walkthrough harness — the Windows twin of macOS <c>ScreenshotHarness.swift</c>.
/// Inert unless <c>TTD_SHOT_KIND</c> is set (a normal launch never touches it). Renders ONE window in
/// the requested state over a clean backdrop, writes its HWND (decimal) to <c>TTD_SHOT_READY</c>, and
/// stays alive so an external capturer (<c>scripts/shot-walkthrough.ps1</c>) grabs the real composited
/// window (DWM acrylic + the rounded border). Behaviour-neutral: no tray, no hotkey, no backend.
/// </summary>
internal static class ScreenshotHarness
{
    // Verbatim sample content — kept identical to the macOS harness so the README pairs line up.
    private const string Src = "A good translation tool stays invisible until you need it — then it is instantly useful.";
    private const string Zh = "好的翻译工具在你需要之前保持隐形——需要时立即可用。";
    private const string ErrMsg = "翻译失败:claude 未登录或网络不可用(可在设置里「检测」后端)";
    private const string Backend = "claude";

    public static bool RunIfRequested()
    {
        var kind = Environment.GetEnvironmentVariable("TTD_SHOT_KIND");
        if (string.IsNullOrWhiteSpace(kind)) return false;
        var readyPath = Environment.GetEnvironmentVariable("TTD_SHOT_READY");

        ShowBackdrop();   // clean, controlled background so the acrylic frost + rounded corners read cleanly

        var target = kind.StartsWith("popup", StringComparison.Ordinal) ? BuildPopup(kind) : BuildSettings(kind);
        target.Activate();

        // Publish the HWND once the app goes idle (first render done + acrylic applied) so the capturer
        // grabs a settled frame. The script additionally sleeps before capturing.
        target.Dispatcher.BeginInvoke(new Action(() =>
        {
            var hwnd = new WindowInteropHelper(target).Handle;
            if (readyPath is not null)
                try { File.WriteAllText(readyPath, ((long)hwnd).ToString()); } catch { /* best effort */ }
        }), DispatcherPriority.ApplicationIdle);

        return true;
    }

    /// <summary>Full-screen neutral gradient behind the target so the translucent popup blurs a clean
    /// surface (not the desktop) and its rounded-corner transparency captures cleanly.</summary>
    private static void ShowBackdrop()
    {
        var w = new Window
        {
            WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize,
            ShowInTaskbar = false,
            Topmost = false,
            AllowsTransparency = false,
            WindowState = WindowState.Maximized,
            Background = new LinearGradientBrush(
                System.Windows.Media.Color.FromRgb(0x3A, 0x3B, 0x42),
                System.Windows.Media.Color.FromRgb(0x26, 0x27, 0x2C),
                new System.Windows.Point(0, 0), new System.Windows.Point(1, 1)),
        };
        w.Show();
    }

    private static Window BuildPopup(string kind)
    {
        var cfg = new PopupConfig { Style = "acrylic", AutoDismissSeconds = 0, KeepOnHover = true, Position = "top-center" };
        var p = new PopupWindow(cfg);
        switch (kind)
        {
            case "popup-loading":
                p.ShowLoading(Src, Backend);
                break;
            case "popup-error":
                p.ShowError(Src, ErrMsg, Backend);
                break;
            case "popup-large":
                var longSrc = string.Concat(Enumerable.Repeat(Src + " ", 6)).Trim();
                var longZh = string.Concat(Enumerable.Repeat(Zh, 6));
                p.ShowResult(longSrc, longZh, Backend);
                break;
            case "popup-history":
                p.ShowResults(new (string, string)[]
                {
                    (Src, Zh),
                    ("Second most recent source line.", "第二近的源文本行。"),
                    ("Oldest cached entry.", "最旧的缓存条目。"),
                }, 1, Backend);
                break;
            default: // popup-result
                p.ShowResult(Src, Zh, Backend);
                break;
        }
        return p;
    }

    private static Window BuildSettings(string kind)
    {
        // Isolated temp config so the harness never reads/writes the user's real profile.
        var dir = Path.Combine(Path.GetTempPath(), "ttd-shot", kind);
        Directory.CreateDirectory(dir);

        var cfg = DefaultConfig.Create();
        switch (kind)
        {
            case "settings-http":
                cfg.General.ActiveBackend = "doubao";
                break;
            case "settings-custom":
                cfg.Backends["my-llm"] = new BackendConfig
                {
                    Type = "http",
                    Protocol = "openai",
                    Endpoint = "https://api.example.com/v1",
                    ApiKey = "sk-secret",
                    Model = "gpt-4o-mini",
                    TimeoutSec = 30,
                };
                cfg.General.ActiveBackend = "my-llm";
                break;
            default:
                cfg.General.ActiveBackend = "claude";   // settings-builtin / settings-lamp-*
                break;
        }

        var svc = new ConfigService(dir);
        svc.Save(cfg);
        var win = new SettingsWindow(svc);
        // Size the shot to match the macOS settings window: 573 DIP wide = mac's 1146px @2x logical width
        // (the script upscales the 150%-DPI capture to 1146px so the README pair lines up), and as tall as
        // the work area allows so the full form shows like mac. Shot-only; the real app window is unchanged.
        win.Width = 573;
        win.Height = SystemParameters.WorkArea.Height;

        // Doctor lamp states (claude = CLI, so the doctor row is visible). Detail text matches macOS.
        switch (kind)
        {
            case "settings-lamp-ok":
                win.ApplyShotDoctor(new DoctorReport("claude", DoctorStatus.Ok, new[]
                {
                    new DoctorCheck("可执行文件", DoctorStatus.Ok, "claude"),
                    new DoctorCheck("认证(本地凭据文件)", DoctorStatus.Ok, "已登录(本地凭据;未做联网验证)"),
                    new DoctorCheck("模型列表", DoctorStatus.Ok, "haiku, sonnet, opus, fable"),
                }));
                break;
            case "settings-lamp-fail":
                win.ApplyShotDoctor(new DoctorReport("claude", DoctorStatus.Fail, new[]
                {
                    new DoctorCheck("可执行文件", DoctorStatus.Ok, "claude"),
                    new DoctorCheck("认证(本地凭据文件)", DoctorStatus.Fail, "未登录(本地凭据检查未通过)"),
                }));
                break;
        }

        win.Show();
        // Canonical dark title bar for the shot (the shipping window uses Mica, which samples the
        // capture machine's wallpaper into the title bar — light against the dark body).
        Interop.WindowEffects.UseDarkTitleBarSolid(new WindowInteropHelper(win).Handle);
        return win;
    }
}
