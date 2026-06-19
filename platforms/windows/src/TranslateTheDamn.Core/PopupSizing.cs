namespace TranslateTheDamn.Core;

/// <summary>
/// Pure decision for the translation popup's fixed size (spec §8, conformance <c>popup-sizing</c>).
///
/// Two sizes: <c>normal</c>, and <c>large</c> = <see cref="LargeWidthFactor"/> × normal width by
/// <see cref="LargeHeightFactor"/> × normal height. The popup uses <c>large</c> when the currently
/// displayed entry's <b>source</b> text length exceeds <see cref="LargeSourceCharThreshold"/>. Keeping
/// this as a pure, platform-neutral function lets the rule be pinned by a shared conformance vector
/// while each platform owns the actual pixels. Mirrors macOS <c>PopupSizing.swift</c>.
/// </summary>
public static class PopupSizing
{
    /// <summary>Source length strictly greater than this → large size. (<c>&gt; 500</c>, so 500 is still normal.)</summary>
    public const int LargeSourceCharThreshold = 500;

    /// <summary>Large width = this × normal width.</summary>
    public const double LargeWidthFactor = 2.0;

    /// <summary>Large height = this × normal height.</summary>
    public const double LargeHeightFactor = 1.5;

    /// <summary>"normal" or "large" for the given source character count.</summary>
    public static string SizeClass(int sourceChars) =>
        sourceChars > LargeSourceCharThreshold ? "large" : "normal";
}
