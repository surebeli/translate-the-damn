import Foundation

/// Pure decision for the translation popup's fixed size (spec §8, conformance `popup-sizing`).
///
/// Two sizes: `normal`, and `large` = `largeWidthFactor` × normal width by `largeHeightFactor` ×
/// normal height. The popup uses `large` when the currently displayed entry's **source** text
/// length exceeds `largeSourceCharThreshold`. Keeping this as a pure, platform-neutral function lets
/// the rule be pinned by a shared conformance vector while each platform owns the actual pixels.
public enum PopupSizing {
    /// Source length strictly greater than this → large size. (`> 500`, so 500 is still normal.)
    public static let largeSourceCharThreshold = 500
    /// Large width = this × normal width.
    public static let largeWidthFactor = 2.0
    /// Large height = this × normal height.
    public static let largeHeightFactor = 1.5

    /// "normal" or "large" for the given source character count.
    public static func sizeClass(sourceChars: Int) -> String {
        sourceChars > largeSourceCharThreshold ? "large" : "normal"
    }
}
