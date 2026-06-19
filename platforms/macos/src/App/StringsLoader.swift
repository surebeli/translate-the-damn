// StringsLoader — loads shared UI strings from strings/zh-CN.json (with a built-in fallback).
// Relocated here when the multi-style UI was consolidated to a single style (was in the
// now-removed TranslationPopup.swift).
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
