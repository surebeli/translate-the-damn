import Foundation

public final class HttpTranslator: Translator {
    private let id: String
    private let config: BackendConfig

    private static func session(timeout: Int) -> URLSession {
        let t = max(timeout, 1)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval(t)
        config.timeoutIntervalForResource = TimeInterval(t)
        return URLSession(configuration: config)
    }

    private static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }

    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _data: Data?
        private var _error: Error?
        private var _statusCode: Int = 0

        var data: Data? {
            lock.lock()
            defer { lock.unlock() }
            return _data
        }

        var error: Error? {
            lock.lock()
            defer { lock.unlock() }
            return _error
        }

        var statusCode: Int {
            lock.lock()
            defer { lock.unlock() }
            return _statusCode
        }

        func setResponse(data: Data?, error: Error?, statusCode: Int) {
            lock.lock()
            _data = data
            _error = error
            _statusCode = statusCode
            lock.unlock()
        }
    }

    public init(id: String, config: BackendConfig) {
        self.id = id
        self.config = config
    }

    public func translate(text: String, model: String) -> TranslationResult {
        let call = HttpBackend.buildCall(backend: id, config: backendTestConfig, text: text)

        guard !call.url.isEmpty else {
            return .failed(.unknownFail, "后端配置缺少 endpoint。")
        }

        guard hasCredential else {
            return .failed(.authFail, "请在设置中填写该后端的 API Key。")
        }

        guard let callUrl = URL(string: call.url) else {
            return .failed(.unknownFail, "后端 endpoint 格式错误。")
        }

        var request = URLRequest(url: callUrl)
        request.httpMethod = call.method
        for (k, v) in call.headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = call.body.data(using: .utf8)

        let box = ResponseBox()
        let semaphore = DispatchSemaphore(value: 0)

        let task = HttpTranslator.session(timeout: config.timeoutSec ?? 60).dataTask(with: request) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            box.setResponse(data: data, error: error, statusCode: code)
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = box.error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                return .failed(.timeout, "请求超时。")
            }
            return .failed(.unknownFail, error.localizedDescription)
        }

        let statusCode = box.statusCode
        guard statusCode == 200 else {
            if statusCode == 401 || statusCode == 403 {
                let bodyStr = box.data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                return .failed(.authFail, "HTTP \(statusCode): \(truncate(bodyStr, 300))")
            }
            let bodyStr = box.data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return .failed(.unknownFail, "HTTP \(statusCode): \(truncate(bodyStr, 300))")
        }

        guard let data = box.data else {
            return .failed(.badOutput, "响应中未找到译文。")
        }

        let responseText = parseResponse(data: data)
        guard let text = responseText, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failed(.badOutput, "响应中未找到译文。")
        }

        return .successful(text.trimmingCharacters(in: .whitespaces))
    }

    private var backendTestConfig: BackendTestConfig {
        return BackendTestConfig(
            apiKey: config.apiKey,
            target: config.target,
            source: config.source,
            format: config.format,
            model: config.model,
            targetLanguage: config.targetLanguage,
            endpoint: config.endpoint,
            sourceLanguage: config.sourceLanguage
        )
    }

    private var hasCredential: Bool {
        guard let key = config.apiKey, !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        return true
    }

    private func parseResponse(data: Data) -> String? {
        guard let def = BackendManifest.backendDef(id) else { return nil }
        guard let responsePath = def["responsePath"] as? String else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return BackendManifest.eval(root: obj, path: responsePath)
    }

    private func truncate(_ s: String, _ maxLen: Int) -> String {
        if s.isEmpty { return "" }
        return s.count <= maxLen ? s : String(s.prefix(maxLen)) + "..."
    }
}
