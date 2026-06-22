<#
  Visual-walkthrough capture (Windows twin of macOS scripts/shot-walkthrough.sh).
  Renders each UI state via the env-gated ScreenshotHarness (TTD_SHOT_KIND) and captures the REAL
  composited window by HWND — CopyFromScreen over the DWM extended-frame bounds — so the acrylic
  frost and the rounded border show. Native dark theme (the Windows app ships dark).

  Output: platforms/windows/.shots/<kind>-windows.png
  Usage:  pwsh platforms/windows/scripts/shot-walkthrough.ps1
#>
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjDir   = Split-Path -Parent $ScriptDir                      # platforms/windows
$Exe = Join-Path $ProjDir 'src\TranslateTheDamn.App\bin\Release\net9.0-windows\TranslateTheDamn.exe'
$Out = Join-Path $ProjDir '.shots'
if (-not (Test-Path $Exe)) { throw "build first: dotnet build platforms\windows\TranslateTheDamn.sln -c Release  (missing $Exe)" }
if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory -Path $Out | Out-Null
Stop-Process -Name TranslateTheDamn -Force -ErrorAction SilentlyContinue   # clear any stragglers
Start-Sleep -Milliseconds 300

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class ShotWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
}
"@
# Match the DWM window coords (physical px) — otherwise VirtualScreen is logical and crops overflow.
[void][ShotWin]::SetProcessDPIAware()

# All scenarios (required + optional). Names match the macOS kinds; files are saved -windows.png.
$kinds = @(
  'popup-result','popup-loading','popup-error','popup-history','popup-large',
  'settings-builtin','settings-lamp-ok','settings-lamp-fail','settings-custom','settings-http'
)
$EXTENDED_FRAME = 9   # DWMWA_EXTENDED_FRAME_BOUNDS

foreach ($kind in $kinds) {
  $ready = [System.IO.Path]::GetTempFileName(); Remove-Item $ready -Force -ErrorAction SilentlyContinue
  $env:TTD_SHOT_KIND = $kind
  $env:TTD_SHOT_READY = $ready
  $proc = Start-Process $Exe -PassThru

  # wait for the harness to publish the HWND
  for ($i = 0; $i -lt 80; $i++) {
    if ((Test-Path $ready) -and ((Get-Item $ready).Length -gt 0)) { break }
    Start-Sleep -Milliseconds 100
  }
  Start-Sleep -Milliseconds 800   # let first render + acrylic settle

  $hwnd = 0
  if (Test-Path $ready) { [void][int64]::TryParse((Get-Content $ready -Raw).Trim(), [ref]$hwnd) }

  if ($hwnd -ne 0) {
    try {
      $h = [IntPtr]$hwnd
      [void][ShotWin]::SetForegroundWindow($h)
      Start-Sleep -Milliseconds 350

      $r = New-Object ShotWin+RECT
      $rc = [ShotWin]::DwmGetWindowAttribute($h, $EXTENDED_FRAME, [ref]$r, 16)
      if ($rc -ne 0) { [void][ShotWin]::GetWindowRect($h, [ref]$r) }

      $w = $r.Right - $r.Left
      $ht = $r.Bottom - $r.Top
      if ($w -gt 0 -and $ht -gt 0 -and $w -lt 8000 -and $ht -lt 8000) {
        # Capture the whole virtual screen from its known-good origin, then crop the window rect out of
        # it (passing a window's own screen coords straight to CopyFromScreen can hit "handle invalid").
        $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $full = New-Object System.Drawing.Bitmap($vs.Width, $vs.Height)
        $fg = [System.Drawing.Graphics]::FromImage($full)
        $fg.CopyFromScreen($vs.X, $vs.Y, 0, 0, $vs.Size)
        $cropRect = New-Object System.Drawing.Rectangle(($r.Left - $vs.X), ($r.Top - $vs.Y), $w, $ht)
        $cropRect = [System.Drawing.Rectangle]::Intersect($cropRect, (New-Object System.Drawing.Rectangle(0, 0, $full.Width, $full.Height)))
        $crop = $full.Clone($cropRect, $full.PixelFormat)
        $dest = Join-Path $Out "$kind-windows.png"
        $crop.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
        $fg.Dispose(); $full.Dispose(); $crop.Dispose()
        Write-Host ("captured {0,-22} {1}x{2} @ {3},{4}" -f $kind, $w, $ht, $r.Left, $r.Top)
      } else { Write-Host ("bad rect for {0}: {1}x{2}" -f $kind, $w, $ht) }
    } catch { Write-Host ("capture error for {0}: {1}" -f $kind, $_.Exception.Message) }
  } else { Write-Host "no hwnd for $kind" }

  Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 350
}

Remove-Item Env:TTD_SHOT_KIND, Env:TTD_SHOT_READY -ErrorAction SilentlyContinue
Write-Host "`nshots -> $Out"
Get-ChildItem $Out -Name
