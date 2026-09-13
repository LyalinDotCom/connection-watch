import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    private var lastNotificationDate: Date?
    private let cooldown: TimeInterval = 30
    private var lastNotifiedState: ConnectionState?
    private var deferredCheckTask: Task<Void, Never>?
    private var currentStateProvider: (() -> ConnectionState)?

    private var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func requestAuthorization() {
        guard canUseUserNotifications else { return }
        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    func setStateProvider(_ provider: @escaping () -> ConnectionState) {
        currentStateProvider = provider
    }

    func notify(state: ConnectionState) {
        // Don't notify if this is the same state we already told the user about
        guard state != lastNotifiedState else {
            deferredCheckTask?.cancel()
            deferredCheckTask = nil
            return
        }

        if canSendNotification() {
            deferredCheckTask?.cancel()
            deferredCheckTask = nil
            sendNotification(state: state)
        } else {
            scheduleDeferredCheck()
        }
    }

    private func sendNotification(state: ConnectionState) {
        lastNotifiedState = state
        lastNotificationDate = Date()

        guard canUseUserNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = state.notificationTitle
        content.body = state.notificationBody
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func scheduleDeferredCheck() {
        deferredCheckTask?.cancel()
        deferredCheckTask = Task { [weak self] in
            guard let self else { return }
            let remaining: TimeInterval
            if let last = self.lastNotificationDate {
                remaining = max(0, self.cooldown - Date().timeIntervalSince(last))
            } else {
                remaining = 0
            }
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining + 0.5))
            }
            guard !Task.isCancelled else { return }
            if let provider = self.currentStateProvider {
                let currentState = provider()
                if currentState != self.lastNotifiedState {
                    self.sendNotification(state: currentState)
                }
            }
        }
    }

    private func canSendNotification() -> Bool {
        guard let last = lastNotificationDate else { return true }
        return Date().timeIntervalSince(last) >= cooldown
    }
}
