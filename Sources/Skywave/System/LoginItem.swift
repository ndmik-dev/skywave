import Foundation
import ServiceManagement

/// Wraps `SMAppService` so the panel can offer a "start at login" toggle.
///
/// Registration only works from a bundle macOS considers installed, which in
/// practice means `/Applications`.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// - Returns: an error message when the system refused, otherwise `nil`.
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
