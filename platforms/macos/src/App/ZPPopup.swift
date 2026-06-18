import AppKit
import Foundation
import TranslateTheDamnCore

/// ZP-style translation popup — modern macOS design with frosted translucency.
/// Uses system semantic colors (auto-adapts to light/dark + vibrancy → no contrast issues).
/// No darkScrim overlay — the vibrancy material provides the backdrop, system text colors
/// guarantee legibility on both light and dark appearances.
///
/// Non-focus-stealing: NSPanel(.nonactivatingPanel) + canBecomeKey/Main=false + .floating level.
/// Common protocol for popup UI implementations (ZP modern + classic).
@MainActor
protocol TranslationPopupUI: AnyObject {
    func showLoading()
    func showResult(translation: String, source: String)
    func showError(message: String)
    func show(source: String, translation: String)
    func update(translation: String)
    func dismiss()
}

final class ZPPopup: NSPanel, TranslationPopupUI {
    private let cfg: PopupConfig
    private let onCopy: (String) -> Void

    // Content views
    private let visualEffectView = NSVisualEffectView()
    private let contentStack = NSStackView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private let translationScrollView = NSScrollView()
    private let translationTextView = NSTextView()
    private let buttonStack = NSStackView()
    private let copyButton = NSButton(title: "复制译文", target: nil, action: nil)
    private let closeButton = NSButton(title: "关闭", target: nil, action: nil)

    // State
    private var dismissTimer: Timer?
    private var copiedTimer: Timer?
    private var isMouseOver = false
    private var currentTranslation = ""

