import AppKit
import Foundation
import TranslateTheDamnCore

enum StringsLoader {
    nonisolated(unsafe) private static var cached: [String: String]?

    static var catalog: [String: String] {
        if let c = cached { return c }
        let loaded = loadFromFile() ?? fallbackStrings
        cached = loaded
        return loaded
    }

    static subscript(_ key: String) -> String {
        catalog[key] ?? key
    }

    private static func loadFromFile() -> [String: String]? {
        let fileName = "zh-CN.json"
        let searchPaths: [String] = {
            var paths: [String] = []
            if let execPath = Bundle.main.executableURL?.path {
                paths.append((execPath as NSString).deletingLastPathComponent)
            }
            if let bundlePath = Bundle.main.resourcePath {
                paths.append(bundlePath)
            }
            paths.append(FileManager.default.currentDirectoryPath)
            return paths
        }()

        for base in searchPaths {
            var url = URL(fileURLWithPath: base)
            for _ in 0..<6 {
                let candidate = url.appendingPathComponent("strings").appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    if let data = FileManager.default.contents(atPath: candidate.path),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let strings = obj["strings"] as? [String: String] {
                        return strings
                    }
                }
                let next = url.deletingLastPathComponent()
                if next.path == url.path { break }
                url = next
            }
        }
        return nil
    }

    private static let fallbackStrings: [String: String] = [
        "popup.header.translating": "翻译中…",
        "popup.header.result": "翻译",
        "popup.header.error": "翻译失败",
        "popup.body.translating": "正在翻译,请稍候…",
        "popup.button.copy": "复制译文",
        "popup.button.copied": "已复制 ✓",
        "popup.button.close": "关闭",
        "tray.tooltip.listening": "translate-the-damn(监听中)",
        "tray.tooltip.paused": "translate-the-damn(已暂停)",
        "tray.menu.listen": "监听剪贴板",
        "tray.menu.settings": "打开设置…",
        "tray.menu.exit": "退出",
        "settings.title": "translate-the-damn · 设置",
        "settings.group.trigger": "监听与触发",
        "settings.group.backend": "翻译后端",
        "settings.group.popup": "浮窗展示",
        "settings.group.general": "通用",
        "settings.field.listen": "启用剪贴板监听(复制即翻译)",
        "settings.field.hotkey": "翻译热键",
        "settings.field.backend": "后端",
        "settings.field.model": "模型",
        "settings.field.apiKey": "API Key",
        "settings.field.endpoint": "Endpoint",
        "settings.field.target": "目标语言",
        "settings.field.timeout": "超时(秒)",
        "settings.field.style": "视觉风格",
        "settings.field.autodismiss": "自动消失",
        "settings.field.keephover": "鼠标悬停时保持不消失",
        "settings.field.startup": "开机自启",
        "settings.button.save": "保存",
        "settings.button.close": "关闭",
        "settings.status.saved": "已保存 ✓",
        "error.auth": "认证失败,请在设置中登录或填写密钥。",
        "error.timeout": "翻译超时({sec}s)",
        "error.notfound": "找不到命令 “{command}”,请确认已安装在 PATH 中。",
        "error.badoutput": "没有返回译文(可能是该 CLI 在 Windows 下的已知输出问题)。",
        "error.apikeyMissing": "请在设置中填写该后端的 API Key。"
    ]
}

final class TranslationPopup: NSPanel {
    private let cfg: PopupConfig
    private var dismissTimer: Timer?
    private var translation: String = ""
    private var trackingArea: NSTrackingArea?
    private let onCopy: (String) -> Void

    private let visualEffectView: NSVisualEffectView
    private let contentStack: NSStackView
    private let headerLabel: NSTextField
    private let sourceLabel: NSTextField
    private let translationScrollView: NSScrollView
    private let translationTextView: NSTextView
    private let buttonStack: NSStackView
    private let copyButton: NSButton
    private let closeButton: NSButton
    private let bodyLabel: NSTextField

    private var copiedTimer: Timer?

