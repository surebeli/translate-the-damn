// The App references both WPF and WinForms (for the tray NotifyIcon), so a handful of type names
// are ambiguous. Resolve them to their WPF versions app-wide; the WinForms tray code uses its own
// fully-scoped types (NotifyIcon, ContextMenuStrip, …) which are unaffected.
global using Application = System.Windows.Application;
global using Clipboard = System.Windows.Clipboard;
global using MessageBox = System.Windows.MessageBox;
global using TranslateTheDamn.Core;
