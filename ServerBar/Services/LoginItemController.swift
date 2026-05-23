import Foundation
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published var isEnabled = false
    @Published var statusMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            statusMessage = nil
            refresh()
        } catch {
            statusMessage = error.localizedDescription
            refresh()
        }
    }
}