    init(cfg: PopupConfig, onCopy: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onCopy = onCopy

        visualEffectView = NSVisualEffectView()
        contentStack = NSStackView()
        headerLabel = NSTextField(labelWithString: "")
        bodyLabel = NSTextField(labelWithString: "")
        sourceLabel = NSTextField(labelWithString: "")
        translationScrollView = NSScrollView()
        translationTextView = NSTextView()
        buttonStack = NSStackView()
        copyButton = NSButton(title: StringsLoader["popup.button.copy"], target: nil, action: nil)
        closeButton = NSButton(title: StringsLoader["popup.button.close"], target: nil, action: nil)

        let panelStyle: NSWindow.StyleMask = [.nonactivatingPanel, .titled, .fullSizeContentView, .borderless]
        super.init(contentRect: .zero, styleMask: panelStyle, backing: .buffered, defer: false)

        setUpWindow()
        setUpContent()
        positionTopCentre()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func showLoading() {
        headerLabel.stringValue = StringsLoader["popup.header.translating"]
        bodyLabel.stringValue = StringsLoader["popup.body.translating"]
        sourceLabel.stringValue = ""
        translationTextView.string = ""
        copyButton.isHidden = true
        dismissTimer?.invalidate()
        dismissTimer = nil
        showAndPlace()
    }

    func showResult(translation: String, source: String) {
        self.translation = translation
        headerLabel.stringValue = StringsLoader["popup.header.result"]
        bodyLabel.stringValue = ""
        sourceLabel.stringValue = truncate(source, max: 400)
        translationTextView.string = translation
        translationTextView.textColor = NSColor(white: 0.95, alpha: 1.0)
        copyButton.title = StringsLoader["popup.button.copy"]
        copyButton.isHidden = false
        showAndPlace()
        if !isMouseOverContent() { restartDismiss() }
    }

    func showError(message: String) {
        headerLabel.stringValue = StringsLoader["popup.header.error"]
        bodyLabel.stringValue = ""
        sourceLabel.stringValue = ""
        translationTextView.string = message
        translationTextView.textColor = NSColor(red: 1.0, green: 0.71, blue: 0.66, alpha: 1.0)
        copyButton.isHidden = true
        showAndPlace()
        if !isMouseOverContent() { restartDismiss() }
    }

    func show(source: String, translation: String) {
        showResult(translation: translation, source: source)
    }

    func update(translation: String) {
        self.translation = translation
        translationTextView.string = translation
        translationTextView.textColor = NSColor(white: 0.95, alpha: 1.0)
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

    private func setUpWindow() {
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        animationBehavior = .none

        contentView = visualEffectView
    }

    private func setUpContent() {
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 12
        visualEffectView.layer?.masksToBounds = true

        let darkScrim = NSView()
        darkScrim.wantsLayer = true
        darkScrim.layer?.backgroundColor = NSColor(white: 0, alpha: 0.45).cgColor
        visualEffectView.addSubview(darkScrim)
        darkScrim.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            darkScrim.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            darkScrim.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            darkScrim.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            darkScrim.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor)
        ])

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 16, right: 24)
        visualEffectView.addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor)
        ])

        headerLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = NSColor(white: 0.9, alpha: 1.0)
        headerLabel.maximumNumberOfLines = 1
        contentStack.addArrangedSubview(headerLabel)

        bodyLabel.font = NSFont.systemFont(ofSize: 11)
        bodyLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        bodyLabel.maximumNumberOfLines = 1
        contentStack.addArrangedSubview(bodyLabel)

        sourceLabel.font = NSFont.systemFont(ofSize: 11)
        sourceLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        sourceLabel.maximumNumberOfLines = 2
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentStack.addArrangedSubview(sourceLabel)

        let scrollSize = NSSize(width: 420, height: min(cfg.autoDismissSeconds > 0 ? 300 : 400, 400))
        translationScrollView.translatesAutoresizingMaskIntoConstraints = false
        translationScrollView.setFrameSize(scrollSize)
        translationScrollView.hasVerticalScroller = true
        translationScrollView.hasHorizontalScroller = false
        translationScrollView.borderType = .noBorder
        translationScrollView.drawsBackground = false
        translationScrollView.autohidesScrollers = true

        translationTextView.isEditable = false
        translationTextView.isSelectable = true
        translationTextView.drawsBackground = false
        translationTextView.textContainerInset = NSSize(width: 0, height: 4)
        translationTextView.font = NSFont.systemFont(ofSize: 14)
        translationTextView.textColor = NSColor(white: 0.95, alpha: 1.0)
        translationTextView.isRichText = false
        translationTextView.usesAdaptiveColorMappingForDarkAppearance = true

        translationScrollView.documentView = translationTextView
        translationScrollView.widthAnchor.constraint(equalToConstant: scrollSize.width).isActive = true
        translationScrollView.heightAnchor.constraint(equalToConstant: scrollSize.height).isActive = true
        contentStack.addArrangedSubview(translationScrollView)

        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fill
        contentStack.addArrangedSubview(buttonStack)

        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .small
        copyButton.font = NSFont.systemFont(ofSize: 11)
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

        let trackingArea = NSTrackingArea(
            rect: visualEffectView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        visualEffectView.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    private func showAndPlace() {
        if !isVisible {
            alphaValue = 0
            makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                animator().alphaValue = 1.0
            }
        }
        translationScrollView.contentView.scroll(to: .zero)
        positionTopCentre()
    }

    private func positionTopCentre() {
        guard let screen = NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let windowWidth: CGFloat = 468
        let preferredHeight = preferredContentHeight()
        let windowHeight = min(preferredHeight, visibleFrame.height * 0.6)
        let maxWidth = visibleFrame.width * 0.8
        let finalWidth = min(windowWidth, maxWidth)

        setContentSize(NSSize(width: finalWidth, height: windowHeight))
        let x = visibleFrame.midX - finalWidth / 2
        let y = visibleFrame.maxY - windowHeight - 24
        setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    private func preferredContentHeight() -> CGFloat {
        var h: CGFloat = 0
        h += 20 + 8 // top padding + header
        if !bodyLabel.stringValue.isEmpty { h += 8 + 16 }
        if !sourceLabel.stringValue.isEmpty { h += 8 + 18 }
        h += 8
        let scrollHeight: CGFloat = min(cfg.autoDismissSeconds > 0 ? 300 : 400, 400)
        h += min(scrollHeight, max(60, scrollHeight))
        h += 8 + 22 + 16 // spacing + buttons + bottom padding
        return ceil(h)
    }

    private func restartDismiss() {
        guard cfg.autoDismissSeconds > 0 else { return }
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(cfg.autoDismissSeconds), repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.dismiss()
            }
        }
    }

    private func isMouseOverContent() -> Bool {
        let wn = windowNumber
        guard wn > 0 else { return false }
        let mouseLocation = NSEvent.mouseLocation
        let frame = frame
        return NSPointInRect(mouseLocation, frame)
    }

    override func mouseEntered(with event: NSEvent) {
        if cfg.keepOnHover {
            dismissTimer?.invalidate()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if cfg.keepOnHover {
            restartDismiss()
        }
    }

    @objc private func onCopyButton() {
        guard !translation.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translation, forType: .string)
        onCopy(translation)

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

    private func truncate(_ s: String, max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max)) + "…"
    }
}
