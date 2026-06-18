import Foundation
import ServiceManagement

/// Manages the app's start-at-login behavior on macOS via `SMAppService`.
/// Mirrors the shared `general.startWithWindows` config flag to the platform
/// login-item mechanism. macOS 13+ only; callers may invoke safely on older
/// systems because every operation is availability-guarded.
@MainActor
final class LoginService {
    static let shared = LoginService()

    private init() {}

    /// Enables or disables start-at-login.
    /// - Parameter on: `true` to register the main app as a login item,
    ///   `false` to unregister it.
    func setEnabled(_ on: Bool) {
        guard #available(macOS 13, *) else {
            NSLog("[LoginService] SMAppService requires macOS 13+")
            return
        }

        let service = SMAppService.mainApp
        if on {
            do {
                try service.register()
                NSLog("[LoginService] Registered login item")
            } catch {
                NSLog("[LoginService] Failed to register login item: %@", error.localizedDescription)
            }
        } else {
            do {
                try service.unregister()
                NSLog("[LoginService] Unregistered login item")
            } catch {
                NSLog("[LoginService] Failed to unregister login item: %@", error.localizedDescription)
            }
        }
    }

    /// Returns whether the main app is currently registered as a login item.
    /// Always returns `false` on macOS versions older than 13.
    func isEnabled() -> Bool {
        guard #available(macOS 13, *) else { return false }

        let status = SMAppService.mainApp.status
        return status == .enabled
    }
}