    init(cfg: PopupConfig, onCopy: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onCopy = onCopy

        let style: NSWindow.StyleMask = [.nonactivatingPanel, .titled, .fullSizeContentView, .borderless]
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 200), styleMask: style, backing: .buffered, defer: false)

        setUpWindow()
        setUpContent()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Setup

    private func setUpWindow() {
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        contentView = visualEffectView
    }

    private func setUpContent() {
        // Frosted translucent material — adapts to system light/dark appearance.
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 12
        visualEffectView.layer?.masksToBounds = true

        // Content stack — clean vertical layout with generous spacing.
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 14, right: 20)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
        ])

        // Header — SF Pro semibold, system label color (adapts to vibrancy + light/dark).
        headerLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = NSColor.labelColor
        headerLabel.maximumNumberOfLines = 1
        contentStack.addArrangedSubview(headerLabel)

        // Source — muted, system secondary label color.
        sourceLabel.font = NSFont.systemFont(ofSize: 11)
        sourceLabel.textColor = NSColor.secondaryLabelColor
        sourceLabel.maximumNumberOfLines = 2
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentStack.addArrangedSubview(sourceLabel)

        // Translation — prominent, system label color, scrollable.
        let scrollHeight: CGFloat = min(cfg.autoDismissSeconds > 0 ? 200 : 280, 280)
        translationScrollView.translatesAutoresizingMaskIntoConstraints = false
        translationScrollView.hasVerticalScroller = true
        translationScrollView.hasHorizontalScroller = false
        translationScrollView.borderType = .noBorder
        translationScrollView.drawsBackground = false
        translationScrollView.autohidesScrollers = true
        translationScrollView.heightAnchor.constraint(equalToConstant: scrollHeight).isActive = true
        translationScrollView.widthAnchor.constraint(equalToConstant: 340).isActive = true

        translationTextView.isEditable = false
        translationTextView.isSelectable = true
        translationTextView.drawsBackground = false
        translationTextView.textContainerInset = NSSize(width: 0, height: 4)
        translationTextView.font = NSFont.systemFont(ofSize: 15)
        translationTextView.textColor = NSColor.labelColor
        translationTextView.isRichText = false
        translationTextView.usesAdaptiveColorMappingForDarkAppearance = true
        translationScrollView.documentView = translationTextView
        contentStack.addArrangedSubview(translationScrollView)

        // Buttons — native .rounded, system accent for copy.
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 10
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fill
        contentStack.addArrangedSubview(buttonStack)

        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .small
        copyButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        copyButton.target = self
        copyButton.action = #selector(onCopyButton)
        copyButton.isHidden = true
        buttonStack.addArrangedSubview(copyButton)

        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .small
        closeButton.font = NSFont.systemFont(ofSize: 11)
        closeButton.target = self
        closeButton.action = #selector(onCloseButton)
        buttonStack.addArrangedSubview(closeButton)

        // Hover tracking for keep-on-hover.
        let trackingArea = NSTrackingArea(
            rect: visualEffectView.bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        visualEffectView.addTrackingArea(trackingArea)
    }

    // MARK: - States

    func showLoading() {
        headerLabel.stringValue = StringsLoader["popup.header.translating"]
        sourceLabel.stringValue = ""
        translationTextView.string = StringsLoader["popup.body.translating"]
        translationTextView.textColor = NSColor.tertiaryLabelColor
        copyButton.isHidden = true
        copyButton.title = StringsLoader["popup.button.copy"]
        dismissTimer?.invalidate()
        dismissTimer = nil
        showAndPlace()
    }

    func showResult(translation: String, source: String) {
        currentTranslation = translation
        headerLabel.stringValue = StringsLoader["popup.header.result"]
        sourceLabel.stringValue = truncate(source, max: 400)
        translationTextView.string = translation
        translationTextView.textColor = NSColor.labelColor
        copyButton.title = StringsLoader["popup.button.copy"]
        copyButton.isHidden = false
        showAndPlace()
        if !isMouseOver { restartDismiss() }
    }

    func showError(message: String) {
        headerLabel.stringValue = StringsLoader["popup.header.error"]
        sourceLabel.stringValue = ""
        translationTextView.string = message
        translationTextView.textColor = NSColor.systemOrange
        copyButton.isHidden = true
        showAndPlace()
        if !isMouseOver { restartDismiss() }
    }

    func show(source: String, translation: String) {
        showResult(translation: translation, source: source)
    }

    func update(translation: String) {
        currentTranslation = translation
        translationTextView.string = translation
        translationTextView.textColor = NSColor.labelColor
        copyButton.title = StringsLoader["popup.button.copy"]
        copyButton.isHidden = false
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        copiedTimer?.invalidate()
        copiedTimer = nil
        NSAnimationContext.runAnimationGroup { [weak self] ctx in
            ctx.duration = 0.2
            self?.animator().alphaValue = 0
        } completionHandler: {
            DispatchQueue.main.async { [weak self] in
                self?.orderOut(nil)
                self?.alphaValue = 1.0
            }
        }
    }

    // MARK: - Private

    private func showAndPlace() {
        alphaValue = 1.0
        if !isVisible {
            orderFrontRegardless()
        }
        positionTopCenter()
    }

    private func positionTopCenter() {
        guard let screen = NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let frame = self.frame
        let x = visibleFrame.midX - frame.width / 2
        let y = visibleFrame.maxY - frame.height - 8
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func restartDismiss() {
        dismissTimer?.invalidate()
        let seconds = cfg.autoDismissSeconds
        if seconds > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
                DispatchQueue.main.async { self?.dismiss() }
            }
        }
    }

    private func truncate(_ s: String, max: Int) -> String {
        s.count > max ? String(s.prefix(max)) + "…" : s
    }

    // MARK: - Hover

    override func mouseEntered(with event: NSEvent) {
        isMouseOver = true
        dismissTimer?.invalidate()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseOver = false
        if cfg.keepOnHover { restartDismiss() }
    }

    // MARK: - Actions

    @objc private func onCopyButton() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentTranslation, forType: .string)
        onCopy(currentTranslation)
        copyButton.title = StringsLoader["popup.button.copied"]
        copiedTimer?.invalidate()
        copiedTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.copyButton.title = StringsLoader["popup.button.copy"]
            }
        }
    }

    @objc private func onCloseButton() {
        dismiss()
    }
}
